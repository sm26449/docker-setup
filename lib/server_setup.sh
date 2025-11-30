#!/bin/bash

#######################################
# Server Setup Functions
# Supports: Ubuntu, Debian, CentOS, Rocky, Alma, Fedora
#######################################

#######################################
# Display server setup menu
#######################################
setup_server_menu() {
    print_header "Server Setup"

    local os=$(detect_os)
    local os_version=$(get_os_version)

    echo -e "${CYAN}Detected OS:${NC} ${BOLD}${os} ${os_version}${NC}"
    echo ""

    # Check current status
    echo -e "${CYAN}Current Status:${NC}"
    if command_exists docker; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        print_success "Docker installed (v${docker_version})"
    else
        print_warning "Docker not installed"
    fi

    if command_exists docker-compose || docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+')
        print_success "Docker Compose installed (${compose_version})"
    else
        print_warning "Docker Compose not installed"
    fi

    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Full Setup - Install Docker + Docker Compose + Dependencies"
    echo -e "  ${GREEN}2)${NC} Install Docker Only"
    echo -e "  ${GREEN}3)${NC} Install Docker Compose Only"
    echo -e "  ${GREEN}4)${NC} Install Additional Tools (htop, curl, git, etc.)"
    echo -e "  ${GREEN}5)${NC} Configure Firewall for Docker"
    echo -e "  ${GREEN}6)${NC} Add Current User to Docker Group"
    echo -e "  ${GREEN}7)${NC} System Tuning (sysctl, swap, log rotation)"
    echo ""
    echo -e "  ${RED}0)${NC} Back to Main Menu"
    echo ""

    read -p "Enter your choice [0-7]: " choice

    case $choice in
        1)
            full_server_setup
            ;;
        2)
            install_docker
            ;;
        3)
            install_docker_compose
            ;;
        4)
            install_additional_tools
            ;;
        5)
            configure_firewall
            ;;
        6)
            add_user_to_docker_group
            ;;
        7)
            system_tuning_menu
            ;;
        0)
            return
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            setup_server_menu
            ;;
    esac
}

#######################################
# Full server setup
#######################################
full_server_setup() {
    print_header "Full Server Setup"

    local os=$(detect_os)

    if [[ "$os" == "unknown" ]]; then
        print_error "Unsupported operating system"
        press_any_key
        return 1
    fi

    print_info "Starting full setup for ${os}..."
    echo ""

    # Update system
    update_system

    # Install dependencies
    install_dependencies

    # Install Docker
    install_docker

    # Install Docker Compose
    install_docker_compose

    # Install additional tools
    install_additional_tools

    # Add user to docker group
    add_user_to_docker_group

    echo ""
    print_success "Full setup completed!"
    print_info "Please log out and back in for docker group changes to take effect"

    press_any_key
}

#######################################
# Update system packages
#######################################
update_system() {
    print_info "Updating system packages..."

    local os=$(detect_os)

    case $os in
        ubuntu|debian)
            apt-get update -y
            apt-get upgrade -y
            ;;
        centos|rocky|alma)
            yum update -y || dnf update -y
            ;;
        fedora)
            dnf update -y
            ;;
    esac

    print_success "System updated"
}

#######################################
# Install dependencies
#######################################
install_dependencies() {
    print_info "Installing dependencies..."

    local os=$(detect_os)

    case $os in
        ubuntu|debian)
            apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg \
                lsb-release \
                software-properties-common
            ;;
        centos|rocky|alma)
            yum install -y \
                yum-utils \
                device-mapper-persistent-data \
                lvm2 \
                curl \
                ca-certificates || \
            dnf install -y \
                dnf-plugins-core \
                device-mapper-persistent-data \
                lvm2 \
                curl \
                ca-certificates
            ;;
        fedora)
            dnf install -y \
                dnf-plugins-core \
                curl \
                ca-certificates
            ;;
    esac

    print_success "Dependencies installed"
}

