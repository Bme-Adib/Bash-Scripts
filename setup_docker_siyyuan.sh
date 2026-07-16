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

validate_numeric() {
    local val="$1"
    local desc="$2"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        log_error "Invalid $desc: '$val'. Must be a numeric value."
        return 1
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
echo -e "${BLUE}=== SiYuan Note Docker Installer & Setup ===${NC}\n"

# --- Usage instructions ---
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -d DIR           Target deployment/installation directory (default: ./siyuan-workspace)
  -e PORT          Expose SiYuan port to host system (default: N/A, do not expose)
  -p PASSWORD      Access Authorization Code/password (default: random 12-char string)
  -t TIMEZONE      Timezone setting (default: detected system timezone)
  -u PUID          PUID for files ownership (default: current user UID)
  -g PGID          PGID for files ownership (default: current user GID)
  -y               Auto-confirm and run non-interactively
  -h               Show this help message
EOF
}

# --- Parse Arguments ---
INSTALL_DIR=""
HOST_PORT=""
AUTH_CODE=""
TZ=""
PUID=""
PGID=""
AUTO_CONFIRM=false

while getopts "d:e:p:t:u:g:yh" opt; do
    case "$opt" in
        d) INSTALL_DIR="$OPTARG" ;;
        e) HOST_PORT="$OPTARG" ;;
        p) AUTH_CODE="$OPTARG" ;;
        t) TZ="$OPTARG" ;;
        u) PUID="$OPTARG" ;;
        g) PGID="$OPTARG" ;;
        y) AUTO_CONFIRM=true ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

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
DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
DETECTED_UID=$(id -u)
DETECTED_GID=$(id -g)

