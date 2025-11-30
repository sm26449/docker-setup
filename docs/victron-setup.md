# Victron Energy Integration Guide

Ghid complet pentru monitorizarea sistemelor Victron Energy folosind Telegraf și InfluxDB.

## Arhitectură

```
┌─────────────────┐     MQTT      ┌──────────┐     InfluxDB    ┌──────────┐
│   Venus OS      │──────────────▶│ Telegraf │───────────────▶│ InfluxDB │
│   (Cerbo GX)    │   SSL:8883    │          │    HTTP:8086    │          │
└─────────────────┘               └──────────┘                 └──────────┘
                                                                     │
                                                                     ▼
                                                               ┌──────────┐
                                                               │ Grafana  │
                                                               │          │
                                                               └──────────┘
```

## Cerințe

### Hardware
- Victron GX device (Cerbo GX, Venus GX, Raspberry Pi cu Venus OS)
- Server pentru Docker (Linux)

### Software
- Venus OS cu MQTT activat
- Docker & Docker Compose
- Telegraf, InfluxDB, Grafana (instalate via docker-setup)

## Configurare Venus OS

### 1. Activare MQTT

Pe Venus OS (via Remote Console sau display local):
```
Settings → Services → MQTT on LAN → Enabled
```

### 2. Securitate MQTT

**SSL/TLS (Recomandat):**
- Port: 8883
- Venus OS folosește certificate self-signed
- Telegraf: `insecure_skip_verify = true`

**Fără SSL:**
- Port: 1883
- Nu necesită configurare TLS

### 3. Găsire Portal ID

```
Settings → VRM Online Portal → VRM Portal ID
```

Format: 12 caractere hexadecimale (ex: `xxxxxxxxxxxx`)

## Configurare Docker Setup

### 1. Instalare servicii necesare

```bash
sudo ./install.sh
# Opțiunea 2 - Add Services
# Selectează: influxdb, telegraf, grafana
```

### 2. Configurare Telegraf pentru Victron

```bash
sudo ./install.sh
# Opțiunea 12 - Telegraf Config
# Opțiunea 1 - Select Operation Mode
# Selectează: 2 (Victron Energy)
```

### 3. Configurare pas cu pas

1. **Portal ID:**
   ```
   Portal ID: xxxxxxxxxxxx
   ```

2. **Selectare dispozitive:**
   - Battery Monitor: Y
   - PV Inverter: Y
   - Inverter/Charger (MultiPlus): Y
   - System overview: Y
   - Grid meter: Y
   - Temperature sensors: Y

3. **Configurare MQTT:**
   ```
   Server: ssl://192.168.88.250:8883
   Skip TLS verification: Y (pentru Venus OS)
   ```

4. **Configurare InfluxDB:**
   ```
   URL: http://influxdb:8086
   Organization: PV-Stack
   Bucket: telegraf
   Token: <your-token>
   ```

## Structura Topic-uri MQTT

Venus OS publică date în format:
```
N/<portal_id>/<device_type>/<instance>/<path>
```

### Exemple:

```
N/xxxxxxxxxxxx/battery/512/Soc                    → State of Charge
N/xxxxxxxxxxxx/battery/512/Voltage                → Tensiune baterie
N/xxxxxxxxxxxx/pvinverter/20/Ac/Power             → Putere PV
N/xxxxxxxxxxxx/grid/30/Ac/Power                   → Putere grid
N/xxxxxxxxxxxx/temperature/26/Temperature         → Temperatură sensor
N/xxxxxxxxxxxx/vebus/276/Ac/ActiveIn/L1/P         → Putere intrare MultiPlus
N/xxxxxxxxxxxx/system/0/Dc/Battery/Power          → Putere baterie (system)
```

### Payload JSON:

```json
{"value": 85.5}        // Numeric
{"value": "Charging"}  // String
```

## Configurare Telegraf (telegraf.conf)

Configurația generată automat:

