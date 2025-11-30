#!/bin/bash

#######################################
# Docker Services Manager
# Interactive script for Ubuntu/CentOS
# Version: 2.0.0
#######################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
LIB_DIR="${SCRIPT_DIR}/lib"
ENV_FILE="${SCRIPT_DIR}/.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# Legacy paths (for compatibility)
CONFIG_DIR="${SCRIPT_DIR}/config"
DATA_DIR="${SCRIPT_DIR}/data"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Source library files
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/server_setup.sh"
source "${LIB_DIR}/services.sh"
source "${LIB_DIR}/templates.sh"
source "${LIB_DIR}/credentials.sh"
source "${LIB_DIR}/container_settings.sh"
source "${LIB_DIR}/maintenance.sh"
source "${LIB_DIR}/telegraf.sh"

#######################################
# Display main menu
#######################################
show_main_menu() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           Docker Services Manager v2.0.0                   ║"
    echo "║           Ubuntu/CentOS/Rocky/Alma Server Setup            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Show current configuration if exists
    if [[ -f "$ENV_FILE" ]]; then
        local docker_root=$(get_env_var "DOCKER_ROOT")
        local network=$(get_env_var "DOCKER_NETWORK")
        if [[ -n "$docker_root" ]]; then
            echo -e "${CYAN}Current Config:${NC} ${GREEN}${docker_root}${NC} | Network: ${GREEN}${network:-docker-services}${NC}"
            echo ""
        fi
    fi

    echo -e "${CYAN}Please select an option:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Setup Server       - Install Docker & dependencies"
    echo -e "  ${GREEN}2)${NC} Add Services       - Deploy new containers"
    echo -e "  ${GREEN}3)${NC} Remove Services    - Stop/remove containers"
    echo -e "  ${GREEN}4)${NC} Define Template    - Create new service templates"
    echo -e "  ${GREEN}5)${NC} View Status        - Show running services"
    echo -e "  ${GREEN}6)${NC} Backup & Restore   - Version control & rollback"
    echo -e "  ${GREEN}7)${NC} Configure          - Initial setup / change settings"
    echo -e "  ${GREEN}8)${NC} Credentials        - Manage DB/MQTT users & passwords"
    echo -e "  ${GREEN}9)${NC} Container Settings - Devices, memory, CPU limits"
    echo -e "  ${GREEN}10)${NC} Device Config     - Serial/RS485 settings (mbusd, ser2net)"
    echo -e "  ${GREEN}11)${NC} Maintenance       - Logs, shell, ports, updates, export"
    echo -e "  ${GREEN}12)${NC} Telegraf Config   - Configure metrics collection modes"
    echo ""
    echo -e "  ${RED}0)${NC} Exit"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#######################################
# Check first run and offer setup
#######################################
check_first_run() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${CYAN}"
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║                   Welcome to Docker Manager!               ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
        echo -e "${YELLOW}This appears to be your first run.${NC}"
        echo -e "Let's configure your Docker environment."
        echo ""

        if confirm "Run initial setup now?" "Y"; then
            run_initial_setup
        fi
    fi
}

#######################################
# Main function
#######################################
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Warning: Some operations require root privileges.${NC}"
        echo -e "${YELLOW}Consider running with sudo for full functionality.${NC}"
        echo ""
        sleep 2
    fi

    # Create necessary directories
    mkdir -p "${TEMPLATES_DIR}"

    # Check for first run
    check_first_run

    while true; do
        show_main_menu
        read -p "Enter your choice [0-12]: " choice

        case $choice in
            1)
                setup_server_menu
                ;;
            2)
                add_services_menu
                ;;
            3)
                remove_services_menu
                ;;
            4)
                define_template_menu
                ;;
            5)
                view_status
                ;;
            6)
                backup_config
                ;;
            7)
                run_initial_setup
                ;;
            8)
                credentials_menu
                ;;
            9)
                container_settings_menu
                ;;
            10)
                device_config_menu
                ;;
            11)
                maintenance_menu
                ;;
            12)
                configure_telegraf_menu
                ;;
            0)
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run main function
main "$@"
