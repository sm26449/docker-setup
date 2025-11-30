#!/bin/bash

#######################################
# Maintenance & Diagnostics Functions
# View logs, shell access, port check,
# image updates, export/import config
#######################################

#######################################
# Maintenance Menu
#######################################
maintenance_menu() {
    print_header "Maintenance & Diagnostics"

    echo -e "${CYAN}Select an option:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} View Logs         - Container log viewer"
    echo -e "  ${GREEN}2)${NC} Quick Shell       - Access container shell"
    echo -e "  ${GREEN}3)${NC} Port Check        - Check port conflicts"
    echo -e "  ${GREEN}4)${NC} Image Updates     - Check/update Docker images"
    echo -e "  ${GREEN}5)${NC} Save Image        - Backup image before update"
    echo -e "  ${GREEN}6)${NC} Export Config     - Export for migration"
    echo -e "  ${GREEN}7)${NC} Import Config     - Import from backup"
    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Enter your choice [0-7]: " choice

    case $choice in
        1) view_logs_menu ;;
        2) quick_shell_menu ;;
        3) port_check_menu ;;
        4) image_update_menu ;;
        5) save_image_menu ;;
        6) export_config_menu ;;
        7) import_config_menu ;;
        0) return ;;
        *)
            print_error "Invalid option"
            sleep 1
            maintenance_menu
            ;;
    esac
}

#######################################
# View Logs
#######################################
view_logs_menu() {
    print_header "View Container Logs"

    # Get running containers
    local containers=($(docker ps --format '{{.Names}}' 2>/dev/null | sort))

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "No running containers found"
        press_any_key
        maintenance_menu
        return
    fi

    echo -e "${CYAN}Running containers:${NC}"
    echo ""

    local i=1
    for container in "${containers[@]}"; do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        local status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
        echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(${image})${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${YELLOW}a)${NC} All containers (combined)"
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Select container: " choice

    if [[ "$choice" == "0" ]]; then
        maintenance_menu
        return
    fi

    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        view_all_logs
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#containers[@]} ]]; then
        local selected="${containers[$((choice-1))]}"
        view_container_logs "$selected"
    else
        print_error "Invalid selection"
        sleep 1
        view_logs_menu
    fi
}

view_container_logs() {
    local container=$1

    print_header "Logs: ${container}"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Last 50 lines"
    echo -e "  ${GREEN}2)${NC} Last 100 lines"
    echo -e "  ${GREEN}3)${NC} Last 500 lines"
    echo -e "  ${GREEN}4)${NC} Follow (live) - Ctrl+C to stop"
    echo -e "  ${GREEN}5)${NC} Since last hour"
    echo -e "  ${GREEN}6)${NC} Since last 24 hours"
    echo -e "  ${GREEN}7)${NC} Search in logs"
    echo -e "  ${GREEN}8)${NC} Export to file"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1)
            echo ""
            docker logs --tail 50 "$container" 2>&1
            ;;
        2)
            echo ""
            docker logs --tail 100 "$container" 2>&1
            ;;
        3)
            echo ""
            docker logs --tail 500 "$container" 2>&1 | less
            ;;
        4)
            echo ""
            echo -e "${YELLOW}Press Ctrl+C to stop following logs${NC}"
            echo ""
            docker logs -f --tail 20 "$container" 2>&1
            ;;
        5)
            echo ""
            docker logs --since 1h "$container" 2>&1
            ;;
        6)
            echo ""
            docker logs --since 24h "$container" 2>&1 | less
            ;;
        7)
            read -p "Search pattern: " pattern
            echo ""
            docker logs "$container" 2>&1 | grep -i --color=auto "$pattern"
            ;;
        8)
            local log_file="${SCRIPT_DIR}/logs/${container}_$(date +%Y%m%d_%H%M%S).log"
            mkdir -p "${SCRIPT_DIR}/logs"
            docker logs "$container" > "$log_file" 2>&1
            print_success "Logs exported to: $log_file"
            ;;
        0)
            view_logs_menu
            return
            ;;
    esac

    echo ""
    press_any_key
    view_container_logs "$container"
}

