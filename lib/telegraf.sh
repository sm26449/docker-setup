#!/bin/bash

#######################################
# Telegraf Configuration Module
# Modular configuration for different data sources
#######################################

# Available Telegraf modes
declare -A TELEGRAF_MODES=(
    ["docker"]="Docker & System Metrics"
    ["victron"]="Victron Energy (MQTT)"
    ["system"]="System Metrics Only"
    ["custom"]="Custom Configuration"
)

# Mode descriptions
declare -A TELEGRAF_MODE_DESC=(
    ["docker"]="Collect CPU, memory, disk, network, and Docker container metrics"
    ["victron"]="Collect data from Victron Energy systems via MQTT (Venus OS)"
    ["system"]="Basic system metrics: CPU, memory, disk, network"
    ["custom"]="Start with empty configuration for manual setup"
)

#######################################
# Main Telegraf configuration menu
#######################################
configure_telegraf_menu() {
    local stack="${CURRENT_STACK:-default}"

    while true; do
        print_header "Telegraf Configuration"

        echo -e "${CYAN}Stack: ${BOLD}${stack}${NC}"
        echo ""

        # Show current mode if configured
        local current_mode=$(get_env_var "TELEGRAF_MODE")
        if [[ -n "$current_mode" ]]; then
            echo -e "${GREEN}Current Mode: ${BOLD}${TELEGRAF_MODES[$current_mode]:-$current_mode}${NC}"
            echo ""
        fi

        echo -e "${CYAN}Options:${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Select Operation Mode"
        echo -e "  ${GREEN}2)${NC} Configure InfluxDB Output"
        echo -e "  ${GREEN}3)${NC} Configure MQTT Input (for Victron/other)"
        echo -e "  ${GREEN}4)${NC} View Current Configuration"
        echo -e "  ${GREEN}5)${NC} Regenerate Configuration"
        echo ""
        echo -e "  ${RED}0)${NC} Back"
        echo ""

        read -p "Select option: " choice

        case $choice in
            1) select_telegraf_mode ;;
            2) configure_influxdb_output ;;
            3) configure_mqtt_input ;;
            4) view_telegraf_config ;;
            5) regenerate_telegraf_config ;;
            0|"") return ;;
            *) print_error "Invalid option" ;;
        esac
    done
}

#######################################
# Select Telegraf operation mode
#######################################
select_telegraf_mode() {
    print_header "Select Telegraf Mode"

    echo -e "${CYAN}Available modes:${NC}"
    echo ""

    local i=1
    local modes=("docker" "victron" "system" "custom")

    for mode in "${modes[@]}"; do
        local name="${TELEGRAF_MODES[$mode]}"
        local desc="${TELEGRAF_MODE_DESC[$mode]}"
        local current=""

        if [[ "$(get_env_var TELEGRAF_MODE)" == "$mode" ]]; then
            current=" ${GREEN}[current]${NC}"
        fi

        echo -e "  ${GREEN}${i})${NC} ${BOLD}${name}${NC}${current}"
        echo -e "      ${YELLOW}${desc}${NC}"
        echo ""
        ((i++))
    done

    echo -e "  ${RED}0)${NC} Cancel"
    echo ""

    read -p "Select mode: " choice

    case $choice in
        1) set_telegraf_mode "docker" ;;
        2) set_telegraf_mode "victron" ;;
        3) set_telegraf_mode "system" ;;
        4) set_telegraf_mode "custom" ;;
        0|"") return ;;
        *) print_error "Invalid option" ;;
    esac
}

#######################################
# Set Telegraf mode and configure
#######################################
set_telegraf_mode() {
    local mode=$1

    print_info "Setting Telegraf mode to: ${TELEGRAF_MODES[$mode]}"
    set_env_var "TELEGRAF_MODE" "$mode"

    # Configure based on mode
    case $mode in
        docker)
            configure_docker_mode
            ;;
        victron)
            configure_victron_mode
            ;;
        system)
            configure_system_mode
            ;;
        custom)
            configure_custom_mode
            ;;
    esac

    # Always configure InfluxDB output
    echo ""
    if confirm "Configure InfluxDB output now?"; then
        configure_influxdb_output
    fi

    # Generate configuration file
    generate_telegraf_config "$mode"

    print_success "Telegraf mode set to: ${TELEGRAF_MODES[$mode]}"
    press_any_key
}

#######################################
# Configure Docker mode specific options
#######################################
configure_docker_mode() {
    print_header "Docker Mode Configuration"

    echo -e "${CYAN}Docker metrics collection options:${NC}"
    echo ""

    # Collection interval
    local current_interval=$(get_env_var "TELEGRAF_INTERVAL")
    current_interval=${current_interval:-"10s"}
    read -p "Collection interval [${current_interval}]: " input
    set_env_var "TELEGRAF_INTERVAL" "${input:-$current_interval}"

    # Docker metrics options
    echo ""
    echo -e "${CYAN}Include metrics for:${NC}"

    local include_cpu=$(get_env_var "TELEGRAF_DOCKER_CPU")
    include_cpu=${include_cpu:-"true"}
    if confirm "  CPU per container?" "Y"; then
        set_env_var "TELEGRAF_DOCKER_CPU" "true"
    else
        set_env_var "TELEGRAF_DOCKER_CPU" "false"
    fi

    local include_mem=$(get_env_var "TELEGRAF_DOCKER_MEM")
    include_mem=${include_mem:-"true"}
    if confirm "  Memory per container?" "Y"; then
        set_env_var "TELEGRAF_DOCKER_MEM" "true"
    else
        set_env_var "TELEGRAF_DOCKER_MEM" "false"
    fi

    local include_net=$(get_env_var "TELEGRAF_DOCKER_NET")
    include_net=${include_net:-"true"}
    if confirm "  Network per container?" "Y"; then
        set_env_var "TELEGRAF_DOCKER_NET" "true"
    else
        set_env_var "TELEGRAF_DOCKER_NET" "false"
    fi

    print_success "Docker mode configured"
}

