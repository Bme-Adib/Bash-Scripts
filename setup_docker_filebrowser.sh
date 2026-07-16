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
echo -e "${BLUE}=== FileBrowser Quantum Container Auto-Setup ===${NC}\n"

# --- Usage instructions ---
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -e PORT          Expose FileBrowser port to host system (default: N/A, do not expose)
  -s SUBDOMAIN     Subdomain for access (required in non-interactive mode)
  -n NETWORK       Cloudflare external docker network (default: proxy-net)
  -p PASSWORD      Initial admin password (required in non-interactive mode)
  -d DIR           Target deployment directory (default: ./filebrowserContainer)
  -y               Auto-confirm and run non-interactively
  -h               Show this help message
EOF
}

# --- Parse Arguments ---
HOST_PORT=""
SUBDOMAIN=""
CLOUDFLARE_NET=""
ADMIN_PASS=""
TARGET_DIR=""
AUTO_CONFIRM=false

while getopts "e:s:n:p:d:yh" opt; do
    case "$opt" in
        e) HOST_PORT="$OPTARG" ;;
        s) SUBDOMAIN="$OPTARG" ;;
        n) CLOUDFLARE_NET="$OPTARG" ;;
        p) ADMIN_PASS="$OPTARG" ;;
        d) TARGET_DIR="$OPTARG" ;;
        y) AUTO_CONFIRM=true ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Resolve default values
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(pwd)/filebrowserContainer"
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
if [ -z "$HOST_PORT" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        HOST_PORT="N/A"
    else
        echo -e "\n${BLUE}>>> Step 1: Configure Port Exposure${NC}"
        read -rp "Would you like to expose the FileBrowser port to the host system? (y/n) [n]: " EXPOSE_PORT
        EXPOSE_PORT=${EXPOSE_PORT:-n}
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
            while true; do
                read -rp "Enter host port to bind FileBrowser to [8081]: " INPUT_PORT
                INPUT_PORT=${INPUT_PORT:-8081}
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

if [ -z "$SUBDOMAIN" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        log_error "Subdomain (-s) is required in non-interactive mode."
        exit 1
    fi
    echo -e "\n${BLUE}>>> Step 2: Configure Cloudflare Subdomain & Network${NC}"
    read -rp "Enter the subdomain they will connect to (e.g. files.example.com): " SUBDOMAIN
    while [ -z "$SUBDOMAIN" ]; do
        log_error "Subdomain cannot be empty."
        read -rp "Enter the subdomain: " SUBDOMAIN
    done
fi

if [ -z "$CLOUDFLARE_NET" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        CLOUDFLARE_NET="proxy-net"
    else
        log_info "Detecting active Docker networks on host..."
        if docker network ls >/dev/null 2>&1; then
            echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
            docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
            echo ""
        fi
        read -rp "Enter the name of your Cloudflare docker network [proxy-net]: " INPUT_NET
        CLOUDFLARE_NET=${INPUT_NET:-proxy-net}
    fi
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

if [ -z "$ADMIN_PASS" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        log_error "Admin password (-p) is required in non-interactive mode."
        exit 1
    fi
    echo -e "\n${BLUE}>>> Step 3: Configure Admin Credentials${NC}"
    read -rsp "Enter the initial password for the admin account: " ADMIN_PASS
    echo ""
    while [ -z "$ADMIN_PASS" ]; do
        log_error "Password cannot be empty."
        read -rsp "Enter the initial password for the admin account: " ADMIN_PASS
        echo ""
    done
fi

# 3. Create Folder and Configuration Files
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

mkdir -p "${TARGET_DIR}/config"
mkdir -p "${TARGET_DIR}/data"

# Write config.yaml
cat <<EOF > "${TARGET_DIR}/config/config.yaml"
server:
  database: /home/filebrowser/data/filebrowser.db
  sources:
    - path: /srv
EOF
log_success "Created: ${TARGET_DIR}/config/config.yaml"

# Write .env file
cat <<EOF > "${TARGET_DIR}/.env"
FILEBROWSER_ADMIN_PASSWORD="${ADMIN_PASS}"
EOF
log_success "Created: ${TARGET_DIR}/.env"

# Write docker-compose.yml
PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 8081:80"
if [ "$HOST_PORT" != "N/A" ]; then
    PORT_MAPPING_BLOCK="ports:
      - ${HOST_PORT}:80"
fi

cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  filebrowser:
    image: gtstef/filebrowser:stable
    container_name: filebrowser
    restart: unless-stopped
    user: root
    ${PORT_MAPPING_BLOCK}
    volumes:
      - /:/srv
      - ./data:/home/filebrowser/data
      - ./config/config.yaml:/home/filebrowser/data/config.yaml
    environment:
      - FILEBROWSER_DATABASE=/home/filebrowser/data/filebrowser.db
      - FILEBROWSER_CONFIG=/home/filebrowser/data/config.yaml
      - FILEBROWSER_ADMIN_PASSWORD=\${FILEBROWSER_ADMIN_PASSWORD}
    networks:
      - ${CLOUDFLARE_NET}

networks:
  ${CLOUDFLARE_NET}:
    external: true
EOF
log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 4. Show Compose file configuration
if [ "$AUTO_CONFIRM" = false ]; then
    echo -e "\n${BLUE}>>> Step 4: Review Configuration${NC}"
    echo -e "${GREEN}============================================================${NC}"
    cat "${TARGET_DIR}/docker-compose.yml"
    echo -e "${GREEN}============================================================${NC}"
fi

deploy="y"
if [ "$AUTO_CONFIRM" = false ]; then
    read -rp "Deploy the FileBrowser Quantum container now? (y/n) [y]: " DEPLOY_CONFIRM
    deploy=${DEPLOY_CONFIRM:-y}
fi

if [[ "$deploy" =~ ^[Yy]$ ]]; then
    pushd "$TARGET_DIR" >/dev/null
    run_with_spinner "Pulling Docker images..." $DOCKER_COMPOSE_CMD pull
    run_with_spinner "Deploying FileBrowser container..." $DOCKER_COMPOSE_CMD up -d
    popd >/dev/null
    
    if validate_health "filebrowser" "$HOST_PORT"; then
        log_success "FileBrowser Quantum is running!"
    else
        log_error "FileBrowser container failed health checks."
        exit 1
    fi
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
ip_addr=$(detect_ip)
default_iface=$(detect_default_interface)

local_access="No ports exposed on host"
if [[ "$HOST_PORT" != "N/A" ]]; then
    local_access="http://${ip_addr}:${HOST_PORT} (or http://localhost:${HOST_PORT})"
fi

summary_lines=(
    "Deployment Folder:  ${TARGET_DIR}"
    "Docker Network:     ${CLOUDFLARE_NET}"
    "Default Interface:  ${default_iface} (${ip_addr})"
    "Local Access:       ${local_access}"
    "Cloudflare URL:     https://${SUBDOMAIN}"
    "Default User:       admin"
    "Default Password:   ${ADMIN_PASS}"
)

echo ""
draw_box "FileBrowser Deployment Summary" "${summary_lines[@]}"

echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
echo -e "  2. Edit the active Tunnel servicing this network."
echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
echo -e "     - Subdomain/Domain: ${GREEN}${SUBDOMAIN}${NC}"
echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
echo -e "     - URL:              ${YELLOW}http://filebrowser:80${NC} (Internal Docker DNS)"
echo -e "  4. Save Hostname. Cloudflare will route traffic securely to the container."

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
