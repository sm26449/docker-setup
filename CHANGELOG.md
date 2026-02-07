# Changelog

All notable changes to Docker Services Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.7.0] - 2026-02-07

### Added
- **PV-Stack UI Template** (`templates/pv-stack-ui/service.yaml`)
  - Flask dashboard for home solar energy monitoring and control
  - Dependencies: mosquitto (MQTT credentials auto-filled), influxdb (token/org auto-filled)
  - 10 prompted variables: port, Node-RED (URL, user, pass), auth (enabled, user, pass), WebAuthn (domain, origin), allowed origins
  - 24 silent variables with defaults: InfluxDB buckets (7), MQTT settings, SocketIO, rate limits, session, maintenance
  - 48 environment variables total — full parity with pv-stack-ui docker-compose.yml
  - Healthcheck via `/api/health` endpoint
  - Persistent data volume for auth.db, analytics.db, secret key

## [2.6.0] - 2026-01-09

### Added
- **Multiple Service Instances**
  - Deploy multiple instances of the same service (e.g., mariadb, mariadb_2, mariadb_3)
  - Automatic instance numbering when adding services already in stack
  - Unique variable names per instance (MARIADB_PORT_2, MYSQL_PASSWORD_2, etc.)
  - Each instance gets its own data directory and container name

- **Port Conflict Detection**
  - Pre-deployment port conflict check between selected services
  - Detection of conflicts with running containers on the host
  - Interactive resolution: choose new port or skip for manual handling
  - Validates new port isn't already in use

- **Template Variable Prompts**
  - Added `prompt: true` to important variables across all templates
  - Users are now prompted for database credentials, ports, and key settings
  - Affected templates: mariadb, influxdb1, mongodb, gotify, n8n, pihole, vscode, redis, uptime-kuma, vaultwarden, zigbee2mqtt

### Changed
- **phpmyadmin**: Default port changed from 8081 to 8084 (avoids conflict with grafana-image-renderer)
- **Template Dependencies**: Cleaned up dependency variable mappings in mqtt-explorer, homeassistant, grafana, zigbee2mqtt, telegraf, seplos-modbus-mqtt, phpmyadmin, fronius templates

### Fixed
- **SERVICE_NAME substitution**: Fixed regex pattern to correctly detect `${SERVICE_NAME}:` in compose blocks
- **Variable suffix handling**: Instance-specific variables (_2, _3) are now correctly preserved through compose generation
- **Port conflict check**: Now includes containers from same stack (not just external containers)

## [2.5.3] - 2026-01-09

### Changed
- **SERVICE_NAME Variable Support in Templates**
  - All templates now use `${SERVICE_NAME}` instead of hardcoded service names
  - Enables service renaming and multiple instances of the same service type
  - Volume paths use `${DOCKER_ROOT}/${SERVICE_NAME}/` for automatic path resolution
  - Container names use `${SERVICE_NAME}` for consistency

### Added
- **Automatic SERVICE_NAME Substitution**
  - `lib/services.sh` now substitutes `${SERVICE_NAME}` when generating compose files
  - Template generators in `lib/templates.sh` use the new pattern by default

### Benefits
- **Multiple Instances**: Deploy multiple instances of the same service (e.g., `redis-cache`, `redis-session`)
- **Custom Naming**: Rename services without editing templates (e.g., `my-grafana` instead of `grafana`)
- **Consistent Paths**: Data directories automatically match service names
- **Easier Migrations**: Move or rename services without path conflicts

## [2.5.2] - 2026-01-07

### Fixed
- **Dependency Resolution Exit Bug**
  - Script no longer exits when selecting "Create NEW container" during dependency resolution
  - Properly captures return codes without triggering `set -e` exit
  - Fixed grep commands in port extraction that could cause script termination
- **Service Configuration Order**
  - Dependencies (influxdb, mosquitto) are now configured BEFORE dependent services
  - Topological sort order is preserved when adding Portainer recommendation
  - Ensures tokens and credentials are available when configuring dependent services

### Changed
- **Global Settings Prompt**
  - "Modify global settings?" now defaults to No instead of Yes

## [2.5.1] - 2026-01-04

### Added
- **InfluxDB Healthcheck**
  - Added healthcheck to influxdb template (`influx ping`)
  - Enables `condition: service_healthy` for dependent services

### Changed
- **Service Dependencies with Health Conditions**
  - Fronius templates now wait for InfluxDB to be healthy before starting
  - Seplos template now waits for InfluxDB to be healthy before starting
  - Uses `depends_on` with `condition: service_healthy` for influxdb
  - Uses `condition: service_started` for mosquitto (no healthcheck needed)

### Fixed
- Services no longer fail to connect to InfluxDB on stack restart
- Proper startup order ensures InfluxDB is ready before dependent services start

## [2.5.0] - 2026-01-03

### Added
- **Deployment Strategy Selection**
  - Interactive prompt when starting services with 3 strategies:
    - "Only new services" (default) - starts only newly added services
    - "All services (no recreate)" - starts all but doesn't recreate existing containers
    - "All services (recreate if changed)" - original behavior
  - Prevents accidental recreation of running containers when adding new services
  - New `get_compose_service_name()` helper function for service name extraction
- **pv-stack.sh Management Script**
  - Standalone helper script for common pv-stack operations
  - Commands: restart, recreate, logs, status, list, up, down, pull
  - Clear guidance on when to use restart vs recreate