#######################################
# Configure Victron mode
#######################################
configure_victron_mode() {
    print_header "Victron Mode Configuration"

    echo -e "${CYAN}Victron Energy MQTT Configuration${NC}"
    echo -e "${YELLOW}Your Victron device (Venus OS) publishes data via MQTT.${NC}"
    echo ""

    # MQTT will be configured via configure_mqtt_input
    # Here we set Victron-specific options

    # Victron Portal ID
    local current_portal=$(get_env_var "VICTRON_PORTAL_ID")
    echo -e "${CYAN}Victron Portal ID:${NC}"
    echo -e "${YELLOW}Found in Venus OS: Settings → VRM Online Portal → VRM Portal ID${NC}"
    echo -e "${YELLOW}Format: usually like 'c0619ab12345' (12 hex characters)${NC}"
    echo ""
    read -p "Portal ID [${current_portal:-auto-detect}]: " input
    if [[ -n "$input" ]]; then
        set_env_var "VICTRON_PORTAL_ID" "$input"
    elif [[ -z "$current_portal" ]]; then
        set_env_var "VICTRON_PORTAL_ID" "+"  # Wildcard to match any
        print_info "Using wildcard (+) to match any Portal ID"
    fi

    echo ""

    # Victron device types to monitor
    echo -e "${CYAN}Select devices to monitor:${NC}"
    echo ""

    # Battery Monitor (BMV/SmartShunt)
    if confirm "  Battery Monitor (BMV/SmartShunt)?" "Y"; then
        set_env_var "VICTRON_MONITOR_BATTERY" "true"
    else
        set_env_var "VICTRON_MONITOR_BATTERY" "false"
    fi

    # PV Inverter (Fronius, SMA, etc.)
    if confirm "  PV Inverter (Fronius, SMA, etc.)?" "Y"; then
        set_env_var "VICTRON_MONITOR_PVINVERTER" "true"
    else
        set_env_var "VICTRON_MONITOR_PVINVERTER" "false"
    fi

    # Solar Charger (MPPT)
    if confirm "  Solar Charger (MPPT)?" "N"; then
        set_env_var "VICTRON_MONITOR_SOLAR" "true"
    else
        set_env_var "VICTRON_MONITOR_SOLAR" "false"
    fi

    # Inverter/Charger (MultiPlus/Quattro)
    if confirm "  Inverter/Charger (MultiPlus/Quattro)?" "Y"; then
        set_env_var "VICTRON_MONITOR_VEBUS" "true"
    else
        set_env_var "VICTRON_MONITOR_VEBUS" "false"
    fi

    # System overview (AC/DC loads, PV power)
    if confirm "  System overview (AC/DC loads, PV power)?" "Y"; then
        set_env_var "VICTRON_MONITOR_SYSTEM" "true"
    else
        set_env_var "VICTRON_MONITOR_SYSTEM" "false"
    fi

    # Grid meter
    if confirm "  Grid meter?" "Y"; then
        set_env_var "VICTRON_MONITOR_GRID" "true"
    else
        set_env_var "VICTRON_MONITOR_GRID" "false"
    fi

    # Temperature sensors (Ruuvi, etc.)
    if confirm "  Temperature sensors (Ruuvi, etc.)?" "Y"; then
        set_env_var "VICTRON_MONITOR_TEMPERATURE" "true"
    else
        set_env_var "VICTRON_MONITOR_TEMPERATURE" "false"
    fi

    # GPS
    if confirm "  GPS data?" "N"; then
        set_env_var "VICTRON_MONITOR_GPS" "true"
    else
        set_env_var "VICTRON_MONITOR_GPS" "false"
    fi

    # Tank sensors
    if confirm "  Tank level sensors?" "N"; then
        set_env_var "VICTRON_MONITOR_TANK" "true"
    else
        set_env_var "VICTRON_MONITOR_TANK" "false"
    fi

    echo ""

    # Configure MQTT connection
    print_info "Now configuring MQTT connection to Venus OS..."
    echo ""
    configure_mqtt_input

    print_success "Victron mode configured"
}

#######################################
# Configure System-only mode
#######################################
configure_system_mode() {
    print_header "System Mode Configuration"

    echo -e "${CYAN}System metrics options:${NC}"
    echo ""

    # Collection interval
    local current_interval=$(get_env_var "TELEGRAF_INTERVAL")
    current_interval=${current_interval:-"10s"}
    read -p "Collection interval [${current_interval}]: " input
    set_env_var "TELEGRAF_INTERVAL" "${input:-$current_interval}"

    echo ""
    echo -e "${CYAN}Select metrics to collect:${NC}"

    if confirm "  CPU metrics?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_CPU" "true"
    else
        set_env_var "TELEGRAF_COLLECT_CPU" "false"
    fi

    if confirm "  Memory metrics?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_MEM" "true"
    else
        set_env_var "TELEGRAF_COLLECT_MEM" "false"
    fi

    if confirm "  Disk usage?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_DISK" "true"
    else
        set_env_var "TELEGRAF_COLLECT_DISK" "false"
    fi

    if confirm "  Disk I/O?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_DISKIO" "true"
    else
        set_env_var "TELEGRAF_COLLECT_DISKIO" "false"
    fi

    if confirm "  Network interfaces?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_NET" "true"
    else
        set_env_var "TELEGRAF_COLLECT_NET" "false"
    fi

    if confirm "  System load?" "Y"; then
        set_env_var "TELEGRAF_COLLECT_SYSTEM" "true"
    else
        set_env_var "TELEGRAF_COLLECT_SYSTEM" "false"
    fi

    print_success "System mode configured"
}

