# multi-bus-gateway-esphome: Docker Setup Integration

This template runs [multi-bus-gateway-esphome](/home/stefanm/multi-bus-gateway-esphome), the ESP nodes service. It
flashes ESPs from the browser, lists the nodes and sends them commands and pull updates. It is served at
`https://mbus.diysolar.ro/nodes/`, behind the Multi-Bus Gateway's login.

The service's own documentation is in its repository (`docs/README.md`). This file covers only what this stack has to
provide.

## Files in this folder

| File | Committed here | What it is |
|---|---|---|
| `service.yaml` | yes | the service fragment: dependencies, variables, volumes |
| `INTEGRATION.md` | yes | this file |
| everything else | no (git-ignored) | an **rsync copy** of the service repository; compose builds from it |

## Deploy

```sh
cd /home/stefanm
rsync -a --delete --exclude .git --exclude __pycache__ --exclude .pytest_cache --exclude .ruff_cache \
      --exclude service.yaml --exclude INTEGRATION.md \
      multi-bus-gateway-esphome/ docker-setup/templates/multi-bus-gateway-esphome/
cd docker-setup
docker compose -f docker-compose.pv-stack.yml build -q mbg-esphome
docker compose -f docker-compose.pv-stack.yml up -d --no-deps --force-recreate mbg-esphome
```

**Gotchas:**
- **The two `--exclude`s matter.** `service.yaml` and `INTEGRATION.md` exist only here, and `--delete` removes them
  without the excludes. It happened once (2026-10-10); `git checkout` restores them.
- **Editing the repository changes nothing in production until the rsync.**
- **A change to the basic image or the node core** also needs the images rebuilt and the nodes updated (the service's
  `docs/operations.md`).

## Compose service (`docker-compose.pv-stack.yml`, host-local)

