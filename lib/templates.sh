#!/bin/bash

#######################################
# Template Management Functions
#######################################

#######################################
# Define template menu
#######################################
define_template_menu() {
    print_header "Define Service Template"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create New Template (Interactive)"
    echo -e "  ${GREEN}2)${NC} Create from Docker Hub Image"
    echo -e "  ${GREEN}3)${NC} List Existing Templates"
    echo -e "  ${GREEN}4)${NC} Edit Existing Template"
    echo -e "  ${GREEN}5)${NC} Delete Template"
    echo -e "  ${GREEN}6)${NC} View Default Templates"
    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Enter your choice [0-6]: " choice

    case $choice in
        1)
            create_template_interactive
            ;;
        2)
            create_template_from_image
            ;;
        3)
            list_templates
            ;;
        4)
            edit_template
            ;;
        5)
            delete_template
            ;;
        6)
            initialize_default_templates
            ;;
        0)
            return
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            define_template_menu
            ;;
    esac
}

#######################################
# Create template interactively
#######################################
create_template_interactive() {
    print_header "Create New Template"

    # Get service name
    read -p "Service name (lowercase, no spaces): " service_name
    service_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    if [[ -z "$service_name" ]]; then
        print_error "Service name is required"
        press_any_key
        return
    fi

    local template_dir="${TEMPLATES_DIR}/${service_name}"
    local service_file="${template_dir}/service.yaml"

    if [[ -d "$template_dir" ]]; then
        print_warning "Template already exists for ${service_name}"
        if ! confirm "Overwrite?"; then
            press_any_key
            return
        fi
    fi

    mkdir -p "$template_dir"

    # Get Docker image
    read -p "Docker image (e.g., nginx:latest): " docker_image
    if [[ -z "$docker_image" ]]; then
        print_error "Docker image is required"
        press_any_key
        return
    fi

    # Get description
    read -p "Description: " description

    # Get ports
    echo -e "${CYAN}Ports (format: host:container, comma-separated):${NC}"
    read -p "Ports (e.g., 8080:80): " ports_input

    # Get dependencies
    read -p "Dependencies (comma-separated service names): " deps_input

    # Get environment variables
    echo -e "${CYAN}Environment variables (one per line, empty to finish):${NC}"
    local env_vars=()
    while true; do
        read -p "  VAR_NAME=default_value: " env_var
        if [[ -z "$env_var" ]]; then
            break
        fi
        env_vars+=("$env_var")
    done

    # Create service.yaml
    cat > "$service_file" << EOF
name: ${service_name}
description: "${description}"
EOF

    # Add dependencies if provided
    if [[ -n "$deps_input" ]]; then
        echo "" >> "$service_file"
        echo "dependencies:" >> "$service_file"
        IFS=',' read -ra deps <<< "$deps_input"
        for dep in "${deps[@]}"; do
            dep=$(echo "$dep" | tr -d ' ')
            echo "  - ${dep}" >> "$service_file"
        done
    fi

    # Add variables section
    echo "" >> "$service_file"
    echo "variables:" >> "$service_file"

    # Add port variable
    local port_var="${service_name^^}_PORT"
    port_var=$(echo "$port_var" | tr '-' '_')
    local host_port=$(echo "$ports_input" | cut -d: -f1 | tr -d ' ')
    host_port=${host_port:-8080}
    cat >> "$service_file" << EOF
  ${port_var}:
    default: "${host_port}"
    description: "Web port"
EOF

    # Add custom env vars
    for env_var in "${env_vars[@]}"; do
        local var_name=$(echo "$env_var" | cut -d'=' -f1)
        local var_default=$(echo "$env_var" | cut -d'=' -f2-)
        cat >> "$service_file" << EOF
  ${var_name}:
    default: "${var_default}"
    description: "${var_name} variable"
EOF
        if [[ "$var_name" =~ PASSWORD|SECRET|TOKEN ]]; then
            echo "    generate: password" >> "$service_file"
        fi
    done

    # Add compose block
    local container_port=$(echo "$ports_input" | cut -d: -f2 | tr -d ' ')
    container_port=${container_port:-80}
    cat >> "$service_file" << EOF

compose: |
  ${service_name}:
    image: ${docker_image}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "\${${port_var}:-${host_port}}:${container_port}"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${DOCKER_ROOT}/${service_name}/config:/config
      - \${DOCKER_ROOT}/${service_name}/data:/data
EOF

    # Add depends_on if there are dependencies
    if [[ -n "$deps_input" ]]; then
        echo "    depends_on:" >> "$service_file"
        IFS=',' read -ra deps <<< "$deps_input"
        for dep in "${deps[@]}"; do
            dep=$(echo "$dep" | tr -d ' ')
            echo "      - ${dep}" >> "$service_file"
        done
    fi

    print_success "Template created for ${service_name}"
    print_info "Location: ${service_file}"

    press_any_key
}