#######################################
# Configure Custom mode
#######################################
configure_custom_mode() {
    print_header "Custom Mode"

    echo -e "${CYAN}Custom mode creates a minimal configuration.${NC}"
    echo -e "${YELLOW}You can edit the configuration file manually after generation.${NC}"
    echo ""

    # Collection interval
    local current_interval=$(get_env_var "TELEGRAF_INTERVAL")
    current_interval=${current_interval:-"10s"}
    read -p "Collection interval [${current_interval}]: " input
    set_env_var "TELEGRAF_INTERVAL" "${input:-$current_interval}"

    print_success "Custom mode configured"
}

#######################################
# Configure InfluxDB output
#######################################
configure_influxdb_output() {
    print_header "InfluxDB Output Configuration"

    echo -e "${CYAN}InfluxDB Connection Type:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Local InfluxDB (in this Docker stack)"
    echo -e "  ${GREEN}2)${NC} Remote InfluxDB (external server)"
    echo ""

    read -p "Select [1]: " choice
    choice=${choice:-1}

    case $choice in
        1) configure_influxdb_local ;;
        2) configure_influxdb_remote ;;
        *) configure_influxdb_local ;;
    esac
}

#######################################
# Configure local InfluxDB
#######################################
configure_influxdb_local() {
    print_header "Local InfluxDB Configuration"

    echo -e "${CYAN}Using InfluxDB from Docker stack${NC}"
    echo ""

    # Check if InfluxDB is in compose
    local influxdb_exists=false
    local influxdb_version="2"

    local compose_file=$(get_compose_file "${CURRENT_STACK:-default}")
    if [[ -f "$compose_file" ]]; then
        if grep -q "influxdb:" "$compose_file" 2>/dev/null; then
            influxdb_exists=true
            # Check if it's v1 or v2
            if grep -q "influxdb:1" "$compose_file" 2>/dev/null; then
                influxdb_version="1"
            fi
        fi
    fi

    if [[ "$influxdb_exists" == false ]]; then
        print_warning "InfluxDB not found in current stack"
        echo ""
        if confirm "Add InfluxDB to stack?"; then
            # Will be handled by service selection
            print_info "Add InfluxDB using 'Add Services' menu"
        fi
    fi

    # InfluxDB URL
    local default_url="http://influxdb:8086"
    local current_url=$(get_env_var "TELEGRAF_INFLUXDB_URL")
    current_url=${current_url:-$default_url}

    echo ""
    echo -e "${CYAN}InfluxDB URL:${NC}"
    read -p "URL [${current_url}]: " input
    set_env_var "TELEGRAF_INFLUXDB_URL" "${input:-$current_url}"

    # Detect InfluxDB version
    echo ""
    echo -e "${CYAN}InfluxDB Version:${NC}"
    echo -e "  ${GREEN}1)${NC} InfluxDB 2.x (recommended)"
    echo -e "  ${GREEN}2)${NC} InfluxDB 1.x (legacy)"
    echo ""

    local current_version=$(get_env_var "TELEGRAF_INFLUXDB_VERSION")
    current_version=${current_version:-"2"}

    read -p "Version [${current_version}]: " input
    local version="${input:-$current_version}"
    set_env_var "TELEGRAF_INFLUXDB_VERSION" "$version"

    if [[ "$version" == "2" ]]; then
        configure_influxdb_v2_auth "local"
    else
        configure_influxdb_v1_auth "local"
    fi

    print_success "Local InfluxDB configured"
    press_any_key
}

