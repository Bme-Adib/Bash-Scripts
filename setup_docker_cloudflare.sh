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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Portable Cloudflare Tunnel Auto-Setup ===${NC}\n"

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
echo -e "\n${BLUE}>>> Step 1: Configure Cloudflare Tunnel${NC}"
read -rp "Enter Cloudflare Tunnel Token: " USER_TOKEN
while [ -z "$USER_TOKEN" ]; do
    log_error "Token cannot be empty. Please enter a valid Cloudflare Tunnel Token."
    read -rp "Enter Cloudflare Tunnel Token: " USER_TOKEN
done

read -rp "Enter Target Docker Network Name [proxy-net]: " NETWORK_NAME
NETWORK_NAME=${NETWORK_NAME:-proxy-net}

# 3. Setup Target Folder
TARGET_DIR="$(pwd)/cloudflareContainer"
log_info "Setting up folder at: ${TARGET_DIR}"

if [ -d "$TARGET_DIR" ]; then
    log_warning "Directory ${TARGET_DIR} already exists."
    read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE_DIR
    OVERWRITE_DIR=${OVERWRITE_DIR:-n}
    if [[ "$OVERWRITE_DIR" =~ ^[Yy]$ ]]; then
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
    read -rp "Would you like to create the '${NETWORK_NAME}' network now? (y/n) [y]: " CREATE_NET
    CREATE_NET=${CREATE_NET:-y}
    if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
        docker network create "$NETWORK_NAME"
        log_success "Created external docker network: ${NETWORK_NAME}"
    else
        log_warning "Skipping network creation. Note that docker compose may fail if the network is missing."
    fi
else
    log_info "External network '${NETWORK_NAME}' already exists."
fi

# 6. Show Compose File
echo -e "\n${BLUE}>>> Step 2: Review Docker Compose Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

# Ask for confirmation before running
read -rp "Deploy the Cloudflare Tunnel container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying container..."
    # Run from target directory to cleanly pick up local .env
    (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "Cloudflare Tunnel service is up and running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Follow-up Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Setup Process Complete!                 ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "\n${BLUE}=== Useful Commands ===${NC}"
echo -e "To view logs for your Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "To stop the Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "To start the Cloudflare container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} up -d${NC}"
echo -e "============================================================\n"
