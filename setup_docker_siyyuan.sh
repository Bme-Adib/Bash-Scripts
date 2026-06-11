#!/bin/bash
# --- Robust Safety & Error Handling ---
set -euo pipefail

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

# --- Helper Functions ---
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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== SiYuan Note Docker Installer & Setup ===${NC}\n"

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
# Auto-detect timezone and current user credentials
DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
DETECTED_UID=$(id -u)
DETECTED_GID=$(id -g)

echo -e "\n${BLUE}>>> Step 1: Configure Installation Directory${NC}"
while true; do
    read -rp "Enter installation directory [./siyuan-workspace]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-"./siyuan-workspace"}
    
    # Resolve to absolute path
    mkdir -p "$INSTALL_DIR"
    ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
    
    # Check for existing docker-compose.yml
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

echo -e "\n${BLUE}>>> Step 2: Configure Port Exposure${NC}"
while true; do
    read -rp "Enter port to bind [6806]: " PORT
    PORT=${PORT:-"6806"}
    if validate_port "$PORT"; then
        break
    fi
done

echo -e "\n${BLUE}>>> Step 3: Configure Security & Timezone${NC}"
# Generate a random password as default
RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 12 || echo "siyuan_secure_password")
read -rp "Enter Access Authorization Code (password) [$RANDOM_PASS]: " AUTH_CODE
AUTH_CODE=${AUTH_CODE:-"$RANDOM_PASS"}

read -rp "Enter Timezone [$DETECTED_TZ]: " TZ
TZ=${TZ:-"$DETECTED_TZ"}

echo -e "\n${BLUE}>>> Step 4: Configure Permissions (PUID/PGID)${NC}"
while true; do
    read -rp "Enter User ID (PUID) [$DETECTED_UID]: " PUID
    PUID=${PUID:-"$DETECTED_UID"}
    if validate_numeric "$PUID" "PUID"; then
        break
    fi
done

while true; do
    read -rp "Enter Group ID (PGID) [$DETECTED_GID]: " PGID
    PGID=${PGID:-"$DETECTED_GID"}
    if validate_numeric "$PGID" "PGID"; then
        break
    fi
done

# Create workspace folder
WORKSPACE_DIR="$ABS_INSTALL_DIR/workspace"
log_info "Creating workspace folder at: ${WORKSPACE_DIR}"
mkdir -p "$WORKSPACE_DIR"

# Write docker-compose.yml
log_info "Writing docker-compose.yml..."
cat << EOF > "$ABS_INSTALL_DIR/docker-compose.yml"
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
log_success "Created: $ABS_INSTALL_DIR/docker-compose.yml"

# Adjust permissions if run as root
if [ "$DETECTED_UID" -eq 0 ]; then
    log_info "Adjusting workspace ownership to $PUID:$PGID..."
    chown -R "$PUID:$PGID" "$WORKSPACE_DIR"
fi

# --- Review & Deploy ---
echo -e "\n${BLUE}>>> Step 5: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "$ABS_INSTALL_DIR/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the SiYuan Note container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying container..."
    (cd "$ABS_INSTALL_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "SiYuan Note is running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Connection Details ===${NC}"
echo -e "Container Name:   ${GREEN}siyuan${NC}"
echo -e "Local Access:     ${YELLOW}http://localhost:${PORT}${NC}"
echo -e "Auth Code:        ${GREEN}${AUTH_CODE}${NC}"

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
