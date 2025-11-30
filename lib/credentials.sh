#!/bin/bash

#######################################
# Credentials Management Functions
# For MariaDB, InfluxDB, MQTT, MongoDB
#######################################

# Current selected container (set by select_service_container)
SELECTED_CONTAINER=""

#######################################
# Find running containers for a service type
# Arguments:
#   $1 - Service type (e.g., "mariadb", "mosquitto")
# Returns:
#   List of matching container names
#######################################
find_service_containers() {
    local service_type=$1
    local containers=()

    # Find containers matching either "service" or "*-service" pattern
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            # Match exact name or stack-prefixed name
            if [[ "$container" == "$service_type" ]] || [[ "$container" == *"-${service_type}" ]]; then
                containers+=("$container")
            fi
        fi
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)

    echo "${containers[@]}"
}

#######################################
# Select a container for a service type
# Arguments:
#   $1 - Service type (e.g., "mariadb", "mosquitto")
# Returns:
#   0 if container selected, 1 if not
# Sets:
#   SELECTED_CONTAINER - The selected container name
#######################################
select_service_container() {
    local service_type=$1
    local containers=()
    mapfile -t containers < <(find_service_containers "$service_type" | tr ' ' '\n')

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "${service_type^} is not running. Start it first."
        SELECTED_CONTAINER=""
        return 1
    fi

    if [[ ${#containers[@]} -eq 1 ]]; then
        # Only one container, use it directly
        SELECTED_CONTAINER="${containers[0]}"
        return 0
    fi

    # Multiple containers found, show selection menu
    echo ""
    echo -e "${CYAN}Multiple ${service_type} containers found. Select one:${NC}"
    echo ""

    local i=1
    for container in "${containers[@]}"; do
        # Extract stack name from container
        local stack_name=""
        if [[ "$container" == *"-${service_type}" ]]; then
            stack_name="${container%-${service_type}}"
            echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(stack: ${stack_name})${NC}"
        else
            echo -e "  ${GREEN}${i})${NC} ${container} ${YELLOW}(default)${NC}"
        fi
        ((i++))
    done

    echo ""
    echo -e "  ${RED}0)${NC} Cancel"
    echo ""

    read -p "Select container: " choice

    if [[ "$choice" == "0" || -z "$choice" ]]; then
        SELECTED_CONTAINER=""
        return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#containers[@]} ]]; then
        SELECTED_CONTAINER="${containers[$((choice-1))]}"
        print_info "Using container: ${SELECTED_CONTAINER}"
        return 0
    fi

    print_error "Invalid selection"
    SELECTED_CONTAINER=""
    return 1
}

#######################################
# Get data directory for a container
# Arguments:
#   $1 - Container name
#   $2 - Service type
# Returns:
#   Path to data directory
#######################################
get_container_data_dir() {
    local container=$1
    local service_type=$2
    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    # Check if container has stack prefix
    if [[ "$container" == *"-${service_type}" ]]; then
        local stack="${container%-${service_type}}"
        echo "${docker_root}/${stack}/${service_type}"
    else
        echo "${docker_root}/${service_type}"
    fi
}

#######################################
# Credentials menu
#######################################
credentials_menu() {
    print_header "Manage Service Credentials"

    echo -e "${CYAN}Select a service to manage:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} MariaDB/MySQL     - Create database & user"
    echo -e "  ${GREEN}2)${NC} InfluxDB 2.x      - Create org, bucket & token"
    echo -e "  ${GREEN}3)${NC} InfluxDB 1.x      - Create database & user"
    echo -e "  ${GREEN}4)${NC} Mosquitto MQTT    - Create MQTT user"
    echo -e "  ${GREEN}5)${NC} MongoDB           - Create database & user"
    echo -e "  ${GREEN}6)${NC} Redis             - Set password"
    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Enter your choice [0-6]: " choice

    case $choice in
        1) mariadb_credentials_menu ;;
        2) influxdb_credentials_menu ;;
        3) influxdb1_credentials_menu ;;
        4) mosquitto_credentials_menu ;;
        5) mongodb_credentials_menu ;;
        6) redis_credentials_menu ;;
        0) return ;;
        *)
            print_error "Invalid option"
            sleep 1
            credentials_menu
            ;;
    esac
}

#######################################
# MariaDB/MySQL Credentials
#######################################
mariadb_credentials_menu() {
    print_header "MariaDB/MySQL Credentials"

    if ! select_service_container "mariadb"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create new database"
    echo -e "  ${GREEN}2)${NC} Create new user"
    echo -e "  ${GREEN}3)${NC} Create database + user (for a service)"
    echo -e "  ${GREEN}4)${NC} List databases"
    echo -e "  ${GREEN}5)${NC} List users"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) mariadb_create_database ;;
        2) mariadb_create_user ;;
        3) mariadb_create_db_and_user ;;
        4) mariadb_list_databases ;;
        5) mariadb_list_users ;;
        0) credentials_menu ;;
        *) mariadb_credentials_menu ;;
    esac
}

mariadb_create_database() {
    local container="$SELECTED_CONTAINER"
    local root_pass=$(get_env_var "MYSQL_ROOT_PASSWORD")

    read -p "Database name: " db_name
    if [[ -z "$db_name" ]]; then
        print_error "Database name is required"
        press_any_key
        mariadb_credentials_menu
        return
    fi

    docker exec -i "$container" mariadb -uroot -p"${root_pass}" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Database '${db_name}' created successfully"
    else
        print_error "Failed to create database"
    fi

    press_any_key
    mariadb_credentials_menu
}

