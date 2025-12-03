# Docker Services Manager v2.2


Script interactiv profesional pentru gestionarea serviciilor Docker pe Ubuntu/CentOS/Rocky/Alma Linux.

**Nou în v2.2:** Sistem de variante pentru template-uri, suport Fronius Modbus MQTT.

**v2.1:** Integrare Victron Energy, configurare modulară Telegraf, suport Modbus/Serial.

## Caracteristici

- **Setup Server**: Instalează Docker, Docker Compose și dependențele necesare
- **Add Services**: Provizionare containere cu dependențe automate
- **Remove Services**: Oprire și ștergere servicii
- **Define Template**: Creare template-uri pentru servicii noi
- **Backup Config**: Backup configurări existente
- **Initial Setup Wizard**: Configurare automată la prima rulare

## Caracteristici v2.2

- **Sistem de variante**: Multiple configurații pentru același serviciu (ex: `telegraf:docker`, `telegraf:victron`)
- **Fronius Modbus MQTT**: Monitorizare invertoare și smartmeter Fronius
- **Smart dependency detection**: Detectare automată containere existente pentru dependențe

## Caracteristici v2.0

- **Director de stocare configurabil** (default: `/docker-storage`)
- **Auto-detectare PUID/PGID** din utilizatorul curent
- **Auto-detectare timezone** din sistem
- **Network Docker dedicat** cu subnet configurabil
- **Structură per container**: `{service}/{config,data,logs}`
- **Parole**: opțiune auto-generare sau manual
- **Verificare disponibilitate porturi** înainte de alocare
- **Afișare credențiale** la finalul instalării

## Instalare rapidă

```bash
# Clone sau download
cd /opt
git clone <repository> docker-setup
cd docker-setup

# Rulare
sudo ./install.sh
```

## Utilizare

### 1. Setup Server (prima rulare)

```bash
sudo ./install.sh
# Selectează opțiunea 1 - Setup Server
# Apoi opțiunea 1 - Full Setup
```

Aceasta va instala:
- Docker Engine
- Docker Compose V2
- Utilitare sistem (htop, git, curl, etc.)
- Configurare firewall (opțional)

### 2. Adăugare Servicii

```bash
sudo ./install.sh
# Selectează opțiunea 2 - Add Services
```

Funcționalități:
- Selectare multiplă (ex: `1,3,5-8` sau `all`)
- Detectare automată dependențe
- Configurare variabile per serviciu
- Generare automată parole
- Păstrare configurări existente

### 3. Servicii Disponibile

| Serviciu | Descriere | Port implicit |
|----------|-----------|---------------|
| portainer | Docker management UI | 9000 |
| nginx-proxy-manager | Reverse proxy cu SSL | 81 |
| homeassistant | Home automation | 8123 |
| grafana | Dashboards & vizualizare | 3000 |
| influxdb | Time-series database | 8086 |
| mariadb | MySQL-compatible DB | 3306 |
| mosquitto | MQTT broker | 1883 |
| nodered | Flow-based programming | 1880 |
| pihole | Network ad-blocking | 8089 |
| vaultwarden | Password manager | 8082 |
| watchtower | Auto-update containers | - |
| uptime-kuma | Status monitoring | 3001 |
| n8n | Workflow automation | 5678 |
| redis | In-memory cache | 6379 |
| mongodb | NoSQL database | 27017 |
| phpmyadmin | MySQL web admin | 8081 |
| filebrowser | Web file manager | 8085 |
| duplicati | Backup solution | 8200 |
| gotify | Push notifications | 8083 |
| heimdall | Application dashboard | 8084 |
| glances | System monitoring | 61208 |
| node-exporter | Prometheus metrics | 9100 |
| vscode | VS Code in browser | 8443 |
| wireguard | VPN server | 51820 |
| zigbee2mqtt | Zigbee bridge | 8088 |
| esphome | ESP firmware builder | 6052 |
| mqtt-explorer | MQTT client | 4000 |
| telegraf | Metrics collector (variante: docker, victron, system) | - |
| fronius-modbus-mqtt | Fronius Modbus MQTT (variante: all, inverters, meter) | - |
| mbusd | Modbus TCP gateway | 502 |
| ser2net | Serial to network | 3000 |
| influxdb1 | InfluxDB 1.x | 8086 |
| tasmoadmin | Tasmota management | 8087 |
| seplos-modbus-mqtt | Seplos BMS monitoring | - |

