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
echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Shlink Server & Shlink UI Auto-Setup ===${NC}\n"

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
TARGET_DIR="$(pwd)/shlink-deployment"

EXISTING_DOMAIN=""
EXISTING_API_KEY=""
EXISTING_GEOLITE=""

# 1. Try to read active API key from running container if it exists
if docker ps --format '{{.Names}}' | grep -q "^shlink-server$"; then
    ACTIVE_KEY=$(docker exec shlink-server shlink api-key:list 2>/dev/null | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1 || true)
    if [ -n "$ACTIVE_KEY" ]; then
        EXISTING_API_KEY="$ACTIVE_KEY"
    fi
fi

# 2. If not found in running container, try to read from existing .env
if [ -z "$EXISTING_API_KEY" ] && [ -f "${TARGET_DIR}/.env" ]; then
    EXISTING_API_KEY=$(grep -E "^INITIAL_API_KEY=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
fi

# 3. Read other defaults if .env exists
if [ -f "${TARGET_DIR}/.env" ]; then
    EXISTING_DOMAIN=$(grep -E "^DEFAULT_DOMAIN=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
    EXISTING_GEOLITE=$(grep -E "^GEOLITE_LICENSE_KEY=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
fi

echo -e "\n${BLUE}>>> Step 1: Shlink Server General Settings${NC}"
DEFAULT_DOMAIN_SUGGESTION=${EXISTING_DOMAIN:-s.example.com}
read -rp "Enter Default Domain for short URLs [$DEFAULT_DOMAIN_SUGGESTION]: " DEFAULT_DOMAIN
DEFAULT_DOMAIN=${DEFAULT_DOMAIN:-$DEFAULT_DOMAIN_SUGGESTION}

read -rp "Is HTTPS enabled for Shlink Server? (y/n) [y]: " HTTPS_INPUT
HTTPS_INPUT=${HTTPS_INPUT:-y}
if [[ "$HTTPS_INPUT" =~ ^[Yy]$ ]]; then
    IS_HTTPS_ENABLED="true"
    SCHEME="https"
else
    IS_HTTPS_ENABLED="false"
    SCHEME="http"
fi

GEOLITE_SUGGESTION=${EXISTING_GEOLITE:-}
if [ -n "$GEOLITE_SUGGESTION" ]; then
    read -rp "Enter GeoLite2 License Key (optional) [$GEOLITE_SUGGESTION]: " GEOLITE_LICENSE_KEY
    GEOLITE_LICENSE_KEY=${GEOLITE_LICENSE_KEY:-$GEOLITE_SUGGESTION}
else
    read -rp "Enter GeoLite2 License Key (optional, press Enter to skip): " GEOLITE_LICENSE_KEY
    GEOLITE_LICENSE_KEY=${GEOLITE_LICENSE_KEY:-}
fi

if [ -n "$EXISTING_API_KEY" ]; then
    RANDOM_API_KEY="$EXISTING_API_KEY"
else
    RANDOM_API_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 32 || echo "shlink_secure_api_key_32_chars_long")
fi
read -rp "Enter Initial API Key [$RANDOM_API_KEY]: " INITIAL_API_KEY
INITIAL_API_KEY=${INITIAL_API_KEY:-$RANDOM_API_KEY}

echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"

# Shlink Server Port
read -rp "Expose Shlink Server port (8080) to the host system? (y/n) [n]: " EXPOSE_SERVER
EXPOSE_SERVER=${EXPOSE_SERVER:-n}
SERVER_PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 8080:8080"
SERVER_HOST_PORT="N/A"
if [[ "$EXPOSE_SERVER" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port for Shlink Server [8080]: " SERVER_HOST_PORT
        SERVER_HOST_PORT=${SERVER_HOST_PORT:-8080}
        if validate_port "$SERVER_HOST_PORT"; then
            break
        fi
    done
    SERVER_PORT_MAPPING_BLOCK="ports:
      - ${SERVER_HOST_PORT}:8080"
fi

# Shlink Web UI Port
read -rp "Expose Shlink Web UI port (8000) to the host system? (y/n) [n]: " EXPOSE_UI
EXPOSE_UI=${EXPOSE_UI:-n}
UI_PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # ports:
    #   - 8000:8080"
UI_HOST_PORT="N/A"
if [[ "$EXPOSE_UI" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port for Shlink Web UI [8000]: " UI_HOST_PORT
        UI_HOST_PORT=${UI_HOST_PORT:-8000}
        if validate_port "$UI_HOST_PORT"; then
            break
        fi
    done
    UI_PORT_MAPPING_BLOCK="ports:
      - ${UI_HOST_PORT}:8080"
fi

echo -e "\n${BLUE}>>> Step 3: Database Configuration${NC}"
echo -e "Shlink supports SQLite (embedded, easy) or PostgreSQL (robust, separate container)."
while true; do
    read -rp "Choose Database Driver (sqlite/postgres) [sqlite]: " DB_DRIVER
    DB_DRIVER=${DB_DRIVER:-sqlite}
    if [[ "$DB_DRIVER" == "sqlite" || "$DB_DRIVER" == "postgres" ]]; then
        break
    fi
    log_error "Invalid driver. Please enter 'sqlite' or 'postgres'."
done

DB_NAME="shlink"
DB_USER="shlink"
DB_PASS=""
PG_PORT_MAPPING_BLOCK=""
PG_HOST_PORT="N/A"

if [ "$DB_DRIVER" == "postgres" ]; then
    read -rp "Enter Database Name [$DB_NAME]: " INPUT_DB_NAME
    DB_NAME=${INPUT_DB_NAME:-$DB_NAME}

    read -rp "Enter Database User [$DB_USER]: " INPUT_DB_USER
    DB_USER=${INPUT_DB_USER:-$DB_USER}

    RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "shlink_secure_db_pass")
    read -rp "Enter Database Password [$RANDOM_PASS]: " DB_PASS
    DB_PASS=${DB_PASS:-$RANDOM_PASS}

    read -rp "Expose PostgreSQL port (5432) to the host system? (y/n) [n]: " EXPOSE_PG
    EXPOSE_PG=${EXPOSE_PG:-n}
    if [[ "$EXPOSE_PG" =~ ^[Yy]$ ]]; then
        while true; do
            read -rp "Enter host port for PostgreSQL [5432]: " PG_HOST_PORT
            PG_HOST_PORT=${PG_HOST_PORT:-5432}
            if validate_port "$PG_HOST_PORT"; then
                break
            fi
        done
        PG_PORT_MAPPING_BLOCK="ports:
      - ${PG_HOST_PORT}:5432"
    fi
fi

echo -e "\n${BLUE}>>> Step 4: Shlink Web Client (UI) Connection Settings${NC}"
echo -e "The Web Client runs in the user's browser, so it needs to connect to the Shlink Server"
echo -e "via a URL that is publicly or locally accessible by the browser."
SUGGESTED_SERVER_URL="${SCHEME}://${DEFAULT_DOMAIN}"
if [[ "$DEFAULT_DOMAIN" == "localhost" || "$DEFAULT_DOMAIN" == "127.0.0.1" ]]; then
    if [ "$SERVER_HOST_PORT" != "N/A" ]; then
        SUGGESTED_SERVER_URL="http://localhost:${SERVER_HOST_PORT}"
    else
        SUGGESTED_SERVER_URL="http://localhost:8080"
    fi
fi
read -rp "Enter Shlink Server URL [$SUGGESTED_SERVER_URL]: " SHLINK_SERVER_URL
SHLINK_SERVER_URL=${SHLINK_SERVER_URL:-$SUGGESTED_SERVER_URL}

read -rp "Enter Shlink Server Display Name in UI [Local Shlink]: " SHLINK_SERVER_NAME
SHLINK_SERVER_NAME=${SHLINK_SERVER_NAME:-Local Shlink}

# Suggest UI URL based on DEFAULT_DOMAIN and HTTPS toggle
SUGGESTED_UI_URL="http://localhost:8000"
if [ "$UI_HOST_PORT" != "N/A" ]; then
    SUGGESTED_UI_URL="http://localhost:${UI_HOST_PORT}"
fi
if [[ "$DEFAULT_DOMAIN" != "localhost" && "$DEFAULT_DOMAIN" != "127.0.0.1" ]]; then
    DOMAIN_SUFFIX=$(echo "$DEFAULT_DOMAIN" | sed -E 's/^[^.]+\.//')
    if [ -n "$DOMAIN_SUFFIX" ] && [[ "$DEFAULT_DOMAIN" =~ \. ]]; then
        SUGGESTED_UI_URL="${SCHEME}://shlink-ui.${DOMAIN_SUFFIX}"
    else
        SUGGESTED_UI_URL="${SCHEME}://shlink-ui.${DEFAULT_DOMAIN}"
    fi
fi
read -rp "Enter Shlink Web UI Access URL [$SUGGESTED_UI_URL]: " SHLINK_UI_URL
SHLINK_UI_URL=${SHLINK_UI_URL:-$SUGGESTED_UI_URL}

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
TARGET_DIR="$(pwd)/shlink-deployment"
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
# Shlink Server Config
DEFAULT_DOMAIN=${DEFAULT_DOMAIN}
IS_HTTPS_ENABLED=${IS_HTTPS_ENABLED}
GEOLITE_LICENSE_KEY=${GEOLITE_LICENSE_KEY}
INITIAL_API_KEY=${INITIAL_API_KEY}

# Shlink UI Config
SHLINK_SERVER_URL=${SHLINK_SERVER_URL}
SHLINK_SERVER_API_KEY=${INITIAL_API_KEY}
SHLINK_SERVER_NAME=${SHLINK_SERVER_NAME}
EOF

if [ "$DB_DRIVER" == "postgres" ]; then
    cat <<EOF >> "${TARGET_DIR}/.env"

# PostgreSQL Database Config
DB_DRIVER=postgres
DB_HOST=postgres
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
EOF
else
    cat <<EOF >> "${TARGET_DIR}/.env"

# SQLite Database Config
DB_DRIVER=sqlite
EOF
fi

log_success "Created env config: ${TARGET_DIR}/.env"

# Compose Network Configurations
NETWORKS_BLOCK="networks:
  shlink-net:
    driver: bridge"

SERVICE_NETWORKS="    networks:
      - shlink-net"

if [ -n "$CLOUDFLARE_NET" ]; then
    NETWORKS_BLOCK="networks:
  shlink-net:
    driver: bridge
  ${CLOUDFLARE_NET}:
    external: true"

    SERVICE_NETWORKS="    networks:
      - shlink-net
      - ${CLOUDFLARE_NET}"
fi

# Write docker-compose.yml based on Database selection
if [ "$DB_DRIVER" == "sqlite" ]; then
    cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  shlink-server:
    image: shlinkio/shlink:stable
    container_name: shlink-server
    restart: unless-stopped
    environment:
      DEFAULT_DOMAIN: \${DEFAULT_DOMAIN}
      IS_HTTPS_ENABLED: \${IS_HTTPS_ENABLED}
      GEOLITE_LICENSE_KEY: \${GEOLITE_LICENSE_KEY}
      INITIAL_API_KEY: \${INITIAL_API_KEY}
      DB_DRIVER: \${DB_DRIVER}
    volumes:
      - shlink-data:/etc/shlink/data
    ${SERVER_PORT_MAPPING_BLOCK}
${SERVICE_NETWORKS}

  shlink-web-client:
    image: shlinkio/shlink-web-client:stable
    container_name: shlink-web-client
    restart: unless-stopped
    environment:
      SHLINK_SERVER_URL: \${SHLINK_SERVER_URL}
      SHLINK_SERVER_API_KEY: \${SHLINK_SERVER_API_KEY}
      SHLINK_SERVER_NAME: \${SHLINK_SERVER_NAME}
    ${UI_PORT_MAPPING_BLOCK}
${SERVICE_NETWORKS}

volumes:
  shlink-data:

${NETWORKS_BLOCK}
EOF
else
    # PostgreSQL selection
    cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  postgres:
    image: postgres:16-alpine
    container_name: shlink-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${DB_NAME}
      POSTGRES_USER: \${DB_USER}
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    ${PG_PORT_MAPPING_BLOCK}
    networks:
      - shlink-net

  shlink-server:
    image: shlinkio/shlink:stable
    container_name: shlink-server
    restart: unless-stopped
    depends_on:
      - postgres
    environment:
      DEFAULT_DOMAIN: \${DEFAULT_DOMAIN}
      IS_HTTPS_ENABLED: \${IS_HTTPS_ENABLED}
      GEOLITE_LICENSE_KEY: \${GEOLITE_LICENSE_KEY}
      INITIAL_API_KEY: \${INITIAL_API_KEY}
      DB_DRIVER: \${DB_DRIVER}
      DB_HOST: \${DB_HOST}
      DB_PORT: \${DB_PORT}
      DB_NAME: \${DB_NAME}
      DB_USER: \${DB_USER}
      DB_PASSWORD: \${DB_PASSWORD}
    volumes:
      - shlink-data:/etc/shlink/data
    ${SERVER_PORT_MAPPING_BLOCK}
${SERVICE_NETWORKS}

  shlink-web-client:
    image: shlinkio/shlink-web-client:stable
    container_name: shlink-web-client
    restart: unless-stopped
    environment:
      SHLINK_SERVER_URL: \${SHLINK_SERVER_URL}
      SHLINK_SERVER_API_KEY: \${SHLINK_SERVER_API_KEY}
      SHLINK_SERVER_NAME: \${SHLINK_SERVER_NAME}
    ${UI_PORT_MAPPING_BLOCK}
${SERVICE_NETWORKS}

volumes:
  shlink-data:

${NETWORKS_BLOCK}
EOF
fi

log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 4. Show Compose file configuration
echo -e "\n${BLUE}>>> Step 6: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Shlink containers now? (y/n) [y]: " DEPLOY_CONFIRM
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
echo -e "Default Domain:      ${GREEN}${DEFAULT_DOMAIN}${NC}"
echo -e "Initial API Key:     ${GREEN}${INITIAL_API_KEY}${NC}"
if [ "$SERVER_HOST_PORT" != "N/A" ]; then
    echo -e "Shlink Server Local: ${YELLOW}http://localhost:${SERVER_HOST_PORT}${NC}"
else
    echo -e "Shlink Server Local: ${RED}Not Exposed to Host${NC}"
fi
if [ "$UI_HOST_PORT" != "N/A" ]; then
    echo -e "Shlink Web UI Local: ${YELLOW}http://localhost:${UI_HOST_PORT}${NC}"
else
    echo -e "Shlink Web UI Local: ${RED}Not Exposed to Host${NC}"
fi
echo -e "Shlink Web UI URL:   ${GREEN}${SHLINK_UI_URL}${NC}"
if [ "$DB_DRIVER" == "postgres" ]; then
    echo -e "PostgreSQL Database: ${GREEN}${DB_NAME}${NC}"
    echo -e "PostgreSQL User:     ${GREEN}${DB_USER}${NC}"
    echo -e "PostgreSQL Password: ${GREEN}${DB_PASS}${NC}"
    if [[ "$PG_HOST_PORT" != "N/A" ]]; then
        echo -e "PostgreSQL Local:    ${YELLOW}localhost:${PG_HOST_PORT}${NC}"
    fi
fi

echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
echo -e "To configure access via Cloudflare Zero Trust Tunnels (if using external network):"
echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
echo -e "  2. Edit the active Tunnel servicing this network."
echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
echo -e "     - Subdomain/Domain: ${GREEN}${DEFAULT_DOMAIN}${NC}"
echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
echo -e "     - URL:              ${YELLOW}http://shlink-server:8080${NC} (Internal Docker DNS)"
if [ -n "$CLOUDFLARE_NET" ]; then
    echo -e "  4. (Optional) For the Web Client UI, add another public hostname (e.g. shlink-ui.example.com):"
    echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
    echo -e "     - URL:              ${YELLOW}http://shlink-web-client:8080${NC} (Internal Docker DNS)"
fi
echo -e "  5. Save Hostname. Cloudflare will route traffic securely."

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Containers:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Containers:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
