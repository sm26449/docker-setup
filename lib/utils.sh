#!/bin/bash

#######################################
# Utility Functions
#######################################

#######################################
# Print success message
#######################################
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

#######################################
# Print error message
#######################################
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

#######################################
# Print warning message
#######################################
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

#######################################
# Print info message
#######################################
print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

#######################################
# Print section header
#######################################
print_header() {
    echo ""
    echo -e "${BOLD}${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${PURPLE}  $1${NC}"
    echo -e "${BOLD}${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

#######################################
# Confirm action
# Arguments:
#   $1 - Prompt message
#   $2 - Default (Y/n)
# Returns:
#   0 if yes, 1 if no
#######################################
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-Y}"
    local answer

    if [[ "$default" == "Y" ]]; then
        read -p "${prompt} [Y/n]: " answer
        answer=${answer:-Y}
    else
        read -p "${prompt} [y/N]: " answer
        answer=${answer:-N}
    fi

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#######################################
# Detect OS
# Returns:
#   ubuntu, centos, rocky, alma, debian, or unknown
#######################################
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu)
                echo "ubuntu"
                ;;
            debian)
                echo "debian"
                ;;
            centos)
                echo "centos"
                ;;
            rocky)
                echo "rocky"
                ;;
            almalinux)
                echo "alma"
                ;;
            fedora)
                echo "fedora"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

#######################################
# Get OS version
#######################################
get_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$VERSION_ID"
    else
        echo "unknown"
    fi
}

#######################################
# Check if command exists
#######################################
command_exists() {
    command -v "$1" &> /dev/null
}

#######################################
# Generate random password
# Arguments:
#   $1 - Length (default: 20)
#######################################
generate_password() {
    local length=${1:-20}
    # Use alphanumeric + safe special chars only
    # Note: hyphen MUST be at end to avoid being interpreted as a range
    tr -dc 'A-Za-z0-9@#_-' < /dev/urandom | head -c "$length"
}

#######################################
# Generate random string (alphanumeric only)
# Arguments:
#   $1 - Length (default: 32)
#######################################
generate_random_string() {
    local length=${1:-32}
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

#######################################
# Load existing .env file
#######################################
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

#######################################
# Check if variable exists in .env
# Arguments:
#   $1 - Variable name
#######################################
env_var_exists() {
    local var_name=$1
    if [[ -f "$ENV_FILE" ]]; then
        grep -q "^${var_name}=" "$ENV_FILE"
        return $?
    fi
    return 1
}

#######################################
# Get variable value from .env
# Arguments:
#   $1 - Variable name
#######################################
get_env_var() {
    local var_name=$1
    if [[ -f "$ENV_FILE" ]]; then
        # Get value and strip surrounding quotes if present
        local value=$(grep "^${var_name}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
        # Remove surrounding quotes (single or double)
        value="${value#\'}"
        value="${value%\'}"
        value="${value#\"}"
        value="${value%\"}"
        echo "$value"
    fi
}

#######################################
# Set variable in .env (append or update)
# Arguments:
#   $1 - Variable name
#   $2 - Variable value
#######################################
set_env_var() {
    local var_name=$1
    local var_value=$2

    # Create .env if it doesn't exist
    touch "$ENV_FILE"

    # Docker-compose .env files: always quote values to be safe
    # This prevents issues with shell metacharacters like ; < > & | etc.
    local final_value="\"${var_value}\""

    if env_var_exists "$var_name"; then
        # Update existing variable - use different delimiter to handle special chars
        sed -i "s|^${var_name}=.*|${var_name}=${final_value}|" "$ENV_FILE"
    else
        # Append new variable
        echo "${var_name}=${final_value}" >> "$ENV_FILE"
    fi
}

#######################################
# Press any key to continue
#######################################
press_any_key() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
}

#######################################
# Parse YAML-like container.yaml
# Simple parser for our template format
# Arguments:
#   $1 - File path
#   $2 - Key to extract
#######################################
parse_yaml_value() {
    local file=$1
    local key=$2
    grep "^${key}:" "$file" 2>/dev/null | sed "s/${key}:[[:space:]]*//" | tr -d '"' | tr -d "'"
}

#######################################
# Parse YAML array
# Arguments:
#   $1 - File path
#   $2 - Array key
#######################################
parse_yaml_array() {
    local file=$1
    local key=$2
    local in_array=false
    local result=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^${key}: ]]; then
            in_array=true
            continue
        fi

        if $in_array; then
            # Handle new format: - name: value
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
                local item="${BASH_REMATCH[1]}"
                item=$(echo "$item" | tr -d '"' | tr -d "'" | xargs)
                result+=("$item")
            # Handle old format: - value
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-z][a-z0-9_-]*)$ ]]; then
                local item="${BASH_REMATCH[1]}"
                result+=("$item")
            # Exit on new top-level key
            elif [[ ! "$line" =~ ^[[:space:]] ]] && [[ -n "$line" ]]; then
                break
            fi
        fi
    done < "$file"

    echo "${result[@]}"
}

