#!/bin/bash
#
# pv-stack.sh - Management script for pv-stack Docker services
#

set -e

# Configuration
COMPOSE_FILE="docker-compose.pv-stack.yml"
PROJECT_NAME="docker-setup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Change to script directory
cd "$SCRIPT_DIR"

# Check if compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}Error: $COMPOSE_FILE not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Helper function for docker compose commands
dc() {
    docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

# Get list of services from compose file
get_services() {
    dc config --services 2>/dev/null | sort
}

# Validate service name
validate_service() {
    local service="$1"
    if [[ -z "$service" ]]; then
        echo -e "${RED}Error: Service name required${NC}"
        echo "Available services:"
        get_services | sed 's/^/  - /'
        exit 1
    fi

    if ! get_services | grep -q "^${service}$"; then
        echo -e "${RED}Error: Unknown service '$service'${NC}"
        echo "Available services:"
        get_services | sed 's/^/  - /'
        exit 1
    fi
}

# Commands
cmd_restart() {
    local service="$1"
    validate_service "$service"
    echo -e "${BLUE}Restarting $service...${NC}"
    dc restart "$service"
    echo -e "${GREEN}Done.${NC}"
}

cmd_recreate() {
    local service="$1"
    validate_service "$service"
    echo -e "${YELLOW}Recreating $service (this will apply device/port/volume changes)...${NC}"
    dc up -d "$service" --force-recreate
    echo -e "${GREEN}Done.${NC}"
}

cmd_logs() {
    local service="$1"
    local lines="${2:-50}"
    validate_service "$service"
    dc logs -f --tail "$lines" "$service"
}

cmd_status() {
    echo -e "${BLUE}PV-Stack Service Status${NC}"
    echo "========================"
    dc ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
}

cmd_list() {
    echo -e "${BLUE}Available services:${NC}"
    get_services | sed 's/^/  - /'
}

cmd_up() {
    local service="$1"
    if [[ -n "$service" ]]; then
        validate_service "$service"
        echo -e "${GREEN}Starting $service...${NC}"
        dc up -d "$service"
    else
        echo -e "${GREEN}Starting all services...${NC}"
        dc up -d
    fi
    echo -e "${GREEN}Done.${NC}"
}

cmd_down() {
    local service="$1"
    if [[ -n "$service" ]]; then
        validate_service "$service"
        echo -e "${YELLOW}Stopping $service...${NC}"
        dc stop "$service"
    else
        echo -e "${YELLOW}Stopping all services...${NC}"
        dc down
    fi
    echo -e "${GREEN}Done.${NC}"
}

cmd_pull() {
    local service="$1"
    if [[ -n "$service" ]]; then
        validate_service "$service"
        echo -e "${BLUE}Pulling latest image for $service...${NC}"
        dc pull "$service"
    else
        echo -e "${BLUE}Pulling latest images for all services...${NC}"
        dc pull
    fi
    echo -e "${GREEN}Done.${NC}"
}

# Usage
usage() {
    cat << EOF
${BLUE}pv-stack.sh${NC} - Management script for pv-stack Docker services

${YELLOW}Usage:${NC}
  ./pv-stack.sh <command> [service] [options]

${YELLOW}Commands:${NC}
  ${GREEN}restart${NC} <service>     Restart a service (for environment variable changes)
  ${GREEN}recreate${NC} <service>    Recreate a service (for device/port/volume changes)
  ${GREEN}logs${NC} <service> [n]    Show logs (last n lines, default 50, follows)
  ${GREEN}status${NC}                Show status of all services
  ${GREEN}list${NC}                  List available services
  ${GREEN}up${NC} [service]          Start service(s)
  ${GREEN}down${NC} [service]        Stop service(s)
  ${GREEN}pull${NC} [service]        Pull latest image(s)

${YELLOW}When to use restart vs recreate:${NC}
  ${BLUE}restart${NC}  - Environment variables (MQTT_SERVER, LOG_LEVEL, etc.)
  ${BLUE}recreate${NC} - Devices, ports, volumes, image changes

${YELLOW}Examples:${NC}
  ./pv-stack.sh restart seplos-modbus-mqtt
  ./pv-stack.sh recreate seplos-modbus-mqtt
  ./pv-stack.sh logs grafana 100
  ./pv-stack.sh status

EOF
}

# Main
case "${1:-}" in
    restart)
        cmd_restart "$2"
        ;;
    recreate)
        cmd_recreate "$2"
        ;;
    logs)
        cmd_logs "$2" "$3"
        ;;
    status)
        cmd_status
        ;;
    list)
        cmd_list
        ;;
    up)
        cmd_up "$2"
        ;;
    down)
        cmd_down "$2"
        ;;
    pull)
        cmd_pull "$2"
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        usage
        exit 1
        ;;
esac
