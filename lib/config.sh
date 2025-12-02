#!/bin/bash

#######################################
# Global Configuration
# Default values and settings
#######################################

# Default base directory for all containers
DEFAULT_DOCKER_ROOT="/docker-storage"

# Default network configuration
DEFAULT_NETWORK_NAME="docker-services"
DEFAULT_NETWORK_SUBNET="172.20.0.0/16"

# Auto-detect PUID/PGID
AUTO_PUID=$(id -u 2>/dev/null || echo "1000")
AUTO_PGID=$(id -g 2>/dev/null || echo "1000")

# If running as root, try multiple methods to get the actual user
if [[ $EUID -eq 0 ]]; then
    _detected=false

    # Method 1: SUDO_USER environment variable
    if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
        AUTO_PUID=$(id -u "$SUDO_USER" 2>/dev/null)
        AUTO_PGID=$(id -g "$SUDO_USER" 2>/dev/null)
        [[ -n "$AUTO_PUID" ]] && [[ "$AUTO_PUID" != "0" ]] && _detected=true
    fi

    # Method 2: logname command
    if [[ "$_detected" == false ]]; then
        _real_user=$(logname 2>/dev/null)
        if [[ -n "$_real_user" ]] && [[ "$_real_user" != "root" ]]; then
            AUTO_PUID=$(id -u "$_real_user" 2>/dev/null)
            AUTO_PGID=$(id -g "$_real_user" 2>/dev/null)
            [[ -n "$AUTO_PUID" ]] && [[ "$AUTO_PUID" != "0" ]] && _detected=true
        fi
    fi

    # Method 3: Find first regular user (UID >= 1000)
    if [[ "$_detected" == false ]]; then
        _first_user=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd 2>/dev/null)
        if [[ -n "$_first_user" ]]; then
            AUTO_PUID=$(id -u "$_first_user" 2>/dev/null)
            AUTO_PGID=$(id -g "$_first_user" 2>/dev/null)
            [[ -n "$AUTO_PUID" ]] && [[ "$AUTO_PUID" != "0" ]] && _detected=true
        fi
    fi

    # Final fallback to 1000
    if [[ "$_detected" == false ]] || [[ -z "$AUTO_PUID" ]] || [[ "$AUTO_PUID" == "0" ]]; then
        AUTO_PUID="1000"
        AUTO_PGID="1000"
    fi
fi

# Default timezone (try to detect)
if [[ -f /etc/timezone ]]; then
    AUTO_TZ=$(cat /etc/timezone 2>/dev/null)
elif [[ -L /etc/localtime ]]; then
    AUTO_TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
else
    AUTO_TZ="Europe/Bucharest"
fi

# Auto-detect server IP (first non-localhost IP)
AUTO_SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$AUTO_SERVER_IP" ]]; then
    # Fallback: try ip command
    AUTO_SERVER_IP=$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')
fi
AUTO_SERVER_IP=${AUTO_SERVER_IP:-"127.0.0.1"}

#######################################
# Service Port Defaults
# Easy to customize per deployment
#######################################
declare -A DEFAULT_PORTS=(
    # Management
    ["PORTAINER_PORT"]="9000"
    ["NPM_PORT"]="81"
    ["HEIMDALL_PORT"]="8084"
    ["FILEBROWSER_PORT"]="8085"

    # Home Automation
    ["HA_PORT"]="8123"
    ["NODERED_PORT"]="1880"
    ["ZIGBEE2MQTT_PORT"]="8088"
    ["ESPHOME_PORT"]="6052"

    # Databases
    ["MARIADB_PORT"]="3306"
    ["MONGODB_PORT"]="27017"
    ["REDIS_PORT"]="6379"
    ["INFLUXDB_PORT"]="8086"

    # Monitoring
    ["GRAFANA_PORT"]="3000"
    ["UPTIME_KUMA_PORT"]="3001"
    ["GLANCES_PORT"]="61208"
    ["NODE_EXPORTER_PORT"]="9100"

    # MQTT
    ["MQTT_PORT"]="1883"
    ["MQTT_WS_PORT"]="9001"
    ["MQTT_EXPLORER_PORT"]="4000"

    # Utilities
    ["VAULTWARDEN_PORT"]="8082"
    ["GOTIFY_PORT"]="8083"
    ["PIHOLE_PORT"]="8089"
    ["PHPMYADMIN_PORT"]="8081"
    ["N8N_PORT"]="5678"
    ["VSCODE_PORT"]="8443"
    ["DUPLICATI_PORT"]="8200"

    # VPN
    ["WG_PORT"]="51820"
)


