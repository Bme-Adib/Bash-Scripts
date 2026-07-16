#!/bin/bash
# --- Robust Safety & Error Handling ---
set -euo pipefail

# --- Redirect stdin to tty if piped and /dev/tty is available ---
if [ ! -t 0 ] && [ -c /dev/tty ]; then
    exec 0</dev/tty
fi

# --- Color Codes for UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Styled Log Helpers ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Exclusive Lock to Prevent Parallel Runs ---
LOCKFILE="/tmp/$(whoami)-$(basename "$0").lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    log_error "Another instance of this script is already running."
    exit 1
fi

# --- Global Spinner PID variable ---
SPINNER_PID=""

# --- Cleanup Trap ---
cleanup() {
    # Terminate background spinner if running
    if [ -n "${SPINNER_PID:-}" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    # Restore cursor
    tput cnorm 2>/dev/null || echo -ne "\033[?25h"
    # Release flock and remove lockfile
    flock -u 9 2>/dev/null || true
    rm -f "$LOCKFILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- Spinner Helper Function ---
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    if [ -t 1 ]; then
        tput civis 2>/dev/null || echo -ne "\033[?25l"
        while kill -0 "$pid" 2>/dev/null; do
            local temp=${spinstr#?}
            printf " [%c]  " "$spinstr"
            spinstr=$temp${spinstr%"$temp"}
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
        printf "      \b\b\b\b\b\b"
        tput cnorm 2>/dev/null || echo -ne "\033[?25h"
    else
        wait "$pid"
    fi
}

run_with_spinner() {
    local msg="$1"
    shift
    log_info "$msg"
    
    local log_file
    log_file=$(mktemp)
    "$@" > "$log_file" 2>&1 &
    local pid=$!
    
    SPINNER_PID=$pid
    show_spinner "$pid"
    wait "$pid"
    local exit_code=$?
    SPINNER_PID=""
    
    if [ $exit_code -ne 0 ]; then
        log_error "Command failed: $*"
        cat "$log_file" >&2
        rm -f "$log_file"
        return $exit_code
    fi
    rm -f "$log_file"
    return 0
}

# --- Box Drawing Helper Function ---
draw_box() {
    local title="$1"
    shift
    local lines=("$@")
    local max_len=0
    
    # Calculate max length of lines
    for line in "${lines[@]}"; do
        local clean_line
        clean_line=$(echo -e "$line" | sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
        if [ ${#clean_line} -gt $max_len ]; then
            max_len=${#clean_line}
        fi
    done
    
    local title_clean=""
    if [ -n "$title" ]; then
        title_clean=$(echo -e "$title" | sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
        if [ ${#title_clean} -gt $max_len ]; then
            max_len=${#title_clean}
        fi
    fi
    
    local width=$((max_len + 4))
    
    # Top border
    printf "${GREEN}+"
    for ((i=0; i<width-2; i++)); do printf "-"; done
    printf "+${NC}\n"
    
    # Title if present
    if [ -n "$title" ]; then
        local pad_total=$((width - 2 - ${#title_clean}))
        local pad_left=$((pad_total / 2))
        local pad_right=$((pad_total - pad_left))
        printf "${GREEN}|"
        for ((i=0; i<pad_left; i++)); do printf " "; done
        printf "${BLUE}%b${NC}" "$title"
        for ((i=0; i<pad_right; i++)); do printf " "; done
        printf "${GREEN}|${NC}\n"
        
        printf "${GREEN}+"
        for ((i=0; i<width-2; i++)); do printf "-"; done
        printf "+${NC}\n"
    fi
    
    # Content lines
    for line in "${lines[@]}"; do
        local clean_line
        clean_line=$(echo -e "$line" | sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
        local pad=$((max_len - ${#clean_line}))
        printf "${GREEN}| ${NC}%b" "$line"
        for ((i=0; i<pad; i++)); do printf " "; done
        printf " ${GREEN}|${NC}\n"
    done
    
    # Bottom border
    printf "${GREEN}+"
    for ((i=0; i<width-2; i++)); do printf "-"; done
    printf "+${NC}\n"
}

# --- Network Interface & IP Auto-Detection ---
detect_default_interface() {
    local iface=""
    if command -v ip >/dev/null 2>&1; then
        iface=$(ip route show | grep default | awk '{print $5}' | head -n 1)
    fi
    if [ -z "$iface" ] && command -v route >/dev/null 2>&1; then
        iface=$(route -n | grep '^0.0.0.0' | awk '{print $8}' | head -n 1)
    fi
    echo "${iface:-eth0}"
}

detect_ip() {
    local iface
    iface=$(detect_default_interface)
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -o -4 addr show dev "$iface" | awk '{split($4,a,"/"); print a[1]}' | head -n 1)
    fi
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig "$iface" 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | head -n 1)
    fi
    echo "${ip:-127.0.0.1}"
}

# --- Validation Helpers ---
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number: '$port'. Must be between 1 and 65535."
        return 1
    fi
    if command -v ss &>/dev/null && ss -tln | grep -q ":${port} "; then
        log_warning "Port $port appears to be already in use on your host system!"
    fi
    return 0
}

# --- Health Check Validation Loop ---
validate_health() {
    local container_name="$1"
    local port="${2:-}"
    local max_attempts=30
    local attempt=1
    
    log_info "Verifying health of container '${container_name}'..."
    
    while [ $attempt -le $max_attempts ]; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not_found")
        
        if [ "$status" != "running" ]; then
            log_warning "Container '${container_name}' is in status: $status (Attempt $attempt/$max_attempts)"
        else
            local health
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || echo "none")
            
            if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
                if [ -n "$port" ] && [ "$port" != "N/A" ] && command -v curl >/dev/null 2>&1; then
                    if curl -sSf "http://localhost:${port}" >/dev/null 2>&1 || curl -sSf -k "https://localhost:${port}" >/dev/null 2>&1 || [ $attempt -gt 5 ]; then
                        log_success "Container '${container_name}' is running and accessible on port $port!"
                        return 0
                    else
                        log_warning "Container is running, but port $port is not yet responding (Attempt $attempt/$max_attempts)"
                    fi
                else
                    log_success "Container '${container_name}' is running!"
                    return 0
                fi
            elif [ "$health" = "unhealthy" ]; then
                log_error "Container '${container_name}' health check reports UNHEALTHY."
                return 1
            else
                log_info "Container '${container_name}' is running, health check status: $health (Attempt $attempt/$max_attempts)"
            fi
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "Container '${container_name}' failed to reach healthy state within timeout."
    return 1
}

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Flame Dashboard Auto-Setup ===${NC}\n"

# --- Usage instructions ---
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -p PASSWORD      Flame Dashboard settings edit password (default: random 16-char string)
  -i INTEGRATION   Enable Docker integration (y/n, default: y)
  -e PORT          Expose Flame port to host system (default: N/A, do not expose)
  -n NETWORK       External docker network name to connect to (default: proxy-net)
  -u URL           External URL for accessing Flame (required if using external network in non-interactive mode)
  -d DIR           Target deployment directory (default: ./flame-deployment)
  -y               Auto-confirm and run non-interactively
  -h               Show this help message
EOF
}

# --- Parse Arguments ---
PASSWORD=""
DOCKER_INT=""
HOST_PORT=""
CLOUDFLARE_NET=""
FLAME_URL=""
TARGET_DIR=""
AUTO_CONFIRM=false

while getopts "p:i:e:n:u:d:yh" opt; do
    case "$opt" in
        p) PASSWORD="$OPTARG" ;;
        i) DOCKER_INT="$OPTARG" ;;
        e) HOST_PORT="$OPTARG" ;;
        n) CLOUDFLARE_NET="$OPTARG" ;;
        u) FLAME_URL="$OPTARG" ;;
        d) TARGET_DIR="$OPTARG" ;;
        y) AUTO_CONFIRM=true ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Resolve defaults for directory
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(pwd)/flame-deployment"
else
    mkdir -p "$TARGET_DIR"
    TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
fi

# 1. System Dependency Checks
log_info "Verifying system requirements..."

if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed on this system. Please install Docker first."
    exit 1
fi

DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    log_error "Docker Compose is required but not installed."
    exit 1
fi
log_success "Docker & Docker Compose detected."

# 2. Gather Configuration Settings
if [ -z "$PASSWORD" ]; then
    # Try to read defaults if .env exists
    EXISTING_PASSWORD=""
    if [ -f "${TARGET_DIR}/.env" ]; then
        EXISTING_PASSWORD=$(grep -E "^PASSWORD=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
    fi
    RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "flame_secure_pass")
    PASSWORD_SUGGESTION=${EXISTING_PASSWORD:-$RANDOM_PASS}
    
    if [ "$AUTO_CONFIRM" = true ]; then
        PASSWORD=$PASSWORD_SUGGESTION
    else
        echo -e "\n${BLUE}>>> Step 1: General Dashboard Settings${NC}"
        read -rp "Enter Flame Dashboard settings edit password [$PASSWORD_SUGGESTION]: " INPUT_PASS
        PASSWORD=${INPUT_PASS:-$PASSWORD_SUGGESTION}
    fi
fi

if [ -z "$DOCKER_INT" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        DOCKER_INT="y"
    else
        read -rp "Enable Docker Integration (allows Flame to discover running containers)? (y/n) [y]: " INPUT_INT
        DOCKER_INT=${INPUT_INT:-y}
    fi
fi

DOCKER_SOCKET_VOLUME_BLOCK=""
if [[ "$DOCKER_INT" =~ ^[Yy]$ ]]; then
    DOCKER_SOCKET_VOLUME_BLOCK="- /var/run/docker.sock:/var/run/docker.sock"
fi

if [ -z "$HOST_PORT" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        HOST_PORT="N/A"
    else
        echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"
        read -rp "Expose Flame port (5005) to the host system? (y/n) [n]: " EXPOSE_PORT
        EXPOSE_PORT=${EXPOSE_PORT:-n}
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
            while true; do
                read -rp "Enter host port for Flame [5005]: " INPUT_PORT
                INPUT_PORT=${INPUT_PORT:-5005}
                if validate_port "$INPUT_PORT"; then
                    HOST_PORT="$INPUT_PORT"
                    break
                fi
            done
        else
            HOST_PORT="N/A"
        fi
    fi
else
    if [ "$HOST_PORT" != "N/A" ]; then
        validate_port "$HOST_PORT" || exit 1
    fi
fi

# Network / Cloudflare Setup
USE_EXT_NET_PROMPT=""
if [ "$AUTO_CONFIRM" = false ] && [ -z "$CLOUDFLARE_NET" ]; then
    echo -e "\n${BLUE}>>> Step 3: Network & Cloudflare Settings${NC}"
    read -rp "Do you want to connect to an external Docker network (e.g. Cloudflare proxy-net)? (y/n) [y]: " USE_EXT_NET_PROMPT
    USE_EXT_NET_PROMPT=${USE_EXT_NET_PROMPT:-y}
fi

if [[ "$USE_EXT_NET_PROMPT" =~ ^[Yy]$ ]] || [ -n "$CLOUDFLARE_NET" ]; then
    if [ -z "$CLOUDFLARE_NET" ]; then
        log_info "Detecting active Docker networks on host..."
        if docker network ls >/dev/null 2>&1; then
            echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
            docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
            echo ""
        fi
        read -rp "Enter the name of your external docker network [proxy-net]: " INPUT_NET
        CLOUDFLARE_NET=${INPUT_NET:-proxy-net}
    fi
    
    # Check and prompt to create network if missing
    if ! docker network inspect "$CLOUDFLARE_NET" >/dev/null 2>&1; then
        log_warning "Docker network '${CLOUDFLARE_NET}' does not exist."
        create_net="y"
        if [ "$AUTO_CONFIRM" = false ]; then
            read -rp "Would you like to create the '${CLOUDFLARE_NET}' network now? (y/n) [y]: " CREATE_NET
            create_net=${CREATE_NET:-y}
        fi
        if [[ "$create_net" =~ ^[Yy]$ ]]; then
            docker network create "$CLOUDFLARE_NET"
            log_success "Created external docker network: ${CLOUDFLARE_NET}"
        else
            log_warning "Skipping network creation. Docker compose may fail if it is missing."
        fi
    fi
    
    if [ -z "$FLAME_URL" ]; then
        if [ "$AUTO_CONFIRM" = true ]; then
            log_error "External URL (-u) is required in non-interactive mode when connecting to an external network."
            exit 1
        fi
        read -rp "Enter the external URL where you will access Flame (e.g. https://homepage.example.com): " CUSTOM_URL
        while [ -z "$CUSTOM_URL" ]; do
            log_error "External URL cannot be empty."
            read -rp "Enter the external URL: " CUSTOM_URL
        done
        FLAME_URL="$CUSTOM_URL"
    fi
else
    CLOUDFLARE_NET=""
    if [ -z "$FLAME_URL" ]; then
        if [ "$HOST_PORT" != "N/A" ]; then
            FLAME_URL="http://localhost:${HOST_PORT}"
        else
            FLAME_URL="http://localhost:5005"
        fi
    fi
fi

# 3. Setup Deployment Directory
log_info "Creating deployment directory at: ${TARGET_DIR}"

if [ -d "$TARGET_DIR" ]; then
    log_warning "Directory ${TARGET_DIR} already exists."
    overwrite="n"
    if [ "$AUTO_CONFIRM" = true ]; then
        overwrite="y"
    else
        read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE_DIR
        overwrite=${OVERWRITE_DIR:-n}
    fi
    
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        log_info "Removing existing folder..."
        rm -rf "$TARGET_DIR"
    else
        log_error "Setup cancelled to protect existing folder."
        exit 1
    fi
fi

mkdir -p "$TARGET_DIR"

# Write .env file
cat <<EOF > "${TARGET_DIR}/.env"
PASSWORD=${PASSWORD}
EOF
log_success "Created env config: ${TARGET_DIR}/.env"

# Compose Network Configurations
NETWORKS_BLOCK="networks:
  flame-net:
    driver: bridge"

SERVICE_NETWORKS="    networks:
      - flame-net"

if [ -n "$CLOUDFLARE_NET" ]; then
    NETWORKS_BLOCK="networks:
  flame-net:
    driver: bridge
  ${CLOUDFLARE_NET}:
    external: true"

    SERVICE_NETWORKS="    networks:
      - flame-net
      - ${CLOUDFLARE_NET}"
fi

# Write docker-compose.yml
PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 5005:5005"
if [ "$HOST_PORT" != "N/A" ]; then
    PORT_MAPPING_BLOCK="ports:
      - ${HOST_PORT}:5005"
fi

cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  flame:
    image: pawelmalak/flame:latest
    container_name: flame
    restart: unless-stopped
    environment:
      PASSWORD: \${PASSWORD}
    volumes:
      - flame-data:/app/data
      ${DOCKER_SOCKET_VOLUME_BLOCK}
    ${PORT_MAPPING_BLOCK}
${SERVICE_NETWORKS}

volumes:
  flame-data:

${NETWORKS_BLOCK}
EOF
log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 4. Review Compose file configuration
if [ "$AUTO_CONFIRM" = false ]; then
    echo -e "\n${BLUE}>>> Step 4: Review Configuration${NC}"
    echo -e "${GREEN}============================================================${NC}"
    cat "${TARGET_DIR}/docker-compose.yml"
    echo -e "${GREEN}============================================================${NC}"
fi

deploy="y"
if [ "$AUTO_CONFIRM" = false ]; then
    read -rp "Deploy the Flame dashboard container now? (y/n) [y]: " DEPLOY_CONFIRM
    deploy=${DEPLOY_CONFIRM:-y}
fi

if [[ "$deploy" =~ ^[Yy]$ ]]; then
    pushd "$TARGET_DIR" >/dev/null
    run_with_spinner "Pulling Docker images..." $DOCKER_COMPOSE_CMD pull
    run_with_spinner "Deploying Flame container..." $DOCKER_COMPOSE_CMD up -d
    popd >/dev/null
    
    if validate_health "flame" "$HOST_PORT"; then
        log_success "Services are running!"
    else
        log_error "Flame container failed health checks."
        exit 1
    fi
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
ip_addr=$(detect_ip)
default_iface=$(detect_default_interface)

local_access="Not Exposed to Host"
if [ "$HOST_PORT" != "N/A" ]; then
    local_access="http://${ip_addr}:${HOST_PORT} (or http://localhost:${HOST_PORT})"
fi

summary_lines=(
    "Deployment Folder:  ${TARGET_DIR}"
    "Dashboard Password: ${PASSWORD}"
    "Docker Integration: ${DOCKER_INT}"
    "Docker Network:     ${CLOUDFLARE_NET:-flame-net (internal)}"
    "Default Interface:  ${default_iface} (${ip_addr})"
    "Local Access:       ${local_access}"
    "Flame URL:          ${FLAME_URL}"
)

echo ""
draw_box "Flame Dashboard Deployment Summary" "${summary_lines[@]}"

if [ -n "$CLOUDFLARE_NET" ]; then
    DOMAIN_NAME=$(echo "$FLAME_URL" | sed -E 's|https?://||' | sed -E 's|/.*||')
    echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
    echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
    echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
    echo -e "  2. Edit the active Tunnel servicing this network."
    echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
    echo -e "     - Subdomain/Domain: ${GREEN}${DOMAIN_NAME}${NC}"
    echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
    echo -e "     - URL:              ${YELLOW}http://flame:5005${NC} (Internal Docker DNS)"
    echo -e "  4. Save Hostname. Cloudflare will route traffic securely."
fi

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
