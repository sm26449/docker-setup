#!/bin/bash

#######################################
# Container Settings Management
# Manage devices, memory, shm_size, etc.
#######################################

# Current compose file for this module (set by select_stack)
SETTINGS_COMPOSE_FILE=""
SETTINGS_CURRENT_STACK=""

#######################################
# Get all available compose files
#######################################
get_all_compose_files() {
    local files=()

    # Check default compose file
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        files+=("${SCRIPT_DIR}/docker-compose.yml")
    fi

    # Check stack-specific compose files
    for file in "${SCRIPT_DIR}"/docker-compose.*.yml; do
        if [[ -f "$file" ]]; then
            files+=("$file")
        fi
    done

    echo "${files[@]}"
}

#######################################
# Select stack for container settings
#######################################
select_settings_stack() {
    local compose_files=()
    mapfile -t compose_files < <(get_all_compose_files | tr ' ' '\n')

    if [[ ${#compose_files[@]} -eq 0 ]]; then
        print_error "No docker-compose files found. Add services first."
        return 1
    fi

    # If only one file, use it directly
    if [[ ${#compose_files[@]} -eq 1 ]]; then
        SETTINGS_COMPOSE_FILE="${compose_files[0]}"
        if [[ "$SETTINGS_COMPOSE_FILE" == *"docker-compose.yml" ]] && [[ ! "$SETTINGS_COMPOSE_FILE" == *"docker-compose."*".yml" ]]; then
            SETTINGS_CURRENT_STACK="default"
        else
            SETTINGS_CURRENT_STACK=$(basename "$SETTINGS_COMPOSE_FILE" | sed 's/docker-compose\.\(.*\)\.yml/\1/')
        fi
        return 0
    fi

    # Multiple files - let user choose
    echo -e "${CYAN}Available stacks:${NC}"
    echo ""

    local i=1
    local stacks=()
    for file in "${compose_files[@]}"; do
        local stack_name
        local basename_file=$(basename "$file")
        if [[ "$basename_file" == "docker-compose.yml" ]]; then
            stack_name="default"
        else
            stack_name=$(echo "$basename_file" | sed 's/docker-compose\.\(.*\)\.yml/\1/')
        fi
        stacks+=("$stack_name")

        # Count services in this file
        local service_count=$(grep -cE "^  [a-zA-Z0-9_-]+:$" "$file" 2>/dev/null || echo 0)
        echo -e "  ${GREEN}${i})${NC} ${stack_name} (${service_count} services)"
        ((i++))
    done
    echo ""

    read -p "Select stack [1]: " stack_choice
    stack_choice=${stack_choice:-1}

    if [[ ! "$stack_choice" =~ ^[0-9]+$ ]] || [[ $stack_choice -lt 1 ]] || [[ $stack_choice -gt ${#compose_files[@]} ]]; then
        print_error "Invalid selection"
        return 1
    fi

    local idx=$((stack_choice - 1))
    SETTINGS_COMPOSE_FILE="${compose_files[$idx]}"
    SETTINGS_CURRENT_STACK="${stacks[$idx]}"

    return 0
}

#######################################
# Container settings menu
#######################################
container_settings_menu() {
    while true; do
        print_header "Container Settings"

        # Select stack first
        if ! select_settings_stack; then
            press_any_key
            return
        fi

        echo -e "${CYAN}Current stack:${NC} ${GREEN}${SETTINGS_CURRENT_STACK}${NC}"
        echo -e "${CYAN}Compose file:${NC} $(basename "$SETTINGS_COMPOSE_FILE")"
        echo ""

        echo -e "${CYAN}Options:${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Attach Device to Container"
        echo -e "  ${GREEN}2)${NC} Remove Device from Container"
        echo -e "  ${GREEN}3)${NC} Set Memory Limits"
        echo -e "  ${GREEN}4)${NC} Set Shared Memory (shm_size)"
        echo -e "  ${GREEN}5)${NC} Set CPU Limits"
        echo -e "  ${GREEN}6)${NC} View Container Settings"
        echo ""
        echo -e "  ${RED}0)${NC} Back to Main Menu"
        echo ""

        read -p "Select option: " choice

        case $choice in
            1) attach_device_menu ;;
            2) remove_device_menu ;;
            3) set_memory_limits_menu ;;
            4) set_shm_size_menu ;;
            5) set_cpu_limits_menu ;;
            6) view_container_settings ;;
            0) return ;;
            *) print_error "Invalid option" ;;
        esac
    done
}

#######################################
# Get services from compose file
#######################################
get_compose_services() {
    local compose_file="${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
    if [[ ! -f "$compose_file" ]]; then
        return
    fi
    grep -E "^  [a-zA-Z0-9_-]+:$" "$compose_file" | sed 's/://' | sed 's/^  //' | sort
}

#######################################
# Select a service from compose file
#######################################
select_service() {
    local prompt="${1:-Select service}"
    local services=($(get_compose_services))

    if [[ ${#services[@]} -eq 0 ]]; then
        print_error "No services found in compose file"
        return 1
    fi

    echo ""
    echo -e "${CYAN}Available Services:${NC}"
    echo ""

    local i=1
    for service in "${services[@]}"; do
        local status=""
        if is_service_running "$service" 2>/dev/null; then
            status=" ${GREEN}[running]${NC}"
        fi
        printf "  ${GREEN}%2d)${NC} %-25s%b\n" "$i" "$service" "$status"
        ((i++))
    done

    echo ""
    read -p "${prompt} (number): " selection

    if [[ -z "$selection" ]] || [[ ! "$selection" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [[ $selection -ge 1 && $selection -le ${#services[@]} ]]; then
        SELECTED_SERVICE="${services[$((selection-1))]}"
        return 0
    fi

    return 1
}

#######################################
# List available devices
#######################################
list_available_devices() {
    echo -e "${CYAN}Common device paths:${NC}"
    echo ""

    # Serial ports
    echo -e "  ${YELLOW}Serial Ports:${NC}"
    for dev in /dev/ttyUSB* /dev/ttyACM* /dev/ttyAMA* /dev/ttyS*; do
        if [[ -e "$dev" ]]; then
            local info=""
            if command -v udevadm &>/dev/null; then
                info=$(udevadm info -q property "$dev" 2>/dev/null | grep -E "ID_MODEL=|ID_VENDOR=" | head -2 | tr '\n' ' ')
            fi
            echo -e "    ${GREEN}${dev}${NC} ${info}"
        fi
    done 2>/dev/null

    # USB devices
    echo ""
    echo -e "  ${YELLOW}USB Devices:${NC}"
    for dev in /dev/bus/usb/*/*; do
        if [[ -e "$dev" ]]; then
            echo -e "    ${GREEN}${dev}${NC}"
        fi
    done 2>/dev/null | head -10

    # Video devices
    echo ""
    echo -e "  ${YELLOW}Video Devices:${NC}"
    for dev in /dev/video*; do
        if [[ -e "$dev" ]]; then
            echo -e "    ${GREEN}${dev}${NC}"
        fi
    done 2>/dev/null

    # GPIO (Raspberry Pi)
    if [[ -e "/dev/gpiomem" ]]; then
        echo ""
        echo -e "  ${YELLOW}GPIO:${NC}"
        echo -e "    ${GREEN}/dev/gpiomem${NC}"
    fi

    # I2C
    echo ""
    echo -e "  ${YELLOW}I2C Devices:${NC}"
    for dev in /dev/i2c-*; do
        if [[ -e "$dev" ]]; then
            echo -e "    ${GREEN}${dev}${NC}"
        fi
    done 2>/dev/null

    # SPI
    echo ""
    echo -e "  ${YELLOW}SPI Devices:${NC}"
    for dev in /dev/spidev*; do
        if [[ -e "$dev" ]]; then
            echo -e "    ${GREEN}${dev}${NC}"
        fi
    done 2>/dev/null

    echo ""
}

#######################################
# Attach device to container
#######################################
attach_device_menu() {
    print_header "Attach Device to Container"

    if ! select_service "Select container to attach device"; then
        press_any_key
        return
    fi

    local service="$SELECTED_SERVICE"
    echo ""
    echo -e "${CYAN}Selected:${NC} ${GREEN}${service}${NC}"
    echo ""

    # Show currently attached devices
    local current_devices=$(get_service_devices "$service")
    if [[ -n "$current_devices" ]]; then
        echo -e "${CYAN}Currently attached devices:${NC}"
        echo "$current_devices" | while read -r dev; do
            echo -e "  ${YELLOW}${dev}${NC}"
        done
        echo ""
    fi

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Quick device selection (presets)"
    echo -e "  ${GREEN}2)${NC} Manual device path entry"
    echo ""

    read -p "Selection [1]: " attach_choice
    attach_choice=${attach_choice:-1}

    case $attach_choice in
        1)
            quick_device_attach "$service"
            # Offer to restart after quick attach
            if is_service_running "$service" 2>/dev/null; then
                echo ""
                if confirm "Restart ${service} to apply changes?"; then
                    docker compose restart "$service"
                    print_success "${service} restarted"
                fi
            fi
            return
            ;;
        2)
            # Manual entry
            ;;
        *)
            return
            ;;
    esac

    # Show available devices for manual entry
    list_available_devices

    echo -e "${CYAN}Enter device path to attach:${NC}"
    echo -e "${YELLOW}Examples: /dev/ttyUSB0, /dev/ttyACM0, /dev/video0${NC}"
    echo ""

    read -p "Device path: " device_path

    if [[ -z "$device_path" ]]; then
        print_warning "No device specified"
        press_any_key
        return
    fi

    # Validate device exists
    if [[ ! -e "$device_path" ]]; then
        print_warning "Device ${device_path} does not exist"
        if ! confirm "Add anyway?"; then
            press_any_key
            return
        fi
    fi

    # Ask for container path (usually same as host)
    echo ""
    read -p "Container path [${device_path}]: " container_path
    container_path="${container_path:-$device_path}"

    # Add device to compose file
    if add_device_to_service "$service" "$device_path" "$container_path"; then
        print_success "Device ${device_path} attached to ${service}"

        # Offer to restart container
        if is_service_running "$service" 2>/dev/null; then
            echo ""
            if confirm "Restart ${service} to apply changes?"; then
                docker compose restart "$service"
                print_success "${service} restarted"
            fi
        fi
    else
        print_error "Failed to attach device"
    fi

    press_any_key
}

#######################################
# Get current devices for a service
#######################################
get_service_devices() {
    local service=$1
    local in_service=false
    local in_devices=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
            continue
        fi

        if $in_service; then
            # Check if we left the service block
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                break
            fi

            if [[ "$line" =~ ^[[:space:]]+devices:[[:space:]]*$ ]]; then
                in_devices=true
                continue
            fi

            if $in_devices; then
                # Check if we left devices block
                if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_]+: ]]; then
                    break
                fi
                # Extract device path
                if [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.*) ]]; then
                    echo "${BASH_REMATCH[1]}"
                fi
            fi
        fi
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
}

#######################################
# Add device to service in compose file
#######################################
add_device_to_service() {
    local service=$1
    local host_device=$2
    local container_device=$3
    local device_mapping="${host_device}:${container_device}"

    # Check if device already exists
    local current_devices=$(get_service_devices "$service")
    if echo "$current_devices" | grep -q "${host_device}"; then
        print_warning "Device ${host_device} already attached to ${service}"
        return 1
    fi

    local temp_file=$(mktemp)
    local in_service=false
    local in_devices=false
    local devices_added=false
    local service_indent=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect service block
        if [[ "$line" =~ ^([[:space:]]{2})${service}:[[:space:]]*$ ]]; then
            in_service=true
            service_indent="${BASH_REMATCH[1]}"
            echo "$line" >> "$temp_file"
            continue
        fi

        if $in_service && ! $devices_added; then
            # Check if we found existing devices section
            if [[ "$line" =~ ^[[:space:]]+devices:[[:space:]]*$ ]]; then
                in_devices=true
                echo "$line" >> "$temp_file"
                continue
            fi

            # If in devices section, add our device after last device
            if $in_devices; then
                if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                    echo "$line" >> "$temp_file"
                    continue
                else
                    # End of devices list, add our device
                    echo "      - ${device_mapping}" >> "$temp_file"
                    devices_added=true
                    in_devices=false
                    in_service=false
                fi
            fi

            # Check if we're at a new top-level property in service
            if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_]+: ]] && ! $in_devices; then
                # No devices section exists, create one before this property
                echo "    devices:" >> "$temp_file"
                echo "      - ${device_mapping}" >> "$temp_file"
                devices_added=true
                in_service=false
            fi

            # Check if we left the service block entirely
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                if ! $devices_added; then
                    # Add devices before leaving service
                    echo "    devices:" >> "$temp_file"
                    echo "      - ${device_mapping}" >> "$temp_file"
                    devices_added=true
                fi
                in_service=false
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"

    mv "$temp_file" "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
    return 0
}

#######################################
# Remove device from container
#######################################
remove_device_menu() {
    print_header "Remove Device from Container"

    if ! select_service "Select container"; then
        press_any_key
        return
    fi

    local service="$SELECTED_SERVICE"
    echo ""

    # Get current devices
    local devices=($(get_service_devices "$service"))

    if [[ ${#devices[@]} -eq 0 ]]; then
        print_warning "No devices attached to ${service}"
        press_any_key
        return
    fi

    echo -e "${CYAN}Attached devices:${NC}"
    echo ""

    local i=1
    for dev in "${devices[@]}"; do
        echo -e "  ${GREEN}${i})${NC} ${dev}"
        ((i++))
    done

    echo ""
    read -p "Select device to remove (number): " selection

    if [[ -z "$selection" ]] || [[ ! "$selection" =~ ^[0-9]+$ ]]; then
        return
    fi

    if [[ $selection -ge 1 && $selection -le ${#devices[@]} ]]; then
        local device_to_remove="${devices[$((selection-1))]}"

        if remove_device_from_service "$service" "$device_to_remove"; then
            print_success "Device removed from ${service}"

            if is_service_running "$service" 2>/dev/null; then
                echo ""
                if confirm "Restart ${service} to apply changes?"; then
                    docker compose restart "$service"
                fi
            fi
        fi
    fi

    press_any_key
}

#######################################
# Remove device from service
#######################################
remove_device_from_service() {
    local service=$1
    local device_pattern=$2

    local temp_file=$(mktemp)
    local in_service=false
    local in_devices=false
    local device_count=0
    local removed=false

    # First pass: count devices
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
            continue
        fi
        if $in_service; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                break
            fi
            if [[ "$line" =~ ^[[:space:]]+devices: ]]; then
                in_devices=true
                continue
            fi
            if $in_devices && [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                ((device_count++))
            fi
            if $in_devices && [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_]+: ]]; then
                break
            fi
        fi
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"

    # Second pass: remove device (and devices: section if last device)
    in_service=false
    in_devices=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
            echo "$line" >> "$temp_file"
            continue
        fi

        if $in_service; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                in_service=false
            fi

            if [[ "$line" =~ ^[[:space:]]+devices:[[:space:]]*$ ]]; then
                in_devices=true
                if [[ $device_count -gt 1 ]]; then
                    echo "$line" >> "$temp_file"
                fi
                continue
            fi

            if $in_devices; then
                if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_]+: ]]; then
                    in_devices=false
                elif [[ "$line" =~ ${device_pattern} ]]; then
                    removed=true
                    continue
                elif [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                    echo "$line" >> "$temp_file"
                    continue
                fi
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"

    mv "$temp_file" "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
    return 0
}

#######################################
# Set memory limits menu
#######################################
set_memory_limits_menu() {
    print_header "Set Memory Limits"

    if ! select_service "Select container"; then
        press_any_key
        return
    fi

    local service="$SELECTED_SERVICE"
    echo ""

    # Show current limits
    local current_mem=$(get_service_property "$service" "mem_limit")
    local current_memswap=$(get_service_property "$service" "memswap_limit")

    echo -e "${CYAN}Current settings for ${service}:${NC}"
    echo -e "  mem_limit:     ${current_mem:-not set}"
    echo -e "  memswap_limit: ${current_memswap:-not set}"
    echo ""

    echo -e "${CYAN}Memory limit format:${NC}"
    echo -e "  ${YELLOW}Examples: 512m, 1g, 2g, 256m${NC}"
    echo -e "  ${YELLOW}Leave empty to remove limit${NC}"
    echo ""

    read -p "Memory limit (mem_limit): " mem_limit

    if [[ -n "$mem_limit" ]]; then
        # Validate format
        if [[ ! "$mem_limit" =~ ^[0-9]+[kmgKMG]?$ ]]; then
            print_error "Invalid format. Use numbers with optional k/m/g suffix"
            press_any_key
            return
        fi
    fi

    read -p "Memory + Swap limit (memswap_limit) [same as mem_limit]: " memswap_limit

    # Set the limits
    if [[ -n "$mem_limit" ]]; then
        set_service_property "$service" "mem_limit" "$mem_limit"
        print_success "mem_limit set to ${mem_limit}"

        memswap_limit="${memswap_limit:-$mem_limit}"
        set_service_property "$service" "memswap_limit" "$memswap_limit"
        print_success "memswap_limit set to ${memswap_limit}"
    else
        remove_service_property "$service" "mem_limit"
        remove_service_property "$service" "memswap_limit"
        print_info "Memory limits removed"
    fi

    if is_service_running "$service" 2>/dev/null; then
        echo ""
        if confirm "Restart ${service} to apply changes?"; then
            docker compose up -d "$service"
            print_success "${service} restarted"
        fi
    fi

    press_any_key
}

#######################################
# Set shm_size menu
#######################################
set_shm_size_menu() {
    print_header "Set Shared Memory Size (shm_size)"

    if ! select_service "Select container"; then
        press_any_key
        return
    fi

    local service="$SELECTED_SERVICE"
    echo ""

    # Show current shm_size
    local current_shm=$(get_service_property "$service" "shm_size")

    echo -e "${CYAN}Current shm_size for ${service}:${NC} ${current_shm:-not set (default 64m)}"
    echo ""
    echo -e "${CYAN}shm_size is useful for:${NC}"
    echo -e "  - Browsers (Chrome/Firefox in containers)"
    echo -e "  - Machine learning workloads"
    echo -e "  - Applications using shared memory for IPC"
    echo ""
    echo -e "${YELLOW}Format: 64m, 128m, 256m, 512m, 1g, 2g${NC}"
    echo ""

    read -p "Enter shm_size (leave empty to remove): " shm_size

    if [[ -n "$shm_size" ]]; then
        if [[ ! "$shm_size" =~ ^[0-9]+[kmgKMG]?$ ]]; then
            print_error "Invalid format"
            press_any_key
            return
        fi

        set_service_property "$service" "shm_size" "$shm_size"
        print_success "shm_size set to ${shm_size}"
    else
        remove_service_property "$service" "shm_size"
        print_info "shm_size removed (will use default 64m)"
    fi

    if is_service_running "$service" 2>/dev/null; then
        echo ""
        if confirm "Restart ${service} to apply changes?"; then
            docker compose up -d "$service"
            print_success "${service} restarted"
        fi
    fi

    press_any_key
}

#######################################
# Set CPU limits menu
#######################################
set_cpu_limits_menu() {
    print_header "Set CPU Limits"

    if ! select_service "Select container"; then
        press_any_key
        return
    fi

    local service="$SELECTED_SERVICE"
    echo ""

    # Show current limits
    local current_cpus=$(get_service_property "$service" "cpus")
    local current_cpu_shares=$(get_service_property "$service" "cpu_shares")

    echo -e "${CYAN}Current CPU settings for ${service}:${NC}"
    echo -e "  cpus:       ${current_cpus:-not set}"
    echo -e "  cpu_shares: ${current_cpu_shares:-not set}"
    echo ""
    echo -e "${CYAN}CPU limit options:${NC}"
    echo -e "  ${YELLOW}cpus${NC}: Number of CPUs (e.g., 0.5, 1, 1.5, 2)"
    echo -e "  ${YELLOW}cpu_shares${NC}: Relative weight (default 1024)"
    echo ""

    read -p "CPU limit (cpus, e.g., 0.5 for half a CPU): " cpus

    if [[ -n "$cpus" ]]; then
        if [[ ! "$cpus" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            print_error "Invalid format. Use decimal number (e.g., 0.5, 1, 2)"
            press_any_key
            return
        fi

        set_service_property "$service" "cpus" "$cpus"
        print_success "cpus set to ${cpus}"
    else
        remove_service_property "$service" "cpus"
        print_info "CPU limit removed"
    fi

    if is_service_running "$service" 2>/dev/null; then
        echo ""
        if confirm "Restart ${service} to apply changes?"; then
            docker compose up -d "$service"
            print_success "${service} restarted"
        fi
    fi

    press_any_key
}

#######################################
# Get a property value from a service
#######################################
get_service_property() {
    local service=$1
    local property=$2
    local in_service=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
            continue
        fi

        if $in_service; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                break
            fi

            if [[ "$line" =~ ^[[:space:]]+${property}:[[:space:]]*(.*) ]]; then
                local value="${BASH_REMATCH[1]}"
                # Remove quotes
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                echo "$value"
                return
            fi
        fi
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
}

#######################################
# Set a property value for a service
#######################################
set_service_property() {
    local service=$1
    local property=$2
    local value=$3

    local temp_file=$(mktemp)
    local in_service=false
    local property_set=false
    local after_image=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect service block
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
            echo "$line" >> "$temp_file"
            continue
        fi

        if $in_service && ! $property_set; then
            # Check if property already exists
            if [[ "$line" =~ ^([[:space:]]+)${property}:[[:space:]]* ]]; then
                echo "${BASH_REMATCH[1]}${property}: ${value}" >> "$temp_file"
                property_set=true
                continue
            fi

            # Track if we've passed the image line (good place to add properties)
            if [[ "$line" =~ ^[[:space:]]+image: ]]; then
                after_image=true
            fi

            # Add property after container_name if it exists, or after image
            if [[ "$line" =~ ^[[:space:]]+container_name: ]] || ($after_image && [[ "$line" =~ ^[[:space:]]{4}[a-z_]+: ]]); then
                echo "$line" >> "$temp_file"
                if ! $property_set && [[ "$line" =~ ^[[:space:]]+container_name: ]]; then
                    echo "    ${property}: ${value}" >> "$temp_file"
                    property_set=true
                fi
                continue
            fi

            # Check if we left the service block
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                if ! $property_set; then
                    echo "    ${property}: ${value}" >> "$temp_file"
                    property_set=true
                fi
                in_service=false
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"

    mv "$temp_file" "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
}

#######################################
# Remove a property from a service
#######################################
remove_service_property() {
    local service=$1
    local property=$2

    local temp_file=$(mktemp)
    local in_service=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]{2}${service}:[[:space:]]*$ ]]; then
            in_service=true
        elif [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
            in_service=false
        fi

        if $in_service && [[ "$line" =~ ^[[:space:]]+${property}: ]]; then
            continue
        fi

        echo "$line" >> "$temp_file"
    done < "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"

    mv "$temp_file" "${SETTINGS_COMPOSE_FILE:-$COMPOSE_FILE}"
}

#######################################
# View all settings for containers
#######################################
view_container_settings() {
    print_header "Container Settings Overview"

    local services=($(get_compose_services))

    for service in "${services[@]}"; do
        echo -e "${CYAN}${BOLD}${service}${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Devices
        local devices=$(get_service_devices "$service")
        if [[ -n "$devices" ]]; then
            echo -e "  ${GREEN}Devices:${NC}"
            echo "$devices" | while read -r dev; do
                echo -e "    - ${dev}"
            done
        fi

        # Memory
        local mem_limit=$(get_service_property "$service" "mem_limit")
        local memswap=$(get_service_property "$service" "memswap_limit")
        if [[ -n "$mem_limit" ]] || [[ -n "$memswap" ]]; then
            echo -e "  ${GREEN}Memory:${NC}"
            [[ -n "$mem_limit" ]] && echo -e "    mem_limit: ${mem_limit}"
            [[ -n "$memswap" ]] && echo -e "    memswap_limit: ${memswap}"
        fi

        # SHM
        local shm=$(get_service_property "$service" "shm_size")
        if [[ -n "$shm" ]]; then
            echo -e "  ${GREEN}Shared Memory:${NC} ${shm}"
        fi

        # CPU
        local cpus=$(get_service_property "$service" "cpus")
        local cpu_shares=$(get_service_property "$service" "cpu_shares")
        if [[ -n "$cpus" ]] || [[ -n "$cpu_shares" ]]; then
            echo -e "  ${GREEN}CPU:${NC}"
            [[ -n "$cpus" ]] && echo -e "    cpus: ${cpus}"
            [[ -n "$cpu_shares" ]] && echo -e "    cpu_shares: ${cpu_shares}"
        fi

        # Privileged
        local privileged=$(get_service_property "$service" "privileged")
        if [[ "$privileged" == "true" ]]; then
            echo -e "  ${RED}Privileged:${NC} yes"
        fi

        echo ""
    done

    press_any_key
}

#######################################
# Quick device attach (for common devices)
# Arguments:
#   $1 - Service name
#######################################
quick_device_attach() {
    local service=$1

    print_header "Quick Device Attach - ${service}"

    echo -e "${CYAN}Common Device Presets:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} USB Serial      /dev/ttyUSB0"
    echo -e "  ${GREEN}2)${NC} USB Serial #2   /dev/ttyUSB1"
    echo -e "  ${GREEN}3)${NC} ACM Serial      /dev/ttyACM0"
    echo -e "  ${GREEN}4)${NC} ACM Serial #2   /dev/ttyACM1"
    echo -e "  ${GREEN}5)${NC} Zigbee (both)   /dev/ttyUSB0 + /dev/ttyUSB1"
    echo -e "  ${GREEN}6)${NC} Z-Wave          /dev/ttyACM0"
    echo -e "  ${GREEN}7)${NC} Webcam          /dev/video0"
    echo -e "  ${GREEN}8)${NC} GPIO (RPi)      /dev/gpiomem + /dev/mem"
    echo -e "  ${GREEN}9)${NC} All USB         /dev/bus/usb"
    echo ""
    echo -e "  ${GREEN}c)${NC} Custom path..."
    echo -e "  ${GREEN}l)${NC} List available serial devices"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Selection: " choice

    case $choice in
        1) add_device_to_service "$service" "/dev/ttyUSB0" "/dev/ttyUSB0" ;;
        2) add_device_to_service "$service" "/dev/ttyUSB1" "/dev/ttyUSB1" ;;
        3) add_device_to_service "$service" "/dev/ttyACM0" "/dev/ttyACM0" ;;
        4) add_device_to_service "$service" "/dev/ttyACM1" "/dev/ttyACM1" ;;
        5)
            add_device_to_service "$service" "/dev/ttyUSB0" "/dev/ttyUSB0"
            add_device_to_service "$service" "/dev/ttyUSB1" "/dev/ttyUSB1"
            ;;
        6) add_device_to_service "$service" "/dev/ttyACM0" "/dev/ttyACM0" ;;
        7) add_device_to_service "$service" "/dev/video0" "/dev/video0" ;;
        8)
            add_device_to_service "$service" "/dev/gpiomem" "/dev/gpiomem"
            add_device_to_service "$service" "/dev/mem" "/dev/mem"
            ;;
        9) add_device_to_service "$service" "/dev/bus/usb" "/dev/bus/usb" ;;
        c|C)
            echo ""
            echo -e "${CYAN}Available serial devices:${NC}"
            ls -la /dev/ttyUSB* /dev/ttyACM* /dev/ttyAMA* 2>/dev/null || echo "  No serial devices found"
            echo ""
            read -p "Enter device path (host): " host_path
            if [[ -n "$host_path" ]]; then
                read -p "Container path [${host_path}]: " container_path
                container_path=${container_path:-$host_path}
                add_device_to_service "$service" "$host_path" "$container_path"
            fi
            ;;
        l|L)
            echo ""
            echo -e "${CYAN}Available serial devices:${NC}"
            echo ""
            ls -la /dev/ttyUSB* 2>/dev/null | sed 's/^/  /' || true
            ls -la /dev/ttyACM* 2>/dev/null | sed 's/^/  /' || true
            ls -la /dev/ttyAMA* 2>/dev/null | sed 's/^/  /' || true
            ls -la /dev/serial/by-id/* 2>/dev/null | sed 's/^/  /' || true
            echo ""
            press_any_key
            quick_device_attach "$service"
            return
            ;;
        0|"")
            return
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            quick_device_attach "$service"
            return
            ;;
    esac

    if [[ "$choice" != "0" ]] && [[ "$choice" != "" ]] && [[ "$choice" != "l" ]] && [[ "$choice" != "L" ]]; then
        print_success "Device attached to ${service}"
        press_any_key
    fi
}

