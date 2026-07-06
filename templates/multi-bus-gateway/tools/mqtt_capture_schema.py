#!/usr/bin/env python3
"""Capture the gateway's live MQTT output and reduce it to a stable SCHEMA.

Byte-identical verification harness for the architectural refactor: run once
BEFORE a change and once AFTER, then plain-diff the two files. Values and
timestamps churn every poll, so the schema keeps only what must not change —
the topic set and, per topic, the payload's structure (JSON key tree with
types, or the raw payload type).

Usage:
    python3 tools/mqtt_capture_schema.py out/before.schema [--seconds 30]
    ... deploy the change ...
    python3 tools/mqtt_capture_schema.py out/after.schema  [--seconds 30]
    diff out/before.schema out/after.schema      # empty diff = wire unchanged

Runs mosquitto_sub inside the broker container (docker exec), reading the
password from the gateway's live config.yaml — nothing is hardcoded and no
secret lands in the output file.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

BROKER_CONTAINER = "pv-stack-mosquitto"
GATEWAY_CONFIG = "/docker-storage/pv-stack/janitza-monitor/config/config.yaml"
TOPIC = "janitza/umg512/#"


def broker_credentials():
    import yaml
    cfg = yaml.safe_load(Path(GATEWAY_CONFIG).read_text()) or {}
    m = cfg.get("mqtt") or {}
    return m.get("username") or "admin", m.get("password") or ""


def json_schema(value, depth=0):
    """A value → its structure: dict keys (sorted, recursive), list item type,
    scalar type name. Numbers all collapse to 'num' (int/float churn per poll)."""
    if isinstance(value, dict):
        if depth >= 4:
            return "{...}"
        return "{" + ",".join(f"{k}:{json_schema(v, depth + 1)}"
                              for k, v in sorted(value.items())) + "}"
    if isinstance(value, list):
        inner = json_schema(value[0], depth + 1) if value else "?"
        return f"[{inner}]"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "num"
    if value is None:
        return "null"
    return "str"


def capture(seconds):
    user, pw = broker_credentials()
    cmd = ["docker", "exec", BROKER_CONTAINER,
           "mosquitto_sub", "-u", user, "-P", pw,
           "-t", TOPIC, "-v", "-W", str(seconds)]
    out = subprocess.run(cmd, capture_output=True, text=True,
                         timeout=seconds + 15).stdout
    schema = {}
    for line in out.splitlines():
        topic, _, payload = line.partition(" ")
        if not topic:
            continue
        try:
            shape = json_schema(json.loads(payload))
        except (json.JSONDecodeError, ValueError):
            shape = "num" if payload.replace(".", "", 1).lstrip("-").isdigit() else "str"
        prev = schema.get(topic)
        if prev is not None and prev != shape:
            shape = f"{prev} | {shape}" if shape not in prev else prev
        schema[topic] = shape
    return schema


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outfile")
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args()
    schema = capture(args.seconds)
    if not schema:
        print("ERROR: nothing captured — broker down or no polling?", file=sys.stderr)
        return 2
    out = Path(args.outfile)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(f"{t} {s}\n" for t, s in sorted(schema.items())))
    print(f"{len(schema)} topics → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