```toml
[[inputs.mqtt_consumer]]
  servers = ["ssl://192.168.88.250:8883"]

  # Topics pentru diferite adâncimi de path
  topics = [
    "N/xxxxxxxxxxxx/+/+/+",
    "N/xxxxxxxxxxxx/+/+/+/+",
    "N/xxxxxxxxxxxx/+/+/+/+/+",
    "N/xxxxxxxxxxxx/+/+/+/+/+/+",
  ]

  # TLS pentru Venus OS (certificate self-signed)
  insecure_skip_verify = true

  # Format date
  data_format = "json"

  # Parsing topic - device_type devine measurement
  [[inputs.mqtt_consumer.topic_parsing]]
    topic = "N/+/+/+/+"
    measurement = "_/_/measurement/_/_"
    tags = "_/portal_id/_/instance/field"
```

## Query-uri InfluxDB

### InfluxDB 2.x (Flux)

```flux
// Toate datele battery din ultima oră
from(bucket: "telegraf")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "battery")

// SOC baterie
from(bucket: "telegraf")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "battery")
  |> filter(fn: (r) => r.field == "Soc")

// Putere PV
from(bucket: "telegraf")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "pvinverter")
  |> filter(fn: (r) => r.field == "Ac" and r.subfield == "Power")
```

### InfluxDB 1.x (InfluxQL)

```sql
-- Toate datele battery
SELECT * FROM "battery" WHERE time > now() - 1h

-- SOC baterie
SELECT "value" FROM "battery" WHERE "field" = 'Soc' AND time > now() - 24h

-- Temperaturi
SELECT * FROM "temperature" WHERE time > now() - 1h
```

## Troubleshooting

### Verificare conexiune MQTT

```bash
# Test cu mosquitto_sub
mosquitto_sub -h 192.168.88.250 -p 8883 \
  --capath /etc/ssl/certs/ \
  --insecure \
  -t "N/xxxxxxxxxxxx/#" -v

# Sau fără SSL
mosquitto_sub -h 192.168.88.250 -p 1883 -t "N/#" -v
```

### Verificare Telegraf

```bash
# Vezi logs
docker logs telegraf -f

# Test configurație
docker exec telegraf telegraf --config /etc/telegraf/telegraf.conf --test
```

### Erori comune

| Eroare | Cauză | Soluție |
|--------|-------|---------|
| `connection reset by peer` | TLS fără insecure_skip_verify | Adaugă `insecure_skip_verify = true` |
| `organization not found` | Nume organizație greșit | Verifică case sensitivity (PV-Stack vs pv-stack) |
| `no data in InfluxDB` | Topics greșite | Verifică Portal ID și wildcard patterns |
| `parsing error` | Date mixte (string/float) | Folosește `data_format = "json"` |

## Measurements și Fields

### battery
- `Soc` - State of Charge (%)
- `Voltage` - Tensiune (V)
- `Current` - Curent (A)
- `Power` - Putere (W)
- `Temperature` - Temperatură (°C)

### pvinverter
- `Ac/Power` - Putere AC totală (W)
- `Ac/L1/Power` - Putere L1 (W)
- `Ac/Energy/Forward` - Energie produsă (kWh)

### grid
- `Ac/Power` - Putere grid (W)
- `Ac/L1/Power` - Putere L1 (W)
- `Ac/Energy/Forward` - Energie consumată (kWh)
- `Ac/Energy/Reverse` - Energie exportată (kWh)

### vebus (MultiPlus)
- `Ac/ActiveIn/L1/P` - Putere intrare (W)
- `Ac/Out/L1/P` - Putere ieșire (W)
- `Dc/0/Voltage` - Tensiune DC (V)
- `State` - Stare (0=Off, 2=Inverting, 3=Charging)

### system
- `Dc/Battery/Power` - Putere baterie (W)
- `Dc/Pv/Power` - Putere PV DC (W)
- `Ac/Consumption/L1/Power` - Consum AC (W)
- `Ac/Grid/L1/Power` - Putere grid (W)

### temperature
- `Temperature` - Temperatură (°C)
- `Humidity` - Umiditate (%) - pentru senzori Ruuvi

## Resurse

- [Venus OS MQTT Documentation](https://github.com/victronenergy/venus/wiki/dbus)
- [dbus-mqtt module](https://github.com/victronenergy/dbus-mqtt)
- [Victron Modbus TCP FAQ](https://www.victronenergy.com/live/ccgx:modbustcp_faq)
- [Telegraf MQTT Consumer](https://github.com/influxdata/telegraf/tree/master/plugins/inputs/mqtt_consumer)