view_all_logs() {
    print_header "Combined Logs (All Containers)"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Last 10 lines per container"
    echo -e "  ${GREEN}2)${NC} Follow all (live) - Ctrl+C to stop"
    echo ""

    read -p "Choice [1]: " choice

    case $choice in
        2)
            echo ""
            echo -e "${YELLOW}Following all containers. Press Ctrl+C to stop${NC}"
            echo ""
            # Use docker compose logs if available
            local compose_files=$(ls docker-compose*.yml 2>/dev/null | head -1)
            if [[ -n "$compose_files" ]]; then
                docker compose -f "$compose_files" logs -f --tail 5
            else
                # Fallback to individual containers
                for container in $(docker ps --format '{{.Names}}'); do
                    docker logs -f --tail 5 "$container" 2>&1 &
                done
                wait
            fi
            ;;
        *)
            echo ""
            for container in $(docker ps --format '{{.Names}}' | sort); do
                echo -e "${YELLOW}=== ${container} ===${NC}"
                docker logs --tail 10 "$container" 2>&1
                echo ""
            done
            ;;
    esac

    press_any_key
    view_logs_menu
}

#######################################
# Quick Shell Access
#######################################
quick_shell_menu() {
    print_header "Quick Shell Access"

    # Get running containers
    local containers=($(docker ps --format '{{.Names}}' 2>/dev/null | sort))

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "No running containers found"
        press_any_key
        maintenance_menu
        return
    fi

    echo -e "${CYAN}Select container to access:${NC}"
    echo ""

    local i=1
    for container in "${containers[@]}"; do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(${image})${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Select container: " choice

    if [[ "$choice" == "0" ]]; then
        maintenance_menu
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#containers[@]} ]]; then
        local selected="${containers[$((choice-1))]}"
        access_container_shell "$selected"
    else
        print_error "Invalid selection"
        sleep 1
        quick_shell_menu
    fi
}

access_container_shell() {
    local container=$1

    echo ""
    echo -e "${CYAN}Shell type:${NC}"
    echo -e "  ${GREEN}1)${NC} bash (most containers)"
    echo -e "  ${GREEN}2)${NC} sh (Alpine-based)"
    echo -e "  ${GREEN}3)${NC} ash (BusyBox)"
    echo -e "  ${GREEN}4)${NC} Custom command"
    echo ""

    read -p "Choice [1]: " shell_choice

    local shell_cmd
    case $shell_choice in
        2) shell_cmd="sh" ;;
        3) shell_cmd="ash" ;;
        4)
            read -p "Command: " shell_cmd
            ;;
        *) shell_cmd="bash" ;;
    esac

    echo ""
    echo -e "${YELLOW}Connecting to ${container}... (type 'exit' to leave)${NC}"
    echo ""

    docker exec -it "$container" $shell_cmd 2>/dev/null

    if [[ $? -ne 0 ]]; then
        print_warning "bash not available, trying sh..."
        docker exec -it "$container" sh 2>/dev/null

        if [[ $? -ne 0 ]]; then
            print_error "Could not access shell in container"
        fi
    fi

    echo ""
    press_any_key
    quick_shell_menu
}

#######################################
# Port Check
#######################################
port_check_menu() {
    print_header "Port Conflict Check"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Check all used ports"
    echo -e "  ${GREEN}2)${NC} Check specific port"
    echo -e "  ${GREEN}3)${NC} Check common service ports"
    echo -e "  ${GREEN}4)${NC} Find process using port"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) check_all_ports ;;
        2) check_specific_port ;;
        3) check_common_ports ;;
        4) find_port_process ;;
        0) maintenance_menu; return ;;
        *) port_check_menu ;;
    esac
}

check_all_ports() {
    print_header "All Used Ports"

    echo -e "${CYAN}Ports used by Docker containers:${NC}"
    echo ""
    docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null | grep -v "^NAMES"

    echo ""
    echo -e "${CYAN}Ports listening on host:${NC}"
    echo ""

    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $6}' | sort -t: -k2 -n | head -30
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $7}' | sort | head -30
    else
        print_warning "ss/netstat not available"
    fi

    press_any_key
    port_check_menu
}