#######################################
# Install Docker
#######################################
install_docker() {
    print_header "Installing Docker"

    if command_exists docker; then
        print_warning "Docker is already installed"
        if ! confirm "Do you want to reinstall?"; then
            return 0
        fi
    fi

    local os=$(detect_os)

    print_info "Installing Docker for ${os}..."

    case $os in
        ubuntu)
            install_docker_ubuntu
            ;;
        debian)
            install_docker_debian
            ;;
        centos)
            install_docker_centos
            ;;
        rocky|alma)
            install_docker_rhel
            ;;
        fedora)
            install_docker_fedora
            ;;
        *)
            print_error "Unsupported OS: ${os}"
            return 1
            ;;
    esac

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    # Verify installation
    if command_exists docker; then
        local docker_version=$(docker --version)
        print_success "Docker installed successfully: ${docker_version}"
    else
        print_error "Docker installation failed"
        return 1
    fi

    press_any_key
}

#######################################
# Install Docker on Ubuntu
#######################################
install_docker_ubuntu() {
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#######################################
# Install Docker on Debian
#######################################
install_docker_debian() {
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#######################################
# Install Docker on CentOS
#######################################
install_docker_centos() {
    # Remove old versions
    yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#######################################
# Install Docker on Rocky/Alma Linux
#######################################
install_docker_rhel() {
    # Remove old versions
    dnf remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # Add Docker repository
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#######################################
# Install Docker on Fedora
#######################################
install_docker_fedora() {
    # Remove old versions
    dnf remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine \
        docker-selinux docker-engine-selinux 2>/dev/null || true

    # Add Docker repository
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # Install Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#######################################
# Install Docker Compose
#######################################
install_docker_compose() {
    print_header "Installing Docker Compose"

    # Check if already installed via plugin
    if docker compose version &>/dev/null; then
        print_success "Docker Compose plugin is already installed"
        docker compose version
        press_any_key
        return 0
    fi

    # Check standalone docker-compose
    if command_exists docker-compose; then
        print_warning "Standalone docker-compose is installed"
        if confirm "Upgrade to Docker Compose V2 plugin?"; then
            rm -f /usr/local/bin/docker-compose 2>/dev/null || true
        else
            press_any_key
            return 0
        fi
    fi

    print_info "Installing Docker Compose V2..."

    # Install as Docker plugin
    local os=$(detect_os)

    case $os in
        ubuntu|debian)
            apt-get update
            apt-get install -y docker-compose-plugin
            ;;
        centos|rocky|alma|fedora)
            dnf install -y docker-compose-plugin 2>/dev/null || \
            yum install -y docker-compose-plugin
            ;;
    esac

    # Verify installation
    if docker compose version &>/dev/null; then
        print_success "Docker Compose installed successfully"
        docker compose version
    else
        # Fallback: Install standalone binary
        print_warning "Plugin installation failed, installing standalone binary..."
        local compose_version="v2.24.0"
        curl -SL "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

        if command_exists docker-compose; then
            print_success "Docker Compose standalone installed"
            docker-compose --version
        else
            print_error "Docker Compose installation failed"
        fi
    fi

    press_any_key
}

#######################################
# Install additional tools
#######################################
install_additional_tools() {
    print_header "Installing Additional Tools"

    local os=$(detect_os)

    print_info "Installing useful tools..."

    case $os in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                htop \
                iotop \
                iftop \
                ncdu \
                tmux \
                vim \
                nano \
                git \
                wget \
                curl \
                net-tools \
                dnsutils \
                jq \
                unzip \
                tree \
                fail2ban \
                ufw
            ;;
        centos|rocky|alma|fedora)
            dnf install -y \
                htop \
                iotop \
                iftop \
                ncdu \
                tmux \
                vim \
                nano \
                git \
                wget \
                curl \
                net-tools \
                bind-utils \
                jq \
                unzip \
                tree \
                fail2ban \
                firewalld 2>/dev/null || \
            yum install -y \
                htop \
                tmux \
                vim \
                nano \
                git \
                wget \
                curl \
                net-tools \
                bind-utils \
                jq \
                unzip \
                tree
            ;;
    esac

    print_success "Additional tools installed"
    press_any_key
}

#######################################
# Configure firewall
#######################################
configure_firewall() {
    print_header "Configuring Firewall"

    local os=$(detect_os)

    echo -e "${CYAN}Common ports to open:${NC}"
    echo "  80   - HTTP"
    echo "  443  - HTTPS"
    echo "  8080 - Alternative HTTP"
    echo "  9000 - Portainer"
    echo "  3000 - Grafana"
    echo ""

    case $os in
        ubuntu|debian)
            if command_exists ufw; then
                print_info "Configuring UFW..."

                # Enable UFW if not already
                ufw --force enable

                # Allow SSH first!
                ufw allow 22/tcp comment 'SSH'

                # Allow common Docker ports
                if confirm "Allow HTTP (80)?"; then
                    ufw allow 80/tcp comment 'HTTP'
                fi

                if confirm "Allow HTTPS (443)?"; then
                    ufw allow 443/tcp comment 'HTTPS'
                fi

                if confirm "Allow port 8080?"; then
                    ufw allow 8080/tcp comment 'HTTP Alt'
                fi

                # Docker network
                ufw allow from 172.16.0.0/12 comment 'Docker'

                ufw reload
                print_success "UFW configured"
                ufw status
            else
                print_error "UFW not installed"
            fi
            ;;
        centos|rocky|alma|fedora)
            if command_exists firewall-cmd; then
                print_info "Configuring firewalld..."

                systemctl start firewalld
                systemctl enable firewalld

                # Allow SSH
                firewall-cmd --permanent --add-service=ssh

                if confirm "Allow HTTP (80)?"; then
                    firewall-cmd --permanent --add-service=http
                fi

                if confirm "Allow HTTPS (443)?"; then
                    firewall-cmd --permanent --add-service=https
                fi

                if confirm "Allow port 8080?"; then
                    firewall-cmd --permanent --add-port=8080/tcp
                fi

                # Docker network
                firewall-cmd --permanent --zone=trusted --add-source=172.16.0.0/12

                firewall-cmd --reload
                print_success "Firewalld configured"
                firewall-cmd --list-all
            else
                print_error "firewalld not installed"
            fi
            ;;
    esac

    press_any_key
}