mariadb_create_user() {
    local container="$SELECTED_CONTAINER"
    local root_pass=$(get_env_var "MYSQL_ROOT_PASSWORD")

    read -p "Username: " username
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        press_any_key
        mariadb_credentials_menu
        return
    fi

    echo -e "${CYAN}Password options:${NC}"
    echo -e "  ${GREEN}1)${NC} Auto-generate"
    echo -e "  ${GREEN}2)${NC} Enter manually"
    read -p "Choice [1]: " pwd_choice

    local password
    if [[ "$pwd_choice" == "2" ]]; then
        read -s -p "Password: " password
        echo ""
    else
        password=$(generate_password 16)
        echo -e "Generated password: ${GREEN}${password}${NC}"
    fi

    read -p "Database to grant access (empty for all): " db_name

    local grant_db="${db_name:-*}"

    docker exec -i "$container" mariadb -uroot -p"${root_pass}" -e "
        CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY '${password}';
        GRANT ALL PRIVILEGES ON \`${grant_db}\`.* TO '${username}'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "User '${username}' created successfully"
        echo -e "${YELLOW}Save these credentials:${NC}"
        echo -e "  Username: ${GREEN}${username}${NC}"
        echo -e "  Password: ${GREEN}${password}${NC}"
        echo -e "  Database: ${GREEN}${grant_db}${NC}"

        # Save to .env
        if confirm "Save to .env file?"; then
            local prefix=$(echo "$db_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            prefix=${prefix:-"MYSQL"}
            set_env_var "${prefix}_USER" "$username"
            set_env_var "${prefix}_PASSWORD" "$password"
            if [[ -n "$db_name" ]]; then
                set_env_var "${prefix}_DATABASE" "$db_name"
            fi
            print_success "Credentials saved to .env"
        fi
    else
        print_error "Failed to create user"
    fi

    press_any_key
    mariadb_credentials_menu
}

mariadb_create_db_and_user() {
    local container="$SELECTED_CONTAINER"
    local root_pass=$(get_env_var "MYSQL_ROOT_PASSWORD")

    read -p "Service name (e.g., nextcloud, wordpress): " service_name
    if [[ -z "$service_name" ]]; then
        print_error "Service name is required"
        press_any_key
        mariadb_credentials_menu
        return
    fi

    local db_name="${service_name}"
    local username="${service_name}"
    local password=$(generate_password 16)

    echo ""
    echo -e "${CYAN}Creating database and user for ${service_name}:${NC}"
    echo -e "  Database: ${GREEN}${db_name}${NC}"
    echo -e "  Username: ${GREEN}${username}${NC}"
    echo -e "  Password: ${GREEN}${password}${NC}"
    echo ""

    if ! confirm "Proceed?"; then
        mariadb_credentials_menu
        return
    fi

    docker exec -i "$container" mariadb -uroot -p"${root_pass}" -e "
        CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
        CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY '${password}';
        GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${username}'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Database and user created successfully"

        # Save to .env
        local prefix=$(echo "$service_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        set_env_var "${prefix}_DB_HOST" "$container"
        set_env_var "${prefix}_DB_NAME" "$db_name"
        set_env_var "${prefix}_DB_USER" "$username"
        set_env_var "${prefix}_DB_PASSWORD" "$password"
        print_success "Credentials saved to .env"
    else
        print_error "Failed to create database/user"
    fi

    press_any_key
    mariadb_credentials_menu
}

mariadb_list_databases() {
    local container="$SELECTED_CONTAINER"
    local root_pass=$(get_env_var "MYSQL_ROOT_PASSWORD")

    echo ""
    echo -e "${CYAN}Databases:${NC}"
    docker exec -i "$container" mariadb -uroot -p"${root_pass}" -e "SHOW DATABASES;" 2>/dev/null

    press_any_key
    mariadb_credentials_menu
}

mariadb_list_users() {
    local container="$SELECTED_CONTAINER"
    local root_pass=$(get_env_var "MYSQL_ROOT_PASSWORD")

    echo ""
    echo -e "${CYAN}Users:${NC}"
    docker exec -i "$container" mariadb -uroot -p"${root_pass}" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null

    press_any_key
    mariadb_credentials_menu
}

#######################################
# InfluxDB Credentials
#######################################
influxdb_credentials_menu() {
    print_header "InfluxDB Credentials"

    if ! select_service_container "influxdb"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create new bucket"
    echo -e "  ${GREEN}2)${NC} Create API token"
    echo -e "  ${GREEN}3)${NC} List buckets"
    echo -e "  ${GREEN}4)${NC} List organizations"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) influxdb_create_bucket ;;
        2) influxdb_create_token ;;
        3) influxdb_list_buckets ;;
        4) influxdb_list_orgs ;;
        0) credentials_menu ;;
        *) influxdb_credentials_menu ;;
    esac
}

influxdb_create_bucket() {
    local container="$SELECTED_CONTAINER"
    local org=$(get_env_var "DOCKER_INFLUXDB_INIT_ORG")
    org=${org:-"homelab"}

    read -p "Bucket name: " bucket_name
    if [[ -z "$bucket_name" ]]; then
        print_error "Bucket name is required"
        press_any_key
        influxdb_credentials_menu
        return
    fi

    read -p "Retention (e.g., 30d, 0 for infinite) [0]: " retention
    retention=${retention:-0}

    docker exec -i "$container" influx bucket create \
        --name "${bucket_name}" \
        --org "${org}" \
        --retention "${retention}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Bucket '${bucket_name}' created"
    else
        print_error "Failed to create bucket"
    fi

    press_any_key
    influxdb_credentials_menu
}

influxdb_create_token() {
    local container="$SELECTED_CONTAINER"
    local org=$(get_env_var "DOCKER_INFLUXDB_INIT_ORG")
    org=${org:-"homelab"}

    read -p "Token description: " description
    read -p "Bucket (empty for all): " bucket

    local bucket_flag=""
    if [[ -n "$bucket" ]]; then
        bucket_flag="--read-bucket ${bucket} --write-bucket ${bucket}"
    else
        bucket_flag="--all-access"
    fi

    echo ""
    local token=$(docker exec -i "$container" influx auth create \
        --org "${org}" \
        --description "${description}" \
        ${bucket_flag} 2>/dev/null | tail -1 | awk '{print $2}')

    if [[ -n "$token" ]]; then
        print_success "Token created:"
        echo -e "${GREEN}${token}${NC}"
        echo ""
        echo -e "${YELLOW}Save this token! It won't be shown again.${NC}"

        if confirm "Save to .env file?"; then
            local var_name=$(echo "${description}_TOKEN" | tr '[:lower:]' '[:upper:]' | tr ' ' '_' | tr '-' '_')
            set_env_var "INFLUXDB_${var_name}" "$token"
            print_success "Token saved to .env"
        fi
    else
        print_error "Failed to create token"
    fi

    press_any_key
    influxdb_credentials_menu
}

influxdb_list_buckets() {
    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Buckets:${NC}"
    docker exec -i "$container" influx bucket list 2>/dev/null

    press_any_key
    influxdb_credentials_menu
}

influxdb_list_orgs() {
    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Organizations:${NC}"
    docker exec -i "$container" influx org list 2>/dev/null

    press_any_key
    influxdb_credentials_menu
}

#######################################
# InfluxDB 1.x Credentials
#######################################
influxdb1_credentials_menu() {
    print_header "InfluxDB 1.x Credentials"

    if ! select_service_container "influxdb1"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create new database"
    echo -e "  ${GREEN}2)${NC} Create new user"
    echo -e "  ${GREEN}3)${NC} Grant user permissions"
    echo -e "  ${GREEN}4)${NC} List databases"
    echo -e "  ${GREEN}5)${NC} List users"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) influxdb1_create_database ;;
        2) influxdb1_create_user ;;
        3) influxdb1_grant_permissions ;;
        4) influxdb1_list_databases ;;
        5) influxdb1_list_users ;;
        0) credentials_menu ;;
        *) influxdb1_credentials_menu ;;
    esac
}

influxdb1_create_database() {
    local container="$SELECTED_CONTAINER"
    local admin_user=$(get_env_var "INFLUXDB1_ADMIN_USER")
    local admin_pass=$(get_env_var "INFLUXDB1_ADMIN_PASSWORD")
    admin_user=${admin_user:-"admin"}

    read -p "Database name: " db_name
    if [[ -z "$db_name" ]]; then
        print_error "Database name is required"
        press_any_key
        influxdb1_credentials_menu
        return
    fi

    read -p "Retention policy duration (e.g., 30d, 52w, INF for infinite) [INF]: " retention
    retention=${retention:-"INF"}

    docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute "CREATE DATABASE \"${db_name}\"" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Database '${db_name}' created"

        # Create retention policy if not infinite
        if [[ "$retention" != "INF" ]]; then
            docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute \
                "CREATE RETENTION POLICY \"default_rp\" ON \"${db_name}\" DURATION ${retention} REPLICATION 1 DEFAULT" 2>/dev/null
            print_info "Retention policy set to ${retention}"
        fi
    else
        print_error "Failed to create database"
    fi

    press_any_key
    influxdb1_credentials_menu
}

influxdb1_create_user() {
    local container="$SELECTED_CONTAINER"
    local admin_user=$(get_env_var "INFLUXDB1_ADMIN_USER")
    local admin_pass=$(get_env_var "INFLUXDB1_ADMIN_PASSWORD")
    admin_user=${admin_user:-"admin"}

    read -p "Username: " username
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        press_any_key
        influxdb1_credentials_menu
        return
    fi

    echo -e "${CYAN}Password options:${NC}"
    echo -e "  ${GREEN}1)${NC} Auto-generate"
    echo -e "  ${GREEN}2)${NC} Enter manually"
    read -p "Choice [1]: " pwd_choice

    local password
    if [[ "$pwd_choice" == "2" ]]; then
        read -s -p "Password: " password
        echo ""
    else
        password=$(generate_password 16)
        echo -e "Generated password: ${GREEN}${password}${NC}"
    fi

    echo ""
    echo -e "${CYAN}User type:${NC}"
    echo -e "  ${GREEN}1)${NC} Regular user (needs grants per database)"
    echo -e "  ${GREEN}2)${NC} Admin user (full access)"
    read -p "Choice [1]: " user_type

    local create_cmd
    if [[ "$user_type" == "2" ]]; then
        create_cmd="CREATE USER \"${username}\" WITH PASSWORD '${password}' WITH ALL PRIVILEGES"
    else
        create_cmd="CREATE USER \"${username}\" WITH PASSWORD '${password}'"
    fi

    docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute "${create_cmd}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "User '${username}' created"
        echo ""
        echo -e "${YELLOW}Connection details:${NC}"
        echo -e "  Host:     ${GREEN}${container}${NC}"
        echo -e "  Port:     ${GREEN}8086${NC}"
        echo -e "  Username: ${GREEN}${username}${NC}"
        echo -e "  Password: ${GREEN}${password}${NC}"

        if confirm "Save to .env file?"; then
            local prefix=$(echo "$username" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            set_env_var "INFLUXDB1_${prefix}_USER" "$username"
            set_env_var "INFLUXDB1_${prefix}_PASSWORD" "$password"
            print_success "Credentials saved to .env"
        fi
    else
        print_error "Failed to create user"
    fi

    press_any_key
    influxdb1_credentials_menu
}

influxdb1_grant_permissions() {
    local container="$SELECTED_CONTAINER"
    local admin_user=$(get_env_var "INFLUXDB1_ADMIN_USER")
    local admin_pass=$(get_env_var "INFLUXDB1_ADMIN_PASSWORD")
    admin_user=${admin_user:-"admin"}

    read -p "Username: " username
    read -p "Database: " db_name

    if [[ -z "$username" || -z "$db_name" ]]; then
        print_error "Username and database are required"
        press_any_key
        influxdb1_credentials_menu
        return
    fi

    echo ""
    echo -e "${CYAN}Permission level:${NC}"
    echo -e "  ${GREEN}1)${NC} READ only"
    echo -e "  ${GREEN}2)${NC} WRITE only"
    echo -e "  ${GREEN}3)${NC} ALL (read + write)"
    read -p "Choice [3]: " perm_choice

    local permission
    case "$perm_choice" in
        1) permission="READ" ;;
        2) permission="WRITE" ;;
        *) permission="ALL" ;;
    esac

    docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute \
        "GRANT ${permission} ON \"${db_name}\" TO \"${username}\"" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Granted ${permission} on '${db_name}' to '${username}'"
    else
        print_error "Failed to grant permissions"
    fi

    press_any_key
    influxdb1_credentials_menu
}

influxdb1_list_databases() {
    local container="$SELECTED_CONTAINER"
    local admin_user=$(get_env_var "INFLUXDB1_ADMIN_USER")
    local admin_pass=$(get_env_var "INFLUXDB1_ADMIN_PASSWORD")
    admin_user=${admin_user:-"admin"}

    echo ""
    echo -e "${CYAN}Databases:${NC}"
    docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute "SHOW DATABASES" 2>/dev/null

    press_any_key
    influxdb1_credentials_menu
}

influxdb1_list_users() {
    local container="$SELECTED_CONTAINER"
    local admin_user=$(get_env_var "INFLUXDB1_ADMIN_USER")
    local admin_pass=$(get_env_var "INFLUXDB1_ADMIN_PASSWORD")
    admin_user=${admin_user:-"admin"}

    echo ""
    echo -e "${CYAN}Users:${NC}"
    docker exec -i "$container" influx -username "${admin_user}" -password "${admin_pass}" -execute "SHOW USERS" 2>/dev/null

    press_any_key
    influxdb1_credentials_menu
}

#######################################
# Mosquitto MQTT Credentials
#######################################
mosquitto_credentials_menu() {
    print_header "Mosquitto MQTT Credentials"

    if ! select_service_container "mosquitto"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create new MQTT user"
    echo -e "  ${GREEN}2)${NC} Delete MQTT user"
    echo -e "  ${GREEN}3)${NC} List MQTT users"
    echo -e "  ${GREEN}4)${NC} Initialize password file"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) mosquitto_create_user ;;
        2) mosquitto_delete_user ;;
        3) mosquitto_list_users ;;
        4) mosquitto_init_pwfile ;;
        0) credentials_menu ;;
        *) mosquitto_credentials_menu ;;
    esac
}

mosquitto_init_pwfile() {
    local container="$SELECTED_CONTAINER"
    local config_dir=$(get_container_data_dir "$container" "mosquitto")
    config_dir="${config_dir}/config"

    # Create config directory if needed
    mkdir -p "$config_dir"

    # Create password file if not exists
    if [[ ! -f "${config_dir}/pwfile" ]]; then
        touch "${config_dir}/pwfile"
        chmod 600 "${config_dir}/pwfile"
        chown 1883:1883 "${config_dir}/pwfile" 2>/dev/null || true
        print_success "Password file created"
    fi

    # Create mosquitto.conf if not exists
    if [[ ! -f "${config_dir}/mosquitto.conf" ]]; then
        cat > "${config_dir}/mosquitto.conf" << 'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_dest stdout

listener 1883
listener 9001
protocol websockets

allow_anonymous false
password_file /mosquitto/config/pwfile
EOF
        chmod 644 "${config_dir}/mosquitto.conf"
        chown 1883:1883 "${config_dir}/mosquitto.conf" 2>/dev/null || true
        print_success "Config file created"
        print_warning "Restart mosquitto for changes to take effect: docker restart ${container}"
    fi

    press_any_key
    mosquitto_credentials_menu
}

mosquitto_create_user() {
    local container="$SELECTED_CONTAINER"
    local config_dir=$(get_container_data_dir "$container" "mosquitto")
    config_dir="${config_dir}/config"

    read -p "MQTT Username: " username
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        press_any_key
        mosquitto_credentials_menu
        return
    fi

    echo -e "${CYAN}Password options:${NC}"
    echo -e "  ${GREEN}1)${NC} Auto-generate"
    echo -e "  ${GREEN}2)${NC} Enter manually"
    read -p "Choice [1]: " pwd_choice

    local password
    if [[ "$pwd_choice" == "2" ]]; then
        read -s -p "Password: " password
        echo ""
    else
        password=$(generate_password 16)
        echo -e "Generated password: ${GREEN}${password}${NC}"
    fi

    # Ensure password file exists
    if [[ ! -f "${config_dir}/pwfile" ]]; then
        print_info "Creating password file..."
        mkdir -p "$config_dir"
        touch "${config_dir}/pwfile"
        chmod 600 "${config_dir}/pwfile"
        chown 1883:1883 "${config_dir}/pwfile" 2>/dev/null || true
    fi

    # Create user using mosquitto_passwd inside container
    local result
    result=$(docker exec "$container" mosquitto_passwd -b /mosquitto/config/pwfile "${username}" "${password}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_success "MQTT user '${username}' created"
        echo ""
        echo -e "${YELLOW}Connection details:${NC}"
        echo -e "  Host:     ${GREEN}${container}${NC} (from other containers)"
        echo -e "  Port:     ${GREEN}1883${NC}"
        echo -e "  Username: ${GREEN}${username}${NC}"
        echo -e "  Password: ${GREEN}${password}${NC}"

        if confirm "Save to .env file?"; then
            local prefix=$(echo "$username" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            set_env_var "MQTT_${prefix}_USER" "$username"
            set_env_var "MQTT_${prefix}_PASSWORD" "$password"
            print_success "Credentials saved to .env"
        fi
    else
        print_error "Failed to create user"
        if [[ -n "$result" ]]; then
            echo -e "${RED}Error: ${result}${NC}"
        fi
        echo ""
        print_info "Try manually: docker exec -it ${container} mosquitto_passwd -c /mosquitto/config/pwfile ${username}"
    fi

    press_any_key
    mosquitto_credentials_menu
}

mosquitto_delete_user() {
    local container="$SELECTED_CONTAINER"

    read -p "Username to delete: " username
    if [[ -z "$username" ]]; then
        press_any_key
        mosquitto_credentials_menu
        return
    fi

    local result
    result=$(docker exec "$container" mosquitto_passwd -D /mosquitto/config/pwfile "${username}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_success "User '${username}' deleted"
    else
        print_error "Failed to delete user"
        if [[ -n "$result" ]]; then
            echo -e "${RED}Error: ${result}${NC}"
        fi
    fi

    press_any_key
    mosquitto_credentials_menu
}

mosquitto_list_users() {
    local container="$SELECTED_CONTAINER"
    local config_dir=$(get_container_data_dir "$container" "mosquitto")

    echo ""
    echo -e "${CYAN}MQTT Users:${NC}"

    if [[ -f "${config_dir}/config/pwfile" ]]; then
        cut -d: -f1 "${config_dir}/config/pwfile" | while read user; do
            echo "  - ${user}"
        done
    else
        print_warning "Password file not found. Initialize it first."
    fi

    press_any_key
    mosquitto_credentials_menu
}

#######################################
# MongoDB Credentials
#######################################
mongodb_credentials_menu() {
    print_header "MongoDB Credentials"

    if ! select_service_container "mongodb"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create database and user"
    echo -e "  ${GREEN}2)${NC} List databases"
    echo -e "  ${GREEN}3)${NC} List users"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) mongodb_create_db_user ;;
        2) mongodb_list_databases ;;
        3) mongodb_list_users ;;
        0) credentials_menu ;;
        *) mongodb_credentials_menu ;;
    esac
}

mongodb_create_db_user() {
    local container="$SELECTED_CONTAINER"
    local root_user=$(get_env_var "MONGO_INITDB_ROOT_USERNAME")
    local root_pass=$(get_env_var "MONGO_INITDB_ROOT_PASSWORD")
    root_user=${root_user:-"root"}

    read -p "Database name: " db_name
    read -p "Username: " username

    if [[ -z "$db_name" || -z "$username" ]]; then
        print_error "Database and username are required"
        press_any_key
        mongodb_credentials_menu
        return
    fi

    local password=$(generate_password 16)
    echo -e "Generated password: ${GREEN}${password}${NC}"

    docker exec -i "$container" mongosh -u "${root_user}" -p "${root_pass}" --authenticationDatabase admin --eval "
        use ${db_name};
        db.createUser({
            user: '${username}',
            pwd: '${password}',
            roles: [{ role: 'readWrite', db: '${db_name}' }]
        });
    " 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Database and user created"
        echo ""
        echo -e "${YELLOW}Connection details:${NC}"
        echo -e "  Host:     ${GREEN}${container}${NC}"
        echo -e "  Port:     ${GREEN}27017${NC}"
        echo -e "  Database: ${GREEN}${db_name}${NC}"
        echo -e "  Username: ${GREEN}${username}${NC}"
        echo -e "  Password: ${GREEN}${password}${NC}"

        if confirm "Save to .env file?"; then
            local prefix=$(echo "$db_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            set_env_var "MONGO_${prefix}_DB" "$db_name"
            set_env_var "MONGO_${prefix}_USER" "$username"
            set_env_var "MONGO_${prefix}_PASSWORD" "$password"
            print_success "Credentials saved to .env"
        fi
    else
        print_error "Failed to create database/user"
    fi

    press_any_key
    mongodb_credentials_menu
}

mongodb_list_databases() {
    local container="$SELECTED_CONTAINER"
    local root_user=$(get_env_var "MONGO_INITDB_ROOT_USERNAME")
    local root_pass=$(get_env_var "MONGO_INITDB_ROOT_PASSWORD")
    root_user=${root_user:-"root"}

    echo ""
    echo -e "${CYAN}Databases:${NC}"
    docker exec -i "$container" mongosh -u "${root_user}" -p "${root_pass}" --authenticationDatabase admin --eval "show dbs" 2>/dev/null

    press_any_key
    mongodb_credentials_menu
}

mongodb_list_users() {
    local container="$SELECTED_CONTAINER"
    local root_user=$(get_env_var "MONGO_INITDB_ROOT_USERNAME")
    local root_pass=$(get_env_var "MONGO_INITDB_ROOT_PASSWORD")
    root_user=${root_user:-"root"}

    read -p "Database (empty for admin): " db_name
    db_name=${db_name:-"admin"}

    echo ""
    echo -e "${CYAN}Users in ${db_name}:${NC}"
    docker exec -i "$container" mongosh -u "${root_user}" -p "${root_pass}" --authenticationDatabase admin --eval "use ${db_name}; db.getUsers()" 2>/dev/null

    press_any_key
    mongodb_credentials_menu
}

#######################################
# Redis Credentials
#######################################
redis_credentials_menu() {
    print_header "Redis Configuration"

    if ! select_service_container "redis"; then
        press_any_key
        return
    fi

    local container="$SELECTED_CONTAINER"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Set/Change password"
    echo -e "  ${GREEN}2)${NC} Test connection"
    echo -e "  ${GREEN}3)${NC} View info"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) redis_set_password ;;
        2) redis_test_connection ;;
        3) redis_info ;;
        0) credentials_menu ;;
        *) redis_credentials_menu ;;
    esac
}

redis_set_password() {
    local container="$SELECTED_CONTAINER"

    echo -e "${CYAN}Password options:${NC}"
    echo -e "  ${GREEN}1)${NC} Auto-generate"
    echo -e "  ${GREEN}2)${NC} Enter manually"
    read -p "Choice [1]: " pwd_choice

    local password
    if [[ "$pwd_choice" == "2" ]]; then
        read -s -p "Password: " password
        echo ""
    else
        password=$(generate_password 32)
    fi

    docker exec -i "$container" redis-cli CONFIG SET requirepass "${password}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Redis password set"
        echo -e "Password: ${GREEN}${password}${NC}"

        set_env_var "REDIS_PASSWORD" "$password"
        print_success "Password saved to .env"

        print_warning "Note: This password will reset when container restarts."
        print_info "For persistent password, update redis.conf"
    else
        print_error "Failed to set password"
    fi

    press_any_key
    redis_credentials_menu
}

redis_test_connection() {
    local container="$SELECTED_CONTAINER"
    local password=$(get_env_var "REDIS_PASSWORD")

    local auth_flag=""
    if [[ -n "$password" ]]; then
        auth_flag="-a ${password}"
    fi

    docker exec -i "$container" redis-cli ${auth_flag} PING 2>/dev/null

    press_any_key
    redis_credentials_menu
}

redis_info() {
    local container="$SELECTED_CONTAINER"
    local password=$(get_env_var "REDIS_PASSWORD")

    local auth_flag=""
    if [[ -n "$password" ]]; then
        auth_flag="-a ${password}"
    fi

    docker exec -i "$container" redis-cli ${auth_flag} INFO server 2>/dev/null

    press_any_key
    redis_credentials_menu
}

#######################################
# Device Configuration Menu
#######################################
device_config_menu() {
    print_header "Device Configuration"

    echo -e "${CYAN}Configure serial/RS485 devices:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} mbusd         - Modbus TCP Gateway"
    echo -e "  ${GREEN}2)${NC} ser2net       - Serial to TCP Proxy"
    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Enter your choice [0-2]: " choice

    case $choice in
        1) mbusd_config_menu ;;
        2) ser2net_config_menu ;;
        0) return ;;
        *)
            print_error "Invalid option"
            sleep 1
            device_config_menu
            ;;
    esac
}

#######################################
# mbusd Configuration
#######################################
mbusd_config_menu() {
    print_header "mbusd Configuration"

    # Show current configuration
    echo -e "${CYAN}Current Configuration:${NC}"
    echo ""

    local serial_port=$(get_env_var "MBUSD_SERIAL_PORT")
    local baud_rate=$(get_env_var "MBUSD_BAUD_RATE")
    local parity=$(get_env_var "MBUSD_PARITY")
    local data_bits=$(get_env_var "MBUSD_DATA_BITS")
    local stop_bits=$(get_env_var "MBUSD_STOP_BITS")
    local tcp_port=$(get_env_var "MBUSD_PORT")
    local max_conn=$(get_env_var "MBUSD_MAX_CONNECTIONS")
    local timeout=$(get_env_var "MBUSD_TIMEOUT")

    echo -e "  Serial Port:    ${GREEN}${serial_port:-/dev/ttyUSB0}${NC}"
    echo -e "  Baud Rate:      ${GREEN}${baud_rate:-9600}${NC}"
    echo -e "  Parity:         ${GREEN}${parity:-none}${NC}"
    echo -e "  Data Bits:      ${GREEN}${data_bits:-8}${NC}"
    echo -e "  Stop Bits:      ${GREEN}${stop_bits:-1}${NC}"
    echo -e "  TCP Port:       ${GREEN}${tcp_port:-502}${NC}"
    echo -e "  Max Connections:${GREEN}${max_conn:-4}${NC}"
    echo -e "  Timeout:        ${GREEN}${timeout:-3}s${NC}"
    echo ""

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Change Serial Port"
    echo -e "  ${GREEN}2)${NC} Change Baud Rate"
    echo -e "  ${GREEN}3)${NC} Change Parity"
    echo -e "  ${GREEN}4)${NC} Change Data Bits"
    echo -e "  ${GREEN}5)${NC} Change Stop Bits"
    echo -e "  ${GREEN}6)${NC} Change TCP Port"
    echo -e "  ${GREEN}7)${NC} Change Max Connections"
    echo -e "  ${GREEN}8)${NC} Change Timeout"
    echo -e "  ${GREEN}9)${NC} Detect Serial Devices"
    echo ""
    echo -e "  ${YELLOW}r)${NC} Restart mbusd container"
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) mbusd_set_serial_port ;;
        2) mbusd_set_baud_rate ;;
        3) mbusd_set_parity ;;
        4) mbusd_set_data_bits ;;
        5) mbusd_set_stop_bits ;;
        6) mbusd_set_tcp_port ;;
        7) mbusd_set_max_connections ;;
        8) mbusd_set_timeout ;;
        9) detect_serial_devices ;;
        r|R) mbusd_restart ;;
        0) device_config_menu ;;
        *) mbusd_config_menu ;;
    esac
}

detect_serial_devices() {
    echo ""
    echo -e "${CYAN}Detecting serial devices...${NC}"
    echo ""

    # List USB serial devices
    echo -e "${YELLOW}USB Serial Devices:${NC}"
    if ls /dev/ttyUSB* 2>/dev/null; then
        for dev in /dev/ttyUSB*; do
            if [[ -e "$dev" ]]; then
                local info=$(udevadm info -q property -n "$dev" 2>/dev/null | grep -E "ID_MODEL=|ID_VENDOR=" | tr '\n' ' ')
                echo -e "  ${GREEN}${dev}${NC} ${info}"
            fi
        done
    else
        echo "  (none found)"
    fi

    echo ""
    echo -e "${YELLOW}ACM Devices (Arduino, etc.):${NC}"
    if ls /dev/ttyACM* 2>/dev/null; then
        for dev in /dev/ttyACM*; do
            if [[ -e "$dev" ]]; then
                local info=$(udevadm info -q property -n "$dev" 2>/dev/null | grep -E "ID_MODEL=|ID_VENDOR=" | tr '\n' ' ')
                echo -e "  ${GREEN}${dev}${NC} ${info}"
            fi
        done
    else
        echo "  (none found)"
    fi

    echo ""
    echo -e "${YELLOW}Hardware Serial (Raspberry Pi, etc.):${NC}"
    for dev in /dev/ttyAMA0 /dev/ttyS0 /dev/serial0 /dev/serial1; do
        if [[ -e "$dev" ]]; then
            echo -e "  ${GREEN}${dev}${NC}"
        fi
    done

    echo ""
    echo -e "${YELLOW}All Serial Ports:${NC}"
    ls -la /dev/tty{USB,ACM,AMA,S}* 2>/dev/null || echo "  (none found)"

    press_any_key
    mbusd_config_menu
}

mbusd_set_serial_port() {
    echo ""
    detect_serial_devices_silent

    local current=$(get_env_var "MBUSD_SERIAL_PORT")
    echo -e "Current: ${GREEN}${current:-/dev/ttyUSB0}${NC}"
    echo ""
    read -p "New serial port path [${current:-/dev/ttyUSB0}]: " new_value

    if [[ -n "$new_value" ]]; then
        if [[ -e "$new_value" ]]; then
            set_env_var "MBUSD_SERIAL_PORT" "$new_value"
            print_success "Serial port set to: $new_value"
            print_warning "Restart mbusd for changes to take effect"
        else
            print_error "Device $new_value does not exist"
            if confirm "Set anyway?"; then
                set_env_var "MBUSD_SERIAL_PORT" "$new_value"
                print_success "Serial port set to: $new_value"
            fi
        fi
    fi

    press_any_key
    mbusd_config_menu
}

detect_serial_devices_silent() {
    echo -e "${CYAN}Available devices:${NC}"
    local found=false
    for dev in /dev/ttyUSB* /dev/ttyACM* /dev/ttyAMA* /dev/ttyS0; do
        if [[ -e "$dev" ]]; then
            echo -e "  ${GREEN}${dev}${NC}"
            found=true
        fi
    done
    if [[ "$found" == false ]]; then
        echo "  (no serial devices found)"
    fi
}

mbusd_set_baud_rate() {
    echo ""
    echo -e "${CYAN}Common baud rates:${NC}"
    echo -e "  ${GREEN}1)${NC} 9600   (default for many Modbus devices)"
    echo -e "  ${GREEN}2)${NC} 19200"
    echo -e "  ${GREEN}3)${NC} 38400"
    echo -e "  ${GREEN}4)${NC} 57600"
    echo -e "  ${GREEN}5)${NC} 115200"
    echo -e "  ${GREEN}6)${NC} Custom"
    echo ""

    local current=$(get_env_var "MBUSD_BAUD_RATE")
    echo -e "Current: ${GREEN}${current:-9600}${NC}"

    read -p "Choice [1]: " choice

    local new_value
    case $choice in
        1|"") new_value="9600" ;;
        2) new_value="19200" ;;
        3) new_value="38400" ;;
        4) new_value="57600" ;;
        5) new_value="115200" ;;
        6)
            read -p "Enter baud rate: " new_value
            ;;
    esac

    if [[ -n "$new_value" ]]; then
        set_env_var "MBUSD_BAUD_RATE" "$new_value"
        print_success "Baud rate set to: $new_value"
        print_warning "Restart mbusd for changes to take effect"
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_parity() {
    echo ""
    echo -e "${CYAN}Parity options:${NC}"
    echo -e "  ${GREEN}1)${NC} none  (most common)"
    echo -e "  ${GREEN}2)${NC} even"
    echo -e "  ${GREEN}3)${NC} odd"
    echo ""

    local current=$(get_env_var "MBUSD_PARITY")
    echo -e "Current: ${GREEN}${current:-none}${NC}"

    read -p "Choice [1]: " choice

    local new_value
    case $choice in
        1|"") new_value="none" ;;
        2) new_value="even" ;;
        3) new_value="odd" ;;
    esac

    if [[ -n "$new_value" ]]; then
        set_env_var "MBUSD_PARITY" "$new_value"
        print_success "Parity set to: $new_value"
        print_warning "Restart mbusd for changes to take effect"
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_data_bits() {
    echo ""
    echo -e "${CYAN}Data bits options:${NC}"
    echo -e "  ${GREEN}1)${NC} 8 (standard)"
    echo -e "  ${GREEN}2)${NC} 7"
    echo ""

    local current=$(get_env_var "MBUSD_DATA_BITS")
    echo -e "Current: ${GREEN}${current:-8}${NC}"

    read -p "Choice [1]: " choice

    local new_value
    case $choice in
        1|"") new_value="8" ;;
        2) new_value="7" ;;
    esac

    if [[ -n "$new_value" ]]; then
        set_env_var "MBUSD_DATA_BITS" "$new_value"
        print_success "Data bits set to: $new_value"
        print_warning "Restart mbusd for changes to take effect"
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_stop_bits() {
    echo ""
    echo -e "${CYAN}Stop bits options:${NC}"
    echo -e "  ${GREEN}1)${NC} 1 (standard)"
    echo -e "  ${GREEN}2)${NC} 2"
    echo ""

    local current=$(get_env_var "MBUSD_STOP_BITS")
    echo -e "Current: ${GREEN}${current:-1}${NC}"

    read -p "Choice [1]: " choice

    local new_value
    case $choice in
        1|"") new_value="1" ;;
        2) new_value="2" ;;
    esac

    if [[ -n "$new_value" ]]; then
        set_env_var "MBUSD_STOP_BITS" "$new_value"
        print_success "Stop bits set to: $new_value"
        print_warning "Restart mbusd for changes to take effect"
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_tcp_port() {
    echo ""
    local current=$(get_env_var "MBUSD_PORT")
    echo -e "Current TCP port: ${GREEN}${current:-502}${NC}"
    echo -e "${YELLOW}Note: Port 502 is the standard Modbus TCP port${NC}"
    echo ""

    read -p "New TCP port [${current:-502}]: " new_value

    if [[ -n "$new_value" ]]; then
        if [[ "$new_value" =~ ^[0-9]+$ ]] && [[ "$new_value" -ge 1 ]] && [[ "$new_value" -le 65535 ]]; then
            set_env_var "MBUSD_PORT" "$new_value"
            print_success "TCP port set to: $new_value"
            print_warning "Restart mbusd for changes to take effect"
        else
            print_error "Invalid port number (1-65535)"
        fi
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_max_connections() {
    echo ""
    local current=$(get_env_var "MBUSD_MAX_CONNECTIONS")
    echo -e "Current max connections: ${GREEN}${current:-4}${NC}"
    echo ""

    read -p "New max connections [${current:-4}]: " new_value

    if [[ -n "$new_value" ]]; then
        if [[ "$new_value" =~ ^[0-9]+$ ]] && [[ "$new_value" -ge 1 ]]; then
            set_env_var "MBUSD_MAX_CONNECTIONS" "$new_value"
            print_success "Max connections set to: $new_value"
            print_warning "Restart mbusd for changes to take effect"
        else
            print_error "Invalid value"
        fi
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_set_timeout() {
    echo ""
    local current=$(get_env_var "MBUSD_TIMEOUT")
    echo -e "Current timeout: ${GREEN}${current:-3}${NC} seconds"
    echo ""

    read -p "New timeout in seconds [${current:-3}]: " new_value

    if [[ -n "$new_value" ]]; then
        if [[ "$new_value" =~ ^[0-9]+$ ]] && [[ "$new_value" -ge 1 ]]; then
            set_env_var "MBUSD_TIMEOUT" "$new_value"
            print_success "Timeout set to: $new_value seconds"
            print_warning "Restart mbusd for changes to take effect"
        else
            print_error "Invalid value"
        fi
    fi

    press_any_key
    mbusd_config_menu
}

mbusd_restart() {
    echo ""
    local containers=()
    mapfile -t containers < <(find_service_containers "mbusd" | tr ' ' '\n')

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "mbusd is not running"
        press_any_key
        mbusd_config_menu
        return
    fi

    for container in "${containers[@]}"; do
        print_info "Restarting $container..."
        docker restart "$container"
        if [[ $? -eq 0 ]]; then
            print_success "$container restarted"
        else
            print_error "Failed to restart $container"
        fi
    done

    press_any_key
    mbusd_config_menu
}

#######################################
# ser2net Configuration
#######################################
ser2net_config_menu() {
    print_header "ser2net Configuration"

    # Show current configuration
    echo -e "${CYAN}Current Configuration:${NC}"
    echo ""

    # Device 1
    local port1=$(get_env_var "SER2NET_PORT1")
    local serial1=$(get_env_var "SER2NET_SERIAL1")
    local baud1=$(get_env_var "SER2NET_BAUD1")

    echo -e "${YELLOW}Device 1:${NC}"
    echo -e "  TCP Port:    ${GREEN}${port1:-3001}${NC}"
    echo -e "  Serial:      ${GREEN}${serial1:-/dev/ttyUSB0}${NC}"
    echo -e "  Baud Rate:   ${GREEN}${baud1:-9600}${NC}"

    # Device 2
    local port2=$(get_env_var "SER2NET_PORT2")
    if [[ -n "$port2" && "$port2" != "0" ]]; then
        local serial2=$(get_env_var "SER2NET_SERIAL2")
        local baud2=$(get_env_var "SER2NET_BAUD2")
        echo ""
        echo -e "${YELLOW}Device 2:${NC}"
        echo -e "  TCP Port:    ${GREEN}${port2}${NC}"
        echo -e "  Serial:      ${GREEN}${serial2:-/dev/ttyUSB1}${NC}"
        echo -e "  Baud Rate:   ${GREEN}${baud2:-9600}${NC}"
    fi

    # Device 3
    local port3=$(get_env_var "SER2NET_PORT3")
    if [[ -n "$port3" && "$port3" != "0" ]]; then
        local serial3=$(get_env_var "SER2NET_SERIAL3")
        local baud3=$(get_env_var "SER2NET_BAUD3")
        echo ""
        echo -e "${YELLOW}Device 3:${NC}"
        echo -e "  TCP Port:    ${GREEN}${port3}${NC}"
        echo -e "  Serial:      ${GREEN}${serial3:-/dev/ttyAMA0}${NC}"
        echo -e "  Baud Rate:   ${GREEN}${baud3:-115200}${NC}"
    fi

    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Configure Device 1"
    echo -e "  ${GREEN}2)${NC} Configure Device 2"
    echo -e "  ${GREEN}3)${NC} Configure Device 3"
    echo -e "  ${GREEN}4)${NC} Detect Serial Devices"
    echo -e "  ${GREEN}5)${NC} Update ser2net.conf"
    echo ""
    echo -e "  ${YELLOW}r)${NC} Restart ser2net container"
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) ser2net_configure_device 1 ;;
        2) ser2net_configure_device 2 ;;
        3) ser2net_configure_device 3 ;;
        4) detect_serial_devices; ser2net_config_menu ;;
        5) ser2net_update_config ;;
        r|R) ser2net_restart ;;
        0) device_config_menu ;;
        *) ser2net_config_menu ;;
    esac
}

ser2net_configure_device() {
    local device_num=$1

    print_header "Configure ser2net Device ${device_num}"

    local port_var="SER2NET_PORT${device_num}"
    local serial_var="SER2NET_SERIAL${device_num}"
    local baud_var="SER2NET_BAUD${device_num}"

    local current_port=$(get_env_var "$port_var")
    local current_serial=$(get_env_var "$serial_var")
    local current_baud=$(get_env_var "$baud_var")

    # Set defaults based on device number
    local default_port=$((3000 + device_num))
    local default_serial="/dev/ttyUSB$((device_num - 1))"
    local default_baud="9600"

    if [[ $device_num -eq 3 ]]; then
        default_serial="/dev/ttyAMA0"
        default_baud="115200"
    fi

    echo ""
    detect_serial_devices_silent
    echo ""

    echo -e "${CYAN}Current settings for Device ${device_num}:${NC}"
    echo -e "  TCP Port:    ${current_port:-$default_port}"
    echo -e "  Serial:      ${current_serial:-$default_serial}"
    echo -e "  Baud Rate:   ${current_baud:-$default_baud}"
    echo ""

    # Enable/Disable
    if [[ $device_num -gt 1 ]]; then
        echo -e "${CYAN}Enable this device?${NC}"
        echo -e "  ${GREEN}1)${NC} Yes"
        echo -e "  ${GREEN}2)${NC} No (disable)"
        read -p "Choice [1]: " enable_choice

        if [[ "$enable_choice" == "2" ]]; then
            set_env_var "$port_var" "0"
            print_success "Device ${device_num} disabled"
            press_any_key
            ser2net_config_menu
            return
        fi
    fi

    # TCP Port
    read -p "TCP Port [${current_port:-$default_port}]: " new_port
    new_port=${new_port:-${current_port:-$default_port}}

    # Serial device
    read -p "Serial device path [${current_serial:-$default_serial}]: " new_serial
    new_serial=${new_serial:-${current_serial:-$default_serial}}

    # Baud rate
    echo ""
    echo -e "${CYAN}Baud rate:${NC}"
    echo -e "  ${GREEN}1)${NC} 9600"
    echo -e "  ${GREEN}2)${NC} 19200"
    echo -e "  ${GREEN}3)${NC} 38400"
    echo -e "  ${GREEN}4)${NC} 57600"
    echo -e "  ${GREEN}5)${NC} 115200"
    echo -e "  ${GREEN}6)${NC} Custom"

    local baud_default="1"
    if [[ "${current_baud:-$default_baud}" == "115200" ]]; then
        baud_default="5"
    fi

    read -p "Choice [$baud_default]: " baud_choice
    baud_choice=${baud_choice:-$baud_default}

    local new_baud
    case $baud_choice in
        1) new_baud="9600" ;;
        2) new_baud="19200" ;;
        3) new_baud="38400" ;;
        4) new_baud="57600" ;;
        5) new_baud="115200" ;;
        6)
            read -p "Enter baud rate: " new_baud
            ;;
        *) new_baud="${current_baud:-$default_baud}" ;;
    esac

    # Validate and save
    if [[ -n "$new_serial" && ! -e "$new_serial" ]]; then
        print_warning "Device $new_serial does not currently exist"
        if ! confirm "Continue anyway?"; then
            press_any_key
            ser2net_config_menu
            return
        fi
    fi

    set_env_var "$port_var" "$new_port"
    set_env_var "$serial_var" "$new_serial"
    set_env_var "$baud_var" "$new_baud"

    print_success "Device ${device_num} configured:"
    echo -e "  TCP Port:    ${GREEN}${new_port}${NC}"
    echo -e "  Serial:      ${GREEN}${new_serial}${NC}"
    echo -e "  Baud Rate:   ${GREEN}${new_baud}${NC}"

    print_warning "Run 'Update ser2net.conf' and restart container for changes to take effect"

    press_any_key
    ser2net_config_menu
}

ser2net_update_config() {
    echo ""

    # Find ser2net data directory
    local containers=()
    mapfile -t containers < <(find_service_containers "ser2net" | tr ' ' '\n')
    local config_dir=""

    if [[ ${#containers[@]} -gt 0 ]]; then
        config_dir=$(get_container_data_dir "${containers[0]}" "ser2net")
        config_dir="${config_dir}/config"
    else
        # Default path
        local docker_root=$(get_env_var "DOCKER_ROOT")
        docker_root=${docker_root:-"/docker-storage"}
        local stack=$(get_env_var "COMPOSE_PROJECT_NAME")
        stack=${stack:-"docker"}
        config_dir="${docker_root}/${stack}/ser2net/config"
    fi

    mkdir -p "$config_dir"

    # Generate ser2net.conf
    local port1=$(get_env_var "SER2NET_PORT1")
    local serial1=$(get_env_var "SER2NET_SERIAL1")
    local baud1=$(get_env_var "SER2NET_BAUD1")

    port1=${port1:-3001}
    serial1=${serial1:-/dev/ttyUSB0}
    baud1=${baud1:-9600}

    cat > "${config_dir}/ser2net.conf" << EOF
# ser2net configuration file
# Generated by Docker Services Manager
# Format: <TCP port>:<state>:<timeout>:<device>:<options>

# Device 1
${port1}:raw:0:${serial1}:${baud1} NONE 1STOPBIT 8DATABITS XONXOFF LOCAL -RTSCTS
EOF

    # Add device 2 if enabled
    local port2=$(get_env_var "SER2NET_PORT2")
    if [[ -n "$port2" && "$port2" != "0" ]]; then
        local serial2=$(get_env_var "SER2NET_SERIAL2")
        local baud2=$(get_env_var "SER2NET_BAUD2")
        serial2=${serial2:-/dev/ttyUSB1}
        baud2=${baud2:-9600}

        cat >> "${config_dir}/ser2net.conf" << EOF

# Device 2
${port2}:raw:0:${serial2}:${baud2} NONE 1STOPBIT 8DATABITS XONXOFF LOCAL -RTSCTS
EOF
    fi

    # Add device 3 if enabled
    local port3=$(get_env_var "SER2NET_PORT3")
    if [[ -n "$port3" && "$port3" != "0" ]]; then
        local serial3=$(get_env_var "SER2NET_SERIAL3")
        local baud3=$(get_env_var "SER2NET_BAUD3")
        serial3=${serial3:-/dev/ttyAMA0}
        baud3=${baud3:-115200}

        cat >> "${config_dir}/ser2net.conf" << EOF

# Device 3
${port3}:raw:0:${serial3}:${baud3} NONE 1STOPBIT 8DATABITS XONXOFF LOCAL -RTSCTS
EOF
    fi

    print_success "Configuration written to: ${config_dir}/ser2net.conf"
    echo ""
    echo -e "${CYAN}Contents:${NC}"
    cat "${config_dir}/ser2net.conf"

    press_any_key
    ser2net_config_menu
}

ser2net_restart() {
    echo ""
    local containers=()
    mapfile -t containers < <(find_service_containers "ser2net" | tr ' ' '\n')

    if [[ ${#containers[@]} -eq 0 ]]; then
        print_error "ser2net is not running"
        press_any_key
        ser2net_config_menu
        return
    fi

    for container in "${containers[@]}"; do
        print_info "Restarting $container..."
        docker restart "$container"
        if [[ $? -eq 0 ]]; then
            print_success "$container restarted"
        else
            print_error "Failed to restart $container"
        fi
    done

    press_any_key
    ser2net_config_menu
}