#######################################
# Check if service is running
# Arguments:
#   $1 - Service name
#######################################
is_service_running() {
    local service=$1
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service}$"
}

#######################################
# Check if service exists in compose
# Arguments:
#   $1 - Service name
#   $2 - Stack name (optional, defaults to CURRENT_STACK)
#######################################
service_in_compose() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"
    stack="${stack:-default}"

    # Get compose file for this stack
    local compose_file
    if [[ "$stack" == "default" ]]; then
        compose_file="${SCRIPT_DIR}/docker-compose.yml"
    else
        compose_file="${SCRIPT_DIR}/docker-compose.${stack}.yml"
    fi

    # Check for service with or without stack prefix
    local container_name="$service"
    [[ "$stack" != "default" ]] && container_name="${stack}-${service}"

    if [[ -f "$compose_file" ]]; then
        # Check both original service name and prefixed container name
        grep -qE "^  (${service}|${container_name}):" "$compose_file" 2>/dev/null
        return $?
    fi
    return 1
}

#######################################
# Create service directories
# Uses the new structure: DOCKER_ROOT/stack/service/{config,data,logs}
# Arguments:
#   $1 - Service name
#   $2 - Stack name (optional, defaults to CURRENT_STACK)
#######################################
create_service_dirs() {
    local service=$1
    local stack="${2:-$CURRENT_STACK}"
    stack="${stack:-default}"

    local docker_root=$(get_env_var "DOCKER_ROOT")
    docker_root=${docker_root:-"/docker-storage"}

    local base_dir
    if [[ "$stack" == "default" ]]; then
        base_dir="${docker_root}/${service}"
    else
        base_dir="${docker_root}/${stack}/${service}"
    fi

    mkdir -p "${base_dir}/config"
    mkdir -p "${base_dir}/data"
    mkdir -p "${base_dir}/logs"

    # Set permissions
    local puid=$(get_env_var "PUID")
    local pgid=$(get_env_var "PGID")
    puid=${puid:-1000}
    pgid=${pgid:-1000}

    chown -R "${puid}:${pgid}" "${base_dir}" 2>/dev/null || true

    # Return the base directory for reference
    echo "$base_dir"
}

#######################################
# View running services status
#######################################
view_status() {
    print_header "Docker Services Status"

    if ! command_exists docker; then
        print_error "Docker is not installed"
        press_any_key
        return
    fi

    echo -e "${CYAN}Running Containers:${NC}"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
    echo ""

    if [[ -f "$COMPOSE_FILE" ]]; then
        echo -e "${CYAN}Services in docker-compose.yml:${NC}"
        echo ""
        grep -E "^  [a-zA-Z0-9_-]+:" "$COMPOSE_FILE" | sed 's/://' | sed 's/^  /  • /' || echo "No services defined"
    fi

    press_any_key
}

#######################################
# Versioning/Backup System
#######################################
BACKUP_DIR="${SCRIPT_DIR}/backups"
MAX_AUTO_BACKUPS=10