#######################################
# Add current user to docker group
#######################################
add_user_to_docker_group() {
    print_header "Add User to Docker Group"

    local current_user="${SUDO_USER:-$USER}"

    if [[ "$current_user" == "root" ]]; then
        print_warning "Running as root, no need to add to docker group"
        press_any_key
        return
    fi

    print_info "Adding user '${current_user}' to docker group..."

    # Create docker group if it doesn't exist
    groupadd -f docker

    # Add user to docker group
    usermod -aG docker "$current_user"

    print_success "User '${current_user}' added to docker group"
    print_warning "Please log out and back in for changes to take effect"
    print_info "Or run: newgrp docker"

    press_any_key
}

#######################################
# System Tuning Menu
#######################################
system_tuning_menu() {
    print_header "System Tuning"

    # Show current status
    echo -e "${CYAN}Current Status:${NC}"
    echo ""

    # Check swap
    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    local swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    if [[ "$swap_total" -gt 0 ]]; then
        echo -e "  Swap: ${YELLOW}Enabled${NC} (${swap_used}MB / ${swap_total}MB used)"
    else
        echo -e "  Swap: ${GREEN}Disabled${NC}"
    fi

    # Check sysctl settings
    local ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [[ "$ip_forward" == "1" ]]; then
        echo -e "  IP Forward: ${GREEN}Enabled${NC}"
    else
        echo -e "  IP Forward: ${RED}Disabled${NC}"
    fi

    # Check Docker log driver
    local log_driver=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)
    echo -e "  Docker Log Driver: ${GREEN}${log_driver:-unknown}${NC}"

    # Check if daemon.json exists
    if [[ -f /etc/docker/daemon.json ]]; then
        echo -e "  Docker daemon.json: ${GREEN}Configured${NC}"
    else
        echo -e "  Docker daemon.json: ${YELLOW}Not configured${NC}"
    fi

    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Apply Sysctl Tuning (kernel parameters for containers)"
    echo -e "  ${GREEN}2)${NC} Disable Swap"
    echo -e "  ${GREEN}3)${NC} Enable Swap"
    echo -e "  ${GREEN}4)${NC} Configure Docker Log Rotation"
    echo -e "  ${GREEN}5)${NC} Apply All Optimizations"
    echo -e "  ${GREEN}6)${NC} View Current Sysctl Settings"
    echo ""
    echo -e "  ${RED}0)${NC} Back"
    echo ""

    read -p "Enter your choice [0-6]: " choice

    case $choice in
        1) apply_sysctl_tuning ;;
        2) disable_swap ;;
        3) enable_swap ;;
        4) configure_docker_logging ;;
        5) apply_all_optimizations ;;
        6) view_sysctl_settings ;;
        0) setup_server_menu; return ;;
        *)
            print_error "Invalid option"
            sleep 1
            system_tuning_menu
            ;;
    esac
}