#######################################
# Configure remote InfluxDB
#######################################
configure_influxdb_remote() {
    print_header "Remote InfluxDB Configuration"

    echo -e "${CYAN}External InfluxDB Server${NC}"
    echo ""

    # URL
    local current_url=$(get_env_var "TELEGRAF_INFLUXDB_URL")
    echo -e "${CYAN}InfluxDB URL:${NC}"
    echo -e "${YELLOW}Examples: http://192.168.1.100:8086, https://influxdb.example.com${NC}"
    read -p "URL [${current_url}]: " input

    if [[ -z "$input" && -z "$current_url" ]]; then
        print_error "URL is required for remote InfluxDB"
        return 1
    fi
    set_env_var "TELEGRAF_INFLUXDB_URL" "${input:-$current_url}"

    # SSL/TLS configuration
    echo ""
    local url="${input:-$current_url}"
    if [[ "$url" == https://* ]]; then
        echo -e "${CYAN}SSL/TLS Configuration:${NC}"

        if confirm "Skip TLS verification (self-signed cert)?" "N"; then
            set_env_var "TELEGRAF_INFLUXDB_INSECURE" "true"
        else
            set_env_var "TELEGRAF_INFLUXDB_INSECURE" "false"

            # CA certificate
            local current_ca=$(get_env_var "TELEGRAF_INFLUXDB_CA")
            read -p "CA certificate path (leave empty if not needed): " input
            if [[ -n "$input" ]]; then
                set_env_var "TELEGRAF_INFLUXDB_CA" "$input"
            fi
        fi
    fi

    # Version selection
    echo ""
    echo -e "${CYAN}InfluxDB Version:${NC}"
    echo -e "  ${GREEN}1)${NC} InfluxDB 2.x"
    echo -e "  ${GREEN}2)${NC} InfluxDB 1.x"
    echo ""

    local current_version=$(get_env_var "TELEGRAF_INFLUXDB_VERSION")
    current_version=${current_version:-"2"}

    read -p "Version [${current_version}]: " input
    local version="${input:-$current_version}"
    set_env_var "TELEGRAF_INFLUXDB_VERSION" "$version"

    if [[ "$version" == "2" ]]; then
        configure_influxdb_v2_auth "remote"
    else
        configure_influxdb_v1_auth "remote"
    fi

    print_success "Remote InfluxDB configured"
    press_any_key
}

#######################################
# Configure InfluxDB v2 authentication
#######################################
configure_influxdb_v2_auth() {
    local location=$1  # local or remote

    echo ""
    echo -e "${BOLD}InfluxDB 2.x Authentication${NC}"
    echo ""

    # Organization
    local current_org=$(get_env_var "TELEGRAF_INFLUXDB_ORG")
    current_org=${current_org:-$(get_env_var "DOCKER_INFLUXDB_INIT_ORG")}
    current_org=${current_org:-"homelab"}

    read -p "Organization [${current_org}]: " input
    set_env_var "TELEGRAF_INFLUXDB_ORG" "${input:-$current_org}"

    # Bucket
    local current_bucket=$(get_env_var "TELEGRAF_INFLUXDB_BUCKET")
    current_bucket=${current_bucket:-"telegraf"}

    read -p "Bucket [${current_bucket}]: " input
    set_env_var "TELEGRAF_INFLUXDB_BUCKET" "${input:-$current_bucket}"

    # Token
    echo ""
    echo -e "${CYAN}API Token:${NC}"

    local current_token=$(get_env_var "TELEGRAF_INFLUXDB_TOKEN")

    if [[ "$location" == "local" ]]; then
        echo -e "${YELLOW}For local InfluxDB, you can:${NC}"
        echo -e "  ${GREEN}1)${NC} Auto-generate token (will need to be added to InfluxDB)"
        echo -e "  ${GREEN}2)${NC} Enter existing token"
        echo -e "  ${GREEN}3)${NC} Create token in InfluxDB first, then enter here"
        echo ""

        read -p "Option [1]: " token_choice
        token_choice=${token_choice:-1}

        case $token_choice in
            1)
                local new_token=$(generate_password 64)
                set_env_var "TELEGRAF_INFLUXDB_TOKEN" "$new_token"
                echo ""
                echo -e "${YELLOW}Generated token:${NC}"
                echo -e "${GREEN}${new_token}${NC}"
                echo ""
                echo -e "${YELLOW}IMPORTANT: Add this token to InfluxDB:${NC}"
                echo -e "1. Open InfluxDB UI → Load Data → API Tokens"
                echo -e "2. Create a new token with write access to bucket '${current_bucket}'"
                echo -e "3. Or use the auto-setup token if available"
                ;;
            2|3)
                if [[ -n "$current_token" ]]; then
                    echo -e "Current token: ${GREEN}${current_token:0:20}...${NC}"
                fi
                read -p "Enter token: " input
                if [[ -n "$input" ]]; then
                    set_env_var "TELEGRAF_INFLUXDB_TOKEN" "$input"
                fi
                ;;
        esac
    else
        # Remote - must enter token
        if [[ -n "$current_token" ]]; then
            echo -e "Current token: ${GREEN}${current_token:0:20}...${NC}"
            if ! confirm "Change token?"; then
                return
            fi
        fi
        read -p "Enter API token: " input
        if [[ -n "$input" ]]; then
            set_env_var "TELEGRAF_INFLUXDB_TOKEN" "$input"
        fi
    fi

    # Auto-create bucket for local InfluxDB?
    if [[ "$location" == "local" ]]; then
        echo ""
        if confirm "Create bucket automatically when InfluxDB starts?" "Y"; then
            set_env_var "TELEGRAF_AUTO_CREATE_BUCKET" "true"
        else
            set_env_var "TELEGRAF_AUTO_CREATE_BUCKET" "false"
        fi
    fi
}

#######################################
# Configure InfluxDB v1 authentication
#######################################
configure_influxdb_v1_auth() {
    local location=$1

    echo ""
    echo -e "${BOLD}InfluxDB 1.x Authentication${NC}"
    echo ""

    # Database
    local current_db=$(get_env_var "TELEGRAF_INFLUXDB_DATABASE")
    current_db=${current_db:-"telegraf"}

    read -p "Database name [${current_db}]: " input
    set_env_var "TELEGRAF_INFLUXDB_DATABASE" "${input:-$current_db}"

    # Username
    local current_user=$(get_env_var "TELEGRAF_INFLUXDB_USERNAME")
    current_user=${current_user:-$(get_env_var "INFLUX_USER")}
    current_user=${current_user:-"telegraf"}

    read -p "Username [${current_user}]: " input
    set_env_var "TELEGRAF_INFLUXDB_USERNAME" "${input:-$current_user}"

    # Password
    local current_pass=$(get_env_var "TELEGRAF_INFLUXDB_PASSWORD")

    echo ""
    if [[ -n "$current_pass" ]]; then
        echo -e "Password: ${GREEN}********${NC} (existing)"
        if ! confirm "Change password?"; then
            return
        fi
    fi

    echo -e "  ${GREEN}1)${NC} Auto-generate password"
    echo -e "  ${GREEN}2)${NC} Enter password manually"
    echo ""

    read -p "Option [1]: " pass_choice
    pass_choice=${pass_choice:-1}

    case $pass_choice in
        1)
            local new_pass=$(generate_password 20)
            set_env_var "TELEGRAF_INFLUXDB_PASSWORD" "$new_pass"
            echo -e "${GREEN}Generated password:${NC} ${new_pass}"
            ;;
        2)
            read -s -p "Enter password: " input
            echo ""
            if [[ -n "$input" ]]; then
                set_env_var "TELEGRAF_INFLUXDB_PASSWORD" "$input"
            fi
            ;;
    esac

    # Retention policy
    local current_rp=$(get_env_var "TELEGRAF_INFLUXDB_RP")
    current_rp=${current_rp:-"autogen"}
    read -p "Retention policy [${current_rp}]: " input
    set_env_var "TELEGRAF_INFLUXDB_RP" "${input:-$current_rp}"
}