| Setting | Value | Why |
|---|---|---|
| service / container | `mbg-esphome` / `pv-stack-mbg-esphome` | |
| build | `context: templates/multi-bus-gateway-esphome` | image `multi-bus-gateway-esphome:latest` |
| ports | **`8091:8091` only** | the update download server: one route, `GET /ota/<token>.bin`, tokens valid 15 min. Nodes behind NAT pull their updates from it. The app port **8090 must never be published**, because the app trusts the role headers Traefik sets |
| depends_on | `mosquitto`, `esphome` | |
| volume | `${DOCKER_ROOT}/pv-stack/mbg-esphome/data:/data` | `nodes.json`, `builds.json`. **Owned by uid 10001** (the image's user): `mkdir -p … && chown 10001:10001 …` before the first start |
| network | `pv-stack-network` (default) | reaches `pv-stack-esphome:6052`, `mosquitto:1883`; Traefik reaches it as `mbg-esphome:8090` |

Environment (values come from `.env`; never put them in the compose file):

| Variable | Set to | `.env` key |
|---|---|---|
| `ESPHOME_URL` | `http://pv-stack-esphome:6052` | — |
| `NODE_MQTT_HOST` | `${MBG_NODE_MQTT_HOST:-192.168.88.239}` | `MBG_NODE_MQTT_HOST` (optional) |
| `NODE_MQTT_PORT` | `1883` | — |
| `NODE_OTA_URL` | `http://${MBG_NODE_MQTT_HOST:-192.168.88.239}:8091` | — |
| `MQTT_HOST` / `MQTT_PORT` | `mosquitto` / `1883` | — |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | the service's own account | `MQTT_USERNAME`, `MQTT_PASSWORD` |
| `NODE_MQTT_USERNAME` / `NODE_MQTT_PASSWORD` | the node account | `MBG_NODE_MQTT_USERNAME`, `MBG_NODE_MQTT_PASSWORD` |
| `AUTH_MODE` | `forward` | — |
| `MBG_URL` | `http://multi-bus-gateway:8080` | — |
| `BUILDER_URL` | `/esphome/` | — (a link to Device Builder for admins) |

The service refuses to prepare images while `NODE_MQTT_*` is missing or equal to `MQTT_USERNAME`
(`GET /nodes/api/status` → `problems`).

## Traefik (`templates/traefik/config/dynamic/mbus.yml`)

Traefik watches the dynamic folder, so a copy to `${DOCKER_ROOT}/pv-stack/traefik/config/dynamic/` applies it live.

```yaml
http:
  routers:
    mbus-nodes:
      rule: "Host(`mbus.diysolar.ro`) && PathPrefix(`/nodes`)"
      priority: 100
      entryPoints: [websecure]
      middlewares: [mbg-login]
      service: mbus-nodes
      tls: { certResolver: cloudflare }
  middlewares:
    mbg-login:
      forwardAuth:
        address: "http://multi-bus-gateway:8080/api/auth/forward"
        authResponseHeaders: [X-Mbg-User, X-Mbg-Role]
  services:
    mbus-nodes:
      loadBalancer: { servers: [ { url: "http://mbg-esphome:8090" } ] }
```

Requires a Multi-Bus Gateway with `/api/auth/forward` and an absolute login redirect (commits `2a82232`, `8dd8985`).
To show the "ESP nodes" link on its Devices page, set `ui.nodes_url: /nodes/` in MBG's config (Settings → Security).

## ESPHome Device Builder (`esphome-builder`, the advanced editor)

| Setting | Value | Why |
|---|---|---|
| service / container | `esphome-builder` / `pv-stack-esphome-builder` | |
| image | `ghcr.io/esphome/esphome:2026.9.1` | from 2026.6 the stock image runs Device Builder as its dashboard |
| ports | **none** | it has no login; reached only through Traefik |
| volume | `${DOCKER_ROOT}/pv-stack/esphome/config:/config` | **the same folder** as `pv-stack-esphome`: both dashboards see the same files. Don't compile the same configuration from both at once (one build tree) |
| mem_limit | `6g` | firmware compiles spike memory |

Traefik router `mbus-esphome`:
- **rule:** `Path(/esphome) || PathPrefix(/esphome/)`, priority 100;
- **`esphome-slash`:** redirects `/esphome` → `/esphome/`;
- **`mbg-admin`:** forwardAuth `…/api/auth/forward?need=admin` (MBG `a5bda6f`); a viewer or operator gets 403;
- **`esphome-strip`:** `stripPrefix /esphome`, which also sets the `X-Forwarded-Prefix` Device Builder uses for
  `<base href>`.

On its first start it:
- turns `/config` into a git repository ("version history"). `secrets.yaml` and `.esphome/` are excluded by
  `/config/.gitignore`; check this before adding files;
- writes `.device-builder*` files;
- connects to the broker for MQTT discovery;
- listens on 6055 (remote builds; not published).

**Back up `/config` before changing its version:**
`tar -C ${DOCKER_ROOT}/pv-stack/esphome -czf …/config-backup-<ts>.tgz --exclude=config/.esphome config`.

## Mosquitto: the node account

Nodes connect as `mbg-node`. The account must be confined, because a board's flash can be read by whoever holds it.

1. **Back up** `${DOCKER_ROOT}/pv-stack/mosquitto/config/pwfile` and `aclfile` (`*.bak-<timestamp>`).
2. **The password:** generate a random one into `.env` as `MBG_NODE_MQTT_PASSWORD`, with
   `MBG_NODE_MQTT_USERNAME=mbg-node`. Do not print it.
3. **Add it to the broker:** `docker exec pv-stack-mosquitto mosquitto_passwd -b /mosquitto/config/pwfile mbg-node "$P"`,
   with `$P` read from `.env`.
4. **Append to `aclfile`:**
   ```
   user mbg-node
   topic write mbg/nodes/+/announce
   topic write mbg/nodes/+/event
   topic read mbg/nodes/+/cmd
   ```
5. **Reload:** `docker exec pv-stack-mosquitto sh -c 'kill -HUP 1'`. Existing clients stay connected.
6. **Check** that `mbg-node` can publish to `mbg/nodes/x/announce` and that a publish to any other topic is dropped.

Rotation without downtime (a second account) is described in the service's `docs/security.md`.

## Not covered here

- **The ESPHome dashboard** (`templates/esphome`, `pv-stack-esphome`, 2026.5.3) is the compiler. The service writes
  `mbg-bootstrap-*.yaml`, `.mbg-core.yaml` and the `mbg_*` keys of `secrets.yaml` into its `/config`.
- **Its `:6052` is no longer published** (closed 2026-10-10). It has no login, so it is reachable only on
  `pv-stack-network`; people edit through Device Builder behind the gateway's login.
