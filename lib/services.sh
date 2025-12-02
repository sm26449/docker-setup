#!/bin/bash

#######################################
# Services Management Functions
#######################################

# Array to hold selected services
declare -a SELECTED_SERVICES=()

# Current stack name (set by select_stack)
CURRENT_STACK="${DEFAULT_STACK:-default}"

# Associative array to track dependency connections
# Format: DEPENDENCY_CONNECTIONS[service]="container_name:host:port"
declare -A DEPENDENCY_CONNECTIONS=()

# Track variables that were set from existing containers (skip port availability check)
declare -A VARS_FROM_EXISTING_CONTAINERS=()

#######################################
# Detect running containers by service type
# Returns container info for services matching the type
# Arguments:
#   $1 - Service type (mosquitto, influxdb, etc.)
# Output:
#   Lines of "container_name|image|host|port"
#######################################
detect_running_containers() {
    local service_type="$1"

    # Map service types to image patterns
    local image_patterns=""
    case "$service_type" in
        mosquitto|mqtt)
            image_patterns="mosquitto|emqx|hivemq|rabbitmq.*mqtt"
            ;;
        influxdb)
            image_patterns="influxdb"
            ;;
        grafana)
            image_patterns="grafana"
            ;;
        mariadb|mysql)
            image_patterns="mariadb|mysql"
            ;;
        mongodb)
            image_patterns="mongo"
            ;;
        redis)
            image_patterns="redis"
            ;;
        *)
            image_patterns="$service_type"
            ;;
    esac

    # Get running containers matching the pattern
    docker ps --format '{{.Names}}|{{.Image}}|{{.Ports}}' 2>/dev/null | while read line; do
        local name=$(echo "$line" | cut -d'|' -f1)
        local image=$(echo "$line" | cut -d'|' -f2)
        local ports=$(echo "$line" | cut -d'|' -f3)

        if echo "$image" | grep -qiE "$image_patterns"; then
            # Extract first mapped port (host:container format)
            local host_port=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | head -1 | cut -d: -f2)
            [[ -z "$host_port" ]] && host_port=$(echo "$ports" | grep -oE '[0-9]+/tcp' | head -1 | cut -d/ -f1)

            # Use container name as host (for Docker network communication)
            # This allows services to communicate via container name instead of localhost
            echo "${name}|${image}|${name}|${host_port:-N/A}"
        fi
    done
}