> **Notă:** Template-urile `fronius-modbus-mqtt` și `seplos-modbus-mqtt` necesită clonarea repository-urilor externe. Vezi secțiunea [Template-uri cu Repository Extern](#template-uri-cu-repository-extern).

### 4. Configurare Telegraf (Victron Energy)

Telegraf suportă mai multe moduri de funcționare:

```bash
sudo ./install.sh
# Selectează opțiunea 12 - Telegraf Config
```

**Moduri disponibile:**

| Mod | Descriere |
|-----|-----------|
| Docker | Metrici sistem + containere Docker |
| Victron | Monitorizare Venus OS via MQTT |
| System | Doar metrici sistem (CPU, RAM, disk) |
| Custom | Configurare manuală |

**Configurare Victron Energy:**

1. **Cerințe:**
   - Venus OS cu MQTT activat (port 8883 SSL sau 1883)
   - Portal ID (din Settings → VRM Online Portal)
   - InfluxDB pentru stocare date

2. **Dispozitive suportate:**
   - Battery Monitor (BMV/SmartShunt)
   - PV Inverter (Fronius, SMA, etc.)
   - Inverter/Charger (MultiPlus/Quattro)
   - Grid Meter
   - Temperature Sensors (Ruuvi)
   - Solar Charger (MPPT)
   - System Overview

3. **Configurare MQTT:**
   ```
   Server: ssl://192.168.x.x:8883
   Portal ID: c0619ab7xxxx (12 caractere hex)
   TLS: Auto-activat insecure_skip_verify pentru Venus OS
   ```

4. **Query-uri InfluxDB simplificate:**
   ```sql
   -- Toate datele battery
   SELECT * FROM "battery"

   -- Toate datele grid
   SELECT * FROM "grid"

   -- Filtrare pe instanță
   SELECT * FROM "temperature" WHERE instance = '26'
   ```

### 5. Structura Directoare

**Script:**
```
docker-setup/
├── install.sh           # Script principal
├── docker-compose.yml   # Generat automat
├── .env                 # Variabile de mediu
├── lib/                 # Biblioteci funcții
│   ├── config.sh        # Configurare globală
│   ├── utils.sh         # Funcții utilitare
│   ├── server_setup.sh  # Setup server
│   ├── services.sh      # Gestionare servicii
│   ├── templates.sh     # Parsare template-uri
│   ├── credentials.sh   # Parole și secrete
│   ├── maintenance.sh   # Backup, diagnostice
│   ├── container_settings.sh  # Setări containere
│   └── telegraf.sh      # Configurare Telegraf
└── templates/           # Template-uri servicii
    ├── portainer/
    │   ├── container.yaml
    │   └── docker-compose.yaml
    └── ...
```

**Container Data (DOCKER_ROOT):**
```
/docker-storage/           # Sau alt path configurat
├── portainer/
│   ├── config/
│   ├── data/
│   └── logs/
├── grafana/
│   ├── config/
│   ├── data/
│   └── logs/
├── homeassistant/
│   ├── config/
│   ├── data/
│   └── logs/
└── ...
```

### 5. Creare Template Nou

```bash
sudo ./install.sh
# Selectează opțiunea 4 - Define Template
# Apoi opțiunea 1 - Create New Template (Interactive)
```

Sau opțiunea 6 pentru a inițializa toate template-urile implicite.

## Fișiere de configurare

### .env (exemplu)
```bash
# Docker storage directory
DOCKER_ROOT=/docker-storage

# User/Group IDs (auto-detected)
PUID=1000
PGID=1000

# Timezone (auto-detected)
TZ=Europe/Bucharest

# Docker network
DOCKER_NETWORK=docker-services
DOCKER_SUBNET=172.20.0.0/16

# Service ports
GRAFANA_PORT=3000
PORTAINER_PORT=9000

# Service passwords (auto-generated)
GF_SECURITY_ADMIN_PASSWORD=xK9#mP2@nL5vQ8wR
MYSQL_ROOT_PASSWORD=hT3$jN7@kM9pL2xR
```

### container.yaml (exemplu)
```yaml
name: myservice
description: "Service description"
image: user/image:latest
restart: unless-stopped

ports:
  - "8080:80"

volumes:
  - "${DOCKER_ROOT}/myservice/config:/config"
  - "${DOCKER_ROOT}/myservice/data:/data"

dependencies:
  - mariadb
  - redis

variables:
  MYSERVICE_PORT:
    default: "8080"
    description: "Web port"
  MYSERVICE_PASSWORD:
    default: ""
    description: "Admin password"
    generate: password
```

## Comenzi Docker utile

```bash
# Pornire toate serviciile
docker compose up -d

# Oprire toate serviciile
docker compose down

# Vezi logs
docker compose logs -f [service]

# Restart serviciu
docker compose restart [service]

# Pull imagini noi
docker compose pull
```

## Backup & Restore

### Backup
```bash
# Din meniu: opțiunea 6 - Backup Config
# Sau manual:
tar -czf backup_$(date +%Y%m%d).tar.gz .env docker-compose.yml config/ templates/
```

### Restore
```bash
tar -xzf backup_YYYYMMDD.tar.gz
```

## Troubleshooting

### Docker nu pornește
```bash
sudo systemctl status docker
sudo systemctl start docker
sudo journalctl -u docker
```

### Permisiuni fișiere
```bash
sudo chown -R $USER:$USER config/ data/
```

### Reset complet
```bash
docker compose down -v
rm -rf config/* data/*
rm .env docker-compose.yml
```

## Template-uri cu Repository Extern

Anumite template-uri necesită clonarea repository-urilor externe înainte de utilizare:

### Fronius Modbus MQTT

Monitorizare invertoare și smart meter-e Fronius via Modbus TCP.

```bash
cd /opt/
git clone https://github.com/sm26449/fronius-modbus-mqtt.git
cp -r fronius-modbus-mqtt/* docker-setup/templates/fronius/
```

**Variante disponibile:**
- `fronius` - Monitorizare completă (invertoare + meter)
- `fronius:inverters` - Doar invertoare
- `fronius:meter` - Doar smart meter

Vezi `templates/fronius/INTEGRATION.md` pentru detalii.

### Seplos Modbus MQTT

Monitorizare baterii Seplos BMS V3 via RS485.

```bash
cd /opt/
git clone https://github.com/sm26449/seplos-modbus-mqtt.git
cp -r seplos-modbus-mqtt/* docker-setup/templates/seplos-modbus-mqtt/
```

**Cerințe hardware:**
- Adaptor RS485 to USB
- Seplos BMS V3 conectat via RS485

Vezi `templates/seplos-modbus-mqtt/INTEGRATION.md` pentru detalii.

## Cerințe sistem

- Ubuntu 20.04+ / Debian 11+ / CentOS 8+ / Rocky 8+ / Alma 8+
- 2GB RAM minim (4GB recomandat)
- 20GB spațiu disk minim
- Acces root/sudo

## Autor

**Stefan M** - [sm26449@diysolar.ro](mailto:sm26449@diysolar.ro)

## Licență

MIT License