#######################################
# Create versioned backup
# Arguments:
#   $1 - Backup reason/label (optional)
#   $2 - Auto backup flag (optional, "auto")
# Returns:
#   0 on success, 1 on failure
#######################################
create_backup() {
    local label="${1:-manual}"
    local auto="${2:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${timestamp}_${label}"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    mkdir -p "$backup_path"

    # Backup all compose files
    local compose_files=()
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        compose_files+=("docker-compose.yml")
    fi
    for file in "${SCRIPT_DIR}"/docker-compose.*.yml; do
        if [[ -f "$file" ]]; then
            compose_files+=("$(basename "$file")")
        fi
    done

    # Copy files to backup directory
    local has_files=false

    # Copy compose files
    for file in "${compose_files[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            cp "${SCRIPT_DIR}/${file}" "${backup_path}/" 2>/dev/null && has_files=true
        fi
    done

    # Copy .env file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        cp "${SCRIPT_DIR}/.env" "${backup_path}/" 2>/dev/null && has_files=true
    fi

    # Save metadata
    if [[ "$has_files" == true ]]; then
        cat > "${backup_path}/backup_info.txt" << EOF
Backup created: $(date)
Label: ${label}
Type: ${auto:-manual}
Compose files: ${compose_files[*]}
EOF
        if [[ -z "$auto" ]]; then
            print_success "Backup created: ${backup_name}"
        fi
        return 0
    else
        rm -rf "$backup_path"
        if [[ -z "$auto" ]]; then
            print_warning "Nothing to backup"
        fi
        return 1
    fi
}

#######################################
# Auto-backup before major operations
# Arguments:
#   $1 - Operation label (e.g., "before-add-service")
#######################################
auto_backup() {
    local label="${1:-auto}"

    # Only create auto-backup if there are compose files
    local has_compose=false
    [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]] && has_compose=true
    for file in "${SCRIPT_DIR}"/docker-compose.*.yml; do
        [[ -f "$file" ]] && has_compose=true && break
    done

    if [[ "$has_compose" == false ]]; then
        return 0
    fi

    create_backup "$label" "auto" >/dev/null 2>&1

    # Cleanup old auto-backups (keep only MAX_AUTO_BACKUPS)
    cleanup_old_backups
}

#######################################
# Cleanup old auto-backups
#######################################
cleanup_old_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return
    fi

    # Get auto-backup directories sorted by date (oldest first)
    local auto_backups=($(ls -dt "${BACKUP_DIR}"/backup_*_auto* 2>/dev/null | tail -n +$((MAX_AUTO_BACKUPS + 1))))

    for backup in "${auto_backups[@]}"; do
        if [[ -d "$backup" ]]; then
            rm -rf "$backup"
        fi
    done
}

#######################################
# List available backups
#######################################
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        print_warning "No backups found"
        return 1
    fi

    echo -e "${CYAN}Available Backups:${NC}"
    echo ""

    local i=1
    local backups=()
    for backup_dir in $(ls -dt "${BACKUP_DIR}"/backup_* 2>/dev/null); do
        if [[ -d "$backup_dir" ]]; then
            local backup_name=$(basename "$backup_dir")
            backups+=("$backup_dir")

            # Parse backup info
            local date_part=$(echo "$backup_name" | sed 's/backup_\([0-9]*\)_\([0-9]*\)_.*/\1 \2/')
            local year=${date_part:0:4}
            local month=${date_part:4:2}
            local day=${date_part:6:2}
            local time_part=$(echo "$backup_name" | sed 's/backup_[0-9]*_\([0-9]*\)_.*/\1/')
            local hour=${time_part:0:2}
            local min=${time_part:2:2}
            local label=$(echo "$backup_name" | sed 's/backup_[0-9]*_[0-9]*_//')

            # Count compose files
            local compose_count=$(ls -1 "${backup_dir}"/docker-compose*.yml 2>/dev/null | wc -l)

            # Display
            local type_color="${GREEN}"
            [[ "$label" == *"auto"* ]] && type_color="${YELLOW}"

            printf "  ${GREEN}%2d)${NC} ${year}-${month}-${day} ${hour}:${min}  " "$i"
            printf "${type_color}%-25s${NC} " "$label"
            printf "${CYAN}(%d compose files)${NC}\n" "$compose_count"

            ((i++))
        fi
    done

    echo ""
    AVAILABLE_BACKUPS=("${backups[@]}")
    return 0
}

