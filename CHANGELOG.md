# Changelog

All notable changes to Docker Services Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2024-11-30

### Added
- **Template Variant System** - Multiple configurations per service using `service.*.yaml` files
  - Single folder approach: all variants in same template directory
  - Naming convention: `service.yaml` (default), `service.inverters.yaml`, `service.meter.yaml`
  - Selection format: `servicename:variant` (e.g., `telegraf:docker`, `fronius:inverters`)
  - Automatic variant detection and menu display
- **Fronius Modbus MQTT** - Monitoring Fronius inverters and smart meters
  - Three variants: `all` (inverters + meter), `inverters`, `meter`
  - Native Modbus TCP support via pymodbus
  - MQTT publishing for Home Assistant integration
  - InfluxDB direct write support
  - Dockerfile with Python dependencies included
- **Seplos Modbus MQTT** - Battery management system monitoring template
- **Telegraf Variants** - Reorganized as separate variants:
  - `telegraf:docker` - System + Docker container metrics
  - `telegraf:victron` - Victron Venus OS MQTT monitoring
  - `telegraf:system` - Lightweight system metrics only

### Changed
- Variant templates now use consistent naming: compose service name = container_name = volume paths
- `get_service_variants()` function for detecting available variants
- `get_service_template_file()` for locating correct template file
- `get_base_service_name()` and `get_variant_name()` for parsing service:variant format
- Improved `compose_service_name` extraction from template's compose block
- Port availability check now correctly skips existing containers from dependencies

### Fixed
- Container naming for variant services (now uses compose_service_name from template)
- Dependency connections tracking for variant services (key lookup uses base_service)
- Dependencies not appearing in docker-compose.yml for variant services
- Port detection incorrectly flagging ports used by existing dependency containers
- Build context paths in templates (changed from `../service` to `.` for single-folder variants)

## [2.1.0] - 2024-11-27

### Added
- **Telegraf Multi-Mode Configuration** - New modular system supporting:
  - Docker mode: System + container metrics
  - Victron mode: Venus OS MQTT monitoring
  - System mode: Basic system metrics
  - Custom mode: Manual configuration
- **Victron Energy Integration**
  - MQTT consumer for Venus OS
  - Device types: battery, pvinverter, grid, system, temperature, vebus, solarcharger, gps, tank
  - Auto SSL/TLS configuration with `insecure_skip_verify` for self-signed certs
  - Topic parsing with device_type as measurement name for simpler InfluxDB queries
- **InfluxDB v1 Support** - Added `influxdb1` template alongside v2
- **Modbus/Serial Templates**
  - `mbusd` - Modbus TCP gateway for RS485 devices
  - `ser2net` - Serial to network proxy
- **Maintenance Module** (`lib/maintenance.sh`)
  - System diagnostics
  - Container log viewer
  - Docker cleanup utilities
  - Backup/restore functionality
- **Server Setup Enhancements**
  - System tuning options (sysctl, ulimits)
  - Firewall configuration helper

### Changed
- Telegraf template now includes all Victron variables
- Improved service installation flow with mode selection for Telegraf
- Better error handling in MQTT configuration

### Fixed
- TLS connection issues with Venus OS (self-signed certificates)
- JSON parsing for mixed Victron data types (float and string values)
- InfluxDB organization name case sensitivity

## [2.0.0] - 2024-11-26

### Added
- **Complete Rewrite** - Modular architecture with separate library files
- **Interactive Menus** - Full TUI-style navigation
- **Auto-Detection**
  - PUID/PGID from current user
  - Timezone from system
  - Available ports
- **33 Service Templates** including:
  - Portainer, Grafana, InfluxDB, Prometheus stack
  - Home Assistant, Node-RED, Zigbee2MQTT, ESPHome
  - MariaDB, MongoDB, Redis
  - Nginx Proxy Manager, Pi-hole, WireGuard
  - And many more...
- **Dependency Resolution** - Automatic installation of required services
- **Multi-Select Installation** - Install multiple services at once (e.g., `1,3,5-8`)
- **Credential Management**
  - Auto-generate secure passwords
  - Store in .env file
  - Display at installation completion
- **Docker Network** - Dedicated network with configurable subnet
- **Template System** - YAML-based service definitions

### Changed
- Storage structure: `${DOCKER_ROOT}/<service>/{config,data,logs}`
- Configuration via service.yaml instead of multiple files

## [1.0.0] - 2024-11-01

### Added
- Initial release
- Basic Docker installation
- Simple service deployment
- Manual configuration

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 2.2.0 | 2024-11-30 | Template variants, Fronius Modbus MQTT, Seplos Modbus MQTT |
| 2.1.0 | 2024-11-27 | Victron Energy integration, Telegraf modes |
| 2.0.0 | 2024-11-26 | Complete rewrite, modular architecture |
| 1.0.0 | 2024-11-01 | Initial release |