check_specific_port() {
    echo ""
    read -p "Enter port number: " port

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        print_error "Invalid port number"
        press_any_key
        port_check_menu
        return
    fi

    echo ""
    echo -e "${CYAN}Checking port ${port}...${NC}"
    echo ""

    # Check if port is in use
    local in_use=false

    # Check Docker
    local docker_container=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep ":${port}->" | awk '{print $1}')
    if [[ -n "$docker_container" ]]; then
        echo -e "${RED}Port ${port} is used by Docker container: ${docker_container}${NC}"
        in_use=true
    fi

    # Check system
    if command -v ss &>/dev/null; then
        local system_use=$(ss -tlnp 2>/dev/null | grep ":${port} ")
        if [[ -n "$system_use" ]]; then
            echo -e "${RED}Port ${port} is used by system process:${NC}"
            echo "$system_use"
            in_use=true
        fi
    fi

    if [[ "$in_use" == false ]]; then
        echo -e "${GREEN}Port ${port} is available${NC}"
    fi

    press_any_key
    port_check_menu
}

check_common_ports() {
    print_header "Common Service Ports"

    # Define common ports
    declare -A common_ports=(
        [80]="HTTP/Nginx"
        [443]="HTTPS/SSL"
        [1883]="MQTT"
        [3000]="Grafana/Node-RED"
        [3306]="MySQL/MariaDB"
        [5432]="PostgreSQL"
        [6379]="Redis"
        [8080]="HTTP Alt"
        [8086]="InfluxDB"
        [8123]="Home Assistant"
        [8883]="MQTT SSL"
        [9000]="Portainer"
        [9001]="MQTT WebSocket"
        [27017]="MongoDB"
    )

    echo ""
    printf "%-8s %-20s %-10s %-30s\n" "PORT" "SERVICE" "STATUS" "USED BY"
    echo "-----------------------------------------------------------------------"

    for port in $(echo "${!common_ports[@]}" | tr ' ' '\n' | sort -n); do
        local service="${common_ports[$port]}"
        local status="FREE"
        local used_by="-"

        # Check Docker
        local docker_container=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep ":${port}->" | awk '{print $1}' | head -1)
        if [[ -n "$docker_container" ]]; then
            status="${RED}IN USE${NC}"
            used_by="$docker_container"
        else
            # Check system
            if command -v ss &>/dev/null; then
                local system_use=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1)
                if [[ -n "$system_use" ]]; then
                    status="${RED}IN USE${NC}"
                    used_by=$(echo "$system_use" | grep -oP 'users:\(\("\K[^"]+' || echo "system")
                else
                    status="${GREEN}FREE${NC}"
                fi
            fi
        fi

        printf "%-8s %-20s " "$port" "$service"
        echo -e "${status}\t${used_by}"
    done

    echo ""
    press_any_key
    port_check_menu
}

find_port_process() {
    echo ""
    read -p "Enter port number: " port

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        print_error "Invalid port number"
        press_any_key
        port_check_menu
        return
    fi

    echo ""
    echo -e "${CYAN}Finding process using port ${port}...${NC}"
    echo ""

    # Try lsof first
    if command -v lsof &>/dev/null; then
        lsof -i :${port} 2>/dev/null
    elif command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep ":${port} "
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep ":${port} "
    else
        print_warning "lsof/ss/netstat not available"
    fi

    # Check Docker
    echo ""
    echo -e "${CYAN}Docker containers using port ${port}:${NC}"
    docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep ":${port}->"

    press_any_key
    port_check_menu
}