#######################################
# Restore from backup
# Arguments:
#   $1 - Backup path
#######################################
restore_backup() {
    local backup_path="$1"

    if [[ ! -d "$backup_path" ]]; then
        print_error "Backup not found: $backup_path"
        return 1
    fi

    local backup_name=$(basename "$backup_path")
    print_info "Restoring from: ${backup_name}"

    # Create a backup of current state before restore
    auto_backup "before-restore"

    # Stop running containers from compose files that will be restored
    local restored_files=()
    for file in "${backup_path}"/docker-compose*.yml; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local target="${SCRIPT_DIR}/${filename}"

            # If target exists and docker is available, stop containers
            if [[ -f "$target" ]] && command_exists docker; then
                print_info "Stopping containers from ${filename}..."
                docker compose -f "$target" down 2>/dev/null || true
            fi

            # Restore the file
            cp "$file" "$target"
            restored_files+=("$filename")
            print_success "Restored: ${filename}"
        fi
    done

    # Restore .env file
    if [[ -f "${backup_path}/.env" ]]; then
        cp "${backup_path}/.env" "${SCRIPT_DIR}/.env"
        print_success "Restored: .env"
    fi

    echo ""
    print_success "Restore completed!"
    print_info "Files restored: ${restored_files[*]}"

    return 0
}

#######################################
# Backup & Restore Menu
#######################################
backup_restore_menu() {
    while true; do
        print_header "Backup & Restore"

        echo -e "${CYAN}Options:${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Create Manual Backup"
        echo -e "  ${GREEN}2)${NC} List Backups"
        echo -e "  ${GREEN}3)${NC} Restore from Backup"
        echo -e "  ${GREEN}4)${NC} Delete Old Backups"
        echo ""
        echo -e "  ${RED}0)${NC} Back to Main Menu"
        echo ""

        read -p "Select option: " choice

        case "$choice" in
            1)
                echo ""
                read -p "Backup label (press Enter for 'manual'): " label
                label=${label:-manual}
                label=$(echo "$label" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
                create_backup "$label"
                press_any_key
                ;;
            2)
                echo ""
                list_backups
                press_any_key
                ;;
            3)
                echo ""
                if list_backups; then
                    echo -e "  ${RED}0)${NC} Cancel"
                    echo ""
                    read -p "Select backup to restore: " backup_choice

                    if [[ "$backup_choice" != "0" && "$backup_choice" =~ ^[0-9]+$ ]]; then
                        local idx=$((backup_choice - 1))
                        if [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_BACKUPS[@]} ]]; then
                            local selected_backup="${AVAILABLE_BACKUPS[$idx]}"
                            echo ""
                            print_warning "This will replace current compose files and .env"
                            if confirm "Proceed with restore?" "N"; then
                                restore_backup "$selected_backup"
                            fi
                        else
                            print_error "Invalid selection"
                        fi
                    fi
                fi
                press_any_key
                ;;
            4)
                echo ""
                if list_backups; then
                    echo ""
                    echo -e "${YELLOW}Select backups to delete (comma-separated), or 'old' to delete auto-backups older than 7 days:${NC}"
                    echo -e "  ${RED}0)${NC} Cancel"
                    echo ""
                    read -p "Selection: " del_choice

                    if [[ "$del_choice" == "old" ]]; then
                        local deleted=0
                        local cutoff=$(date -d '7 days ago' +%Y%m%d 2>/dev/null || date -v-7d +%Y%m%d 2>/dev/null)
                        for backup in "${AVAILABLE_BACKUPS[@]}"; do
                            local backup_name=$(basename "$backup")
                            local backup_date=$(echo "$backup_name" | sed 's/backup_\([0-9]*\)_.*/\1/')
                            if [[ "$backup_date" < "$cutoff" ]] && [[ "$backup_name" == *"auto"* ]]; then
                                rm -rf "$backup"
                                ((deleted++))
                            fi
                        done
                        print_success "Deleted ${deleted} old auto-backups"
                    elif [[ "$del_choice" != "0" && -n "$del_choice" ]]; then
                        IFS=',' read -ra parts <<< "$del_choice"
                        for part in "${parts[@]}"; do
                            part=$(echo "$part" | tr -d ' ')
                            if [[ "$part" =~ ^[0-9]+$ ]]; then
                                local idx=$((part - 1))
                                if [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_BACKUPS[@]} ]]; then
                                    rm -rf "${AVAILABLE_BACKUPS[$idx]}"
                                    print_success "Deleted: $(basename "${AVAILABLE_BACKUPS[$idx]}")"
                                fi
                            fi
                        done
                    fi
                fi
                press_any_key
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Legacy function for compatibility
backup_config() {
    backup_restore_menu
}