#######################################
# Configure MQTT input
#######################################
configure_mqtt_input() {
    print_header "MQTT Input Configuration"

    echo -e "${CYAN}MQTT Broker Connection${NC}"
    echo ""

    # Server URL
    local current_server=$(get_env_var "TELEGRAF_MQTT_SERVER")
    echo -e "${CYAN}MQTT Server:${NC}"
    echo -e "${YELLOW}Examples: tcp://mosquitto:1883, tcp://192.168.1.100:1883, ssl://mqtt.example.com:8883${NC}"

    # Suggest local Mosquitto if available
    local compose_file=$(get_compose_file "${CURRENT_STACK:-default}")
    if [[ -f "$compose_file" ]] && grep -q "mosquitto:" "$compose_file" 2>/dev/null; then
        current_server=${current_server:-"tcp://mosquitto:1883"}
        echo -e "${GREEN}Detected local Mosquitto in stack${NC}"
    fi

    read -p "Server [${current_server:-tcp://localhost:1883}]: " input
    local server="${input:-${current_server:-tcp://localhost:1883}}"
    set_env_var "TELEGRAF_MQTT_SERVER" "$server"

    # SSL/TLS configuration
    if [[ "$server" == ssl://* ]] || [[ "$server" == tls://* ]]; then
        configure_mqtt_tls
    fi

    # Authentication
    echo ""
    echo -e "${CYAN}MQTT Authentication:${NC}"

    if confirm "MQTT requires authentication?" "N"; then
        local current_user=$(get_env_var "TELEGRAF_MQTT_USERNAME")
        read -p "Username [${current_user}]: " input
        set_env_var "TELEGRAF_MQTT_USERNAME" "${input:-$current_user}"

        local current_pass=$(get_env_var "TELEGRAF_MQTT_PASSWORD")
        if [[ -n "$current_pass" ]]; then
            echo -e "Password: ${GREEN}********${NC} (existing)"
            if confirm "Change password?"; then
                read -s -p "New password: " input
                echo ""
                set_env_var "TELEGRAF_MQTT_PASSWORD" "$input"
            fi
        else
            read -s -p "Password: " input
            echo ""
            set_env_var "TELEGRAF_MQTT_PASSWORD" "$input"
        fi
    else
        set_env_var "TELEGRAF_MQTT_USERNAME" ""
        set_env_var "TELEGRAF_MQTT_PASSWORD" ""
    fi

    # Topics configuration based on mode
    local mode=$(get_env_var "TELEGRAF_MODE")

    echo ""
    echo -e "${CYAN}MQTT Topics:${NC}"

    if [[ "$mode" == "victron" ]]; then
        configure_victron_topics
    else
        configure_generic_mqtt_topics
    fi

    # QoS
    echo ""
    local current_qos=$(get_env_var "TELEGRAF_MQTT_QOS")
    current_qos=${current_qos:-"0"}
    read -p "QoS level (0, 1, or 2) [${current_qos}]: " input
    set_env_var "TELEGRAF_MQTT_QOS" "${input:-$current_qos}"

    # Client ID
    local current_client=$(get_env_var "TELEGRAF_MQTT_CLIENT_ID")
    current_client=${current_client:-"telegraf-$(hostname -s 2>/dev/null || echo 'docker')"}
    read -p "Client ID [${current_client}]: " input
    set_env_var "TELEGRAF_MQTT_CLIENT_ID" "${input:-$current_client}"

    print_success "MQTT input configured"
    press_any_key
}

#######################################
# Configure MQTT TLS/SSL
#######################################
configure_mqtt_tls() {
    echo ""
    echo -e "${BOLD}MQTT SSL/TLS Configuration${NC}"
    echo ""

    local mode=$(get_env_var "TELEGRAF_MODE")

    # For Victron, default to insecure (Venus OS uses self-signed certs)
    local default_insecure="N"
    if [[ "$mode" == "victron" ]]; then
        default_insecure="Y"
        echo -e "${YELLOW}Note: Venus OS typically uses self-signed certificates.${NC}"
        echo -e "${YELLOW}Recommended: Skip TLS verification for Venus OS.${NC}"
        echo ""
    fi

    # Skip verification
    if confirm "Skip TLS certificate verification (self-signed)?" "$default_insecure"; then
        set_env_var "TELEGRAF_MQTT_TLS_INSECURE" "true"
        print_success "TLS verification disabled (insecure mode)"
    else
        set_env_var "TELEGRAF_MQTT_TLS_INSECURE" "false"

        # CA Certificate
        local current_ca=$(get_env_var "TELEGRAF_MQTT_TLS_CA")
        echo -e "${CYAN}CA Certificate:${NC}"
        echo -e "${YELLOW}Path to CA certificate file (leave empty if not needed)${NC}"
        read -p "CA cert path [${current_ca}]: " input
        if [[ -n "$input" ]]; then
            set_env_var "TELEGRAF_MQTT_TLS_CA" "$input"
        fi
    fi

    # Client certificate (mutual TLS)
    if confirm "Use client certificate (mutual TLS)?" "N"; then
        local current_cert=$(get_env_var "TELEGRAF_MQTT_TLS_CERT")
        read -p "Client certificate path [${current_cert}]: " input
        if [[ -n "$input" ]]; then
            set_env_var "TELEGRAF_MQTT_TLS_CERT" "$input"
        fi

        local current_key=$(get_env_var "TELEGRAF_MQTT_TLS_KEY")
        read -p "Client key path [${current_key}]: " input
        if [[ -n "$input" ]]; then
            set_env_var "TELEGRAF_MQTT_TLS_KEY" "$input"
        fi
    fi
}

#######################################
# Configure Victron MQTT topics
#######################################
configure_victron_topics() {
    echo -e "${YELLOW}Victron MQTT uses specific topic structure.${NC}"
    echo -e "${YELLOW}Topics are auto-configured based on your selections.${NC}"
    echo ""

    local portal_id=$(get_env_var "VICTRON_PORTAL_ID")
    portal_id=${portal_id:-"+"}

    echo -e "Portal ID: ${GREEN}${portal_id}${NC}"
    echo ""

    # Build topic list based on selected devices
    local topics=""

    if [[ "$(get_env_var VICTRON_MONITOR_BATTERY)" == "true" ]]; then
        topics="${topics}N/${portal_id}/battery/#,"
        echo -e "  ${GREEN}✓${NC} Battery monitor topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_PVINVERTER)" == "true" ]]; then
        topics="${topics}N/${portal_id}/pvinverter/#,"
        echo -e "  ${GREEN}✓${NC} PV Inverter topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_SOLAR)" == "true" ]]; then
        topics="${topics}N/${portal_id}/solarcharger/#,"
        echo -e "  ${GREEN}✓${NC} Solar charger topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_VEBUS)" == "true" ]]; then
        topics="${topics}N/${portal_id}/vebus/#,"
        echo -e "  ${GREEN}✓${NC} VE.Bus (inverter/charger) topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_SYSTEM)" == "true" ]]; then
        topics="${topics}N/${portal_id}/system/#,"
        echo -e "  ${GREEN}✓${NC} System overview topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_GRID)" == "true" ]]; then
        topics="${topics}N/${portal_id}/grid/#,"
        echo -e "  ${GREEN}✓${NC} Grid meter topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_TEMPERATURE)" == "true" ]]; then
        topics="${topics}N/${portal_id}/temperature/#,"
        echo -e "  ${GREEN}✓${NC} Temperature sensor topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_GPS)" == "true" ]]; then
        topics="${topics}N/${portal_id}/gps/#,"
        echo -e "  ${GREEN}✓${NC} GPS topics"
    fi

    if [[ "$(get_env_var VICTRON_MONITOR_TANK)" == "true" ]]; then
        topics="${topics}N/${portal_id}/tank/#,"
        echo -e "  ${GREEN}✓${NC} Tank sensor topics"
    fi

    # Remove trailing comma
    topics="${topics%,}"

    set_env_var "TELEGRAF_MQTT_TOPICS" "$topics"

    echo ""
    echo -e "Configured topics: ${CYAN}${topics}${NC}"
}