#######################################
# Image Update Check
#######################################
image_update_menu() {
    print_header "Docker Image Updates"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Check for updates (all images)"
    echo -e "  ${GREEN}2)${NC} Update specific container"
    echo -e "  ${GREEN}3)${NC} Update all containers"
    echo -e "  ${GREEN}4)${NC} List current images"
    echo -e "  ${GREEN}5)${NC} Clean unused images"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) check_image_updates ;;
        2) update_specific_image ;;
        3) update_all_images ;;
        4) list_current_images ;;
        5) clean_unused_images ;;
        0) maintenance_menu; return ;;
        *) image_update_menu ;;
    esac
}

check_image_updates() {
    print_header "Checking for Image Updates"

    echo -e "${YELLOW}This may take a while...${NC}"
    echo ""

    local containers=($(docker ps --format '{{.Names}}' 2>/dev/null))

    for container in "${containers[@]}"; do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        local image_id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null)

        echo -ne "Checking ${container} (${image})... "

        # Pull latest image info (without downloading)
        docker pull "$image" > /tmp/pull_output_$$ 2>&1

        if grep -q "Image is up to date" /tmp/pull_output_$$; then
            echo -e "${GREEN}Up to date${NC}"
        elif grep -q "Downloaded newer image" /tmp/pull_output_$$ || grep -q "Pull complete" /tmp/pull_output_$$; then
            echo -e "${YELLOW}Update available!${NC}"
        else
            echo -e "${CYAN}Unknown${NC}"
        fi

        rm -f /tmp/pull_output_$$
    done

    echo ""
    press_any_key
    image_update_menu
}

update_specific_image() {
    print_header "Update Specific Container"

    local containers=($(docker ps --format '{{.Names}}' 2>/dev/null | sort))

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "No running containers found"
        press_any_key
        image_update_menu
        return
    fi

    echo -e "${CYAN}Select container to update:${NC}"
    echo ""

    local i=1
    for container in "${containers[@]}"; do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(${image})${NC}"
        ((i++))
    done

    echo ""
    read -p "Select container: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#containers[@]} ]]; then
        local selected="${containers[$((choice-1))]}"
        local image=$(docker inspect --format '{{.Config.Image}}' "$selected" 2>/dev/null)

        echo ""
        print_warning "This will:"
        echo "  1. Save current image as backup"
        echo "  2. Pull the latest image"
        echo "  3. Recreate the container"
        echo ""

        if confirm "Proceed with update?"; then
            update_container "$selected" "$image"
        fi
    fi

    press_any_key
    image_update_menu
}

update_container() {
    local container=$1
    local image=$2

    echo ""
    print_info "Saving current image..."

    # Save current image
    local backup_tag="${image%%:*}:backup-$(date +%Y%m%d_%H%M%S)"
    local current_image_id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null)
    docker tag "$current_image_id" "$backup_tag" 2>/dev/null
    print_success "Backup saved as: $backup_tag"

    # Pull new image
    print_info "Pulling latest image..."
    docker pull "$image"

    # Find compose file for this container
    local compose_file=$(find_compose_for_container "$container")

    if [[ -n "$compose_file" ]]; then
        print_info "Recreating container via compose..."
        docker compose -f "$compose_file" up -d "$container" 2>/dev/null || \
        docker-compose -f "$compose_file" up -d "$container" 2>/dev/null
    else
        print_warning "No compose file found. Manual restart required."
        print_info "To complete update:"
        echo "  docker stop $container"
        echo "  docker rm $container"
        echo "  # Then recreate with same parameters"
    fi

    print_success "Update complete!"
    echo ""
    echo -e "${YELLOW}To rollback if needed:${NC}"
    echo "  docker tag $backup_tag $image"
    echo "  docker compose up -d $container"
}

find_compose_for_container() {
    local container=$1

    # Look for compose files
    for compose_file in docker-compose*.yml docker-compose*.yaml; do
        if [[ -f "$compose_file" ]]; then
            if grep -q "container_name:.*${container}" "$compose_file" 2>/dev/null; then
                echo "$compose_file"
                return
            fi
        fi
    done
}