#######################################
# Apply sysctl tuning for containers
#######################################
apply_sysctl_tuning() {
    print_header "Sysctl Tuning for Containers"

    echo -e "${CYAN}This will configure kernel parameters optimized for Docker:${NC}"
    echo ""
    echo "  - Enable IP forwarding"
    echo "  - Increase connection tracking limits"
    echo "  - Optimize network buffer sizes"
    echo "  - Increase file descriptor limits"
    echo "  - Optimize virtual memory"
    echo ""

    if ! confirm "Apply sysctl tuning?"; then
        system_tuning_menu
        return
    fi

    print_info "Creating sysctl configuration..."

    # Create sysctl config for Docker
    cat > /etc/sysctl.d/99-docker-tuning.conf << 'EOF'
# Docker and Container Optimizations
# Generated by Docker Services Manager

# Enable IP forwarding (required for Docker networking)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Connection tracking
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576

# Increase network buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 65536

# TCP optimizations
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1

# Increase file descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Virtual memory tuning
vm.max_map_count = 262144
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# Increase PID limit
kernel.pid_max = 4194304

# ARP cache
net.ipv4.neigh.default.gc_thresh1 = 8192
net.ipv4.neigh.default.gc_thresh2 = 32768
net.ipv4.neigh.default.gc_thresh3 = 65536

# Allow unprivileged users to use user namespaces
kernel.unprivileged_userns_clone = 1
EOF

    # Apply settings
    print_info "Applying sysctl settings..."
    sysctl --system

    if [[ $? -eq 0 ]]; then
        print_success "Sysctl tuning applied successfully"
        echo ""
        echo -e "${YELLOW}Key settings applied:${NC}"
        echo "  net.ipv4.ip_forward = 1"
        echo "  vm.swappiness = 10"
        echo "  fs.file-max = 2097152"
        echo "  vm.max_map_count = 262144"
    else
        print_error "Some settings may have failed to apply"
    fi

    press_any_key
    system_tuning_menu
}

#######################################
# Disable swap
#######################################
disable_swap() {
    print_header "Disable Swap"

    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')

    if [[ "$swap_total" -eq 0 ]]; then
        print_info "Swap is already disabled"
        press_any_key
        system_tuning_menu
        return
    fi

    echo -e "${YELLOW}Warning: Disabling swap can cause out-of-memory issues${NC}"
    echo -e "${YELLOW}if your system runs low on RAM.${NC}"
    echo ""
    echo -e "Current swap: ${GREEN}${swap_total}MB${NC}"
    echo ""

    if ! confirm "Disable swap?"; then
        system_tuning_menu
        return
    fi

    print_info "Disabling swap..."

    # Turn off swap
    swapoff -a

    # Comment out swap entries in fstab
    if [[ -f /etc/fstab ]]; then
        print_info "Updating /etc/fstab..."
        sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
        print_info "Backup saved as /etc/fstab.bak"
    fi

    # Verify
    local swap_after=$(free -m | awk '/^Swap:/ {print $2}')
    if [[ "$swap_after" -eq 0 ]]; then
        print_success "Swap disabled successfully"
    else
        print_warning "Swap may not be fully disabled. Check manually."
    fi

    press_any_key
    system_tuning_menu
}