- **Mosquitto Victron Variant** (`service.victron.yaml`)
  - MQTT bridge template for Venus OS integration
  - Automatic keepalive and SSL support

### Changed
- **Fronius Templates**
  - Added post-deploy hook to auto-create InfluxDB bucket
  - Added `PING_CHECK_ENABLED=false` environment variable
- **Telegraf Victron Template**
  - Improved configuration and documentation
- **Gitignore Updates**
  - External projects (fronius, seplos-modbus-mqtt) source files now ignored
  - Only `service*.yaml` and `INTEGRATION.md` are tracked for integration

### Fixed
- Container conflict errors when adding new services to existing stack
- Unnecessary recreation of healthy containers during service additions

## [2.4.0] - 2025-12-03

### Added
- **Mosquitto Bridge Auto-Configuration**
  - Pre-deploy hooks generate `mosquitto.conf` with all variables substituted
  - Automatic SSL certificate download from remote broker
  - Support for self-signed certificates with `bridge_insecure` option
- **Docker Network Setup Service**
  - Systemd service (`docker-network-setup.service`) for persistent network config
  - Automatic IP forwarding and masquerade rules at boot
  - Works with all Docker network subnets
- **Environment Variable Substitution Function**
  - `substitute_env_vars()` in utils.sh for template processing

### Changed
- **Dependency Resolution Improvements**
  - Pre-populate `DEPENDENCY_CONNECTIONS` for services already in `SELECTED_SERVICES`
  - Fixed credential mapping when dependencies are selected simultaneously
  - InfluxDB token/org now correctly passed to dependent services (seplos, fronius, etc.)
- **Hook System Improvements**
  - `run_service_hooks()` now extracts `compose_service_name` from template
  - Correct path resolution for variant services (e.g., `mosquitto-bridge` vs `mosquitto`)
  - Proper `SERVICE_DATA` and `CONTAINER_NAME` substitution in hooks
- **Grafana Template**
  - Dynamic InfluxDB datasource UID using `GRAFANA_INFLUXDB_UID` variable
  - Fixes hardcoded datasource references

### Fixed
- **Seplos MQTT Credentials**
  - Removed automatic MQTT credential copy from mosquitto dependency
  - Allows setting separate MQTT user/password for seplos service
  - Post-deploy hook creates user in mosquitto container
- **Fronius Example Config**
  - Changed default InfluxDB URL from `localhost` to `influxdb` (Docker container name)
- **Fresh Install Variable Population**
  - `SEPLOS_INFLUXDB_TOKEN`, `SEPLOS_INFLUXDB_ORG` now correctly populated
  - `SEPLOS_MQTT_SERVER` uses container name instead of `localhost`

## [2.3.0] - 2024-12-03

### Added
- **SERVER_IP Variable** - Global server IP for service-to-service communication
  - Required for Grafana Image Renderer to work correctly in browser
  - Added to `.env` template and service configurations

### Changed
- **Grafana Template Improvements**
  - `updateIntervalSeconds: 0` - Allows saving provisioned dashboards from UI
  - `allowUiUpdates: true` - Enables dashboard modifications in Grafana UI
  - Renderer URLs now use `${SERVER_IP}` instead of container hostnames
  - Added `hostname: grafana` for consistent container naming
- **Grafana Image Renderer Template**
  - Added rendering configuration variables:
    - `RENDERING_MODE` (default: clustered)
    - `RENDERING_CLUSTERING_MODE` (default: context)
    - `RENDERING_CLUSTERING_MAX_CONCURRENCY` (default: 5)
  - URLs use `${SERVER_IP}:${RENDERING_PORT}` for browser compatibility

### Fixed
- **Critical Security Fix in `lib/utils.sh`**
  - `set_env_var()` function rewritten to avoid sed injection vulnerabilities
  - Special characters in values (spaces, quotes, semicolons, etc.) now handled safely
  - Uses while-loop instead of sed for reliable variable updates
- **Code Injection Prevention in `lib/services.sh`**
  - Replaced unsafe `eval echo` with manual variable substitution
  - Pattern: `while [[ "$value" =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]` for safe expansion
- **Dependency Resolution Warning**
  - Added circular dependency detection in topological sort
  - Warns user when service order may not be optimal

### Updated
- **Seplos Modbus MQTT Template** (synced from seplos-modbus-mqtt v2.5)
  - Thread safety: Added `threading.Lock()` for battery data access
  - Config path fix: Added `/app/config/seplos_bms_mqtt.ini` to search paths
  - Version consistency: All files now report v2.5

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
| 2.7.0 | 2026-02-07 | PV-Stack UI template (Flask dashboard, 48 env vars, mosquitto+influxdb deps) |
| 2.6.0 | 2026-01-09 | Multiple instances per service, port conflict detection, template prompts |
| 2.5.0 | 2026-01-03 | Deployment strategy selection, pv-stack.sh helper, Mosquitto Victron variant |
| 2.4.0 | 2025-12-03 | Mosquitto bridge auto-config, dependency resolution fixes, hook improvements |
| 2.3.0 | 2024-12-03 | Security fixes, Grafana renderer improvements, SERVER_IP support |
| 2.2.0 | 2024-11-30 | Template variants, Fronius Modbus MQTT, Seplos Modbus MQTT |
| 2.1.0 | 2024-11-27 | Victron Energy integration, Telegraf modes |
| 2.0.0 | 2024-11-26 | Complete rewrite, modular architecture |
| 1.0.0 | 2024-11-01 | Initial release |