#######################################
# Create template from Docker Hub image
#######################################
create_template_from_image() {
    print_header "Create Template from Docker Image"

    read -p "Docker image name (e.g., nginx, redis, postgres): " image_name

    if [[ -z "$image_name" ]]; then
        print_error "Image name is required"
        press_any_key
        return
    fi

    # Extract service name from image
    local service_name=$(echo "$image_name" | cut -d: -f1 | cut -d/ -f2)
    service_name=${service_name:-$image_name}
    service_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    read -p "Service name [${service_name}]: " custom_name
    service_name=${custom_name:-$service_name}

    # Use full image name with tag
    if [[ ! "$image_name" =~ : ]]; then
        image_name="${image_name}:latest"
    fi

    local template_dir="${TEMPLATES_DIR}/${service_name}"
    mkdir -p "$template_dir"

    read -p "Description: " description
    read -p "Exposed port (e.g., 8080:80): " port
    read -p "Data volume path in container (e.g., /data): " data_path

    local host_port=$(echo "$port" | cut -d: -f1)
    host_port=${host_port:-8080}
    local container_port=$(echo "$port" | cut -d: -f2)
    container_port=${container_port:-80}
    local port_var="${service_name^^}_PORT"
    port_var=$(echo "$port_var" | tr '-' '_')

    # Create service.yaml
    cat > "${template_dir}/service.yaml" << EOF
name: ${service_name}
description: "${description}"

variables:
  ${port_var}:
    default: "${host_port}"
    description: "Web port"

compose: |
  ${service_name}:
    image: ${image_name}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "\${${port_var}:-${host_port}}:${container_port}"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${DOCKER_ROOT}/${service_name}/config:/config
      - \${DOCKER_ROOT}/${service_name}/data:${data_path:-/data}
EOF

    print_success "Template created for ${service_name}"
    press_any_key
}

#######################################
# List existing templates
#######################################
list_templates() {
    print_header "Existing Templates"

    local templates=($(get_available_services))

    if [[ ${#templates[@]} -eq 0 ]]; then
        print_warning "No templates found"
        press_any_key
        return
    fi

    echo -e "${CYAN}Available Templates:${NC}"
    echo ""

    for template in "${templates[@]}"; do
        local yaml="${TEMPLATES_DIR}/${template}/service.yaml"
        if [[ -f "$yaml" ]]; then
            local desc=$(parse_yaml_value "$yaml" "description")
            local deps=$(parse_yaml_array "$yaml" "dependencies")
            echo -e "  ${GREEN}${template}${NC}"
            if [[ -n "$desc" ]]; then
                echo -e "    Description: ${desc}"
            fi
            if [[ -n "$deps" ]]; then
                echo -e "    Dependencies: ${deps}"
            fi
            echo ""
        fi
    done

    press_any_key
}

#######################################
# Edit existing template
#######################################
edit_template() {
    print_header "Edit Template"

    local templates=($(get_available_services))

    if [[ ${#templates[@]} -eq 0 ]]; then
        print_warning "No templates found"
        press_any_key
        return
    fi

    echo -e "${CYAN}Select template to edit:${NC}"
    echo ""

    local i=1
    for template in "${templates[@]}"; do
        echo -e "  ${GREEN}${i})${NC} ${template}"
        ((i++))
    done
    echo ""

    read -p "Selection: " selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#templates[@]} ]]; then
        print_error "Invalid selection"
        press_any_key
        return
    fi

    local selected="${templates[$((selection-1))]}"
    local yaml="${TEMPLATES_DIR}/${selected}/service.yaml"

    # Use available editor
    local editor="${EDITOR:-nano}"
    if ! command_exists "$editor"; then
        editor="vi"
    fi

    $editor "$yaml"

    print_success "Template updated"
    press_any_key
}

#######################################
# Delete template
#######################################
delete_template() {
    print_header "Delete Template"

    local templates=($(get_available_services))

    if [[ ${#templates[@]} -eq 0 ]]; then
        print_warning "No templates found"
        press_any_key
        return
    fi

    echo -e "${CYAN}Select template to delete:${NC}"
    echo ""

    local i=1
    for template in "${templates[@]}"; do
        echo -e "  ${RED}${i})${NC} ${template}"
        ((i++))
    done
    echo ""

    read -p "Selection: " selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#templates[@]} ]]; then
        print_error "Invalid selection"
        press_any_key
        return
    fi

    local selected="${templates[$((selection-1))]}"

    if confirm "Are you sure you want to delete ${selected} template?" "N"; then
        rm -rf "${TEMPLATES_DIR}/${selected}"
        print_success "Template ${selected} deleted"
    fi

    press_any_key
}

#######################################
# View default templates
#######################################
initialize_default_templates() {
    print_header "Default Templates"

    local count=$(ls -d ${TEMPLATES_DIR}/*/ 2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
        print_success "Templates are already installed!"
        print_info "Found ${count} service templates"
        echo ""

        local templates=($(get_available_services))
        local cols=4
        local i=0
        for template in "${templates[@]}"; do
            printf "  ${GREEN}%-20s${NC}" "$template"
            ((i++))
            if (( i % cols == 0 )); then
                echo ""
            fi
        done
        echo ""
    else
        print_warning "No templates found"
        print_info "Templates should be in: ${TEMPLATES_DIR}"
    fi

    press_any_key
}
