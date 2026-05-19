"""Docker container state publisher.

Polls the local Docker daemon every POLL_INTERVAL_S seconds and
publishes one retained MQTT message per tracked container under
``pv-stack/infra/docker/<name>/state``.

Why
---
alertd has no native docker visibility — the only thing it can do is
bind an MQTT variable to a topic and alert when a value crosses a
threshold or staleness window. With this publisher, every tracked
container becomes a regular MQTT variable in alertd, so the existing
rule machinery (persist_n, thresholds, channel routing) covers
"container down" the same way it covers "battery temp too high".

What's published
----------------
For each container whose name starts with ``CONTAINER_PREFIX`` (or
which is explicitly listed in ``CONTAINER_WHITELIST``), a JSON
payload like::

    {
      "state": "running",
      "running": true,
      "health": "healthy",   // or "unhealthy"/"starting"/"none"
      "exit_code": null,
      "uptime_s": 12345,
      "restart_count": 0,
      "image": "pv-stack-alerts-alertd",
      "ts": "2026-05-19T20:00:00Z"
    }

Also publishes a roll-up on ``pv-stack/infra/docker/_summary`` with
aggregate counts (running / unhealthy / total), which a single alertd
rule can use to alert on "≥1 tracked container down".

Failure modes
-------------
- Docker socket unreachable → log + retry next tick. No publish so
  retained values remain — alertd ``stale_after_sec`` will eventually
  flag the missing data.
- MQTT broker unreachable → paho auto-reconnects in background.
- Race during ``docker stop`` → container may briefly report
  ``status='exited'`` with ``running=False``. That is the intended
  signal.

Security
--------
``/var/run/docker.sock`` is mounted read-only (``-ro`` in compose).
The Docker socket without --privileged still permits container
control via the API, so a compromise of this container could stop /
restart other containers. Defense in depth: this image runs as a
non-root user except for the brief socket call (the socket itself is
group-owned by the docker group; we add the container user to that
group via DOCKER_GID).
"""
from __future__ import annotations

import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

try:
    import docker
except ImportError:
    print("docker SDK not installed", file=sys.stderr)
    sys.exit(1)


LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("docker-monitor")

MQTT_BROKER = os.environ.get("MQTT_BROKER", "pv-stack-mosquitto")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
POLL_INTERVAL_S = max(10, int(os.environ.get("POLL_INTERVAL_S", "30")))
CONTAINER_PREFIX = os.environ.get("CONTAINER_PREFIX", "pv-stack-")
WHITELIST = {
    n.strip() for n in os.environ.get("CONTAINER_WHITELIST", "").split(",")
    if n.strip()
}
BLACKLIST = {
    n.strip() for n in os.environ.get("CONTAINER_BLACKLIST", "").split(",")
    if n.strip()
}
TOPIC_PREFIX = os.environ.get(
    "MQTT_TOPIC_PREFIX", "pv-stack/infra/docker"
)
CLIENT_ID = f"docker-monitor-{os.getpid()}-{os.urandom(3).hex()}"


_stop = False


def _on_sig(_signum, _frame):
    global _stop
    _stop = True


signal.signal(signal.SIGTERM, _on_sig)
signal.signal(signal.SIGINT, _on_sig)


def _select(containers):
    """Filter containers based on whitelist OR prefix, minus blacklist."""
    for c in containers:
        name = c.name
        if name in BLACKLIST:
            continue
        if WHITELIST and name not in WHITELIST:
            continue
        if not WHITELIST and not name.startswith(CONTAINER_PREFIX):
            continue
        yield c


def _build_payload(c) -> dict:
    """Extract the relevant fields from a docker container object.

    Docker SDK ``container.attrs`` mirrors the JSON from
    ``docker inspect``. ``State.Health`` is only present if the image
    declares a HEALTHCHECK; absent → reported as ``"none"`` so the
    consumer can distinguish "unknown health" from "no health probe
    configured".
    """
    attrs = c.attrs
    state = attrs.get("State", {}) or {}
    config = attrs.get("Config", {}) or {}
    health = (state.get("Health") or {}).get("Status") or "none"
    started_at = state.get("StartedAt") or ""
    uptime_s = 0
    if started_at and state.get("Running"):
        try:
            # Truncate fractional seconds; some images emit > 6 digits
            # which fromisoformat rejects.
            ts = started_at.split(".")[0]
            dt = datetime.fromisoformat(ts.rstrip("Z")).replace(
                tzinfo=timezone.utc
            )
            uptime_s = int((datetime.now(timezone.utc) - dt).total_seconds())
        except Exception:
            pass
    return {
        "state": state.get("Status", "unknown"),
        "running": bool(state.get("Running", False)),
        "health": health,
        "exit_code": state.get("ExitCode"),
        "uptime_s": uptime_s,
        "restart_count": attrs.get("RestartCount", 0),
        "image": config.get("Image", ""),
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main() -> int:
    log.info("starting docker-monitor: prefix=%r whitelist=%r "
             "poll=%ds broker=%s:%d",
             CONTAINER_PREFIX, WHITELIST, POLL_INTERVAL_S,
             MQTT_BROKER, MQTT_PORT)

    try:
        docker_client = docker.from_env()
    except Exception as e:
        log.exception("could not connect to docker daemon: %s", e)
        return 2

    mqtt_client = mqtt.Client(client_id=CLIENT_ID, clean_session=True)
    if MQTT_USER:
        mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
    mqtt_client.reconnect_delay_set(min_delay=1, max_delay=60)
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    except Exception as e:
        log.warning("initial broker connect failed: %s (will retry)", e)
    mqtt_client.loop_start()

    while not _stop:
        t0 = time.time()
        try:
            containers = list(docker_client.containers.list(all=True))
        except Exception as e:
            log.warning("docker list failed: %s", e)
            time.sleep(POLL_INTERVAL_S)
            continue

        tracked = list(_select(containers))
        running = 0
        unhealthy = 0
        for c in tracked:
            payload = _build_payload(c)
            if payload["running"]:
                running += 1
            if payload["health"] == "unhealthy":
                unhealthy += 1
            topic = f"{TOPIC_PREFIX}/{c.name}/state"
            try:
                mqtt_client.publish(topic, json.dumps(payload),
                                    qos=1, retain=True)
            except Exception as e:
                log.warning("publish %s failed: %s", topic, e)

        # Rollup snapshot — single topic to alert on "anything down".
        summary = {
            "total": len(tracked),
            "running": running,
            "stopped": len(tracked) - running,
            "unhealthy": unhealthy,
            "names": [c.name for c in tracked],
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        try:
            mqtt_client.publish(f"{TOPIC_PREFIX}/_summary",
                                json.dumps(summary), qos=1, retain=True)
        except Exception:
            pass

        dt = time.time() - t0
        log.debug("tick: %d containers, %d running, %d unhealthy "
                  "(%.1fms)", len(tracked), running, unhealthy, dt * 1000)
        time.sleep(max(0.1, POLL_INTERVAL_S - dt))

    log.info("shutting down")
    mqtt_client.loop_stop()
    mqtt_client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