#######################################
# Enable swap
#######################################
enable_swap() {
    print_header "Enable Swap"

    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')

    if [[ "$swap_total" -gt 0 ]]; then
        print_info "Swap is already enabled (${swap_total}MB)"
        press_any_key
        system_tuning_menu
        return
    fi

    echo -e "${CYAN}Options:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Re-enable from fstab"
    echo -e "  ${GREEN}2)${NC} Create new swap file (2GB)"
    echo -e "  ${GREEN}3)${NC} Create new swap file (4GB)"
    echo -e "  ${GREEN}4)${NC} Create new swap file (custom size)"
    echo ""

    read -p "Choice [1]: " choice

    case $choice in
        1)
            print_info "Enabling swap from fstab..."
            # Uncomment swap lines in fstab
            sed -i 's/^#\(.*\sswap\s\)/\1/' /etc/fstab
            swapon -a
            ;;
        2)
            create_swap_file 2048
            ;;
        3)
            create_swap_file 4096
            ;;
        4)
            read -p "Swap size in MB: " swap_size
            if [[ "$swap_size" =~ ^[0-9]+$ ]] && [[ "$swap_size" -ge 512 ]]; then
                create_swap_file "$swap_size"
            else
                print_error "Invalid size (minimum 512MB)"
            fi
            ;;
        *)
            # Re-enable from fstab
            sed -i 's/^#\(.*\sswap\s\)/\1/' /etc/fstab
            swapon -a
            ;;
    esac

    # Verify
    local swap_after=$(free -m | awk '/^Swap:/ {print $2}')
    if [[ "$swap_after" -gt 0 ]]; then
        print_success "Swap enabled: ${swap_after}MB"
    else
        print_warning "Swap may not be enabled. Check manually."
    fi

    press_any_key
    system_tuning_menu
}

#######################################
# Create swap file
#######################################
create_swap_file() {
    local size_mb=$1
    local swap_file="/swapfile"

    print_info "Creating ${size_mb}MB swap file..."

    # Check if swap file exists
    if [[ -f "$swap_file" ]]; then
        print_warning "Swap file already exists"
        if ! confirm "Remove and recreate?"; then
            return
        fi
        swapoff "$swap_file" 2>/dev/null
        rm -f "$swap_file"
    fi

    # Create swap file
    dd if=/dev/zero of="$swap_file" bs=1M count="$size_mb" status=progress
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    swapon "$swap_file"

    # Add to fstab if not present
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
        print_info "Added to /etc/fstab"
    fi

    print_success "Swap file created and enabled"
}

#######################################
# Configure Docker logging
#######################################
configure_docker_logging() {
    print_header "Configure Docker Log Rotation"

    echo -e "${CYAN}This configures Docker daemon to limit container log sizes.${NC}"
    echo ""
    echo "Recommended settings:"
    echo "  - Max log file size: 10MB"
    echo "  - Max log files: 3"
    echo "  - Total per container: ~30MB"
    echo ""

    local daemon_json="/etc/docker/daemon.json"
    local backup_file="${daemon_json}.bak"

    # Show current config if exists
    if [[ -f "$daemon_json" ]]; then
        echo -e "${CYAN}Current daemon.json:${NC}"
        cat "$daemon_json"
        echo ""
    fi

    if ! confirm "Configure Docker log rotation?"; then
        system_tuning_menu
        return
    fi

    # Backup existing config
    if [[ -f "$daemon_json" ]]; then
        cp "$daemon_json" "$backup_file"
        print_info "Backup saved as $backup_file"
    fi

    # Check if we need to merge with existing config
    if [[ -f "$daemon_json" ]] && command_exists jq; then
        # Merge with existing config
        print_info "Merging with existing configuration..."

        local new_config=$(cat "$daemon_json" | jq '. + {
            "log-driver": "json-file",
            "log-opts": {
                "max-size": "10m",
                "max-file": "3"
            }
        }')

        echo "$new_config" > "$daemon_json"
    else
        # Create new config
        print_info "Creating new configuration..."

        mkdir -p /etc/docker

        cat > "$daemon_json" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "default-address-pools": [
        {
            "base": "172.17.0.0/12",
            "size": 24
        }
    ]
}
EOF
    fi

    print_success "Docker logging configured"
    echo ""
    echo -e "${CYAN}New configuration:${NC}"
    cat "$daemon_json"
    echo ""

    if confirm "Restart Docker now to apply changes?"; then
        print_info "Restarting Docker..."
        systemctl restart docker

        if [[ $? -eq 0 ]]; then
            print_success "Docker restarted successfully"
        else
            print_error "Failed to restart Docker"
            print_info "You may need to fix the configuration and restart manually"
        fi
    else
        print_warning "Remember to restart Docker: systemctl restart docker"
    fi

    press_any_key
    system_tuning_menu
}

