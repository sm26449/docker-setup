# Mosquitto MQTT Broker - Integration Guide

This template provides two variants:
- **mosquitto** (default) - Standalone MQTT broker
- **mosquitto:bridge** - MQTT bridge to connect remote brokers locally

## Variants

### 1. Standalone Broker (`mosquitto`)

Basic MQTT broker with authentication. Use this when you need a local MQTT broker for your IoT devices.

```bash
# Install via Docker Services Manager
./install.sh
# Select: mosquitto
```

**Features:**
- Authentication required (username/password)
- WebSocket support (port 9001)
- Persistent message storage
- Logging to file and stdout

### 2. Bridge Mode (`mosquitto:bridge`)

Connects to a remote MQTT broker and mirrors topics locally. Clients connect to your local broker and access remote data transparently.

```bash
# Install via Docker Services Manager
./install.sh
# Select: mosquitto:bridge
```

**Features:**
- All standalone features, plus:
- Bridge to any remote MQTT broker
- SSL/TLS support with self-signed certificate handling
- Configurable topic mapping (in/out/both)
- Connection status monitoring
- Automatic reconnection

---

## Use Cases

### Victron Venus OS Integration

Bridge your Victron Energy system's MQTT data locally:

| Setting | Value |
|---------|-------|
| REMOTE_MQTT_HOST | `192.168.1.100` (Venus OS IP) |
| REMOTE_MQTT_PORT | `8883` |
| REMOTE_MQTT_USE_SSL | `true` |
| REMOTE_MQTT_INSECURE | `true` (Venus uses self-signed certs) |
| BRIDGE_NAME | `victron` |
| BRIDGE_TOPICS_IN | `N/c0619ab7d12b/#` (your portal ID) |
| BRIDGE_TOPICS_OUT | `W/c0619ab7d12b/#` (for write commands) |

**Finding your Portal ID:**
1. Venus OS → Settings → VRM Online Portal
2. Copy the 12-character hex ID (e.g., `c0619ab7d12b`)

**Available topics after bridge setup:**
```
N/<portal_id>/battery/#      - Battery data (SOC, voltage, current)
N/<portal_id>/grid/#         - Grid meter data
N/<portal_id>/pvinverter/#   - PV inverter data
N/<portal_id>/vebus/#        - MultiPlus/Quattro data
N/<portal_id>/system/#       - System overview
N/<portal_id>/temperature/#  - Temperature sensors
```

**Monitor bridge status:**
```bash
mosquitto_sub -h localhost -u mqtt -P password -t "bridge/victron/status" -v
# Output: bridge/victron/status 1  (connected)
# Output: bridge/victron/status 0  (disconnected)
```

### AWS IoT Core Integration

Bridge AWS IoT MQTT to local broker:

| Setting | Value |
|---------|-------|
| REMOTE_MQTT_HOST | `xxxxx.iot.region.amazonaws.com` |
| REMOTE_MQTT_PORT | `8883` |
| REMOTE_MQTT_USE_SSL | `true` |
| REMOTE_MQTT_INSECURE | `false` |
| BRIDGE_NAME | `aws` |
| BRIDGE_TOPICS_IN | `devices/#` |
| BRIDGE_TOPICS_OUT | `commands/#` |

> Note: AWS IoT requires certificate authentication. You'll need to mount certificates and modify the config.

### Home Assistant Integration

If Home Assistant runs on a different machine:

| Setting | Value |
|---------|-------|
| REMOTE_MQTT_HOST | `homeassistant.local` |
| REMOTE_MQTT_PORT | `1883` |
| REMOTE_MQTT_USE_SSL | `false` |
| REMOTE_MQTT_USERNAME | `ha_mqtt_user` |
| REMOTE_MQTT_PASSWORD | `ha_mqtt_pass` |
| BRIDGE_NAME | `homeassistant` |
| BRIDGE_TOPICS_IN | `homeassistant/#` |
| BRIDGE_TOPICS_OUT | `homeassistant/#` |

### Multi-Site Synchronization

Sync MQTT data between two locations:

**Site A (Main):**
```
BRIDGE_NAME=siteB
BRIDGE_TOPICS_IN=siteB/#
BRIDGE_TOPICS_OUT=siteA/#
```

**Site B (Remote):**
```
BRIDGE_NAME=siteA
BRIDGE_TOPICS_IN=siteA/#
BRIDGE_TOPICS_OUT=siteB/#
```

---

## Configuration Reference