#######################################
# Stack Configuration
# Stacks allow grouping services together
# Each stack gets its own compose file
#######################################
DEFAULT_STACK="default"
CURRENT_STACK=""

# Get list of existing stacks from compose files
get_existing_stacks() {
    local stacks=()
    for file in "${SCRIPT_DIR}"/docker-compose.*.yml; do
        if [[ -f "$file" ]]; then
            local stack_name=$(basename "$file" | sed 's/docker-compose\.\(.*\)\.yml/\1/')
            if [[ -n "$stack_name" ]] && [[ "$stack_name" != "*" ]]; then
                stacks+=("$stack_name")
            fi
        fi
    done
    # Also check for legacy docker-compose.yml (default stack)
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        stacks+=("default")
    fi
    echo "${stacks[@]}" | tr ' ' '\n' | sort -u
}

#######################################
# Initial setup wizard
# Called on first run
#######################################
run_initial_setup() {
    print_header "Initial Setup Wizard"

    echo -e "${CYAN}Welcome! Let's configure your Docker environment.${NC}"
    echo ""

    # Check if .env exists
    if [[ -f "$ENV_FILE" ]]; then
        print_info "Existing configuration found."
        if ! confirm "Do you want to reconfigure?"; then
            load_env
            return 0
        fi
    fi

    # Docker root directory
    echo -e "${BOLD}1. Docker Storage Directory${NC}"
    echo -e "   ${YELLOW}This is where all container data will be stored.${NC}"
    echo -e "   ${YELLOW}Each container will have its own subdirectory.${NC}"
    echo ""

    local current_root=$(get_env_var "DOCKER_ROOT")
    current_root=${current_root:-$DEFAULT_DOCKER_ROOT}

    read -p "   Docker root directory [${current_root}]: " input_root
    DOCKER_ROOT="${input_root:-$current_root}"

    # Create directory if it doesn't exist
    if [[ ! -d "$DOCKER_ROOT" ]]; then
        if confirm "   Directory doesn't exist. Create it?"; then
            mkdir -p "$DOCKER_ROOT"
            chown -R "${AUTO_PUID}:${AUTO_PGID}" "$DOCKER_ROOT" 2>/dev/null || true
            print_success "Created: $DOCKER_ROOT"
        fi
    fi

    echo ""

    # User/Group IDs
    echo -e "${BOLD}2. User & Group IDs${NC}"
    echo -e "   ${YELLOW}Used for file permissions in containers.${NC}"
    echo ""

    local current_puid=$(get_env_var "PUID")
    current_puid=${current_puid:-$AUTO_PUID}
    local current_pgid=$(get_env_var "PGID")
    current_pgid=${current_pgid:-$AUTO_PGID}

    echo -e "   Detected: PUID=${GREEN}${AUTO_PUID}${NC}, PGID=${GREEN}${AUTO_PGID}${NC}"
    if confirm "   Use detected values?" "Y"; then
        PUID=$AUTO_PUID
        PGID=$AUTO_PGID
    else
        read -p "   PUID [${current_puid}]: " input_puid
        read -p "   PGID [${current_pgid}]: " input_pgid
        PUID="${input_puid:-$current_puid}"
        PGID="${input_pgid:-$current_pgid}"
    fi

    echo ""

    # Timezone
    echo -e "${BOLD}3. Timezone${NC}"
    echo ""

    local current_tz=$(get_env_var "TZ")
    current_tz=${current_tz:-$AUTO_TZ}

    echo -e "   Detected: ${GREEN}${AUTO_TZ}${NC}"
    if confirm "   Use detected timezone?" "Y"; then
        TZ=$AUTO_TZ
    else
        read -p "   Timezone [${current_tz}]: " input_tz
        TZ="${input_tz:-$current_tz}"
    fi

    echo ""

    # Server IP
    echo -e "${BOLD}4. Server IP Address${NC}"
    echo -e "   ${YELLOW}Used as default for service URLs (InfluxDB, MQTT, etc.)${NC}"
    echo ""

    local current_ip=$(get_env_var "SERVER_IP")
    current_ip=${current_ip:-$AUTO_SERVER_IP}

    echo -e "   Detected: ${GREEN}${AUTO_SERVER_IP}${NC}"
    if confirm "   Use detected IP?" "Y"; then
        SERVER_IP=$AUTO_SERVER_IP
    else
        read -p "   Server IP [${current_ip}]: " input_ip
        SERVER_IP="${input_ip:-$current_ip}"
    fi

    echo ""

    # Network configuration
    echo -e "${BOLD}5. Docker Network${NC}"
    echo -e "   ${YELLOW}Containers will communicate over this network.${NC}"
    echo ""

    local current_network=$(get_env_var "DOCKER_NETWORK")
    current_network=${current_network:-$DEFAULT_NETWORK_NAME}
    local current_subnet=$(get_env_var "DOCKER_SUBNET")
    current_subnet=${current_subnet:-$DEFAULT_NETWORK_SUBNET}

    read -p "   Network name [${current_network}]: " input_network
    DOCKER_NETWORK="${input_network:-$current_network}"

    read -p "   Subnet [${current_subnet}]: " input_subnet
    DOCKER_SUBNET="${input_subnet:-$current_subnet}"

    echo ""

    # Save configuration
    echo -e "${BOLD}Saving configuration...${NC}"

    # Write to .env
    cat > "$ENV_FILE" << EOF
#######################################
# Docker Services Configuration
# Generated: $(date)
#######################################

# Base directory for all containers
DOCKER_ROOT=${DOCKER_ROOT}

# User/Group IDs for file permissions
PUID=${PUID}
PGID=${PGID}

# Timezone
TZ=${TZ}

# Server IP (used as default for service URLs)
SERVER_IP=${SERVER_IP}

# Network configuration
DOCKER_NETWORK=${DOCKER_NETWORK}
DOCKER_SUBNET=${DOCKER_SUBNET}

#######################################
# Service-specific variables below
#######################################
EOF

    print_success "Configuration saved to .env"

    # Create Docker network if it doesn't exist
    create_docker_network

    echo ""
    print_success "Initial setup complete!"
    echo ""

    # Reload env
    load_env

    press_any_key
}

