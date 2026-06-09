#!/bin/bash

# Exit immediately if a command exits with a non-zero status
# Treat unset variables as an error
# Prevent errors in a pipeline from being masked
set -euo pipefail

# --- Color Codes for UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number: '$port'. Must be between 1 and 65535."
        return 1
    fi
    # Optional: Check if port is in use on the host
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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== SiYuan Note Docker Installer & Setup ===${NC}\n"

# 1. Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    echo "    On Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y docker.io"
    exit 1
fi

# 2. Check if Docker Compose is installed
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Determine compose command to use
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 3. Gather inputs
# Auto-detect timezone and current user credentials
DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
DETECTED_UID=$(id -u)
DETECTED_GID=$(id -g)

# Prompts
while true; do
    read -p "Enter installation directory [default: ./siyuan-workspace]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-"./siyuan-workspace"}
    
    # Resolve to absolute path
    mkdir -p "$INSTALL_DIR"
    ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
    
    # Check for existing docker-compose.yml
    if [ -f "$ABS_INSTALL_DIR/docker-compose.yml" ]; then
        log_warning "A docker-compose.yml already exists in '$ABS_INSTALL_DIR'."
        read -p "Do you want to overwrite it? (y/N): " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[yY]$ ]]; then
            log_info "Please choose a different directory."
            continue
        fi
    fi
    break
done

while true; do
    read -p "Enter port to bind [default: 6806]: " PORT
    PORT=${PORT:-"6806"}
    if validate_port "$PORT"; then
        break
    fi
done

# Generate a random password as default
RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 12 || echo "siyuan_secure_password")
read -p "Enter Access Authorization Code (password) [default: $RANDOM_PASS]: " AUTH_CODE
AUTH_CODE=${AUTH_CODE:-"$RANDOM_PASS"}

read -p "Enter Timezone [default: $DETECTED_TZ]: " TZ
TZ=${TZ:-"$DETECTED_TZ"}

while true; do
    read -p "Enter User ID (PUID) [default: $DETECTED_UID]: " PUID
    PUID=${PUID:-"$DETECTED_UID"}
    if validate_numeric "$PUID" "PUID"; then
        break
    fi
done

while true; do
    read -p "Enter Group ID (PGID) [default: $DETECTED_GID]: " PGID
    PGID=${PGID:-"$DETECTED_GID"}
    if validate_numeric "$PGID" "PGID"; then
        break
    fi
done

echo -e "\n${BLUE}Configuration Summary:${NC}"
echo "----------------------"
echo "Installation Dir : $ABS_INSTALL_DIR"
echo "Port             : $PORT"
echo "Auth Code        : $AUTH_CODE"
echo "Timezone         : $TZ"
echo "PUID/PGID        : $PUID:$PGID"
echo "----------------------"

# Create workspace folder
WORKSPACE_DIR="$ABS_INSTALL_DIR/workspace"
log_info "Creating workspace folder at $WORKSPACE_DIR..."
mkdir -p "$WORKSPACE_DIR"

# Write docker-compose.yml
log_info "Writing docker-compose.yml..."
cat << EOF > "$ABS_INSTALL_DIR/docker-compose.yml"
version: "3.9"

services:
  siyuan:
    image: b3log/siyuan:latest
    container_name: siyuan
    command:
      - --workspace=/siyuan/workspace/
      - --accessAuthCode=$AUTH_CODE
    ports:
      - "$PORT:6806"
    volumes:
      - ./workspace:/siyuan/workspace
    environment:
      - TZ=$TZ
      - PUID=$PUID
      - PGID=$PGID
    restart: unless-stopped
EOF

# Adjust permissions if run as root
if [ "$DETECTED_UID" -eq 0 ]; then
    log_info "Adjusting workspace ownership to $PUID:$PGID..."
    chown -R "$PUID:$PGID" "$WORKSPACE_DIR"
fi

# Review file prompt before execution
read -p "Would you like to open/review docker-compose.yml before running the service? (y/N): " OPEN_EDITOR
if [[ "$OPEN_EDITOR" =~ ^[yY]$ ]]; then
    EDITOR_CMD="${EDITOR:-$(which nano 2>/dev/null || which vi 2>/dev/null || echo "")}"
    if [ -n "$EDITOR_CMD" ]; then
        $EDITOR_CMD "$ABS_INSTALL_DIR/docker-compose.yml"
    else
        log_warning "No text editor found (nano/vi). Displaying file instead:"
        cat "$ABS_INSTALL_DIR/docker-compose.yml"
    fi
fi

# Starting container prompt
read -p "Do you want to start the SiYuan container now? (y/N): " START_CONTAINER
if [[ "$START_CONTAINER" =~ ^[yY]$ ]]; then
    log_info "Starting SiYuan container..."
    cd "$ABS_INSTALL_DIR"
    $DOCKER_COMPOSE_CMD up -d
    
    log_success "Success! SiYuan has been deployed and started."
    echo "Access URL : http://localhost:$PORT (or http://<your-server-ip>:$PORT)"
    echo "Auth Code  : $AUTH_CODE"
else
    log_success "Setup completed! docker-compose.yml has been written to: $ABS_INSTALL_DIR"
fi

echo -e "\nTo manage this project, run:"
echo -e "${GREEN}cd ${ABS_INSTALL_DIR}${NC}"
echo -e "To start: ${BLUE}$DOCKER_COMPOSE_CMD up -d${NC}"
echo -e "To stop:  ${BLUE}$DOCKER_COMPOSE_CMD down${NC}"
echo "============================================="