update_all_images() {
    print_header "Update All Images"

    print_warning "This will update all running containers!"
    echo ""

    if ! confirm "Are you sure?"; then
        image_update_menu
        return
    fi

    echo ""
    print_info "Creating backups first..."

    # Backup all images
    for container in $(docker ps --format '{{.Names}}'); do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        local current_image_id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null)
        local backup_tag="${image%%:*}:backup-$(date +%Y%m%d)"

        docker tag "$current_image_id" "$backup_tag" 2>/dev/null
        echo "  Backed up: $container -> $backup_tag"
    done

    echo ""
    print_info "Pulling latest images..."

    # Pull all images
    for container in $(docker ps --format '{{.Names}}'); do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        echo -ne "  Pulling ${image}... "
        docker pull "$image" > /dev/null 2>&1 && echo -e "${GREEN}done${NC}" || echo -e "${RED}failed${NC}"
    done

    echo ""
    print_info "Recreating containers..."

    # Recreate via compose if available
    for compose_file in docker-compose*.yml; do
        if [[ -f "$compose_file" ]]; then
            docker compose -f "$compose_file" up -d 2>/dev/null || \
            docker-compose -f "$compose_file" up -d 2>/dev/null
        fi
    done

    print_success "All containers updated!"

    press_any_key
    image_update_menu
}

list_current_images() {
    print_header "Current Docker Images"

    echo -e "${CYAN}Images in use:${NC}"
    echo ""

    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | head -30

    echo ""
    press_any_key
    image_update_menu
}

clean_unused_images() {
    print_header "Clean Unused Images"

    echo -e "${CYAN}Unused images (dangling):${NC}"
    docker images -f "dangling=true" --format "{{.Repository}}:{{.Tag}} ({{.Size}})"

    echo ""
    echo -e "${CYAN}Unused images (not used by containers):${NC}"
    docker images --format "{{.Repository}}:{{.Tag}}" | while read img; do
        if ! docker ps -a --format '{{.Image}}' | grep -q "^${img}$"; then
            echo "  $img"
        fi
    done | head -20

    echo ""
    if confirm "Remove all unused images?"; then
        docker image prune -af
        print_success "Unused images removed"
    fi

    press_any_key
    image_update_menu
}

#######################################
# Save Image for Rollback
#######################################
save_image_menu() {
    print_header "Save Image for Rollback"

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Save container image"
    echo -e "  ${GREEN}2)${NC} List saved images"
    echo -e "  ${GREEN}3)${NC} Restore from saved image"
    echo -e "  ${GREEN}4)${NC} Export image to file"
    echo -e "  ${GREEN}5)${NC} Import image from file"
    echo -e "  ${GREEN}6)${NC} Delete saved images"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) save_container_image ;;
        2) list_saved_images ;;
        3) restore_saved_image ;;
        4) export_image_file ;;
        5) import_image_file ;;
        6) delete_saved_images ;;
        0) maintenance_menu; return ;;
        *) save_image_menu ;;
    esac
}

save_container_image() {
    print_header "Save Container Image"

    local containers=($(docker ps --format '{{.Names}}' 2>/dev/null | sort))

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "No running containers found"
        press_any_key
        save_image_menu
        return
    fi

    echo -e "${CYAN}Select container to save:${NC}"
    echo ""

    local i=1
    for container in "${containers[@]}"; do
        local image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
        echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(${image})${NC}"
        ((i++))
    done

    echo ""
    read -p "Select container: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#containers[@]} ]]; then
        local selected="${containers[$((choice-1))]}"
        local image=$(docker inspect --format '{{.Config.Image}}' "$selected" 2>/dev/null)
        local current_image_id=$(docker inspect --format '{{.Image}}' "$selected" 2>/dev/null)

        echo ""
        read -p "Tag name (e.g., v1.0, stable, before-update) [backup]: " tag_name
        tag_name=${tag_name:-backup}

        local backup_tag="${image%%:*}:${tag_name}-$(date +%Y%m%d_%H%M%S)"

        docker tag "$current_image_id" "$backup_tag"

        if [[ $? -eq 0 ]]; then
            print_success "Image saved as: $backup_tag"
        else
            print_error "Failed to save image"
        fi
    fi

    press_any_key
    save_image_menu
}