#######################################
# Show detected containers and let user choose
# Arguments:
#   $1 - Service type (mosquitto, influxdb, etc.)
#   $2 - Required by (parent service name)
# Returns:
#   0 if user chose existing container (sets DEPENDENCY_CONNECTIONS)
#   1 if user wants to create new container
#   2 if user wants to skip dependency
#######################################
prompt_dependency_choice() {
    local service_type="$1"
    local required_by="$2"

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Dependency: ${BOLD}${service_type}${NC} ${CYAN}(required by ${required_by})${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Detect running containers
    local containers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && containers+=("$line")
    done < <(detect_running_containers "$service_type")

    if [[ ${#containers[@]} -gt 0 ]]; then
        echo ""
        echo -e "${GREEN}Found running ${service_type} containers:${NC}"
        echo ""

        local i=1
        for container in "${containers[@]}"; do
            local name=$(echo "$container" | cut -d'|' -f1)
            local image=$(echo "$container" | cut -d'|' -f2)
            local host=$(echo "$container" | cut -d'|' -f3)
            local port=$(echo "$container" | cut -d'|' -f4)

            echo -e "  ${GREEN}${i})${NC} ${BOLD}${name}${NC}"
            echo -e "     Image: ${image}"
            echo -e "     Address: ${host}:${port}"
            echo ""
            ((i++))
        done

        echo -e "  ${YELLOW}n)${NC} Create ${BOLD}NEW${NC} ${service_type} container (with suffix: ${required_by}-${service_type})"
        echo -e "  ${RED}s)${NC} Skip - I'll configure ${service_type} manually later"
        echo ""

        local choice
        read -p "Select option [1]: " choice
        choice=${choice:-1}

        if [[ "$choice" == "n" || "$choice" == "N" ]]; then
            return 1  # Create new
        elif [[ "$choice" == "s" || "$choice" == "S" ]]; then
            return 2  # Skip
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#containers[@]} ]]; then
            # User selected existing container
            local selected="${containers[$((choice-1))]}"
            local name=$(echo "$selected" | cut -d'|' -f1)
            local host=$(echo "$selected" | cut -d'|' -f3)
            local port=$(echo "$selected" | cut -d'|' -f4)

            # Store connection info
            DEPENDENCY_CONNECTIONS["${required_by}_${service_type}"]="${name}:${host}:${port}"

            print_success "Will use existing container: ${name} (${host}:${port})"
            return 0  # Use existing
        else
            print_warning "Invalid selection, will create new container"
            return 1
        fi
    else
        echo ""
        echo -e "${YELLOW}No running ${service_type} containers found.${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Create ${BOLD}NEW${NC} ${service_type} container (with suffix: ${required_by}-${service_type})"
        echo -e "  ${RED}2)${NC} Skip - I'll configure ${service_type} manually later"
        echo ""

        local choice
        read -p "Select option [1]: " choice
        choice=${choice:-1}

        if [[ "$choice" == "2" ]]; then
            return 2  # Skip
        else
            return 1  # Create new
        fi
    fi
}


#######################################
# Apply dependency connection info to service variables
# Reads variable mappings from template's dependencies section
# Arguments:
#   $1 - Service name (can include variant like "service:variant")
#######################################
apply_dependency_connections() {
    local service="$1"
    local base_service=$(get_base_service_name "$service")
    local template=$(get_service_template_file "$service")

    if [[ ! -f "$template" ]]; then
        return 0
    fi

    # Parse dependencies section to get variable mappings
    local in_deps=false
    local current_dep=""
    local in_vars=false
    local in_creds=false

    while IFS= read -r line <&4 || [[ -n "$line" ]]; do
        # Enter dependencies section
        if [[ "$line" == "dependencies:" ]]; then
            in_deps=true
            continue
        fi

        # Skip if not in dependencies section
        if ! $in_deps; then
            continue
        fi

        # Exit dependencies section (new top-level key)
        if [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_deps=false
            continue
        fi

        # New dependency entry (- name: xxx)
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
            current_dep="${BASH_REMATCH[1]}"
            current_dep=$(echo "$current_dep" | xargs)  # trim
            in_vars=false
            in_creds=false
            continue
        fi

        # Old format (- depname) - skip, no variable mapping
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-z][a-z0-9_-]*)$ ]]; then
            current_dep="${BASH_REMATCH[1]}"
            in_vars=false
            in_creds=false
            continue
        fi

        # Enter variables subsection
        if [[ "$line" =~ ^[[:space:]]+variables:[[:space:]]*$ ]]; then
            in_vars=true
            in_creds=false
            continue
        fi

        # Enter credentials subsection
        if [[ "$line" =~ ^[[:space:]]+credentials:[[:space:]]*$ ]]; then
            in_creds=true
            in_vars=false
            continue
        fi

        # Check if we have connection info for this dependency
        local dep_key="${base_service}_${current_dep}"

        # Parse variable mapping (VAR_NAME: "value with ${HOST} ${PORT}")
        if $in_vars && [[ "$line" =~ ^[[:space:]]+([A-Z][A-Z0-9_]*):[[:space:]]*[\"\']?(.*)[\"\']?$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_template="${BASH_REMATCH[2]}"
            # Remove trailing quote if present
            var_template="${var_template%\"}"
            var_template="${var_template%\'}"

            if [[ -n "${DEPENDENCY_CONNECTIONS[$dep_key]}" ]]; then
                local info="${DEPENDENCY_CONNECTIONS[$dep_key]}"
                local container=$(echo "$info" | cut -d: -f1)
                local host=$(echo "$info" | cut -d: -f2)
                local port=$(echo "$info" | cut -d: -f3)

                # Substitute ${HOST}, ${PORT}, ${CONTAINER} in template
                local final_value="$var_template"
                final_value="${final_value//\$\{HOST\}/$host}"
                final_value="${final_value//\$\{PORT\}/$port}"
                final_value="${final_value//\$\{CONTAINER\}/$container}"

                # Only print once per dependency
                if [[ -z "${_printed_deps[$dep_key]}" ]]; then
                    echo -e "  ${GREEN}→${NC} Using ${current_dep}: ${BOLD}${container}${NC} (${host}:${port})"
                    _printed_deps[$dep_key]=1
                fi

                set_env_var "$var_name" "$final_value"

                # Mark this variable as coming from existing container (skip port availability check)
                VARS_FROM_EXISTING_CONTAINERS["$var_name"]=1
            fi
        fi

        # Parse credentials mapping (DEST_VAR: "SOURCE_VAR")
        # This copies the value of SOURCE_VAR from .env to DEST_VAR
        if $in_creds && [[ "$line" =~ ^[[:space:]]+([A-Z][A-Z0-9_]*):[[:space:]]*[\"\']?([A-Z][A-Z0-9_]*)[\"\']?$ ]]; then
            local dest_var="${BASH_REMATCH[1]}"
            local source_var="${BASH_REMATCH[2]}"

            # Only copy if we have connection info (dependency was selected/created)
            if [[ -n "${DEPENDENCY_CONNECTIONS[$dep_key]}" ]]; then
                # Check if source var exists in .env
                local source_value=$(get_env_var "$source_var")
                if [[ -n "$source_value" ]]; then
                    set_env_var "$dest_var" "$source_value"
                    VARS_FROM_EXISTING_CONTAINERS["$dest_var"]=1
                    echo -e "  ${GREEN}→${NC} Copied ${source_var} → ${dest_var}"
                fi
            fi
        fi
    done 4< "$template"
}

# Helper array to track printed dependencies
declare -A _printed_deps=()

#######################################
# Select or create a stack
#######################################
select_stack() {
    print_header "Select Stack"

    echo -e "${CYAN}Stacks allow you to group related services together.${NC}"
    echo -e "${YELLOW}Each stack gets its own compose file and can be managed independently.${NC}"
    echo ""

    # Get existing stacks
    local existing_stacks=($(get_existing_stacks))

    echo -e "${CYAN}Existing Stacks:${NC}"
    echo ""

    local i=1
    if [[ ${#existing_stacks[@]} -gt 0 ]]; then
        for stack in "${existing_stacks[@]}"; do
            local service_count=0
            local compose_file="${SCRIPT_DIR}/docker-compose.${stack}.yml"
            [[ "$stack" == "default" ]] && compose_file="${SCRIPT_DIR}/docker-compose.yml"

            if [[ -f "$compose_file" ]]; then
                service_count=$(grep -c "^  [a-zA-Z0-9_-]*:$" "$compose_file" 2>/dev/null || echo "0")
            fi

            echo -e "  ${GREEN}${i})${NC} ${BOLD}${stack}${NC} ${YELLOW}(${service_count} services)${NC}"
            ((i++))
        done
    else
        echo -e "  ${YELLOW}No existing stacks found${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}n)${NC} Create ${BOLD}new${NC} stack"
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Select stack or create new [1]: " choice
    choice=${choice:-1}

    if [[ "$choice" == "0" ]]; then
        return 1
    fi

    if [[ "$choice" == "n" ]] || [[ "$choice" == "N" ]]; then
        create_new_stack
        return $?
    fi

    # Select existing stack
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice - 1))
        if [[ $idx -ge 0 ]] && [[ $idx -lt ${#existing_stacks[@]} ]]; then
            CURRENT_STACK="${existing_stacks[$idx]}"
            print_success "Selected stack: ${CURRENT_STACK}"
            return 0
        fi
    fi

    # Default to first stack or "default"
    if [[ ${#existing_stacks[@]} -gt 0 ]]; then
        CURRENT_STACK="${existing_stacks[0]}"
    else
        CURRENT_STACK="default"
    fi

    print_success "Selected stack: ${CURRENT_STACK}"
    return 0
}

#######################################
# Create a new stack
#######################################
create_new_stack() {
    echo ""
    echo -e "${CYAN}Create New Stack${NC}"
    echo ""
    echo -e "Stack name should be lowercase, alphanumeric, hyphens allowed."
    echo -e "Examples: ${GREEN}homelab${NC}, ${GREEN}monitoring${NC}, ${GREEN}home-automation${NC}"
    echo ""

    read -p "Stack name: " stack_name

    # Validate stack name
    if [[ -z "$stack_name" ]]; then
        print_error "Stack name cannot be empty"
        return 1
    fi

    # Convert to lowercase and validate
    stack_name=$(echo "$stack_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    if [[ ! "$stack_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        print_error "Invalid stack name. Use lowercase letters, numbers, and hyphens only."
        return 1
    fi

    # Check if stack already exists
    local compose_file="${SCRIPT_DIR}/docker-compose.${stack_name}.yml"
    if [[ -f "$compose_file" ]]; then
        print_warning "Stack '${stack_name}' already exists"
        if confirm "Use existing stack?"; then
            CURRENT_STACK="$stack_name"
            return 0
        fi
        return 1
    fi

    CURRENT_STACK="$stack_name"
    print_success "Created new stack: ${CURRENT_STACK}"
    return 0
}

#######################################
# Get compose file path for current stack
#######################################
get_compose_file() {
    local stack="${1:-$CURRENT_STACK}"
    if [[ "$stack" == "default" ]]; then
        echo "${SCRIPT_DIR}/docker-compose.yml"
    else
        echo "${SCRIPT_DIR}/docker-compose.${stack}.yml"
    fi
}

#######################################
# Get container name with stack prefix
#######################################
get_container_name() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"

    if [[ "$stack" == "default" ]]; then
        echo "$service"
    else
        echo "${stack}-${service}"
    fi
}

#######################################
# Get service data directory
#######################################
get_service_data_dir() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    if [[ "$stack" == "default" ]]; then
        echo "${docker_root}/${service}"
    else
        echo "${docker_root}/${stack}/${service}"
    fi
}

#######################################
# Add services menu
#######################################
add_services_menu() {
    print_header "Add Services"

    if ! command_exists docker; then
        print_error "Docker is not installed. Please run Server Setup first."
        press_any_key
        return
    fi

    # First, select or create a stack
    if ! select_stack; then
        return
    fi

    echo ""
    print_header "Add Services to Stack: ${CURRENT_STACK}"

    # Reset selected services
    SELECTED_SERVICES=()

    # Get available services
    local services=($(get_available_services))

    if [[ ${#services[@]} -eq 0 ]]; then
        print_error "No service templates found in ${TEMPLATES_DIR}"
        print_info "Use 'Define Template' to create service templates"
        press_any_key
        return
    fi

    echo -e "${CYAN}Available Services:${NC}"
    echo -e "${YELLOW}(Services marked with ▶ have multiple variants)${NC}"
    echo ""

    # Display services in columns
    local i=1
    local cols=3
    for service in "${services[@]}"; do
        local status=""
        local variant_marker=""

        if service_in_compose "$service"; then
            status=" ${GREEN}[installed]${NC}"
        fi

        # Check if service has variants
        if has_service_variants "$service"; then
            variant_marker="${CYAN}▶${NC}"
        fi

        # Use printf %b to interpret escape sequences
        printf "  ${GREEN}%2d)${NC} %-18s%b%b" "$i" "$service" "$variant_marker" "$status"
        if (( i % cols == 0 )); then
            echo ""
        fi
        ((i++))
    done
    echo ""
    echo ""

    echo -e "${CYAN}Enter service numbers (comma-separated or ranges):${NC}"
    echo -e "${YELLOW}Example: 1,3,5-8 or 'all' for all services${NC}"
    echo ""

    read -p "Selection: " selection

    if [[ -z "$selection" ]]; then
        return
    fi

    # Parse selection
    parse_service_selection "$selection" "${services[@]}"

    if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
        print_warning "No services selected"
        press_any_key
        return
    fi

    echo ""
    echo -e "${CYAN}Selected services:${NC}"
    for service in "${SELECTED_SERVICES[@]}"; do
        echo -e "  • ${service}"
    done
    echo ""

    # Check and prompt for dependencies
    check_dependencies

    # Confirm selection
    echo ""
    echo -e "${CYAN}Final selection (including dependencies):${NC}"
    for service in "${SELECTED_SERVICES[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${service}"
    done
    echo ""

    if ! confirm "Proceed with installation?"; then
        return
    fi

    # Collect variables for each service
    collect_service_variables

    # Auto-backup before making changes
    auto_backup "before-add-${CURRENT_STACK}"

    # Generate compose file
    generate_compose_file

    # Start services
    if confirm "Start services now?"; then
        start_services
    fi

    press_any_key
}

#######################################
# Get available services from templates
# Each folder with service.yaml is a service
# Variants are service.*.yaml files within the same folder
#######################################
get_available_services() {
    local services=()

    if [[ -d "$TEMPLATES_DIR" ]]; then
        for dir in "$TEMPLATES_DIR"/*/; do
            if [[ -f "${dir}service.yaml" ]]; then
                services+=("$(basename "$dir")")
            fi
        done
    fi

    echo "${services[@]}" | tr ' ' '\n' | sort
}

#######################################
# Get variants for a service
# Looks for service.*.yaml files in the service folder
# Returns list of variant names (the * part)
# Arguments:
#   $1 - Service name
#######################################
get_service_variants() {
    local service=$1
    local service_dir="${TEMPLATES_DIR}/${service}"
    local variants=()

    if [[ -d "$service_dir" ]]; then
        # Look for service.*.yaml files (e.g., service.docker.yaml, service.victron.yaml)
        for variant_file in "$service_dir"/service.*.yaml; do
            if [[ -f "$variant_file" ]]; then
                # Extract variant name: service.docker.yaml -> docker
                local filename=$(basename "$variant_file")
                local variant_name="${filename#service.}"
                variant_name="${variant_name%.yaml}"
                variants+=("$variant_name")
            fi
        done
    fi

    echo "${variants[@]}"
}

#######################################
# Check if service has variants
# Arguments:
#   $1 - Service name
# Returns:
#   0 if has variants, 1 if not
#######################################
has_service_variants() {
    local service=$1
    local variants=$(get_service_variants "$service")
    [[ -n "$variants" ]]
}

#######################################
# Select service variant from sub-menu
# Arguments:
#   $1 - Service name
# Returns:
#   Sets SELECTED_VARIANT to service name
#   Sets SELECTED_VARIANT_FILE to template file path (service.yaml or service.*.yaml)
#######################################
select_service_variant() {
    local service=$1
    local service_dir="${TEMPLATES_DIR}/${service}"
    local variants=($(get_service_variants "$service"))

    SELECTED_VARIANT=""
    SELECTED_VARIANT_FILE=""

    if [[ ${#variants[@]} -eq 0 ]]; then
        # No variants, use main service.yaml directly
        SELECTED_VARIANT="$service"
        SELECTED_VARIANT_FILE="${service_dir}/service.yaml"
        return 0
    fi

    echo ""
    print_header "Select ${service} variant"

    # Get main service description
    local main_template="${service_dir}/service.yaml"
    local main_desc=""
    if [[ -f "$main_template" ]]; then
        main_desc=$(grep -E "^description:" "$main_template" | head -1 | sed 's/description:[[:space:]]*//' | tr -d '"')
    fi

    echo -e "${CYAN}Available variants:${NC}"
    echo ""

    local i=1
    local variant_list=()
    local variant_files=()

    # Option for main template (if it has compose section - i.e., it's not just a marker)
    if grep -q "^compose:" "$main_template" 2>/dev/null; then
        local display_name="${service} (default)"
        echo -e "  ${GREEN}${i})${NC} ${BOLD}${display_name}${NC}"
        [[ -n "$main_desc" ]] && echo -e "     ${YELLOW}${main_desc}${NC}"
        variant_list+=("$service")
        variant_files+=("$main_template")
        ((i++))
    fi

    # Options for variant files
    for variant in "${variants[@]}"; do
        local variant_template="${service_dir}/service.${variant}.yaml"
        local variant_desc=""
        if [[ -f "$variant_template" ]]; then
            variant_desc=$(grep -E "^description:" "$variant_template" | head -1 | sed 's/description:[[:space:]]*//' | tr -d '"')
        fi

        echo -e "  ${GREEN}${i})${NC} ${BOLD}${variant}${NC}"
        [[ -n "$variant_desc" ]] && echo -e "     ${YELLOW}${variant_desc}${NC}"
        variant_list+=("${service}:${variant}")
        variant_files+=("$variant_template")
        ((i++))
    done

    echo ""
    echo -e "  ${GREEN}0)${NC} Cancel"
    echo ""

    read -p "Select variant [1]: " choice
    choice=${choice:-1}

    if [[ "$choice" == "0" ]]; then
        return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#variant_list[@]} ]]; then
        SELECTED_VARIANT="${variant_list[$((choice-1))]}"
        SELECTED_VARIANT_FILE="${variant_files[$((choice-1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

# Associative array to map service to its template file
# Format: SERVICE_TEMPLATE_FILES[service_name]="/path/to/service.yaml"
# For variants: SERVICE_TEMPLATE_FILES[service:variant]="/path/to/service.variant.yaml"
declare -A SERVICE_TEMPLATE_FILES=()

#######################################
# Get template file path for a service
# Uses SERVICE_TEMPLATE_FILES if available, otherwise defaults
# Arguments:
#   $1 - Service name (can be "service" or "service:variant")
# Returns:
#   Path to the template file
#######################################
get_service_template_file() {
    local service=$1

    # Check if we have a stored path from selection
    if [[ -n "${SERVICE_TEMPLATE_FILES[$service]}" ]]; then
        echo "${SERVICE_TEMPLATE_FILES[$service]}"
        return
    fi

    # For "service:variant" format, construct the path
    if [[ "$service" == *":"* ]]; then
        local base_service="${service%%:*}"
        local variant="${service#*:}"
        echo "${TEMPLATES_DIR}/${base_service}/service.${variant}.yaml"
        return
    fi

    # Default to service.yaml
    echo "${TEMPLATES_DIR}/${service}/service.yaml"
}

#######################################
# Get the base service name (without variant)
# Arguments:
#   $1 - Service name (can be "service" or "service:variant")
# Returns:
#   Base service name
#######################################
get_base_service_name() {
    local service=$1
    echo "${service%%:*}"
}

#######################################
# Get the variant name if present
# Arguments:
#   $1 - Service name (can be "service" or "service:variant")
# Returns:
#   Variant name or empty string
#######################################
get_variant_name() {
    local service=$1
    if [[ "$service" == *":"* ]]; then
        echo "${service#*:}"
    else
        echo ""
    fi
}

#######################################
# Parse service selection
# Arguments:
#   $1 - Selection string (e.g., "1,3,5-8" or "all")
#   $@ - Array of services
#######################################
parse_service_selection() {
    local selection=$1
    shift
    local services=("$@")
    local temp_selection=()

    # Reset template files mapping
    SERVICE_TEMPLATE_FILES=()

    if [[ "$selection" == "all" ]]; then
        temp_selection=("${services[@]}")
    else
        # Split by comma
        IFS=',' read -ra parts <<< "$selection"

        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d ' ')

            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # Range
                local start=${BASH_REMATCH[1]}
                local end=${BASH_REMATCH[2]}
                for ((i=start; i<=end; i++)); do
                    if [[ $i -ge 1 && $i -le ${#services[@]} ]]; then
                        temp_selection+=("${services[$((i-1))]}")
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                # Single number
                if [[ $part -ge 1 && $part -le ${#services[@]} ]]; then
                    temp_selection+=("${services[$((part-1))]}")
                fi
            fi
        done
    fi

    # Process each selected service - check for variants
    for service in "${temp_selection[@]}"; do
        if has_service_variants "$service"; then
            # Service has variants - show sub-menu
            if select_service_variant "$service"; then
                SELECTED_SERVICES+=("$SELECTED_VARIANT")
                SERVICE_TEMPLATE_FILES["$SELECTED_VARIANT"]="$SELECTED_VARIANT_FILE"
            fi
        else
            # No variants - add directly
            SELECTED_SERVICES+=("$service")
            SERVICE_TEMPLATE_FILES["$service"]="${TEMPLATES_DIR}/${service}/service.yaml"
        fi
    done

    # Remove duplicates
    SELECTED_SERVICES=($(echo "${SELECTED_SERVICES[@]}" | tr ' ' '\n' | sort -u))
}

#######################################
# Check dependencies for selected services
# Now with smart detection of existing containers
#######################################
check_dependencies() {
    local all_deps=()

    # Reset dependency connections and existing container tracking
    DEPENDENCY_CONNECTIONS=()
    VARS_FROM_EXISTING_CONTAINERS=()

    for service in "${SELECTED_SERVICES[@]}"; do
        local template=$(get_service_template_file "$service")
        local base_service=$(get_base_service_name "$service")
        if [[ -f "$template" ]]; then
            local deps=$(parse_yaml_array "$template" "dependencies")
            for dep in $deps; do
                # Check if dependency is already selected or installed in current stack
                if [[ ! " ${SELECTED_SERVICES[*]} " =~ " ${dep} " ]]; then
                    if ! service_in_compose "$dep"; then
                        all_deps+=("$dep:$base_service")
                    fi
                fi
            done
        fi
    done

    # Remove duplicates
    local unique_deps=($(echo "${all_deps[@]}" | tr ' ' '\n' | sort -u))

    if [[ ${#unique_deps[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Dependency Resolution${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    for dep_info in "${unique_deps[@]}"; do
        local dep=$(echo "$dep_info" | cut -d: -f1)
        local required_by=$(echo "$dep_info" | cut -d: -f2)

        # Use smart dependency resolution
        prompt_dependency_choice "$dep" "$required_by"
        local result=$?

        case $result in
            0)
                # User chose existing container - connection info saved
                # Don't add to SELECTED_SERVICES
                ;;
            1)
                # User wants to create new container
                if [[ -d "${TEMPLATES_DIR}/${dep}" ]]; then
                    # Add with suffix to track relationship
                    local suffixed_dep="${required_by}-${dep}"
                    SELECTED_SERVICES+=("$dep")
                    # Store the suffix info for later use in compose generation
                    DEPENDENCY_CONNECTIONS["${required_by}_${dep}_suffix"]="$suffixed_dep"
                    print_info "Will create new container: ${suffixed_dep}"
                else
                    print_warning "Template for ${dep} not found. You may need to configure manually."
                fi
                ;;
            2)
                # User chose to skip - they'll configure manually
                print_info "Skipped ${dep} - configure connection manually in .env"
                ;;
        esac
    done

    # Remove duplicates
    SELECTED_SERVICES=($(echo "${SELECTED_SERVICES[@]}" | tr ' ' '\n' | sort -u))

    # Suggest Portainer for non-default stacks (for Portainer labels to work)
    suggest_portainer_for_stack
}

#######################################
# Suggest Portainer installation for stack labels
#######################################
suggest_portainer_for_stack() {
    local stack="${CURRENT_STACK:-default}"

    # Only suggest for non-default stacks
    if [[ "$stack" == "default" ]]; then
        return
    fi

    # Skip if Portainer is already selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " portainer " ]]; then
        return
    fi

    # Check if Portainer is installed in any stack
    local portainer_installed=false
    for compose_file in "${SCRIPT_DIR}"/docker-compose*.yml; do
        if [[ -f "$compose_file" ]]; then
            if grep -qE "^  portainer:|^  [a-z]+-portainer:" "$compose_file" 2>/dev/null; then
                portainer_installed=true
                break
            fi
        fi
    done

    # Also check if container is running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "portainer"; then
        portainer_installed=true
    fi

    if [[ "$portainer_installed" == false ]]; then
        echo ""
        echo -e "${YELLOW}Recommendation:${NC}"
        echo -e "  Stack ${BOLD}${stack}${NC} uses Portainer labels for grouping."
        echo -e "  ${CYAN}Portainer${NC} is not installed yet."
        echo ""

        if [[ -d "${TEMPLATES_DIR}/portainer" ]]; then
            if confirm "  Install Portainer for container management?"; then
                SELECTED_SERVICES+=("portainer")
                # Remove duplicates
                SELECTED_SERVICES=($(echo "${SELECTED_SERVICES[@]}" | tr ' ' '\n' | sort -u))
            fi
        else
            print_info "  Install Portainer separately to view stack groupings."
        fi
    fi
}

#######################################
# Collect variables for each service
#######################################
collect_service_variables() {
    print_header "Configure Services"

    # Load existing env
    load_env

    # Check if initial setup was done
    local docker_root=$(get_env_var "DOCKER_ROOT")
    if [[ -z "$docker_root" ]]; then
        print_warning "Initial configuration not found."
        print_info "Running initial setup wizard..."
        echo ""
        if declare -f run_initial_setup &>/dev/null; then
            run_initial_setup
        else
            set_global_variables
        fi
    else
        # Show current config
        echo -e "${CYAN}Current Configuration:${NC}"
        echo -e "  DOCKER_ROOT: ${GREEN}${docker_root}${NC}"
        echo -e "  PUID/PGID:   ${GREEN}$(get_env_var PUID)/$(get_env_var PGID)${NC}"
        echo -e "  Timezone:    ${GREEN}$(get_env_var TZ)${NC}"
        echo -e "  Network:     ${GREEN}$(get_env_var DOCKER_NETWORK)${NC}"
        echo ""

        if confirm "Modify global settings?"; then
            run_initial_setup
        fi
    fi

    echo ""
    echo -e "${BOLD}${CYAN}Service-Specific Configuration${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Collect per-service variables
    for service in "${SELECTED_SERVICES[@]}"; do
        collect_service_vars "$service"
    done
}

#######################################
# Set global variables (legacy fallback)
#######################################
set_global_variables() {
    echo -e "${CYAN}Global Configuration:${NC}"
    echo ""

    # Docker root directory
    local default_root="/docker-storage"
    local current_root=$(get_env_var "DOCKER_ROOT")
    if [[ -z "$current_root" ]]; then
        read -p "  Docker storage path [${default_root}]: " input_root
        local docker_root="${input_root:-$default_root}"
        set_env_var "DOCKER_ROOT" "$docker_root"

        # Create directory
        if [[ ! -d "$docker_root" ]]; then
            mkdir -p "$docker_root"
            print_success "Created: $docker_root"
        fi
    else
        echo -e "  DOCKER_ROOT: ${GREEN}${current_root}${NC} (existing)"
    fi

    # PUID - Auto-detect
    local default_puid="${AUTO_PUID:-$(id -u 2>/dev/null || echo 1000)}"
    local current_puid=$(get_env_var "PUID")
    if [[ -z "$current_puid" ]]; then
        echo -e "  PUID: ${GREEN}${default_puid}${NC} (auto-detected)"
        set_env_var "PUID" "$default_puid"
    else
        echo -e "  PUID: ${GREEN}${current_puid}${NC} (existing)"
    fi

    # PGID - Auto-detect
    local default_pgid="${AUTO_PGID:-$(id -g 2>/dev/null || echo 1000)}"
    local current_pgid=$(get_env_var "PGID")
    if [[ -z "$current_pgid" ]]; then
        echo -e "  PGID: ${GREEN}${default_pgid}${NC} (auto-detected)"
        set_env_var "PGID" "$default_pgid"
    else
        echo -e "  PGID: ${GREEN}${current_pgid}${NC} (existing)"
    fi

    # Timezone - Auto-detect
    local default_tz="${AUTO_TZ:-Europe/Bucharest}"
    local current_tz=$(get_env_var "TZ")
    if [[ -z "$current_tz" ]]; then
        echo -e "  TZ: ${GREEN}${default_tz}${NC} (auto-detected)"
        set_env_var "TZ" "$default_tz"
    else
        echo -e "  TZ: ${GREEN}${current_tz}${NC} (existing)"
    fi

    # Network
    local default_network="${DEFAULT_NETWORK_NAME:-docker-services}"
    local current_network=$(get_env_var "DOCKER_NETWORK")
    if [[ -z "$current_network" ]]; then
        set_env_var "DOCKER_NETWORK" "$default_network"
        set_env_var "DOCKER_SUBNET" "${DEFAULT_NETWORK_SUBNET:-172.20.0.0/16}"
    fi

    echo ""
}

#######################################
# Collect variables for a specific service
# Simple approach: extract VAR=value from template, write to .env
# Passwords are auto-generated, other values use defaults
# User can edit .env later with sed or manually
# Arguments:
#   $1 - Service name
#######################################
collect_service_vars() {
    local service=$1
    local base_service=$(get_base_service_name "$service")
    local template=$(get_service_template_file "$service")

    if [[ ! -f "$template" ]]; then
        print_warning "Template not found for ${service}"
        return
    fi

    # Extract compose service name from template (e.g., "fronius-inverters" from "  fronius-inverters:")
    local compose_service_name=""
    local in_compose=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^compose:[[:space:]]*\| ]]; then
            in_compose=true
            continue
        fi
        if $in_compose && [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+): ]]; then
            compose_service_name="${BASH_REMATCH[1]}"
            break
        fi
    done < "$template"
    compose_service_name="${compose_service_name:-$base_service}"

    echo -e "${CYAN}Configuring ${BOLD}${service}${NC}${CYAN}:${NC}"

    # Create service directories (use compose_service_name for directory path to match volume mounts)
    create_service_dirs "$compose_service_name"

    # Apply dependency connection info if available
    apply_dependency_connections "$service"

    # Set TELEGRAF_MODE based on variant selection (for backward compatibility with lib/telegraf.sh)
    local variant=$(get_variant_name "$service")
    if [[ "$base_service" == "telegraf" ]] && [[ -n "$variant" ]]; then
        set_env_var "TELEGRAF_MODE" "$variant"
        print_info "Telegraf mode: ${variant}"
    fi

    # Simple parsing using grep to extract variables
    # This is more portable than complex bash regex
    # NOTE: We use file descriptor 3 to avoid conflicts with stdin (used by read -p prompts)
    local in_vars=false
    local current_var=""
    local current_default=""
    local current_generate=""
    local current_prompt=""
    local current_description=""

    while IFS= read -r line <&3 || [[ -n "$line" ]]; do
        # Enter variables section
        if [[ "$line" == "variables:" ]]; then
            in_vars=true
            continue
        fi

        # Skip if not in variables section yet
        $in_vars || continue

        # Exit variables section (line starts with letter, no leading space)
        # Check for lines like "compose:", "config_files:", "dependencies:", etc.
        case "$line" in
            compose:*|config_files:*|dependencies:*|name:*|description:*)
                # Process last variable before exiting
                if [[ -n "$current_var" ]]; then
                    process_template_variable "$current_var" "$current_default" "$current_generate" "$current_prompt" "$current_description"
                    current_var=""
                fi
                in_vars=false
                continue
                ;;
        esac

        # Detect new variable: line starts with 2 spaces then uppercase letter
        # Use simple pattern matching instead of regex
        local trimmed="${line#  }"  # Remove leading 2 spaces
        if [[ "$line" != "$trimmed" ]] && [[ "$trimmed" =~ ^[A-Z] ]] && [[ "$trimmed" == *: ]]; then
            # This is a variable declaration line
            # Process previous variable first
            if [[ -n "$current_var" ]]; then
                process_template_variable "$current_var" "$current_default" "$current_generate" "$current_prompt" "$current_description"
            fi
            # Extract variable name (remove trailing colon)
            current_var="${trimmed%:}"
            current_default=""
            current_generate=""
            current_prompt=""
            current_description=""
            continue
        fi

        # Check for default value (line with "default:")
        if [[ "$line" == *"default:"* ]]; then
            # Extract value after "default: "
            local after_default="${line#*default: }"
            # Remove surrounding quotes if present
            after_default="${after_default#\"}"
            after_default="${after_default%\"}"
            current_default="$after_default"
        fi

        # Check for description (line with "description:")
        if [[ "$line" == *"description:"* ]]; then
            local after_desc="${line#*description: }"
            after_desc="${after_desc#\"}"
            after_desc="${after_desc%\"}"
            current_description="$after_desc"
        fi

        # Check for generate type (line with "generate:")
        if [[ "$line" == *"generate:"* ]]; then
            # Extract value after "generate: "
            local after_generate="${line#*generate: }"
            # Trim any trailing whitespace
            current_generate="${after_generate%% *}"
            current_generate="${current_generate%%$'\r'}"
        fi

        # Check for prompt flag (line with "prompt:")
        if [[ "$line" == *"prompt:"* ]]; then
            local after_prompt="${line#*prompt: }"
            after_prompt="${after_prompt%% *}"
            after_prompt="${after_prompt%%$'\r'}"
            current_prompt="$after_prompt"
        fi
    done 3< "$template"

    # Process last variable if we're still in vars section
    if [[ -n "$current_var" ]]; then
        process_template_variable "$current_var" "$current_default" "$current_generate" "$current_prompt" "$current_description"
    fi

    # Generate config files for this service
    generate_service_config_files "$service" "$base_service" "$compose_service_name" || true

    # Copy template files to service directory
    copy_template_files "$service" "$base_service" "$compose_service_name" || true

    # Run pre-deploy hooks
    run_service_hooks "$service" "pre_deploy" || true

    # Special post-processing for Telegraf - generate mode-specific config
    if [[ "$base_service" == "telegraf" ]]; then
        local telegraf_mode=$(get_env_var "TELEGRAF_MODE")
        telegraf_mode=${telegraf_mode:-"docker"}

        # Generate mode-specific configuration (from lib/telegraf.sh if available)
        if declare -f generate_telegraf_config &>/dev/null; then
            generate_telegraf_config "$telegraf_mode"
        fi

        # Show configuration tips
        echo ""
        echo -e "${CYAN}Telegraf configured in ${BOLD}${telegraf_mode}${NC}${CYAN} mode${NC}"

        if [[ "$telegraf_mode" == "victron" ]]; then
            echo -e "${YELLOW}Next steps:${NC}"
            echo -e "  1. Use menu option 12 (Telegraf Config) to configure MQTT connection"
            echo -e "  2. Set your Victron Portal ID"
            echo -e "  3. Regenerate configuration"
        fi
    fi

    echo ""
}

#######################################
# Process a template variable
# Decides whether to prompt user or use default
# Arguments:
#   $1 - Variable name
#   $2 - Default value
#   $3 - Generate type (password, random, or empty)
#   $4 - Prompt flag (true/false)
#   $5 - Description
#######################################
process_template_variable() {
    local var_name=$1
    local var_default=$2
    local var_generate=$3
    local var_prompt=$4
    local var_description=$5

    # Skip if already exists in .env
    if env_var_exists "$var_name"; then
        local current_val=$(get_env_var "$var_name")

        # For PORT variables, check if the existing port is still available
        # BUT skip this check if the variable was set from an existing container
        if [[ "$var_name" =~ _PORT$ ]] && [[ -z "${VARS_FROM_EXISTING_CONTAINERS[$var_name]}" ]]; then
            if ! is_port_available "$current_val" 2>/dev/null; then
                echo -e "    ${YELLOW}⚠ ${var_name}=${current_val} is already in use!${NC}"
                local new_port=$(find_available_port "$current_val" 2>/dev/null)
                echo -e "    ${CYAN}Suggested alternative: ${new_port}${NC}"
                read -p "    Use new port ${new_port}? [Y/n]: " use_new
                use_new=${use_new:-Y}
                if [[ "$use_new" =~ ^[Yy] ]]; then
                    set_env_var "$var_name" "$new_port"
                    echo -e "    ${var_name}: ${GREEN}${new_port}${NC} (updated)"
                else
                    read -p "    Enter custom port: " custom_port
                    if [[ -n "$custom_port" ]]; then
                        set_env_var "$var_name" "$custom_port"
                        echo -e "    ${var_name}: ${GREEN}${custom_port}${NC} (custom)"
                    else
                        echo -e "    ${var_name}: ${YELLOW}${current_val}${NC} (kept, may conflict!)"
                    fi
                fi
                return
            fi
        fi

        # Mask passwords
        if [[ "$var_name" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
            echo -e "    ${var_name}: ${GREEN}********${NC} (existing)"
        else
            echo -e "    ${var_name}: ${GREEN}${current_val}${NC} (existing)"
        fi
        return
    fi

    # If prompt is requested, ask user for input
    if [[ "$var_prompt" == "true" ]]; then
        prompt_for_variable "$var_name" "$var_default" "$var_description" "$var_generate"
    else
        # Use default value or generate
        set_variable_value "$var_name" "$var_default" "$var_generate"
    fi
}

#######################################
# Set a variable value in .env
# Auto-generates passwords, uses defaults for others
# Arguments:
#   $1 - Variable name
#   $2 - Default value
#   $3 - Generate type (password, random, or empty)
#######################################
set_variable_value() {
    local var_name=$1
    local var_default=$2
    local var_generate=$3

    # Skip if already exists in .env (double-check)
    if env_var_exists "$var_name"; then
        echo -e "    ${var_name}: ${GREEN}(existing)${NC}"
        return
    fi

    local value="$var_default"

    # Auto-generate passwords
    if [[ "$var_generate" == "password" ]]; then
        value=$(generate_password 20)
        echo -e "    ${var_name}: ${GREEN}[auto-generated password]${NC}"
    elif [[ "$var_generate" == "random" ]]; then
        value=$(generate_random_string 32)
        echo -e "    ${var_name}: ${GREEN}[auto-generated]${NC}"
    # For PORT variables without prompt, check availability and find alternative
    elif [[ "$var_name" =~ _PORT$ ]]; then
        if ! is_port_available "$value" 2>/dev/null; then
            local new_port=$(find_available_port "$value" 2>/dev/null)
            echo -e "    ${YELLOW}⚠ Port ${value} in use, using ${new_port}${NC}"
            value="$new_port"
        fi
        echo -e "    ${var_name}: ${GREEN}${value}${NC}"
    else
        echo -e "    ${var_name}: ${GREEN}${value:-<empty>}${NC}"
    fi

    # Write to .env
    set_env_var "$var_name" "$value"
}

#######################################
# Generate config files for a service
# Arguments:
#   $1 - Service name (can include variant like "service:variant")
#   $2 - Base service name (folder name)
#   $3 - Compose service name (for directory paths)
#######################################
generate_service_config_files() {
    local service=$1
    local base_service="${2:-$(get_base_service_name "$service")}"
    local compose_service_name="${3:-$base_service}"
    local stack="${CURRENT_STACK:-default}"
    local template=$(get_service_template_file "$service")
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root="${docker_root:-/docker-storage}"

    if [[ ! -f "$template" ]]; then
        return 0
    fi

    # Check if template has config_files section
    if ! grep -q "^config_files:" "$template" 2>/dev/null; then
        return 0
    fi

    local in_config_files=false
    local current_path=""
    local current_content=""
    local in_content=false
    local -A written_files=()  # Track files already written to prevent duplicates

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if we're entering config_files section
        if [[ "$line" == "config_files:" ]]; then
            in_config_files=true
            continue
        fi

        # Skip if not in config_files section
        if ! $in_config_files; then
            continue
        fi

        # Check if we've left config_files section (line starts with letter, no indent)
        if [[ "$line" =~ ^[a-z] ]]; then
            # Write last file if exists and not already written
            if [[ -n "$current_path" ]] && [[ -n "$current_content" ]] && [[ -z "${written_files[$current_path]}" ]]; then
                write_config_file "$compose_service_name" "$current_path" "$current_content" "$docker_root" "$stack"
                written_files[$current_path]=1
            fi
            current_path=""
            current_content=""
            in_config_files=false
            continue
        fi

        # New config file entry (starts with "  - path:")
        if [[ "$line" == "  - path:"* ]]; then
            # Write previous file if exists and not already written
            if [[ -n "$current_path" ]] && [[ -n "$current_content" ]] && [[ -z "${written_files[$current_path]}" ]]; then
                write_config_file "$compose_service_name" "$current_path" "$current_content" "$docker_root" "$stack"
                written_files[$current_path]=1
            fi
            # Extract path value
            current_path="${line#*path: }"
            current_path="${current_path#\"}"
            current_path="${current_path%\"}"
            current_content=""
            in_content=false
            continue
        fi

        # Content start (content: |)
        if [[ "$line" == *"content: |"* ]]; then
            in_content=true
            continue
        fi

        # Collect content lines (indented with 6 spaces)
        if $in_content && [[ -n "$current_path" ]]; then
            if [[ "$line" == "      "* ]] || [[ -z "$line" ]]; then
                # Remove the base indentation (6 spaces)
                local content_line="${line#      }"
                if [[ -n "$current_content" ]]; then
                    current_content="${current_content}"$'\n'"${content_line}"
                else
                    current_content="${content_line}"
                fi
            else
                # End of content block (line not indented enough)
                in_content=false
            fi
        fi
    done < "$template"

    # Write last file if exists and not already written
    if [[ -n "$current_path" ]] && [[ -n "$current_content" ]] && [[ -z "${written_files[$current_path]}" ]]; then
        write_config_file "$compose_service_name" "$current_path" "$current_content" "$docker_root" "$stack"
        written_files[$current_path]=1
    fi

    return 0
}

#######################################
# Write a config file for a service
# Arguments:
#   $1 - Service name (compose service name for directory path)
#   $2 - Relative path within service directory
#   $3 - File content
#   $4 - Docker root path
#   $5 - Stack name (optional, defaults to CURRENT_STACK)
#######################################
write_config_file() {
    local service=$1
    local rel_path=$2
    local content=$3
    local docker_root=$4
    local stack="${5:-${CURRENT_STACK:-default}}"

    # Build full path based on stack
    local full_path
    if [[ "$stack" == "default" ]]; then
        full_path="${docker_root}/${service}/${rel_path}"
    else
        full_path="${docker_root}/${stack}/${service}/${rel_path}"
    fi
    local dir_path=$(dirname "$full_path")

    # Create directory if needed
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
    fi

    # Only write if file doesn't exist (don't overwrite user configs)
    if [[ -f "$full_path" ]]; then
        print_info "  Config exists: ${rel_path} (skipped)"
        return
    fi

    # Substitute environment variables in content
    local final_content="$content"

    # Replace common variables
    final_content=$(echo "$final_content" | sed "s|\${DOCKER_ROOT}|${docker_root}|g")
    final_content=$(echo "$final_content" | sed "s|\${PUID}|$(get_env_var PUID)|g")
    final_content=$(echo "$final_content" | sed "s|\${PGID}|$(get_env_var PGID)|g")
    final_content=$(echo "$final_content" | sed "s|\${TZ}|$(get_env_var TZ)|g")

    # Replace all other ${VAR} patterns with values from .env
    while [[ "$final_content" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value=$(get_env_var "$var_name")
        # Escape special characters in value for sed
        var_value=$(printf '%s\n' "$var_value" | sed 's/[&/\]/\\&/g')
        final_content=$(echo "$final_content" | sed "s|\${${var_name}}|${var_value}|g")
    done

    # Write the file
    echo "$final_content" > "$full_path"
    print_success "  Created: ${rel_path}"
}

#######################################
# Copy template files to service directory
# Parses copy_files: section from service.yaml
# Arguments:
#   $1 - Service name (can include variant like "service:variant")
#   $2 - Base service name (template folder name)
#   $3 - Compose service name (for directory paths)
#######################################
copy_template_files() {
    local service=$1
    local base_service="${2:-$(get_base_service_name "$service")}"
    local compose_service_name="${3:-$base_service}"
    local stack="${CURRENT_STACK:-default}"
    local template=$(get_service_template_file "$service")
    local template_dir="${TEMPLATES_DIR}/${base_service}"
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root="${docker_root:-/docker-storage}"

    if [[ ! -f "$template" ]]; then
        return 0
    fi

    # Check if template has copy_files section
    if ! grep -q "^copy_files:" "$template" 2>/dev/null; then
        return 0
    fi

    # Build destination base path (use compose_service_name to match volume mounts)
    local dest_base
    if [[ "$stack" == "default" ]]; then
        dest_base="${docker_root}/${compose_service_name}"
    else
        dest_base="${docker_root}/${stack}/${compose_service_name}"
    fi

    local in_copy_files=false
    local current_src=""
    local current_dest=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if we're entering copy_files section
        if [[ "$line" == "copy_files:" ]]; then
            in_copy_files=true
            continue
        fi

        # Skip if not in copy_files section
        if ! $in_copy_files; then
            continue
        fi

        # Check if we've left copy_files section (line starts with letter, no indent)
        if [[ "$line" =~ ^[a-z] ]]; then
            in_copy_files=false
            continue
        fi

        # Parse source file (- src: filename)
        if [[ "$line" == *"- src:"* ]]; then
            current_src="${line#*src: }"
            current_src="${current_src#\"}"
            current_src="${current_src%\"}"
            current_src=$(echo "$current_src" | xargs)  # trim whitespace
            continue
        fi

        # Parse destination (dest: path)
        if [[ "$line" == *"dest:"* ]]; then
            current_dest="${line#*dest: }"
            current_dest="${current_dest#\"}"
            current_dest="${current_dest%\"}"
            current_dest=$(echo "$current_dest" | xargs)  # trim whitespace

            # Copy the file if we have both src and dest
            if [[ -n "$current_src" ]] && [[ -n "$current_dest" ]]; then
                local src_file="${template_dir}/${current_src}"
                local dest_file="${dest_base}/${current_dest}"
                local dest_dir=$(dirname "$dest_file")

                # Create destination directory
                mkdir -p "$dest_dir"

                # Only copy if source exists and dest doesn't (don't overwrite)
                if [[ -f "$src_file" ]]; then
                    if [[ ! -f "$dest_file" ]]; then
                        # Copy and substitute environment variables
                        if [[ "$src_file" == *.ini ]] || [[ "$src_file" == *.conf ]] || [[ "$src_file" == *.yaml ]] || [[ "$src_file" == *.yml ]]; then
                            # Text files - substitute env vars
                            envsubst < "$src_file" > "$dest_file"
                        else
                            # Binary or other files - direct copy
                            cp "$src_file" "$dest_file"
                        fi
                        print_success "  Copied: ${current_src} -> ${current_dest}"
                    else
                        print_info "  File exists: ${current_dest} (skipped)"
                    fi
                else
                    print_warning "  Source not found: ${current_src}"
                fi

                current_src=""
                current_dest=""
            fi
        fi
    done < "$template"

    return 0
}

#######################################
# Run service hooks (pre_deploy/post_deploy)
# Parses hooks: section from service.yaml
# Arguments:
#   $1 - Service name (can include variant like "service:variant")
#   $2 - Hook type (pre_deploy or post_deploy)
#######################################
run_service_hooks() {
    local service=$1
    local hook_type=$2
    local base_service=$(get_base_service_name "$service")
    local stack="${CURRENT_STACK:-default}"
    local template=$(get_service_template_file "$service")
    local template_dir="${TEMPLATES_DIR}/${base_service}"
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root="${docker_root:-/docker-storage}"

    if [[ ! -f "$template" ]]; then
        return 0
    fi

    # Check if template has hooks section
    if ! grep -q "^hooks:" "$template" 2>/dev/null; then
        return 0
    fi

    # Build service data path
    local service_data
    if [[ "$stack" == "default" ]]; then
        service_data="${docker_root}/${base_service}"
    else
        service_data="${docker_root}/${stack}/${base_service}"
    fi

    local container_name
    if [[ "$stack" == "default" ]]; then
        container_name="${base_service}"
    else
        container_name="${stack}-${base_service}"
    fi

    local in_hooks=false
    local in_target_hook=false
    local commands=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if we're entering hooks section
        if [[ "$line" == "hooks:" ]]; then
            in_hooks=true
            continue
        fi

        # Skip if not in hooks section
        if ! $in_hooks; then
            continue
        fi

        # Check if we've left hooks section (line starts with letter, no indent)
        if [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_hooks=false
            in_target_hook=false
            continue
        fi

        # Check for hook type (pre_deploy: or post_deploy:)
        if [[ "$line" == "  ${hook_type}:" ]]; then
            in_target_hook=true
            continue
        fi

        # Check if we're leaving target hook section (another hook type)
        if [[ "$line" == "  pre_deploy:" ]] || [[ "$line" == "  post_deploy:" ]]; then
            if [[ "$line" != "  ${hook_type}:" ]]; then
                in_target_hook=false
            fi
            continue
        fi

        # Collect commands (lines starting with "    - ")
        if $in_target_hook && [[ "$line" == "    - "* ]]; then
            local cmd="${line#    - }"
            cmd="${cmd#\"}"
            cmd="${cmd%\"}"
            commands+=("$cmd")
        fi
    done < "$template"

    # Execute collected commands
    if [[ ${#commands[@]} -gt 0 ]]; then
        print_info "Running ${hook_type} hooks for ${service}..."

        for cmd in "${commands[@]}"; do
            # Substitute variables in command
            cmd="${cmd//\$\{SERVICE_DATA\}/${service_data}}"
            cmd="${cmd//\$\{TEMPLATE_DIR\}/${template_dir}}"
            cmd="${cmd//\$\{CONTAINER_NAME\}/${container_name}}"
            cmd="${cmd//\$\{DOCKER_ROOT\}/${docker_root}}"
            cmd="${cmd//\$\{SERVICE\}/${service}}"
            cmd="${cmd//\$\{STACK\}/${stack}}"

            # Substitute environment variables from .env file
            while [[ "$cmd" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
                local var_name="${BASH_REMATCH[1]}"
                local var_value=$(get_env_var "$var_name")
                cmd="${cmd//\$\{${var_name}\}/${var_value}}"
            done

            print_info "  Executing: ${cmd}"
            if eval "$cmd"; then
                print_success "  Hook completed"
            else
                print_warning "  Hook returned non-zero exit code"
            fi
        done
    fi

    return 0
}

#######################################
# Prompt for a variable value
# Arguments:
#   $1 - Variable name
#   $2 - Default value
#   $3 - Description
#   $4 - Generate type (password, random, port, etc.)
#######################################
prompt_for_variable() {
    local var_name=$1
    local var_default=$2
    local var_description=$3
    local var_generate=$4

    # Check if variable already exists
    if env_var_exists "$var_name"; then
        local current_val=$(get_env_var "$var_name")
        # Mask passwords
        if [[ "$var_name" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
            echo -e "    ${var_name}: ${GREEN}********${NC} (existing)"
        else
            echo -e "    ${var_name}: ${GREEN}${current_val}${NC} (existing)"
        fi
        return
    fi

    # Handle PORT variables
    if [[ "$var_name" =~ _PORT$ ]]; then
        # Get default from config.sh if available
        local config_default="${DEFAULT_PORTS[$var_name]:-$var_default}"
        config_default=${config_default:-8080}

        # Check port availability
        local suggested_port=$config_default
        if command_exists ss || command_exists netstat; then
            if ! is_port_available "$config_default" 2>/dev/null; then
                suggested_port=$(find_available_port "$config_default" 2>/dev/null)
                if [[ "$suggested_port" != "$config_default" ]]; then
                    echo -e "    ${YELLOW}⚠ Port ${config_default} in use, suggesting ${suggested_port}${NC}"
                fi
            fi
        fi

        read -p "    ${var_name} [${suggested_port}]: " input_port
        local port="${input_port:-$suggested_port}"
        set_env_var "$var_name" "$port"
        return
    fi

    # Handle PASSWORD variables with menu
    if [[ "$var_generate" == "password" ]] || [[ "$var_name" =~ PASSWORD|SECRET ]]; then
        echo ""
        echo -e "    ${CYAN}${var_name}${NC}"
        if [[ -n "$var_description" ]]; then
            echo -e "    ${YELLOW}${var_description}${NC}"
        fi
        echo -e "      ${GREEN}1)${NC} Auto-generate secure password (recommended)"
        echo -e "      ${GREEN}2)${NC} Enter password manually"
        echo ""

        local choice
        read -p "      Choice [1]: " choice
        choice=${choice:-1}

        case $choice in
            2)
                while true; do
                    read -s -p "      Enter password: " password
                    echo ""
                    read -s -p "      Confirm password: " password2
                    echo ""

                    if [[ "$password" == "$password2" ]]; then
                        if [[ ${#password} -lt 8 ]]; then
                            echo -e "      ${RED}Password must be at least 8 characters${NC}"
                        else
                            set_env_var "$var_name" "$password"
                            echo -e "      ${GREEN}✓${NC} Password set"
                            break
                        fi
                    else
                        echo -e "      ${RED}Passwords don't match. Try again.${NC}"
                    fi
                done
                ;;
            *)
                local generated=$(generate_password 20)
                set_env_var "$var_name" "$generated"
                echo -e "      ${GREEN}Generated:${NC} ${generated}"
                echo -e "      ${YELLOW}⚠ Save this password!${NC}"
                ;;
        esac
        return
    fi

    # Handle random strings (tokens, secrets)
    if [[ "$var_generate" == "random" ]]; then
        local generated=$(generate_random_string 32)
        set_env_var "$var_name" "$generated"
        echo -e "    ${var_name}: ${GREEN}[auto-generated]${NC}"
        return
    fi

    # Regular variable prompt
    local prompt="    ${var_name}"
    if [[ -n "$var_description" ]]; then
        prompt="${prompt} (${var_description})"
    fi
    if [[ -n "$var_default" ]]; then
        prompt="${prompt} [${var_default}]"
    fi
    prompt="${prompt}: "

    read -p "$prompt" input_val
    local final_val="${input_val:-$var_default}"

    if [[ -n "$final_val" ]]; then
        set_env_var "$var_name" "$final_val"
    fi
}

#######################################
# Generate docker-compose.yml for current stack
#######################################
generate_compose_file() {
    print_header "Generating Docker Compose File"

    local stack="${CURRENT_STACK:-default}"

    # Get compose file path for this stack
    local compose_file=$(get_compose_file "$stack")

    # Get network configuration - each stack gets its own network
    local base_network=$(get_env_var "DOCKER_NETWORK")
    base_network=${base_network:-"docker-services"}

    local network_name
    if [[ "$stack" == "default" ]]; then
        network_name="$base_network"
    else
        network_name="${stack}-network"
    fi

    local network_subnet=$(get_env_var "DOCKER_SUBNET")
    network_subnet=${network_subnet:-"172.20.0.0/16"}

    print_info "Stack: ${stack}"
    print_info "Compose file: ${compose_file}"

    # Backup existing file
    if [[ -f "$compose_file" ]]; then
        cp "$compose_file" "${compose_file}.bak"
        print_info "Backed up existing compose file"
    fi

    # Initialize compose file if it doesn't exist or recreate if corrupted
    local needs_init=false
    if [[ ! -f "$compose_file" ]]; then
        needs_init=true
    elif ! grep -q "^services:" "$compose_file" 2>/dev/null; then
        needs_init=true
    fi

    if [[ "$needs_init" == true ]]; then
        cat > "$compose_file" << EOF
#######################################
# Docker Services - Stack: ${stack}
# Generated: $(date)
# Network: ${network_name}
#######################################

services:

EOF
        print_info "Created new compose file for stack: ${stack}"

        # Create Docker network if needed
        if declare -f create_docker_network &>/dev/null; then
            create_docker_network "$network_name"
        fi
    fi

    # Remove existing networks section (will be regenerated at the end)
    if grep -q "^networks:" "$compose_file" 2>/dev/null; then
        # Remove networks section and everything below it
        local temp_compose=$(mktemp)
        sed '/^networks:/,$d' "$compose_file" > "$temp_compose"
        mv "$temp_compose" "$compose_file"
    fi

    # Store compose file path for add_service_to_compose
    CURRENT_COMPOSE_FILE="$compose_file"

    # Add each service
    for service in "${SELECTED_SERVICES[@]}"; do
        add_service_to_compose "$service" "$stack"
    done

    # Add networks section at the end (only if services don't all use network_mode: host)
    local has_networked_services=false
    for service in "${SELECTED_SERVICES[@]}"; do
        local template=$(get_service_template_file "$service")
        if [[ -f "$template" ]]; then
            if ! grep -q "network_mode: host" "$template" 2>/dev/null; then
                has_networked_services=true
                break
            fi
        fi
    done

    if [[ "$has_networked_services" == true ]]; then
        cat >> "$compose_file" << EOF

networks:
  default:
    name: ${network_name}
    driver: bridge
EOF
    fi

    print_success "Docker Compose file generated: ${compose_file}"

    # Show generated passwords
    show_generated_credentials

    # Validate compose file
    if docker compose config &>/dev/null; then
        print_success "Compose file validation passed"
    else
        print_warning "Compose file validation warning"
        print_info "Run 'docker compose config' to see details"
    fi
}

#######################################
# Show generated credentials
#######################################
show_generated_credentials() {
    echo ""
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  IMPORTANT: Save these credentials!${NC}"
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local found_passwords=false

    if [[ -f "$ENV_FILE" ]]; then
        while IFS='=' read -r key value; do
            if [[ "$key" =~ PASSWORD|SECRET|TOKEN|ADMIN ]] && [[ -n "$value" ]]; then
                echo -e "  ${CYAN}${key}${NC}: ${GREEN}${value}${NC}"
                found_passwords=true
            fi
        done < "$ENV_FILE"
    fi

    if ! $found_passwords; then
        echo -e "  ${GREEN}No new credentials generated${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Credentials are stored in: ${ENV_FILE}${NC}"
    echo ""
}

#######################################
# Add a service to docker-compose.yml
# Arguments:
#   $1 - Service name
#   $2 - Stack name (optional)
#######################################
add_service_to_compose() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"
    stack="${stack:-default}"

    local base_service=$(get_base_service_name "$service")
    local template=$(get_service_template_file "$service")
    local compose_file="${CURRENT_COMPOSE_FILE:-$(get_compose_file "$stack")}"

    if [[ ! -f "$template" ]]; then
        print_warning "Template not found for ${service}, skipping"
        return
    fi

    # Extract compose block from service.yaml
    local compose_snippet=$(mktemp)
    local in_compose=false
    local compose_service_name=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^compose:[[:space:]]*\| ]]; then
            in_compose=true
            continue
        fi

        if $in_compose; then
            # Check if we've left the compose block (line not starting with space)
            if [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            # Extract service name from first line (e.g., "  fronius-inverters:")
            if [[ -z "$compose_service_name" ]] && [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+): ]]; then
                compose_service_name="${BASH_REMATCH[1]}"
            fi
            # Keep the indentation - services need 2-space indent under services: key
            echo "$line" >> "$compose_snippet"
        fi
    done < "$template"

    if [[ ! -s "$compose_snippet" ]]; then
        print_warning "No compose block found in ${service} template"
        rm -f "$compose_snippet"
        return
    fi

    # Use compose_service_name if found, fallback to base_service
    compose_service_name="${compose_service_name:-$base_service}"

    # Check if service already exists in compose file
    if service_in_compose "$compose_service_name" "$stack"; then
        print_warning "${compose_service_name} already in stack ${stack}, skipping"
        rm -f "$compose_snippet"
        return
    fi

    # Get data directory for this stack (use base_service for folder path)
    local data_dir=$(get_service_data_dir "$base_service" "$stack")
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    print_info "Adding ${service} to stack ${stack}..."
    print_info "  Service: ${compose_service_name}"
    print_info "  Data dir: ${data_dir}"

    # Check if this service needs to be built (has build: section)
    local needs_build=false
    local template_dir="${TEMPLATES_DIR}/${base_service}"
    if grep -q "build:" "$compose_snippet" 2>/dev/null; then
        needs_build=true
        print_info "  Build required: yes (local Dockerfile)"

        # Update build context to absolute path of template directory
        local temp_build=$(mktemp)
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Replace relative context (. or ./) with absolute template path
            if [[ "$line" == *"context:"* ]]; then
                # Extract indentation and replace the context value
                local indent="${line%%context:*}"
                line="${indent}context: ${template_dir}"
            fi
            echo "$line" >> "$temp_build"
        done < "$compose_snippet"
        mv "$temp_build" "$compose_snippet"
    fi

    # Transform the compose snippet for this stack
    local transformed_snippet=$(mktemp)
    local stack_container_name="${stack}-${compose_service_name}"

    # If not default stack, we need to:
    # 1. Update container_name to include stack prefix
    # 2. Update volume paths to include stack
    # 3. Add labels for Portainer grouping
    if [[ "$stack" != "default" ]]; then
        local first_line=true
        local added_labels=false

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Update container_name
            if [[ "$line" == *"container_name:"* ]]; then
                # Replace the container name with stack-prefixed version
                line=$(echo "$line" | sed "s/container_name:.*/container_name: ${stack_container_name}/")
            fi

            # Update volume paths: ${DOCKER_ROOT}/xxx -> ${DOCKER_ROOT}/stack/xxx
            # This adds stack prefix to any DOCKER_ROOT path for multi-tenant setups
            if [[ "$line" == *'${DOCKER_ROOT}/'* ]]; then
                line=$(echo "$line" | sed "s|\${DOCKER_ROOT}/|\${DOCKER_ROOT}/${stack}/|g")
            fi

            # Update depends_on references to use stack prefix
            if [[ "$line" == *"depends_on:"* ]]; then
                echo "$line" >> "$transformed_snippet"
                continue
            fi

            # Add labels after restart line (or after container_name if no restart)
            if [[ "$line" == *"restart:"* ]] && [[ "$added_labels" == false ]]; then
                echo "$line" >> "$transformed_snippet"
                echo "    labels:" >> "$transformed_snippet"
                echo "      - \"com.docker.compose.project=${stack}\"" >> "$transformed_snippet"
                echo "      - \"io.portainer.accesscontrol.teams=${stack}\"" >> "$transformed_snippet"
                added_labels=true
                continue
            fi

            echo "$line" >> "$transformed_snippet"
        done < "$compose_snippet"

        # If we didn't add labels yet, append them before the end
        if [[ "$added_labels" == false ]]; then
            # Add labels at the end of the service block
            echo "    labels:" >> "$transformed_snippet"
            echo "      - \"com.docker.compose.project=${stack}\"" >> "$transformed_snippet"
            echo "      - \"io.portainer.accesscontrol.teams=${stack}\"" >> "$transformed_snippet"
        fi

        mv "$transformed_snippet" "$compose_snippet"
    else
        rm -f "$transformed_snippet"
    fi

    # Check if we need to add depends_on for dependencies in same stack
    local deps_to_add=()
    local template_deps=$(parse_yaml_array "$template" "dependencies")

    for dep in $template_deps; do
        # Check if this dependency is being installed in the same stack
        # Either: 1) was created as new via prompt_dependency_choice, or
        #         2) is in the current SELECTED_SERVICES list for this stack
        local suffix_key="${base_service}_${dep}_suffix"
        local dep_in_stack=false

        # Check if created via prompt
        if [[ -n "${DEPENDENCY_CONNECTIONS[$suffix_key]}" ]]; then
            dep_in_stack=true
        fi

        # Check if in SELECTED_SERVICES (installed together in same session)
        for selected in "${SELECTED_SERVICES[@]}"; do
            local selected_base=$(get_base_service_name "$selected")
            if [[ "$selected_base" == "$dep" ]]; then
                dep_in_stack=true
                break
            fi
        done

        # Check if service already exists in this compose file
        if [[ -f "$compose_file" ]] && grep -q "^  ${dep}:" "$compose_file" 2>/dev/null; then
            dep_in_stack=true
        fi

        if $dep_in_stack; then
            deps_to_add+=("$dep")
        fi
    done

    # Add depends_on section if we have dependencies to add
    if [[ ${#deps_to_add[@]} -gt 0 ]]; then
        # Check if depends_on already exists in the snippet
        if ! grep -q "depends_on:" "$compose_snippet" 2>/dev/null; then
            # Find the right place to insert depends_on (after restart or container_name)
            local temp_deps=$(mktemp)
            local inserted=false

            while IFS= read -r line || [[ -n "$line" ]]; do
                echo "$line" >> "$temp_deps"

                # Insert after restart: line
                if [[ "$line" == *"restart:"* ]] && [[ "$inserted" == false ]]; then
                    echo "    depends_on:" >> "$temp_deps"
                    for dep in "${deps_to_add[@]}"; do
                        echo "      - ${dep}" >> "$temp_deps"
                    done
                    inserted=true
                fi
            done < "$compose_snippet"

            # If restart: wasn't found, append at the end
            if [[ "$inserted" == false ]]; then
                echo "    depends_on:" >> "$temp_deps"
                for dep in "${deps_to_add[@]}"; do
                    echo "      - ${dep}" >> "$temp_deps"
                done
            fi

            mv "$temp_deps" "$compose_snippet"
            print_info "  Added depends_on: ${deps_to_add[*]}"
        fi
    fi

    # Append service to compose file (networks section is added at the end by generate_compose_file)
    cat "$compose_snippet" >> "$compose_file"
    echo "" >> "$compose_file"

    rm -f "$compose_snippet"

    print_success "Added ${service} to stack ${stack}"
}

#######################################
# Check Portainer health and offer fix if needed
# Arguments:
#   $1 - Stack name (optional)
#######################################
check_portainer_health() {
    local stack="${1:-${CURRENT_STACK:-default}}"
    local container_name=$(get_container_name "portainer" "$stack")

    echo ""
    print_info "Checking Portainer health..."

    # Wait for container to start
    sleep 3

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        print_warning "Portainer container is not running"
        return
    fi

    # Get Portainer port
    local port=$(get_env_var "PORTAINER_PORT")
    port=${port:-9443}

    # Wait a bit more for Portainer to initialize
    print_info "Waiting for Portainer to initialize..."
    sleep 5

    # Try to access Portainer (allow self-signed cert)
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:${port}/api/status" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "401" ]] || [[ "$http_code" == "303" ]]; then
        print_success "Portainer is responding (HTTP ${http_code})"
        echo -e "  Access Portainer at: ${GREEN}https://$(hostname -I | awk '{print $1}'):${port}${NC}"
        return
    fi

    # Check logs for Docker API compatibility issue
    local logs
    logs=$(docker logs "$container_name" 2>&1 | tail -20)

    if echo "$logs" | grep -qi "unreachable\|API.*version\|minimum.*API"; then
        echo ""
        print_warning "Portainer cannot connect to Docker!"
        echo -e "${YELLOW}This may be due to Docker Engine v29+ API incompatibility.${NC}"
        echo ""
        echo -e "Docker Engine v29 requires minimum API version 1.44, but Portainer"
        echo -e "may need an older API version."
        echo ""

        if confirm "Apply Docker API compatibility fix?"; then
            apply_docker_api_fix
        else
            echo ""
            print_info "You can manually fix this by adding to /etc/docker/daemon.json:"
            echo -e "  ${CYAN}{\"min-api-version\": \"1.24\"}${NC}"
            echo -e "  Then run: ${CYAN}systemctl restart docker${NC}"
        fi
    else
        print_warning "Portainer is not responding (HTTP ${http_code})"
        echo -e "Check logs with: ${CYAN}docker logs portainer${NC}"
    fi
}

#######################################
# Apply Docker API compatibility fix
#######################################
apply_docker_api_fix() {
    local daemon_json="/etc/docker/daemon.json"

    print_info "Applying Docker API compatibility fix..."

    # Backup existing config
    if [[ -f "$daemon_json" ]]; then
        cp "$daemon_json" "${daemon_json}.bak"
        print_info "Backed up existing daemon.json"

        # Check if min-api-version already set
        if grep -q "min-api-version" "$daemon_json"; then
            print_info "min-api-version already configured"
            return
        fi

        # Add min-api-version to existing config using simple sed
        # Remove trailing } and add the new setting
        if grep -q "^{" "$daemon_json"; then
            # JSON file exists with content
            sed -i 's/}$/,\n  "min-api-version": "1.24"\n}/' "$daemon_json"
        fi
    else
        # Create new config
        cat > "$daemon_json" << 'EOF'
{
  "min-api-version": "1.24"
}
EOF
    fi

    print_success "Updated ${daemon_json}"

    # Restart Docker
    print_info "Restarting Docker daemon..."
    systemctl restart docker

    if [[ $? -eq 0 ]]; then
        print_success "Docker restarted successfully"

        # Wait for Docker to be ready
        sleep 3

        # Restart Portainer
        print_info "Restarting Portainer..."
        docker start portainer 2>/dev/null || docker compose up -d portainer

        sleep 5

        # Check again
        local port=$(get_env_var "PORTAINER_PORT")
        port=${port:-9443}
        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:${port}/api/status" 2>/dev/null || echo "000")

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "401" ]] || [[ "$http_code" == "303" ]]; then
            print_success "Portainer is now working!"
            echo -e "  Access at: ${GREEN}https://$(hostname -I | awk '{print $1}'):${port}${NC}"
        else
            print_warning "Portainer still not responding. Check logs: docker logs portainer"
        fi
    else
        print_error "Failed to restart Docker"
    fi
}

#######################################
# Start services
#######################################
start_services() {
    print_header "Starting Services"

    local stack="${CURRENT_STACK:-default}"
    local compose_file=$(get_compose_file "$stack")

    cd "$SCRIPT_DIR"

    print_info "Stack: ${stack}"
    print_info "Compose file: ${compose_file}"

    # Check if any services need to be built
    local needs_build=false
    for service in "${SELECTED_SERVICES[@]}"; do
        local template=$(get_service_template_file "$service")
        if [[ -f "$template" ]] && grep -q "build:" "$template" 2>/dev/null; then
            needs_build=true
            break
        fi
    done

    # Build services that have Dockerfiles
    if [[ "$needs_build" == true ]]; then
        print_info "Building images from local Dockerfiles..."
        if ! docker compose -f "$compose_file" build; then
            print_error "Build failed!"
            if ! confirm "Continue with available images?"; then
                return 1
            fi
        fi
        print_success "Build completed"
    fi

    # Pull remote images (skip services that are built locally)
    print_info "Pulling remote images..."
    docker compose -f "$compose_file" pull --ignore-buildable 2>/dev/null || docker compose -f "$compose_file" pull

    print_info "Starting containers..."
    docker compose -f "$compose_file" -p "$stack" up -d

    echo ""
    print_success "Services started in stack: ${stack}"
    echo ""

    # Show running containers
    docker compose -f "$compose_file" -p "$stack" ps

    # Post-start checks and hooks for services
    for service in "${SELECTED_SERVICES[@]}"; do
        # Service-specific checks
        case "$service" in
            portainer)
                check_portainer_health "$stack"
                ;;
        esac

        # Run post-deploy hooks for all services
        run_service_hooks "$service" "post_deploy" || true
    done
}

#######################################
# Remove services menu
#######################################
remove_services_menu() {
    print_header "Remove Services"

    if ! command_exists docker; then
        print_error "Docker is not installed"
        press_any_key
        return
    fi

    # First, select a stack
    local existing_stacks=($(get_existing_stacks))

    if [[ ${#existing_stacks[@]} -eq 0 ]]; then
        print_error "No stacks found"
        press_any_key
        return
    fi

    echo -e "${CYAN}Select Stack:${NC}"
    echo ""

    local i=1
    for stack in "${existing_stacks[@]}"; do
        local compose_file=$(get_compose_file "$stack")
        local service_count=0
        if [[ -f "$compose_file" ]]; then
            service_count=$(grep -c "^  [a-zA-Z0-9_-]*:" "$compose_file" 2>/dev/null || echo "0")
        fi
        echo -e "  ${GREEN}${i})${NC} ${BOLD}${stack}${NC} ${YELLOW}(${service_count} services)${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Select stack: " stack_choice

    if [[ "$stack_choice" == "0" || -z "$stack_choice" ]]; then
        return
    fi

    local stack_idx=$((stack_choice - 1))
    if [[ $stack_idx -lt 0 ]] || [[ $stack_idx -ge ${#existing_stacks[@]} ]]; then
        print_error "Invalid selection"
        press_any_key
        return
    fi

    CURRENT_STACK="${existing_stacks[$stack_idx]}"
    local compose_file=$(get_compose_file "$CURRENT_STACK")

    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found for stack: ${CURRENT_STACK}"
        press_any_key
        return
    fi

    # Get services from compose file
    local services=($(grep -E "^  [a-zA-Z0-9_-]+:" "$compose_file" | sed 's/://' | sed 's/^  //' | sort))

    if [[ ${#services[@]} -eq 0 ]]; then
        print_warning "No services found in stack: ${CURRENT_STACK}"
        press_any_key
        return
    fi

    echo ""
    print_header "Remove Services from Stack: ${CURRENT_STACK}"

    echo -e "${CYAN}Installed Services:${NC}"
    echo ""

    local i=1
    for service in "${services[@]}"; do
        local container_name=$(get_container_name "$service" "$CURRENT_STACK")
        local status=""
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            status="${GREEN}[running]${NC}"
        else
            status="${RED}[stopped]${NC}"
        fi
        echo -e "  ${GREEN}${i})${NC} ${service} ${status}"
        ((i++))
    done

    echo ""
    echo -e "  ${RED}a)${NC} Remove ALL services from this stack"
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Select service(s) to remove (comma-separated): " selection

    if [[ "$selection" == "0" || -z "$selection" ]]; then
        return
    fi

    local to_remove=()

    if [[ "$selection" == "a" || "$selection" == "A" ]]; then
        to_remove=("${services[@]}")
    else
        # Parse selection
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d ' ')
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                if [[ $part -ge 1 && $part -le ${#services[@]} ]]; then
                    to_remove+=("${services[$((part-1))]}")
                fi
            fi
        done
    fi

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        print_warning "No valid services selected"
        press_any_key
        return
    fi

    echo ""
    echo -e "${RED}Services to remove from stack ${CURRENT_STACK}:${NC}"
    for service in "${to_remove[@]}"; do
        echo -e "  • ${service}"
    done
    echo ""

    if ! confirm "Are you sure you want to remove these services?" "N"; then
        return
    fi

    # Ask about data removal
    local remove_data=false
    if confirm "Also remove data directories? (This is permanent!)" "N"; then
        remove_data=true
    fi

    # Auto-backup before making changes
    auto_backup "before-remove-${CURRENT_STACK}"

    # Remove services
    for service in "${to_remove[@]}"; do
        remove_service "$service" "$remove_data" "$CURRENT_STACK"
    done

    print_success "Services removed"
    press_any_key
}

#######################################
# Remove a service
# Arguments:
#   $1 - Service name
#   $2 - Remove data (true/false)
#   $3 - Stack name (optional)
#######################################
remove_service() {
    local service=$1
    local remove_data=$2
    local stack="${3:-$CURRENT_STACK}"
    stack="${stack:-default}"

    local container_name=$(get_container_name "$service" "$stack")
    local compose_file=$(get_compose_file "$stack")

    print_info "Removing ${service} from stack ${stack}..."

    # Stop and remove container using docker directly (more reliable)
    # This works even if service was removed from compose file
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        print_info "Stopping container ${container_name}..."
        docker stop "$container_name" 2>/dev/null || true
        docker rm -f "$container_name" 2>/dev/null || true
        print_success "Container ${container_name} removed"
    fi

    # Remove from compose file
    if service_in_compose "$service" "$stack"; then
        remove_service_from_compose "$service" "$stack"
        print_info "Removed ${service} from ${compose_file}"
    fi

    # Remove data if requested
    if [[ "$remove_data" == true ]]; then
        local data_dir=$(get_service_data_dir "$service" "$stack")

        if [[ -d "$data_dir" ]]; then
            rm -rf "$data_dir"
            print_info "Removed data: ${data_dir}"
        fi
    fi

    print_success "Service ${service} removed from stack ${stack}"
}

#######################################
# Remove service from docker-compose.yml
# Arguments:
#   $1 - Service name
#   $2 - Stack name (optional)
#######################################
remove_service_from_compose() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"
    stack="${stack:-default}"

    local compose_file=$(get_compose_file "$stack")
    local temp_file=$(mktemp)
    local in_service=false

    if [[ ! -f "$compose_file" ]]; then
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if this is the service we want to remove
        if [[ "$line" =~ ^[[:space:]]{2}${service}: ]]; then
            in_service=true
            continue
        fi

        if $in_service; then
            # Check if we've moved to a new service or section
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z0-9_-]+: ]] || [[ "$line" =~ ^[a-zA-Z]+: ]]; then
                in_service=false
            else
                continue
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$compose_file"

    mv "$temp_file" "$compose_file"
}