#######################################
# Create Docker network
#######################################
create_docker_network() {
    if ! command_exists docker; then
        print_warning "Docker not installed, skipping network creation"
        return 0
    fi

    local network_name="${DOCKER_NETWORK:-$DEFAULT_NETWORK_NAME}"
    local subnet="${DOCKER_SUBNET:-$DEFAULT_NETWORK_SUBNET}"

    # Check if network exists
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        print_info "Network '${network_name}' already exists"
        return 0
    fi

    print_info "Creating Docker network: ${network_name}"

    # Use || true to prevent set -e from exiting on failure
    local result
    result=$(docker network create \
        --driver bridge \
        --subnet "$subnet" \
        --opt "com.docker.network.bridge.name"="br-${network_name}" \
        "$network_name" 2>&1) || true

    # Check if network was created successfully
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        print_success "Network '${network_name}' created with subnet ${subnet}"
    else
        print_warning "Could not create network (may already exist with different config)"
        print_info "Continuing anyway..."
    fi

    return 0
}

#######################################
# Check if port is available
# Arguments:
#   $1 - Port number
#######################################
is_port_available() {
    local port=$1

    # Check with ss or netstat
    if command_exists ss; then
        ! ss -tuln 2>/dev/null | grep -q ":${port} "
    elif command_exists netstat; then
        ! netstat -tuln 2>/dev/null | grep -q ":${port} "
    else
        # If neither available, assume port is free
        return 0
    fi
}

#######################################
# Find next available port
# Arguments:
#   $1 - Starting port
#######################################
find_available_port() {
    local port=$1
    local max_tries=100

    for ((i=0; i<max_tries; i++)); do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
        ((port++))
    done

    # Return original if no free port found
    echo "$1"
}
