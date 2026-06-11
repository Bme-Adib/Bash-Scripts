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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Postgres 16 Alpine & PostgREST Auto-Setup ===${NC}\n"

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
echo -e "\n${BLUE}>>> Step 1: Database Settings${NC}"
read -rp "Enter Database Name [app_db]: " DB_NAME
DB_NAME=${DB_NAME:-app_db}

read -rp "Enter Database User [db_user]: " DB_USER
DB_USER=${DB_USER:-db_user}

RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "pg_secure_password")
read -rp "Enter Database Password [$RANDOM_PASS]: " DB_PASS
DB_PASS=${DB_PASS:-$RANDOM_PASS}

echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"
# Postgres Port
read -rp "Expose PostgreSQL port (5432) to the host system? (y/n) [n]: " EXPOSE_PG
EXPOSE_PG=${EXPOSE_PG:-n}
PG_PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # Change the port number before the colon (5432) to whatever port you want.
    # ports:
    #   - 5432:5432"
PG_HOST_PORT="N/A"
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

# PostgREST Port
read -rp "Expose PostgREST API port (3000) to the host system? (y/n) [y]: " EXPOSE_PGRST
EXPOSE_PGRST=${EXPOSE_PGRST:-y}
PGRST_PORT_MAPPING_BLOCK="# To expose the port to the host system, uncomment the lines below.
    # Change the port number before the colon (3000) to whatever port you want.
    # ports:
    #   - 3000:3000"
PGRST_HOST_PORT="N/A"
if [[ "$EXPOSE_PGRST" =~ ^[Yy]$ ]]; then
    while true; do
        read -rp "Enter host port for PostgREST API [3000]: " PGRST_HOST_PORT
        PGRST_HOST_PORT=${PGRST_HOST_PORT:-3000}
        if validate_port "$PGRST_HOST_PORT"; then
            break
        fi
    done
    PGRST_PORT_MAPPING_BLOCK="ports:
      - ${PGRST_HOST_PORT}:3000"
fi

echo -e "\n${BLUE}>>> Step 3: PostgREST Settings${NC}"
read -rp "Enter PostgREST Schema [public]: " PGRST_SCHEMA
PGRST_SCHEMA=${PGRST_SCHEMA:-public}

read -rp "Enter PostgREST Anonymous Role [anon]: " PGRST_ANON_ROLE
PGRST_ANON_ROLE=${PGRST_ANON_ROLE:-anon}

echo -e "\n${BLUE}>>> Step 4: Configure Cloudflare Subdomain & Network${NC}"
read -rp "Enter subdomain for PostgREST API (e.g. api.example.com): " SUBDOMAIN
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
TARGET_DIR="$(pwd)/postgres-postgrest"
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

# Write init.sql for Postgres setup
cat <<EOF > "${TARGET_DIR}/init.sql"
-- Automatically generated initialization script for PostgREST
CREATE ROLE ${PGRST_ANON_ROLE} NOLOGIN;
GRANT ${PGRST_ANON_ROLE} TO ${DB_USER};
EOF
log_success "Created initialization script: ${TARGET_DIR}/init.sql"

# Write .env file
cat <<EOF > "${TARGET_DIR}/.env"
POSTGRES_DB=${DB_NAME}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASS}
PGRST_DB_SCHEMA=${PGRST_SCHEMA}
PGRST_DB_ANON_ROLE=${PGRST_ANON_ROLE}
EOF
log_success "Created env config: ${TARGET_DIR}/.env"

# Write docker-compose.yml
cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - ./data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    ${PG_PORT_MAPPING_BLOCK}
    networks:
      - ${CLOUDFLARE_NET}

  postgrest:
    image: postgrest/postgrest:v12.0.2
    container_name: postgrest
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
      PGRST_DB_SCHEMA: \${PGRST_DB_SCHEMA}
      PGRST_DB_ANON_ROLE: \${PGRST_DB_ANON_ROLE}
    depends_on:
      - postgres
    ${PGRST_PORT_MAPPING_BLOCK}
    networks:
      - ${CLOUDFLARE_NET}

networks:
  ${CLOUDFLARE_NET}:
    external: true
EOF
log_success "Created: ${TARGET_DIR}/docker-compose.yml"

# 4. Show Compose file configuration
echo -e "\n${BLUE}>>> Step 5: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Postgres & PostgREST containers now? (y/n) [y]: " DEPLOY_CONFIRM
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
echo -e "PostgreSQL Database: ${GREEN}${DB_NAME}${NC}"
echo -e "PostgreSQL User:     ${GREEN}${DB_USER}${NC}"
echo -e "PostgreSQL Password: ${GREEN}${DB_PASS}${NC}"
if [[ "$PG_HOST_PORT" != "N/A" ]]; then
    echo -e "PostgreSQL Local:    ${YELLOW}localhost:${PG_HOST_PORT}${NC}"
fi
if [[ "$PGRST_HOST_PORT" != "N/A" ]]; then
    echo -e "PostgREST API Local: ${YELLOW}http://localhost:${PGRST_HOST_PORT}${NC}"
fi

echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
echo -e "  2. Edit the active Tunnel servicing this network."
echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
echo -e "     - Subdomain/Domain: ${GREEN}${SUBDOMAIN}${NC}"
echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
echo -e "     - URL:              ${YELLOW}http://postgrest:3000${NC} (Internal Docker DNS)"
echo -e "  4. Save Hostname. Cloudflare will route traffic securely to the API."

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Shutdown Containers:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Restart Containers:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
echo -e "============================================================\n"