if [ -z "$INSTALL_DIR" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        INSTALL_DIR="./siyuan-workspace"
        mkdir -p "$INSTALL_DIR"
        ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
    else
        echo -e "\n${BLUE}>>> Step 1: Configure Installation Directory${NC}"
        while true; do
            read -rp "Enter installation directory [./siyuan-workspace]: " INPUT_DIR
            INPUT_DIR=${INPUT_DIR:-"./siyuan-workspace"}
            
            mkdir -p "$INPUT_DIR"
            ABS_INSTALL_DIR=$(cd "$INPUT_DIR" && pwd)
            
            if [ -f "$ABS_INSTALL_DIR/docker-compose.yml" ]; then
                log_warning "A docker-compose.yml already exists in '$ABS_INSTALL_DIR'."
                read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE
                OVERWRITE=${OVERWRITE:-n}
                if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
                    log_info "Please choose a different directory."
                    continue
                fi
            fi
            break
        done
    fi
else
    mkdir -p "$INSTALL_DIR"
    ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
    if [ -f "$ABS_INSTALL_DIR/docker-compose.yml" ]; then
        log_warning "A docker-compose.yml already exists in '$ABS_INSTALL_DIR'."
        overwrite="n"
        if [ "$AUTO_CONFIRM" = true ]; then
            overwrite="y"
        else
            read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE
            overwrite=${OVERWRITE:-n}
        fi
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_error "Installation cancelled to protect existing configuration."
            exit 1
        fi
    fi
fi

if [ -z "$HOST_PORT" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        HOST_PORT="N/A"
    else
        echo -e "\n${BLUE}>>> Step 2: Configure Port Exposure${NC}"
        read -rp "Would you like to expose the SiYuan port to the host system? (y/n) [n]: " EXPOSE_PORT
        EXPOSE_PORT=${EXPOSE_PORT:-n}
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
            while true; do
                read -rp "Enter port to bind [6806]: " INPUT_PORT
                INPUT_PORT=${INPUT_PORT:-"6806"}
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

if [ -z "$AUTH_CODE" ]; then
    RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 12 || echo "siyuan_secure_password")
    if [ "$AUTO_CONFIRM" = true ]; then
        AUTH_CODE="$RANDOM_PASS"
    else
        echo -e "\n${BLUE}>>> Step 3: Configure Security & Timezone${NC}"
        read -rp "Enter Access Authorization Code (password) [$RANDOM_PASS]: " INPUT_AUTH
        AUTH_CODE=${INPUT_AUTH:-"$RANDOM_PASS"}
    fi
fi

if [ -z "$TZ" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        TZ="$DETECTED_TZ"
    else
        read -rp "Enter Timezone [$DETECTED_TZ]: " INPUT_TZ
        TZ=${INPUT_TZ:-"$DETECTED_TZ"}
    fi
fi

if [ -z "$PUID" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        PUID="$DETECTED_UID"
    else
        echo -e "\n${BLUE}>>> Step 4: Configure Permissions (PUID/PGID)${NC}"
        while true; do
            read -rp "Enter User ID (PUID) [$DETECTED_UID]: " INPUT_PUID
            INPUT_PUID=${INPUT_PUID:-"$DETECTED_UID"}
            if validate_numeric "$INPUT_PUID" "PUID"; then
                PUID="$INPUT_PUID"
                break
            fi
        done
    fi
else
    validate_numeric "$PUID" "PUID" || exit 1
fi

if [ -z "$PGID" ]; then
    if [ "$AUTO_CONFIRM" = true ]; then
        PGID="$DETECTED_GID"
    else
        while true; do
            read -rp "Enter Group ID (PGID) [$DETECTED_GID]: " INPUT_PGID
            INPUT_PGID=${INPUT_PGID:-"$DETECTED_GID"}
            if validate_numeric "$INPUT_PGID" "PGID"; then
                PGID="$INPUT_PGID"
                break
            fi
        done
    fi
else
    validate_numeric "$PGID" "PGID" || exit 1
fi

# Create workspace folder
WORKSPACE_DIR="$ABS_INSTALL_DIR/workspace"
log_info "Creating workspace folder at: ${WORKSPACE_DIR}"
mkdir -p "$WORKSPACE_DIR"

# Write docker-compose.yml
log_info "Writing docker-compose.yml..."
PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 6806:6806"
if [ "$HOST_PORT" != "N/A" ]; then
    PORT_MAPPING_BLOCK="ports:
      - \"$HOST_PORT:6806\""
fi

cat << EOF > "$ABS_INSTALL_DIR/docker-compose.yml"
services:
  siyuan:
    image: b3log/siyuan:latest
    container_name: siyuan
    command:
      - --workspace=/siyuan/workspace/
      - --accessAuthCode=$AUTH_CODE
    ${PORT_MAPPING_BLOCK}
    volumes:
      - ./workspace:/siyuan/workspace
    environment:
      - TZ=$TZ
      - PUID=$PUID
      - PGID=$PGID
    restart: unless-stopped
EOF
log_success "Created: $ABS_INSTALL_DIR/docker-compose.yml"

# Adjust permissions if run as root
if [ "$DETECTED_UID" -eq 0 ]; then
    log_info "Adjusting workspace ownership to $PUID:$PGID..."
    chown -R "$PUID:$PGID" "$WORKSPACE_DIR"
fi

# --- Review & Deploy ---
if [ "$AUTO_CONFIRM" = false ]; then
    echo -e "\n${BLUE}>>> Step 5: Review Configuration${NC}"
    echo -e "${GREEN}============================================================${NC}"
    cat "$ABS_INSTALL_DIR/docker-compose.yml"
    echo -e "${GREEN}============================================================${NC}"
fi

deploy="y"
if [ "$AUTO_CONFIRM" = false ]; then
    read -rp "Deploy the SiYuan Note container now? (y/n) [y]: " DEPLOY_CONFIRM
    deploy=${DEPLOY_CONFIRM:-y}
fi

if [[ "$deploy" =~ ^[Yy]$ ]]; then
    pushd "$ABS_INSTALL_DIR" >/dev/null
    run_with_spinner "Pulling Docker images..." $DOCKER_COMPOSE_CMD pull
    run_with_spinner "Deploying SiYuan Note container..." $DOCKER_COMPOSE_CMD up -d
    popd >/dev/null
    
    if validate_health "siyuan" "$HOST_PORT"; then
        log_success "SiYuan Note is running!"
    else
        log_error "SiYuan container failed health checks."
        exit 1
    fi
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary Box ---
ip_addr=$(detect_ip)
default_iface=$(detect_default_interface)

local_access="No ports exposed on host"
if [[ "$HOST_PORT" != "N/A" ]]; then
    local_access="http://${ip_addr}:${HOST_PORT} (or http://localhost:${HOST_PORT})"
fi

summary_lines=(
    "Installation Directory: ${ABS_INSTALL_DIR}"
    "Default Interface:      ${default_iface} (${ip_addr})"
    "Local Access:           ${local_access}"
    "Auth Code (Password):   ${AUTH_CODE}"
    "PUID / PGID:            ${PUID} / ${PGID}"
    "Timezone:               ${TZ}"
)

echo ""
draw_box "SiYuan Note Deployment Summary" "${summary_lines[@]}"

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