list_saved_images() {
    print_header "Saved Images (Backups)"

    echo -e "${CYAN}Images with backup tags:${NC}"
    echo ""

    docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | grep -E "backup|stable|v[0-9]" | column -t

    echo ""
    echo -e "${CYAN}All tagged images:${NC}"
    echo ""

    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | grep -v "<none>"

    press_any_key
    save_image_menu
}

restore_saved_image() {
    print_header "Restore Saved Image"

    # Get backup images
    local backup_images=($(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "backup|stable" | sort))

    if [[ ${#backup_images[@]} -eq 0 ]]; then
        print_error "No backup images found"
        press_any_key
        save_image_menu
        return
    fi

    echo -e "${CYAN}Available backup images:${NC}"
    echo ""

    local i=1
    for image in "${backup_images[@]}"; do
        local size=$(docker images --format "{{.Size}}" "$image")
        local created=$(docker images --format "{{.CreatedSince}}" "$image")
        echo -e "  ${GREEN}${i})${NC} ${image} ${YELLOW}(${size}, ${created})${NC}"
        ((i++))
    done

    echo ""
    read -p "Select image to restore: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#backup_images[@]} ]]; then
        local selected="${backup_images[$((choice-1))]}"

        # Get original image name
        local original_name="${selected%-backup*}"
        original_name="${original_name%-stable*}"
        original_name="${original_name%-v*}"

        echo ""
        read -p "Restore as image name [$original_name:latest]: " restore_name
        restore_name=${restore_name:-"${original_name}:latest"}

        docker tag "$selected" "$restore_name"

        if [[ $? -eq 0 ]]; then
            print_success "Image restored as: $restore_name"
            print_info "Now restart the container to use the restored image"
        else
            print_error "Failed to restore image"
        fi
    fi

    press_any_key
    save_image_menu
}

export_image_file() {
    print_header "Export Image to File"

    echo -e "${CYAN}Select image to export:${NC}"
    echo ""

    local images=($(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | sort | head -30))

    local i=1
    for image in "${images[@]}"; do
        echo -e "  ${GREEN}${i})${NC} ${image}"
        ((i++))
    done

    echo ""
    read -p "Select image: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#images[@]} ]]; then
        local selected="${images[$((choice-1))]}"

        local export_dir="${SCRIPT_DIR}/image-backups"
        mkdir -p "$export_dir"

        local filename=$(echo "$selected" | tr '/:' '_')
        local export_file="${export_dir}/${filename}_$(date +%Y%m%d).tar"

        echo ""
        print_info "Exporting ${selected} to ${export_file}..."
        print_warning "This may take a while for large images..."

        docker save -o "$export_file" "$selected"

        if [[ $? -eq 0 ]]; then
            local size=$(du -h "$export_file" | cut -f1)
            print_success "Image exported: $export_file ($size)"
        else
            print_error "Failed to export image"
        fi
    fi

    press_any_key
    save_image_menu
}

import_image_file() {
    print_header "Import Image from File"

    local export_dir="${SCRIPT_DIR}/image-backups"

    if [[ ! -d "$export_dir" ]]; then
        print_error "No image backups directory found"
        press_any_key
        save_image_menu
        return
    fi

    local files=($(ls -1 "$export_dir"/*.tar 2>/dev/null))

    if [[ ${#files[@]} -eq 0 ]]; then
        print_error "No image files found in $export_dir"
        press_any_key
        save_image_menu
        return
    fi

    echo -e "${CYAN}Available image files:${NC}"
    echo ""

    local i=1
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        echo -e "  ${GREEN}${i})${NC} ${filename} ${YELLOW}(${size})${NC}"
        ((i++))
    done

    echo ""
    read -p "Select file to import: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#files[@]} ]]; then
        local selected="${files[$((choice-1))]}"

        echo ""
        print_info "Importing from ${selected}..."

        docker load -i "$selected"

        if [[ $? -eq 0 ]]; then
            print_success "Image imported successfully"
        else
            print_error "Failed to import image"
        fi
    fi

    press_any_key
    save_image_menu
}

delete_saved_images() {
    print_header "Delete Saved Images"

    local backup_images=($(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "backup|stable" | sort))

    if [[ ${#backup_images[@]} -eq 0 ]]; then
        print_error "No backup images found"
        press_any_key
        save_image_menu
        return
    fi

    echo -e "${CYAN}Backup images:${NC}"
    echo ""

    local i=1
    for image in "${backup_images[@]}"; do
        local size=$(docker images --format "{{.Size}}" "$image")
        echo -e "  ${GREEN}${i})${NC} ${image} ${YELLOW}(${size})${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${YELLOW}a)${NC} Delete all backups"
    echo ""

    read -p "Select image to delete (or 'a' for all): " choice

    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        if confirm "Delete ALL backup images?"; then
            for image in "${backup_images[@]}"; do
                docker rmi "$image" 2>/dev/null
                echo "  Deleted: $image"
            done
            print_success "All backup images deleted"
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#backup_images[@]} ]]; then
        local selected="${backup_images[$((choice-1))]}"
        docker rmi "$selected"
        print_success "Deleted: $selected"
    fi

    press_any_key
    save_image_menu
}

#######################################
# Export Config
#######################################
export_config_menu() {
    print_header "Export Configuration"

    local export_dir="${SCRIPT_DIR}/exports"
    mkdir -p "$export_dir"

    echo -e "${CYAN}Export options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Full export (compose, env, templates, configs)"
    echo -e "  ${GREEN}2)${NC} Compose files only"
    echo -e "  ${GREEN}3)${NC} Environment variables only"
    echo -e "  ${GREEN}4)${NC} Service data (volumes)"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) export_full_config ;;
        2) export_compose_only ;;
        3) export_env_only ;;
        4) export_service_data ;;
        0) maintenance_menu; return ;;
        *) export_config_menu ;;
    esac
}

export_full_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_name="docker-manager-export_${timestamp}"
    local export_path="${SCRIPT_DIR}/exports/${export_name}"

    mkdir -p "$export_path"

    print_info "Creating full export..."

    # Copy compose files
    cp docker-compose*.yml "$export_path/" 2>/dev/null
    cp docker-compose*.yaml "$export_path/" 2>/dev/null

    # Copy .env
    cp .env "$export_path/" 2>/dev/null

    # Copy templates
    if [[ -d "templates" ]]; then
        cp -r templates "$export_path/"
    fi

    # Copy lib
    if [[ -d "lib" ]]; then
        cp -r lib "$export_path/"
    fi

    # Copy backups info
    if [[ -d "backups" ]]; then
        ls -la backups > "$export_path/backups_list.txt"
    fi

    # Create metadata
    cat > "$export_path/export_info.txt" << EOF
Docker Services Manager Export
==============================
Date: $(date)
Hostname: $(hostname)
Docker version: $(docker --version)

Containers at export time:
$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}')

Images:
$(docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}')
EOF

    # Create tarball
    local tarball="${SCRIPT_DIR}/exports/${export_name}.tar.gz"
    tar -czf "$tarball" -C "${SCRIPT_DIR}/exports" "$export_name"
    rm -rf "$export_path"

    local size=$(du -h "$tarball" | cut -f1)
    print_success "Export created: $tarball ($size)"

    press_any_key
    export_config_menu
}

export_compose_only() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_path="${SCRIPT_DIR}/exports/compose_${timestamp}"

    mkdir -p "$export_path"

    cp docker-compose*.yml "$export_path/" 2>/dev/null
    cp docker-compose*.yaml "$export_path/" 2>/dev/null
    cp .env "$export_path/" 2>/dev/null

    local tarball="${export_path}.tar.gz"
    tar -czf "$tarball" -C "${SCRIPT_DIR}/exports" "compose_${timestamp}"
    rm -rf "$export_path"

    print_success "Compose files exported: $tarball"

    press_any_key
    export_config_menu
}

export_env_only() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_file="${SCRIPT_DIR}/exports/env_${timestamp}.env"

    cp .env "$export_file" 2>/dev/null

    # Remove sensitive data option
    if confirm "Remove passwords from export?"; then
        sed -i 's/PASSWORD=.*/PASSWORD=REDACTED/g' "$export_file"
        sed -i 's/_PASS=.*/_PASS=REDACTED/g' "$export_file"
        print_info "Passwords redacted"
    fi

    print_success "Environment exported: $export_file"

    press_any_key
    export_config_menu
}

export_service_data() {
    print_header "Export Service Data"

    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    if [[ ! -d "$docker_root" ]]; then
        print_error "Docker root not found: $docker_root"
        press_any_key
        export_config_menu
        return
    fi

    echo -e "${CYAN}Services with data:${NC}"
    echo ""

    local services=($(ls -1 "$docker_root" 2>/dev/null))
    local i=1
    for service in "${services[@]}"; do
        local size=$(du -sh "$docker_root/$service" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}${i})${NC} ${service} ${YELLOW}(${size})${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${YELLOW}a)${NC} Export all"
    echo ""

    read -p "Select service: " choice

    local to_export=()
    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        to_export=("${services[@]}")
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#services[@]} ]]; then
        to_export=("${services[$((choice-1))]}")
    else
        press_any_key
        export_config_menu
        return
    fi

    print_warning "This may take a long time for large data directories!"
    if ! confirm "Continue?"; then
        export_config_menu
        return
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    for service in "${to_export[@]}"; do
        local tarball="${SCRIPT_DIR}/exports/${service}_data_${timestamp}.tar.gz"
        print_info "Exporting ${service}..."
        tar -czf "$tarball" -C "$docker_root" "$service"
        local size=$(du -h "$tarball" | cut -f1)
        print_success "Exported: $tarball ($size)"
    done

    press_any_key
    export_config_menu
}

#######################################
# Import Config
#######################################
import_config_menu() {
    print_header "Import Configuration"

    local export_dir="${SCRIPT_DIR}/exports"

    if [[ ! -d "$export_dir" ]]; then
        print_error "No exports directory found"
        press_any_key
        maintenance_menu
        return
    fi

    local files=($(ls -1 "$export_dir"/*.tar.gz "$export_dir"/*.env 2>/dev/null))

    if [[ ${#files[@]} -eq 0 ]]; then
        print_error "No export files found"
        press_any_key
        maintenance_menu
        return
    fi

    echo -e "${CYAN}Available exports:${NC}"
    echo ""

    local i=1
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        local date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
        echo -e "  ${GREEN}${i})${NC} ${filename} ${YELLOW}(${size}, ${date})${NC}"
        ((i++))
    done

    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Select file to import: " choice

    if [[ "$choice" == "0" ]]; then
        maintenance_menu
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#files[@]} ]]; then
        local selected="${files[$((choice-1))]}"
        import_config_file "$selected"
    fi

    press_any_key
    import_config_menu
}

import_config_file() {
    local file=$1

    print_warning "This will overwrite existing configuration!"

    if ! confirm "Continue?"; then
        return
    fi

    if [[ "$file" == *.env ]]; then
        cp "$file" .env
        print_success "Environment imported"
    elif [[ "$file" == *.tar.gz ]]; then
        local temp_dir=$(mktemp -d)
        tar -xzf "$file" -C "$temp_dir"

        # Find the extracted directory
        local extract_dir=$(ls -1 "$temp_dir" | head -1)

        if [[ -d "$temp_dir/$extract_dir" ]]; then
            # Copy files
            cp "$temp_dir/$extract_dir"/*.yml . 2>/dev/null
            cp "$temp_dir/$extract_dir"/*.yaml . 2>/dev/null
            cp "$temp_dir/$extract_dir"/.env . 2>/dev/null

            if [[ -d "$temp_dir/$extract_dir/templates" ]]; then
                cp -r "$temp_dir/$extract_dir/templates" .
            fi

            print_success "Configuration imported"
        fi

        rm -rf "$temp_dir"
    fi
}
