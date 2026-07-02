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
check_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port "
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i :"$port" >/dev/null 2>&1
    else
        # Fallback check via bash TCP connection
        (echo > /dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
    fi
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number: '$port'. Must be between 1 and 65535."
        return 1
    fi
    if check_port_in_use "$port"; then
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
echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Actual Budget Docker Installer & Setup ===${NC}\n"

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

echo -e "\n${BLUE}>>> Step 1: Configure Installation Directory${NC}"
while true; do
    read -rp "Enter installation directory [./actualbudget-deployment]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-"./actualbudget-deployment"}
    
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
read -rp "Would you like to expose the Actual Budget port to the host system? (y/n) [y]: " EXPOSE_PORT
EXPOSE_PORT=${EXPOSE_PORT:-y}

PORT_MAPPING_BLOCK=""
PORT="N/A"
if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port to bind to Actual Budget [5006]: " PORT
        PORT=${PORT:-"5006"}
        if validate_port "$PORT"; then
            break
        fi
    done
    PORT_MAPPING_BLOCK="ports:
      - \"$PORT:5006\""
fi

echo -e "\n${BLUE}>>> Step 3: SSL / HTTPS Configuration${NC}"
log_info "Actual Budget uses Web Cryptography APIs, which requires HTTPS on non-localhost client access."
log_info "You can configure built-in HTTPS with your certificates or run behind a reverse proxy (recommended)."
read -rp "Would you like to configure built-in HTTPS? (y/n) [n]: " ENABLE_SSL
ENABLE_SSL=${ENABLE_SSL:-n}

SSL_ENV_BLOCK=""
SSL_KEY_PATH=""
SSL_CERT_PATH=""

if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter path to SSL private key file (PEM format): " SSL_KEY_PATH
        if [ -n "$SSL_KEY_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
            break
        else
            log_error "File not found or empty: '$SSL_KEY_PATH'. Please enter a valid path."
        fi
    done
    while true; do
        read -rp "Enter path to SSL certificate file (PEM format): " SSL_CERT_PATH
        if [ -n "$SSL_CERT_PATH" ] && [ -f "$SSL_CERT_PATH" ]; then
            break
        else
            log_error "File not found or empty: '$SSL_CERT_PATH'. Please enter a valid path."
        fi
    done
fi

echo -e "\n${BLUE}>>> Step 4: Configure Limits & Variables${NC}"
while true; do
    read -rp "Enter maximum sync file upload limit (in MB) [20]: " UPLOAD_LIMIT
    UPLOAD_LIMIT=${UPLOAD_LIMIT:-"20"}
    if validate_numeric "$UPLOAD_LIMIT" "Upload Limit"; then
        break
    fi
done

while true; do
    read -rp "Enter maximum encrypted file sync upload limit (in MB) [50]: " ENCRYPTED_LIMIT
    ENCRYPTED_LIMIT=${ENCRYPTED_LIMIT:-"50"}
    if validate_numeric "$ENCRYPTED_LIMIT" "Encrypted Upload Limit"; then
        break
    fi
done

echo -e "\n${BLUE}>>> Step 5: Network Settings${NC}"
read -rp "Do you want to connect to an external Docker network (e.g. Cloudflare proxy-net)? (y/n) [y]: " USE_EXT_NET
USE_EXT_NET=${USE_EXT_NET:-y}

CLOUDFLARE_NET=""
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
fi

# 3. Create Folder and Configuration Files
log_info "Creating deployment directory at: ${ABS_INSTALL_DIR}"
mkdir -p "$ABS_INSTALL_DIR/actual-data"

# Setup SSL files if enabled
if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    mkdir -p "$ABS_INSTALL_DIR/actual-data/ssl"
    cp "$SSL_KEY_PATH" "$ABS_INSTALL_DIR/actual-data/ssl/key.pem"
    cp "$SSL_CERT_PATH" "$ABS_INSTALL_DIR/actual-data/ssl/cert.pem"
    SSL_ENV_BLOCK="
      - ACTUAL_HTTPS_KEY=/data/ssl/key.pem
      - ACTUAL_HTTPS_CERT=/data/ssl/cert.pem"
fi

# Ensure user permissions on actual-data
if [ "$DETECTED_UID" -eq 0 ]; then
    log_info "Running as root. Setting ownership of data folder to UID: $DETECTED_UID..."
fi
chown -R "$DETECTED_UID:$DETECTED_GID" "$ABS_INSTALL_DIR/actual-data"

# Write docker-compose.yml
log_info "Writing docker-compose.yml..."

# Compose Network block
NETWORKS_BLOCK=""
SERVICE_NETWORKS=""
if [ -n "$CLOUDFLARE_NET" ]; then
    NETWORKS_BLOCK="

networks:
  ${CLOUDFLARE_NET}:
    external: true"

    SERVICE_NETWORKS="
    networks:
      - ${CLOUDFLARE_NET}"
fi

cat << EOF > "$ABS_INSTALL_DIR/docker-compose.yml"
services:
  actualbudget:
    image: docker.io/actualbudget/actual-server:latest
    container_name: actualbudget
    restart: unless-stopped
    ${PORT_MAPPING_BLOCK}
    environment:
      - ACTUAL_PORT=5006
      - ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB=${UPLOAD_LIMIT}
      - ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB=${ENCRYPTED_LIMIT}
      - ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB=${UPLOAD_LIMIT}${SSL_ENV_BLOCK}
    volumes:
      - ./actual-data:/data${SERVICE_NETWORKS}${NETWORKS_BLOCK}
EOF

log_success "Created: $ABS_INSTALL_DIR/docker-compose.yml"

# 4. Show Compose file configuration
echo -e "\n${BLUE}>>> Step 6: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "$ABS_INSTALL_DIR/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Actual Budget container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying container..."
    (cd "$ABS_INSTALL_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "Actual Budget is running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Connection Details ===${NC}"
echo -e "Container Name:      ${GREEN}actualbudget${NC}"
if [[ "$PORT" != "N/A" ]]; then
    SCHEME_STR="http"
    if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
        SCHEME_STR="https"
    fi
    echo -e "Local Access:        ${YELLOW}${SCHEME_STR}://localhost:${PORT}${NC}"
else
    echo -e "Local Access:        ${YELLOW}No ports exposed on host (Access via Tunnel/Proxy only)${NC}"
fi

echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
echo -e "To configure access via Cloudflare Zero Trust Tunnels (if using external network):"
echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
echo -e "  2. Edit the active Tunnel servicing this network."
echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
echo -e "     - Subdomain/Domain: ${GREEN}budget.yourdomain.com${NC}"
echo -e "     - Service Type:     ${YELLOW}HTTP${NC} (or HTTPS if you enabled built-in SSL)"
echo -e "     - URL:              ${YELLOW}http://actualbudget:5006${NC} (Internal Docker DNS)"
echo -e "  4. Save Hostname. Cloudflare will route traffic securely."

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Container:"
echo -e "  ${YELLOW}cd ${ABS_INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