#######################################
# Configure generic MQTT topics
#######################################
configure_generic_mqtt_topics() {
    local current_topics=$(get_env_var "TELEGRAF_MQTT_TOPICS")
    current_topics=${current_topics:-"sensors/#,home/#"}

    echo -e "${YELLOW}Enter MQTT topics to subscribe (comma-separated)${NC}"
    echo -e "${YELLOW}Wildcards: + (single level), # (multi level)${NC}"
    echo -e "${YELLOW}Examples: sensors/#, home/+/temperature, iot/devices/#${NC}"
    echo ""

    read -p "Topics [${current_topics}]: " input
    set_env_var "TELEGRAF_MQTT_TOPICS" "${input:-$current_topics}"

    # Data format
    echo ""
    echo -e "${CYAN}MQTT message format:${NC}"
    echo -e "  ${GREEN}1)${NC} JSON (most common)"
    echo -e "  ${GREEN}2)${NC} Value (plain numeric/string)"
    echo -e "  ${GREEN}3)${NC} InfluxDB line protocol"
    echo ""

    local current_format=$(get_env_var "TELEGRAF_MQTT_DATA_FORMAT")
    current_format=${current_format:-"json"}

    read -p "Format [1]: " format_choice

    case $format_choice in
        2) set_env_var "TELEGRAF_MQTT_DATA_FORMAT" "value" ;;
        3) set_env_var "TELEGRAF_MQTT_DATA_FORMAT" "influx" ;;
        *) set_env_var "TELEGRAF_MQTT_DATA_FORMAT" "json" ;;
    esac
}

#######################################
# View current Telegraf configuration
#######################################
view_telegraf_config() {
    print_header "Current Telegraf Configuration"

    local stack="${CURRENT_STACK:-default}"
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    local config_path
    if [[ "$stack" == "default" ]]; then
        config_path="${docker_root}/telegraf/config/telegraf.conf"
    else
        config_path="${docker_root}/${stack}/telegraf/config/telegraf.conf"
    fi

    if [[ -f "$config_path" ]]; then
        echo -e "${CYAN}Configuration file: ${config_path}${NC}"
        echo ""
        cat "$config_path"
    else
        print_warning "Configuration file not found: ${config_path}"
        echo ""
        echo -e "${CYAN}Current settings from .env:${NC}"
        echo ""
        grep "^TELEGRAF_\|^VICTRON_" "$ENV_FILE" 2>/dev/null || echo "No Telegraf settings found"
    fi

    echo ""
    press_any_key
}

#######################################
# Regenerate Telegraf configuration
#######################################
regenerate_telegraf_config() {
    local mode=$(get_env_var "TELEGRAF_MODE")
    mode=${mode:-"docker"}

    if confirm "Regenerate configuration for mode '${TELEGRAF_MODES[$mode]}'?"; then
        generate_telegraf_config "$mode" "force"
        print_success "Configuration regenerated"
    fi

    press_any_key
}

#######################################
# Generate Telegraf configuration file
# Arguments:
#   $1 - Mode (docker, victron, system, custom)
#   $2 - Force overwrite (optional)
#######################################
generate_telegraf_config() {
    local mode=$1
    local force=${2:-""}
    local stack="${CURRENT_STACK:-default}"
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    local config_dir
    if [[ "$stack" == "default" ]]; then
        config_dir="${docker_root}/telegraf/config"
    else
        config_dir="${docker_root}/${stack}/telegraf/config"
    fi

    local config_file="${config_dir}/telegraf.conf"

    # Check if exists and not forcing
    if [[ -f "$config_file" && "$force" != "force" ]]; then
        print_info "Configuration exists: ${config_file}"
        if ! confirm "Overwrite existing configuration?"; then
            return
        fi
    fi

    # Create directory
    mkdir -p "$config_dir"

    print_info "Generating Telegraf configuration..."

    # Generate based on mode
    case $mode in
        docker)
            generate_docker_config "$config_file"
            ;;
        victron)
            generate_victron_config "$config_file"
            ;;
        system)
            generate_system_config "$config_file"
            ;;
        custom)
            generate_custom_config "$config_file"
            ;;
        *)
            generate_docker_config "$config_file"
            ;;
    esac

    # Set permissions
    chmod 644 "$config_file"

    print_success "Generated: ${config_file}"
}

