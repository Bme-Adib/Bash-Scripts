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
echo -e "${BLUE}=== Flame Dashboard Auto-Setup ===${NC}\n"

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
TARGET_DIR="$(pwd)/flame-deployment"

EXISTING_PASSWORD=""
EXISTING_INTEGRATION=""

# Try to read defaults if .env exists
if [ -f "${TARGET_DIR}/.env" ]; then
    EXISTING_PASSWORD=$(grep -E "^PASSWORD=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
fi

echo -e "\n${BLUE}>>> Step 1: General Dashboard Settings${NC}"
RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "flame_secure_pass")
PASSWORD_SUGGESTION=${EXISTING_PASSWORD:-$RANDOM_PASS}
read -rp "Enter Flame Dashboard settings edit password [$PASSWORD_SUGGESTION]: " PASSWORD
PASSWORD=${PASSWORD:-$PASSWORD_SUGGESTION}

read -rp "Enable Docker Integration (allows Flame to discover running containers)? (y/n) [y]: " DOCKER_INT
DOCKER_INT=${DOCKER_INT:-y}

DOCKER_SOCKET_VOLUME_BLOCK=""
if [[ "$DOCKER_INT" =~ ^[Yy]$ ]]; then
    DOCKER_SOCKET_VOLUME_BLOCK="- /var/run/docker.sock:/var/run/docker.sock"
fi

echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"
read -rp "Expose Flame port (5005) to the host system? (y/n) [n]: " EXPOSE_PORT
EXPOSE_PORT=${EXPOSE_PORT:-n}
PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 5005:5005"
HOST_PORT="N/A"
if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port for Flame [5005]: " HOST_PORT
        HOST_PORT=${HOST_PORT:-5005}
        if validate_port "$HOST_PORT"; then
            break
        fi
    done
    PORT_MAPPING_BLOCK="ports:
      - ${HOST_PORT}:5005"
fi

echo -e "\n${BLUE}>>> Step 3: Network & Cloudflare Settings${NC}"
read -rp "Do you want to connect to an external Docker network (e.g. Cloudflare proxy-net)? (y/n) [y]: " USE_EXT_NET
USE_EXT_NET=${USE_EXT_NET:-y}

CLOUDFLARE_NET=""
FLAME_URL="http://localhost:5005"
if [ "$HOST_PORT" != "N/A" ]; then
    FLAME_URL="http://localhost:${HOST_PORT}"
fi

if [[ "$USE_EXT_NET" =~ ^[Yy]$ ]]; then
    log_info "Detecting active Docker networks on host..."
    if docker network ls >/dev/null 2>&1; then
        echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
        docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
        echo ""
    fi

    read -rp "Enter the name of your external docker network [proxy-net]: " CLOUDFLARE_NET
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

    read -rp "Enter the external URL where you will access Flame (e.g. https://homepage.example.com): " CUSTOM_URL
    while [ -z "$CUSTOM_URL" ]; do
        log_error "External URL cannot be empty."
        read -rp "Enter the external URL: " CUSTOM_URL
    done
    FLAME_URL="$CUSTOM_URL"
fi

# 3. Create Folder and Configuration Files
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

# 4. Show Compose file configuration
echo -e "\n${BLUE}>>> Step 4: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Flame dashboard container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying containers..."
    (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "Services are running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Connection Details ===${NC}"
echo -e "Dashboard Password:  ${GREEN}${PASSWORD}${NC}"
if [ "$HOST_PORT" != "N/A" ]; then
    echo -e "Flame Local:         ${YELLOW}http://localhost:${HOST_PORT}${NC}"
else
    echo -e "Flame Local:         ${RED}Not Exposed to Host${NC}"
fi
echo -e "Flame URL:           ${GREEN}${FLAME_URL}${NC}"

if [ -n "$CLOUDFLARE_NET" ]; then
    # Extract domain from URL
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
