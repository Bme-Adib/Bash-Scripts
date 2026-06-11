#!/bin/bash
# --- Robust Safety & Error Handling ---
set -euo pipefail

# --- Redirect stdin to tty if piped ---
if [ ! -t 0 ]; then
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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Dozzle Log Viewer Auto-Setup ===${NC}\n"

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
echo -e "\n${BLUE}>>> Step 1: Configure Port Exposure${NC}"
read -rp "Would you like to expose the Dozzle port to the host system? (y/n) [n]: " EXPOSE_PORT
EXPOSE_PORT=${EXPOSE_PORT:-n}

PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # Change the port number before the colon (8888) to whatever port you want.
    # ports:
    #   - 8888:8080"
HOST_PORT="N/A"
if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port to bind Dozzle to [8888]: " HOST_PORT
        HOST_PORT=${HOST_PORT:-8888}
        if validate_port "$HOST_PORT"; then
            break
        fi
    done
    PORT_MAPPING_BLOCK="ports:
      - ${HOST_PORT}:8080"
fi

echo -e "\n${BLUE}>>> Step 2: Configure Cloudflare Subdomain & Network${NC}"
read -rp "Enter the subdomain they will connect to (e.g. logs.example.com): " SUBDOMAIN
while [ -z "$SUBDOMAIN" ]; do
    log_error "Subdomain cannot be empty."
    read -rp "Enter the subdomain: " SUBDOMAIN
done

# Show existing networks on the host
log_info "Detecting active Docker networks on host..."
if docker network ls >/dev/null 2>&1; then
    echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
    docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
    echo ""
fi

read -rp "Enter the name of your Cloudflare docker network [proxy-net]: " CLOUDFLARE_NET
CLOUDFLARE_NET=${CLOUDFLARE_NET:-proxy-net}

# Check and prompt to create network if missing
if ! docker network inspect "$CLOUDFLARE_NET" >/dev/null 2>&1; then
    log_warning "Docker network '${CLOUDFLARE_NET}' does not exist."
    read -rp "Would you like to create the '${CLOUDFLARE_NET}' network now? (y/n) [y]: " CREATE_NET
    CREATE_NET=${CREATE_NET:-y}
    if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
        docker network create "$CLOUDFLARE_NET"
        log_success "Created external docker network: ${CLOUDFLARE_NET}"
    else
        log_warning "Skipping network creation. Docker compose may fail if it is missing."
    fi
fi

# 3. Create Folder and Configuration Files
TARGET_DIR="$(pwd)/dozzle"
log_info "Creating deployment directory at: ${TARGET_DIR}"

if [ -d "$TARGET_DIR" ]; then
    log_warning "Directory ${TARGET_DIR} already exists."
    read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE_DIR
    OVERWRITE_DIR=${OVERWRITE_DIR:-n}
    if [[ "$OVERWRITE_DIR" =~ ^[Yy]$ ]]; then
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
DOZZLE_TAILSIZE=300
EOF
log_success "Created: ${TARGET_DIR}/.env"

# Write docker-compose.yml
cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    ${PORT_MAPPING_BLOCK}
    environment:
      - TAILSIZE=\${DOZZLE_TAILSIZE}
    networks:
      - ${CLOUDFLARE_NET}

networks:
  ${CLOUDFLARE_NET}:
    external: true
EOF
log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 4. Show Compose file configuration
echo -e "\n${BLUE}>>> Step 3: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Dozzle container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying container..."
    (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "Dozzle Log Viewer is running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Connection Details ===${NC}"
echo -e "Container Name:   ${GREEN}dozzle${NC}"
if [[ "$HOST_PORT" != "N/A" ]]; then
    echo -e "Local Access:     ${YELLOW}http://localhost:${HOST_PORT}${NC}"
else
    echo -e "Local Access:     ${YELLOW}No ports exposed on host (Access via Tunnel only)${NC}"
fi

echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
echo -e "  2. Edit the active Tunnel servicing this network."
echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
echo -e "     - Subdomain/Domain: ${GREEN}${SUBDOMAIN}${NC}"
echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
echo -e "     - URL:              ${YELLOW}http://dozzle:8080${NC} (Internal Docker DNS)"
echo -e "  4. Save Hostname. Cloudflare will route traffic securely to the container."

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