#######################################
# Apply all optimizations
#######################################
apply_all_optimizations() {
    print_header "Apply All Optimizations"

    echo -e "${CYAN}This will:${NC}"
    echo "  1. Apply sysctl tuning for containers"
    echo "  2. Configure Docker log rotation"
    echo "  3. Optionally disable swap"
    echo ""

    if ! confirm "Proceed with all optimizations?"; then
        system_tuning_menu
        return
    fi

    echo ""

    # 1. Sysctl tuning
    print_info "Step 1: Applying sysctl tuning..."
    cat > /etc/sysctl.d/99-docker-tuning.conf << 'EOF'
# Docker and Container Optimizations
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_max = 1048576
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
vm.max_map_count = 262144
vm.swappiness = 10
kernel.pid_max = 4194304
EOF
    sysctl --system > /dev/null 2>&1
    print_success "Sysctl tuning applied"

    # 2. Docker logging
    print_info "Step 2: Configuring Docker logging..."
    mkdir -p /etc/docker
    if [[ ! -f /etc/docker/daemon.json ]]; then
        cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF
        print_success "Docker logging configured"
    else
        print_info "Docker daemon.json already exists, skipping"
    fi

    # 3. Swap
    echo ""
    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    if [[ "$swap_total" -gt 0 ]]; then
        echo -e "${YELLOW}Swap is currently enabled (${swap_total}MB)${NC}"
        if confirm "Disable swap? (recommended for container workloads)"; then
            swapoff -a
            sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
            print_success "Swap disabled"
        fi
    else
        print_info "Swap is already disabled"
    fi

    echo ""
    print_success "All optimizations applied!"

    if confirm "Restart Docker now?"; then
        systemctl restart docker
        print_success "Docker restarted"
    else
        print_warning "Remember to restart Docker: systemctl restart docker"
    fi

    press_any_key
    system_tuning_menu
}

#######################################
# View current sysctl settings
#######################################
view_sysctl_settings() {
    print_header "Current Sysctl Settings"

    echo -e "${CYAN}Network settings:${NC}"
    echo "  net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'N/A')"
    echo "  net.ipv4.tcp_tw_reuse = $(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 'N/A')"
    echo "  net.core.rmem_max = $(sysctl -n net.core.rmem_max 2>/dev/null || echo 'N/A')"
    echo "  net.core.wmem_max = $(sysctl -n net.core.wmem_max 2>/dev/null || echo 'N/A')"

    echo ""
    echo -e "${CYAN}File system settings:${NC}"
    echo "  fs.file-max = $(sysctl -n fs.file-max 2>/dev/null || echo 'N/A')"
    echo "  fs.inotify.max_user_watches = $(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 'N/A')"

    echo ""
    echo -e "${CYAN}Virtual memory settings:${NC}"
    echo "  vm.swappiness = $(sysctl -n vm.swappiness 2>/dev/null || echo 'N/A')"
    echo "  vm.max_map_count = $(sysctl -n vm.max_map_count 2>/dev/null || echo 'N/A')"

    echo ""
    echo -e "${CYAN}Kernel settings:${NC}"
    echo "  kernel.pid_max = $(sysctl -n kernel.pid_max 2>/dev/null || echo 'N/A')"

    echo ""
    echo -e "${CYAN}Connection tracking:${NC}"
    local conntrack=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 'N/A')
    echo "  net.netfilter.nf_conntrack_max = $conntrack"

    echo ""
    echo -e "${CYAN}Swap status:${NC}"
    free -h | grep -E "^(Mem|Swap):"

    echo ""
    echo -e "${CYAN}Docker daemon.json:${NC}"
    if [[ -f /etc/docker/daemon.json ]]; then
        cat /etc/docker/daemon.json
    else
        echo "  (not configured)"
    fi

    press_any_key
    system_tuning_menu
}