### Local Broker Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `MQTT_PORT` | `1883` | Local MQTT port |
| `MQTT_WS_PORT` | `9001` | WebSocket port |
| `MQTT_USERNAME` | `mqtt` | Local authentication username |
| `MQTT_PASSWORD` | (generated) | Local authentication password |

### Remote Connection Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE_MQTT_HOST` | (required) | Remote broker hostname/IP |
| `REMOTE_MQTT_PORT` | `1883` | Remote broker port |
| `REMOTE_MQTT_USE_SSL` | `false` | Enable SSL/TLS |
| `REMOTE_MQTT_USERNAME` | (empty) | Remote authentication user |
| `REMOTE_MQTT_PASSWORD` | (empty) | Remote authentication pass |
| `REMOTE_MQTT_INSECURE` | `true` | Skip certificate verification |

### Bridge Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIDGE_NAME` | `remote` | Connection name (used in status topic) |
| `BRIDGE_TOPICS_IN` | `#` | Topics to subscribe from remote |
| `BRIDGE_TOPICS_OUT` | (empty) | Topics to publish to remote |
| `BRIDGE_LOCAL_PREFIX` | (empty) | Prefix added to local topics |
| `BRIDGE_QOS` | `1` | Quality of Service (0, 1, 2) |
| `BRIDGE_KEEPALIVE` | `60` | Keepalive interval (seconds) |
| `BRIDGE_RESTART_TIMEOUT` | `30` | Reconnect delay (seconds) |

---

## Topic Direction Explained

### `in` - Remote to Local
Subscribe to topics on the remote broker, publish them locally.
```
topic sensors/# in 1
# Remote: sensors/temp → Local: sensors/temp
```

### `out` - Local to Remote
Subscribe to topics locally, publish them to the remote broker.
```
topic commands/# out 1
# Local: commands/restart → Remote: commands/restart
```

### `both` - Bidirectional
Full two-way sync between brokers.
```
topic sync/# both 1
# Changes on either side are mirrored
```

### Using Prefixes
Add a prefix to distinguish remote topics locally:
```
BRIDGE_LOCAL_PREFIX=victron/
BRIDGE_TOPICS_IN=N/#

# Remote: N/xxx/battery/512/Soc
# Local:  victron/N/xxx/battery/512/Soc
```

---

## Monitoring & Troubleshooting

### Check Bridge Status
```bash
# Subscribe to bridge status
mosquitto_sub -h localhost -u mqtt -P yourpass -t "bridge/+/status" -v

# Check $SYS topics
mosquitto_sub -h localhost -u mqtt -P yourpass -t "\$SYS/broker/connection/#" -v
```

### View Logs
```bash
# Container logs
docker logs mosquitto-bridge -f

# Log file (if mounted)
tail -f /docker-storage/mosquitto-bridge/logs/mosquitto.log
```

### Test Remote Connection
```bash
# Test connection to remote broker manually
mosquitto_sub -h remote-host -p 8883 --capath /etc/ssl/certs --insecure -t "test/#" -v
```

### Common Issues

**Bridge not connecting:**
1. Check remote host is reachable: `ping remote-host`
2. Check port is open: `nc -zv remote-host 8883`
3. Verify credentials are correct
4. Check SSL settings match remote broker

**No messages appearing:**
1. Verify topic patterns match (wildcards: `+` single level, `#` multi-level)
2. Check QoS settings
3. Ensure remote broker has messages on those topics

**Connection drops frequently:**
1. Increase `BRIDGE_KEEPALIVE` value
2. Check network stability
3. Review remote broker connection limits

---

## Security Recommendations

1. **Always use authentication** - Never set `allow_anonymous true` in production
2. **Use SSL/TLS** when bridging over the internet
3. **Limit topic scope** - Only bridge topics you need
4. **Use read-only bridges** when you don't need to write to remote
5. **Firewall rules** - Restrict MQTT ports to trusted networks
6. **Rotate passwords** - Change credentials periodically

---

## File Locations

After installation, files are located at:
```
${DOCKER_ROOT}/<stack>/mosquitto-bridge/
├── config/
│   ├── mosquitto.conf    # Main configuration
│   └── pwfile            # Password file
├── data/
│   └── mosquitto.db      # Persistent storage
└── logs/
    └── mosquitto.log     # Log file
```

---

## Related Services

- **Telegraf** - Collect MQTT data into InfluxDB
- **Node-RED** - Process and route MQTT messages
- **Home Assistant** - Home automation with MQTT
- **MQTT Explorer** - Visual MQTT client for debugging