#######################################
# Generate Docker mode configuration
#######################################
generate_docker_config() {
    local config_file=$1

    local interval=$(get_env_var "TELEGRAF_INTERVAL")
    interval=${interval:-"10s"}

    cat > "$config_file" << 'TELEGRAF_EOF'
# Telegraf Configuration - Docker & System Mode
# Generated by Docker Services Manager

[global_tags]
  # Add custom tags to all metrics
  # environment = "production"

[agent]
  interval = "${TELEGRAF_INTERVAL}"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

TELEGRAF_EOF

    # Add InfluxDB output
    append_influxdb_output "$config_file"

    cat >> "$config_file" << 'TELEGRAF_EOF'

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

# Read metrics about cpu usage
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

# Read metrics about memory usage
[[inputs.mem]]

# Read metrics about disk usage
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

# Read metrics about disk IO
[[inputs.diskio]]

# Read metrics about network interface usage
[[inputs.net]]

# Read metrics about system load
[[inputs.system]]

# Read metrics about running processes
[[inputs.processes]]

# Read metrics from docker containers
[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  gather_services = false
  source_tag = false
  container_name_include = []
  container_name_exclude = []
  timeout = "5s"
  perdevice = true
  total = false
  docker_label_include = []
  docker_label_exclude = []

TELEGRAF_EOF

    # Substitute variables
    substitute_telegraf_variables "$config_file"
}

#######################################
# Generate Victron mode configuration
#######################################
generate_victron_config() {
    local config_file=$1
    local portal_id=$(get_env_var "VICTRON_PORTAL_ID")
    portal_id=${portal_id:-"+"}

    cat > "$config_file" << 'TELEGRAF_EOF'
# Telegraf Configuration - Victron Energy Mode
# Generated by Docker Services Manager
# Collects data from Victron Venus OS via MQTT
#
# Data organization:
#   - Each device type (battery, pvinverter, grid, etc.) becomes a measurement
#   - Tags: portal_id, instance, field (path component)
#   - This allows simple queries like: SELECT * FROM "battery"

[global_tags]
  source = "victron"

[agent]
  interval = "${TELEGRAF_INTERVAL}"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

TELEGRAF_EOF

    # Add InfluxDB output
    append_influxdb_output "$config_file"

    cat >> "$config_file" << TELEGRAF_EOF

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

# Victron MQTT Input
# Venus OS publishes data to MQTT in JSON format
# Topic structure: N/<portal_id>/<device_type>/<instance>/<path...>
[[inputs.mqtt_consumer]]
  servers = ["\${TELEGRAF_MQTT_SERVER}"]

  # Topics to subscribe - wildcard patterns for different path depths
  # Using wildcards to capture all devices and paths
  topics = [
    "N/${portal_id}/+/+/+",
    "N/${portal_id}/+/+/+/+",
    "N/${portal_id}/+/+/+/+/+",
    "N/${portal_id}/+/+/+/+/+/+",
  ]

  # QoS policy
  qos = \${TELEGRAF_MQTT_QOS}

  # Connection settings
  client_id = "\${TELEGRAF_MQTT_CLIENT_ID}"
  persistent_session = false

TELEGRAF_EOF

    # Add authentication if configured
    local mqtt_user=$(get_env_var "TELEGRAF_MQTT_USERNAME")
    if [[ -n "$mqtt_user" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
  # Authentication
  username = "${TELEGRAF_MQTT_USERNAME}"
  password = "${TELEGRAF_MQTT_PASSWORD}"

TELEGRAF_EOF
    fi

    # Add TLS configuration if needed
    # For Victron/Venus OS, always use insecure_skip_verify as it uses self-signed certs
    local mqtt_server=$(get_env_var "TELEGRAF_MQTT_SERVER")
    if [[ "$mqtt_server" == ssl://* ]] || [[ "$mqtt_server" == tls://* ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
  # TLS Configuration
  # Venus OS uses self-signed certificates, so we skip verification
  insecure_skip_verify = true

TELEGRAF_EOF
    fi

    cat >> "$config_file" << 'TELEGRAF_EOF'
  # Data format - Victron uses JSON
  # Venus OS publishes: {"value": 123.45} or {"value": "string"}
  data_format = "json"

  # Topic parsing - extract device_type as measurement name
  # This allows simple queries: SELECT * FROM "battery", SELECT * FROM "grid"
  #
  # Topic structure: N/<portal_id>/<device_type>/<instance>/<field1>/<field2>/...
  # We use 'measurement' in the pattern to set the InfluxDB measurement name

  [[inputs.mqtt_consumer.topic_parsing]]
    topic = "N/+/+/+/+"
    measurement = "_/_/measurement/_/_"
    tags = "_/portal_id/_/instance/field"

  [[inputs.mqtt_consumer.topic_parsing]]
    topic = "N/+/+/+/+/+"
    measurement = "_/_/measurement/_/_/_"
    tags = "_/portal_id/_/instance/field/subfield"

  [[inputs.mqtt_consumer.topic_parsing]]
    topic = "N/+/+/+/+/+/+"
    measurement = "_/_/measurement/_/_/_/_"
    tags = "_/portal_id/_/instance/field/subfield/detail"

  [[inputs.mqtt_consumer.topic_parsing]]
    topic = "N/+/+/+/+/+/+/+"
    measurement = "_/_/measurement/_/_/_/_/_"
    tags = "_/portal_id/_/instance/field/subfield/detail/extra"

TELEGRAF_EOF

    # Substitute variables
    substitute_telegraf_variables "$config_file"
}

#######################################
# Generate System-only mode configuration
#######################################
generate_system_config() {
    local config_file=$1

    cat > "$config_file" << 'TELEGRAF_EOF'
# Telegraf Configuration - System Metrics Mode
# Generated by Docker Services Manager

[global_tags]

[agent]
  interval = "${TELEGRAF_INTERVAL}"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

TELEGRAF_EOF

    # Add InfluxDB output
    append_influxdb_output "$config_file"

    cat >> "$config_file" << 'TELEGRAF_EOF'

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

TELEGRAF_EOF

    # Add plugins based on configuration
    if [[ "$(get_env_var TELEGRAF_COLLECT_CPU)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# CPU metrics
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

TELEGRAF_EOF
    fi

    if [[ "$(get_env_var TELEGRAF_COLLECT_MEM)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# Memory metrics
[[inputs.mem]]

TELEGRAF_EOF
    fi

    if [[ "$(get_env_var TELEGRAF_COLLECT_DISK)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# Disk usage
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

TELEGRAF_EOF
    fi

    if [[ "$(get_env_var TELEGRAF_COLLECT_DISKIO)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# Disk I/O
[[inputs.diskio]]

TELEGRAF_EOF
    fi

    if [[ "$(get_env_var TELEGRAF_COLLECT_NET)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# Network interfaces
[[inputs.net]]

TELEGRAF_EOF
    fi

    if [[ "$(get_env_var TELEGRAF_COLLECT_SYSTEM)" != "false" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
# System load
[[inputs.system]]

# Processes
[[inputs.processes]]

TELEGRAF_EOF
    fi

    # Substitute variables
    substitute_telegraf_variables "$config_file"
}

#######################################
# Generate Custom mode configuration
#######################################
generate_custom_config() {
    local config_file=$1

    cat > "$config_file" << 'TELEGRAF_EOF'
# Telegraf Configuration - Custom Mode
# Generated by Docker Services Manager
# Edit this file to add your own inputs and outputs

[global_tags]
  # Add custom tags

[agent]
  interval = "${TELEGRAF_INTERVAL}"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

TELEGRAF_EOF

    # Add InfluxDB output
    append_influxdb_output "$config_file"

    cat >> "$config_file" << 'TELEGRAF_EOF'

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

# Add your input plugins here
# Examples:
#
# [[inputs.cpu]]
#   percpu = true
#
# [[inputs.mqtt_consumer]]
#   servers = ["tcp://localhost:1883"]
#   topics = ["sensors/#"]
#
# [[inputs.http]]
#   urls = ["http://localhost/metrics"]

TELEGRAF_EOF

    # Substitute variables
    substitute_telegraf_variables "$config_file"
}

#######################################
# Append InfluxDB output configuration
#######################################
append_influxdb_output() {
    local config_file=$1
    local version=$(get_env_var "TELEGRAF_INFLUXDB_VERSION")
    version=${version:-"2"}

    if [[ "$version" == "2" ]]; then
        cat >> "$config_file" << 'TELEGRAF_EOF'
[[outputs.influxdb_v2]]
  urls = ["${TELEGRAF_INFLUXDB_URL}"]
  token = "${TELEGRAF_INFLUXDB_TOKEN}"
  organization = "${TELEGRAF_INFLUXDB_ORG}"
  bucket = "${TELEGRAF_INFLUXDB_BUCKET}"
TELEGRAF_EOF

        # Add TLS options if configured
        local insecure=$(get_env_var "TELEGRAF_INFLUXDB_INSECURE")
        if [[ "$insecure" == "true" ]]; then
            echo "  insecure_skip_verify = true" >> "$config_file"
        fi

        local ca_cert=$(get_env_var "TELEGRAF_INFLUXDB_CA")
        if [[ -n "$ca_cert" ]]; then
            echo "  tls_ca = \"${ca_cert}\"" >> "$config_file"
        fi

    else
        # InfluxDB 1.x
        cat >> "$config_file" << 'TELEGRAF_EOF'
[[outputs.influxdb]]
  urls = ["${TELEGRAF_INFLUXDB_URL}"]
  database = "${TELEGRAF_INFLUXDB_DATABASE}"
  username = "${TELEGRAF_INFLUXDB_USERNAME}"
  password = "${TELEGRAF_INFLUXDB_PASSWORD}"
  retention_policy = "${TELEGRAF_INFLUXDB_RP}"
  skip_database_creation = false
TELEGRAF_EOF

        local insecure=$(get_env_var "TELEGRAF_INFLUXDB_INSECURE")
        if [[ "$insecure" == "true" ]]; then
            echo "  insecure_skip_verify = true" >> "$config_file"
        fi
    fi
}

#######################################
# Substitute environment variables in config
#######################################
substitute_telegraf_variables() {
    local config_file=$1

    # Create a temporary file
    local temp_file=$(mktemp)

    # Read config and substitute variables
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Find all ${VAR} patterns and substitute
        while [[ "$line" =~ \$\{([A-Z_]+)\} ]]; do
            local var_name="${BASH_REMATCH[1]}"
            local var_value=$(get_env_var "$var_name")

            # Use default if not set
            if [[ -z "$var_value" ]]; then
                case "$var_name" in
                    TELEGRAF_INTERVAL) var_value="10s" ;;
                    TELEGRAF_INFLUXDB_URL) var_value="http://influxdb:8086" ;;
                    TELEGRAF_INFLUXDB_ORG) var_value="homelab" ;;
                    TELEGRAF_INFLUXDB_BUCKET) var_value="telegraf" ;;
                    TELEGRAF_INFLUXDB_DATABASE) var_value="telegraf" ;;
                    TELEGRAF_INFLUXDB_RP) var_value="autogen" ;;
                    TELEGRAF_MQTT_SERVER) var_value="tcp://mosquitto:1883" ;;
                    TELEGRAF_MQTT_QOS) var_value="0" ;;
                    TELEGRAF_MQTT_CLIENT_ID) var_value="telegraf" ;;
                    *) var_value="" ;;
                esac
            fi

            # Escape special characters for sed
            var_value=$(echo "$var_value" | sed 's/[&/\]/\\&/g')
            line=$(echo "$line" | sed "s|\${${var_name}}|${var_value}|g")
        done

        echo "$line" >> "$temp_file"
    done < "$config_file"

    mv "$temp_file" "$config_file"
}
