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
echo -e "${BLUE}=== Portable Cloudflare Tunnel Auto-Setup ===${NC}\n"

# --- Usage instructions ---
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -t TOKEN         Cloudflare Tunnel Token (required in non-interactive mode)
  -n NETWORK       Target Docker network name (default: proxy-net)
  -d DIR           Target deployment directory (default: ./cloudflareContainer)
  -y               Auto-confirm and run non-interactively
  -h               Show this help message
EOF
}

# --- Parse Arguments ---
USER_TOKEN=""
NETWORK_NAME="proxy-net"
NETWORK_PASSED=false
TARGET_DIR=""
AUTO_CONFIRM=false

while getopts "t:n:d:yh" opt; do
    case "$opt" in
        t) USER_TOKEN="$OPTARG" ;;
        n) NETWORK_NAME="$OPTARG"; NETWORK_PASSED=true ;;
        d) TARGET_DIR="$OPTARG" ;;
        y) AUTO_CONFIRM=true ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Resolve default values
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(pwd)/cloudflareContainer"
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
    log_error "Docker Compose is not installed. Please install the docker-compose-plugin or docker-compose first."
    exit 1
fi
log_success "Docker & Docker Compose detected."

# 2. Information Gathering
if [ -z "$USER_TOKEN" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        log_error "Cloudflare Tunnel Token (-t) is required in non-interactive mode."
        exit 1
    fi
    echo -e "\n${BLUE}>>> Step 1: Configure Cloudflare Tunnel${NC}"
    read -rp "Enter Cloudflare Tunnel Token: " USER_TOKEN
    while [ -z "$USER_TOKEN" ]; do
        log_error "Token cannot be empty. Please enter a valid Cloudflare Tunnel Token."
        read -rp "Enter Cloudflare Tunnel Token: " USER_TOKEN
    done
fi

if [ "$AUTO_CONFIRM" = false ] && [ "$NETWORK_PASSED" = false ]; then
    read -rp "Enter Target Docker Network Name [proxy-net]: " INPUT_NET
    NETWORK_NAME=${INPUT_NET:-$NETWORK_NAME}
fi

# 3. Setup Target Folder
log_info "Setting up folder at: ${TARGET_DIR}"

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
        log_info "Removing existing directory..."
        rm -rf "$TARGET_DIR"
    else
        log_error "Setup cancelled to prevent overwriting existing configuration."
        exit 1
    fi
fi

mkdir -p "$TARGET_DIR"

# 4. Generate Configuration Files (.env and docker-compose.yml)
log_info "Generating configuration files..."

# Write .env file
cat <<EOF > "${TARGET_DIR}/.env"
CLOUDFLARE_TUNNEL_TOKEN="${USER_TOKEN}"
EOF
log_success "Created: ${TARGET_DIR}/.env"

# Write docker-compose.yml
cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=\${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - ${NETWORK_NAME}

networks:
  ${NETWORK_NAME}:
    external: true
EOF
log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 5. Check and prompt to create network if it doesn't exist
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    log_warning "Docker network '${NETWORK_NAME}' does not exist."
    create_net="y"
    if [ "$AUTO_CONFIRM" = false ]; then
        read -rp "Would you like to create the '${NETWORK_NAME}' network now? (y/n) [y]: " CREATE_NET
        create_net=${CREATE_NET:-y}
    fi
    if [[ "$create_net" =~ ^[Yy]$ ]]; then
        docker network create "$NETWORK_NAME"
        log_success "Created external docker network: ${NETWORK_NAME}"
    else
        log_warning "Skipping network creation. Note that docker compose may fail if the network is missing."
    fi
else
    log_info "External network '${NETWORK_NAME}' already exists."
fi

# 6. Show Compose File
if [ "$AUTO_CONFIRM" = false ]; then
    echo -e "\n${BLUE}>>> Step 2: Review Docker Compose Configuration${NC}"
    echo -e "${GREEN}============================================================${NC}"
    cat "${TARGET_DIR}/docker-compose.yml"
    echo -e "${GREEN}============================================================${NC}"
fi

# Ask for confirmation before running
deploy="y"
if [ "$AUTO_CONFIRM" = false ]; then
    read -rp "Deploy the Cloudflare Tunnel container now? (y/n) [y]: " DEPLOY_CONFIRM
    deploy=${DEPLOY_CONFIRM:-y}
fi

if [[ "$deploy" =~ ^[Yy]$ ]]; then
    # Run from target directory to cleanly pick up local .env
    pushd "$TARGET_DIR" >/dev/null
    run_with_spinner "Pulling Docker images..." $DOCKER_COMPOSE_CMD pull
    run_with_spinner "Deploying Cloudflare Tunnel container..." $DOCKER_COMPOSE_CMD up -d
    popd >/dev/null
    
    if validate_health "cloudflared" "N/A"; then
        log_success "Cloudflare Tunnel service is up and running!"
    else
        log_error "Cloudflare Tunnel container failed to start properly."
        exit 1
    fi
else
    log_warning "Deployment skipped by user."
fi

# --- Follow-up Instructions ---
ip_addr=$(detect_ip)
default_iface=$(detect_default_interface)

summary_lines=(
    "Deployment Folder: ${TARGET_DIR}"
    "Docker Network:    ${NETWORK_NAME}"
    "Default Interface: ${default_iface} (${ip_addr})"
    "Container Name:    cloudflared"
)

echo ""
draw_box "Setup Process Complete!" "${summary_lines[@]}"

echo -e "\n${BLUE}=== Useful Commands ===${NC}"
echo -e "To view logs for your Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "To stop the Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "To start the Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} up -d${NC}"
echo -e "============================================================\n"
