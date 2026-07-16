#!/bin/bash
# --- Robust Safety & Error Handling ---
set -euo pipefail

# --- Redirect stdin to tty if piped ---
if [ ! -t 0 ]; then
    exec 0</dev/tty
fi

# --- Lock File (Single Instance) ---
LOCK_FILE="/tmp/$(basename "$0").lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo -e "\033[0;31m[ERROR]\033[0m Another instance of this script is running." >&2
    exit 1
fi

# --- Color Codes for UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Styled Log Helpers ---
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Traps & Cleanup ---
TEMP_DIR=""
cleanup() {
    tput cnorm 2>/dev/null || printf "\033[?25h" # Restore cursor
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    flock -u 9 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT SIGINT SIGTERM

# --- UI Components ---
show_spinner() {
    local pid=$1
    tput civis 2>/dev/null || printf "\033[?25l"
    while kill -0 "$pid" 2>/dev/null; do
        printf " [|] \b\b\b\b\b" && sleep 0.05
        printf " [/] \b\b\b\b\b" && sleep 0.05
        printf " [-] \b\b\b\b\b" && sleep 0.05
        printf " [\\] \b\b\b\b\b" && sleep 0.05
    done
    tput cnorm 2>/dev/null || printf "\033[?25h"
    printf "    \b\b\b\b"
}

box_message() {
    local title="$1"
    shift
    local lines=("$@")
    local max_len=${#title}
    for line in "${lines[@]}"; do
        [ ${#line} -gt $max_len ] && max_len=${#line}
    done
    local width=$((max_len + 4))
    
    printf "${GREEN}┌"
    for ((i=0; i<width; i++)); do printf "─"; done
    printf "┐${NC}\n"
    printf "${GREEN}│${NC}  ${BLUE}%-${max_len}s${NC}  ${GREEN}│${NC}\n" "$title"
    printf "${GREEN}├"
    for ((i=0; i<width; i++)); do printf "─"; done
    printf "┤${NC}\n"
    for line in "${lines[@]}"; do
        printf "${GREEN}│${NC}  %-${max_len}s  ${GREEN}│${NC}\n" "$line"
    done
    printf "${GREEN}└"
    for ((i=0; i<width; i++)); do printf "─"; done
    printf "┘${NC}\n"
}

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

detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

detect_ip() {
    local iface
    iface=$(detect_interface)
    ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "127.0.0.1"
}

verify_container_health() {
    local container_name=$1
    local port=${2:-}
    log_info "Verifying health of container '${container_name}'..."
    local success=false
    for i in {1..15}; do
        if [ "$(docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null)" = "true" ]; then
            if [ -n "$port" ] && [ "$port" != "N/A" ]; then
                if curl -sSf "http://localhost:${port}" &>/dev/null; then
                    success=true
                    break
                fi
            else
                success=true
                break
            fi
        fi
        sleep 1
    done
    if [ "$success" = "true" ]; then
        log_success "Container '${container_name}' is healthy and running!"
        return 0
    else
        log_warning "Container '${container_name}' health check failed or timed out."
        return 1
    fi
}

prompt_input() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        eval "$var_name=\"\$default_val\""
    else
        read -rp "$prompt_text [$default_val]: " user_val
        user_val=${user_val:-$default_val}
        eval "$var_name=\"\$user_val\""
    fi
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        eval "$var_name=\"\$default_val\""
    else
        read -rp "$prompt_text (y/n) [$default_val]: " user_val
        user_val=${user_val:-$default_val}
        eval "$var_name=\"\$user_val\""
    fi
}

# --- Header ---
show_header() {
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Shlink Server & Shlink UI Auto-Setup ===${NC}\n"
}

# --- Getopts Argument Parsing ---
NON_INTERACTIVE=false
TARGET_DIR=""
DEFAULT_DOMAIN_VAL=""
HTTPS_VAL=""
GEOLITE_VAL=""
API_KEY_VAL=""
SERVER_PORT_VAL=""
UI_PORT_VAL=""
DB_DRIVER_VAL=""
DB_NAME_VAL=""
DB_USER_VAL=""
DB_PASS_VAL=""
PG_PORT_VAL=""
SHLINK_SERVER_URL_VAL=""
SHLINK_SERVER_NAME_VAL=""
SHLINK_UI_URL_VAL=""
USE_EXT_NET_VAL=""
CLOUDFLARE_NET_VAL=""
DEPLOY_CONFIRM_VAL=""
CONTAINER_NAME_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h             Show this help message"
    echo "  -y             Run non-interactively (use defaults)"
    echo "  -d DIR         Target deployment directory"
    echo "  -m DOMAIN      Default domain for short URLs"
    echo "  -s SSL_BOOL    HTTPS enabled (y/n)"
    echo "  -g GEOLITE     GeoLite2 License Key"
    echo "  -k API_KEY     Initial API Key"
    echo "  -a SRV_PORT    Shlink Server host port (or 'none')"
    echo "  -b UI_PORT     Shlink Web UI host port (or 'none')"
    echo "  -r DRIVER      Database driver (sqlite/postgres)"
    echo "  -n DB_NAME     Postgres database name"
    echo "  -u DB_USER     Postgres database user"
    echo "  -p DB_PASS     Postgres database password"
    echo "  -f PG_PORT     Postgres host port (or 'none')"
    echo "  -l SRV_URL     Shlink Server URL"
    echo "  -e SRV_NAME    Shlink Server Display Name in UI"
    echo "  -w UI_URL      Shlink Web UI Access URL"
    echo "  -t NET_NAME    Cloudflare external docker network (or 'none')"
    echo "  -o DEPLOY_CONF Deploy containers automatically (y/n)"
    echo "  -c NAME        Shlink container name (or 'shlink-server')"
}

while getopts "hyd:m:s:g:k:a:b:r:n:u:p:f:l:e:w:t:o:c:" opt; do
    case "$opt" in
        h) print_help; exit 0 ;;
        y) NON_INTERACTIVE=true ;;
        d) TARGET_DIR="$OPTARG" ;;
        m) DEFAULT_DOMAIN_VAL="$OPTARG" ;;
        s) HTTPS_VAL="$OPTARG" ;;
        g) GEOLITE_VAL="$OPTARG" ;;
        k) API_KEY_VAL="$OPTARG" ;;
        a) SERVER_PORT_VAL="$OPTARG" ;;
        b) UI_PORT_VAL="$OPTARG" ;;
        r) DB_DRIVER_VAL="$OPTARG" ;;
        n) DB_NAME_VAL="$OPTARG" ;;
        u) DB_USER_VAL="$OPTARG" ;;
        p) DB_PASS_VAL="$OPTARG" ;;
        f) PG_PORT_VAL="$OPTARG" ;;
        l) SHLINK_SERVER_URL_VAL="$OPTARG" ;;
        e) SHLINK_SERVER_NAME_VAL="$OPTARG" ;;
        w) SHLINK_UI_URL_VAL="$OPTARG" ;;
        t) CLOUDFLARE_NET_VAL="$OPTARG" ;;
        o) DEPLOY_CONFIRM_VAL="$OPTARG" ;;
        c) CONTAINER_NAME_VAL="$OPTARG" ;;
        *) print_help; exit 1 ;;
    esac
done

main() {
    show_header

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

    # 2. Setup directory
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$(pwd)/shlink-deployment"
    fi

    # Read defaults from existing setup if available
    local EXISTING_CONTAINER=""
    if [ -f "${TARGET_DIR}/.env" ]; then
        EXISTING_CONTAINER=$(grep -E "^SHLINK_CONTAINER_NAME=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
    fi
    local active_container="${EXISTING_CONTAINER:-shlink-server}"
    if docker ps --format '{{.Names}}' | grep -q "^${active_container}$"; then
        ACTIVE_KEY=$(docker exec "${active_container}" shlink api-key:list 2>/dev/null | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1 || true)
        if [ -n "$ACTIVE_KEY" ]; then
            EXISTING_API_KEY="$ACTIVE_KEY"
        fi
    fi

    if [ -f "${TARGET_DIR}/.env" ]; then
        if [ -z "$EXISTING_API_KEY" ]; then
            EXISTING_API_KEY=$(grep -E "^INITIAL_API_KEY=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
        fi
        EXISTING_DOMAIN=$(grep -E "^DEFAULT_DOMAIN=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
        EXISTING_GEOLITE=$(grep -E "^GEOLITE_LICENSE_KEY=" "${TARGET_DIR}/.env" | cut -d'=' -f2- || true)
    fi

    echo -e "\n${BLUE}>>> Step 1: Shlink Server General Settings${NC}"
    
    SHLINK_CONTAINER_NAME=${CONTAINER_NAME_VAL:-""}
    if [ -z "$SHLINK_CONTAINER_NAME" ]; then
        prompt_input "Enter Shlink container name" "${EXISTING_CONTAINER:-shlink-server}" SHLINK_CONTAINER_NAME
    fi

    DEFAULT_DOMAIN=${DEFAULT_DOMAIN_VAL:-""}
    if [ -z "$DEFAULT_DOMAIN" ]; then
        DEFAULT_DOMAIN_SUGGESTION=${EXISTING_DOMAIN:-s.example.com}
        prompt_input "Enter Default Domain for short URLs" "$DEFAULT_DOMAIN_SUGGESTION" DEFAULT_DOMAIN
    fi

    HTTPS_INPUT=${HTTPS_VAL:-""}
    if [ -z "$HTTPS_INPUT" ]; then
        prompt_yes_no "Is HTTPS enabled for Shlink Server?" "y" HTTPS_INPUT
    fi

    if [[ "$HTTPS_INPUT" =~ ^[Yy]$ || "$HTTPS_INPUT" = "true" ]]; then
        IS_HTTPS_ENABLED="true"
        SCHEME="https"
    else
        IS_HTTPS_ENABLED="false"
        SCHEME="http"
    fi

    GEOLITE_LICENSE_KEY=${GEOLITE_VAL:-""}
    if [ -z "$GEOLITE_VAL" ] && [ "$NON_INTERACTIVE" = "false" ]; then
        GEOLITE_SUGGESTION=${EXISTING_GEOLITE:-}
        if [ -n "$GEOLITE_SUGGESTION" ]; then
            read -rp "Enter GeoLite2 License Key (optional) [$GEOLITE_SUGGESTION]: " GEOLITE_LICENSE_KEY
            GEOLITE_LICENSE_KEY=${GEOLITE_LICENSE_KEY:-$GEOLITE_SUGGESTION}
        else
            read -rp "Enter GeoLite2 License Key (optional, press Enter to skip): " GEOLITE_LICENSE_KEY
            GEOLITE_LICENSE_KEY=${GEOLITE_LICENSE_KEY:-}
        fi
    fi

    INITIAL_API_KEY=${API_KEY_VAL:-""}
    if [ -z "$INITIAL_API_KEY" ]; then
        if [ -n "$EXISTING_API_KEY" ]; then
            RANDOM_API_KEY="$EXISTING_API_KEY"
        else
            RANDOM_API_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 32 || echo "shlink_secure_api_key_32_chars_long")
        fi
        prompt_input "Enter Initial API Key" "$RANDOM_API_KEY" INITIAL_API_KEY
    fi

    echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"
    
    # Shlink Server Port
    SERVER_PORT_MAPPING_BLOCK="# Ports not exposed"
    SERVER_HOST_PORT="N/A"
    if [ -z "$SERVER_PORT_VAL" ]; then
        prompt_yes_no "Expose Shlink Server port (8080) to the host system?" "n" EXPOSE_SERVER
        if [[ "$EXPOSE_SERVER" =~ ^[Yy]$ ]]; then
            while true; do
                prompt_input "Enter host port for Shlink Server" "8080" SERVER_HOST_PORT
                if validate_port "$SERVER_HOST_PORT"; then
                    break
                fi
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            SERVER_PORT_MAPPING_BLOCK="ports:
      - ${SERVER_HOST_PORT}:8080"
        fi
    else
        if [ "$SERVER_PORT_VAL" != "none" ] && [ "$SERVER_PORT_VAL" != "false" ]; then
            SERVER_HOST_PORT="$SERVER_PORT_VAL"
            if ! validate_port "$SERVER_HOST_PORT" && [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            SERVER_PORT_MAPPING_BLOCK="ports:
      - ${SERVER_HOST_PORT}:8080"
        fi
    fi

    # Shlink Web UI Port
    UI_PORT_MAPPING_BLOCK="# Ports not exposed"
    UI_HOST_PORT="N/A"
    if [ -z "$UI_PORT_VAL" ]; then
        prompt_yes_no "Expose Shlink Web UI port (8000) to the host system?" "n" EXPOSE_UI
        if [[ "$EXPOSE_UI" =~ ^[Yy]$ ]]; then
            while true; do
                prompt_input "Enter host port for Shlink Web UI" "8000" UI_HOST_PORT
                if validate_port "$UI_HOST_PORT"; then
                    break
                fi
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            UI_PORT_MAPPING_BLOCK="ports:
      - ${UI_HOST_PORT}:8080"
        fi
    else
        if [ "$UI_PORT_VAL" != "none" ] && [ "$UI_PORT_VAL" != "false" ]; then
            UI_HOST_PORT="$UI_PORT_VAL"
            if ! validate_port "$UI_HOST_PORT" && [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            UI_PORT_MAPPING_BLOCK="ports:
      - ${UI_HOST_PORT}:8080"
        fi
    fi

    echo -e "\n${BLUE}>>> Step 3: Database Configuration${NC}"
    DB_DRIVER=${DB_DRIVER_VAL:-""}
    if [ -z "$DB_DRIVER" ]; then
        while true; do
            prompt_input "Choose Database Driver (sqlite/postgres)" "sqlite" DB_DRIVER
            if [[ "$DB_DRIVER" == "sqlite" || "$DB_DRIVER" == "postgres" ]]; then
                break
            fi
            log_error "Invalid driver. Please enter 'sqlite' or 'postgres'."
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
    fi

    DB_NAME="shlink"
    DB_USER="shlink"
    DB_PASS=""
    PG_PORT_MAPPING_BLOCK=""
    PG_HOST_PORT="N/A"

    if [ "$DB_DRIVER" == "postgres" ]; then
        DB_NAME=${DB_NAME_VAL:-"shlink"}
        if [ -z "$DB_NAME_VAL" ]; then
            prompt_input "Enter Database Name" "shlink" DB_NAME
        fi

        DB_USER=${DB_USER_VAL:-"shlink"}
        if [ -z "$DB_USER_VAL" ]; then
            prompt_input "Enter Database User" "shlink" DB_USER
        fi

        RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "shlink_secure_db_pass")
        DB_PASS=${DB_PASS_VAL:-""}
        if [ -z "$DB_PASS" ]; then
            prompt_input "Enter Database Password" "$RANDOM_PASS" DB_PASS
        fi

        if [ -z "$PG_PORT_VAL" ]; then
            prompt_yes_no "Expose PostgreSQL port (5432) to the host system?" "n" EXPOSE_PG
            if [[ "$EXPOSE_PG" =~ ^[Yy]$ ]]; then
                while true; do
                    prompt_input "Enter host port for PostgreSQL" "5432" PG_HOST_PORT
                    if validate_port "$PG_HOST_PORT"; then
                        break
                    fi
                    if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
                done
                PG_PORT_MAPPING_BLOCK="ports:
      - ${PG_HOST_PORT}:5432"
            fi
        else
            if [ "$PG_PORT_VAL" != "none" ] && [ "$PG_PORT_VAL" != "false" ]; then
                PG_HOST_PORT="$PG_PORT_VAL"
                if ! validate_port "$PG_HOST_PORT" && [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
                PG_PORT_MAPPING_BLOCK="ports:
      - ${PG_HOST_PORT}:5432"
            fi
        fi
    fi

    echo -e "\n${BLUE}>>> Step 4: Shlink Web Client (UI) Connection Settings${NC}"
    
    SHLINK_SERVER_URL=${SHLINK_SERVER_URL_VAL:-""}
    if [ -z "$SHLINK_SERVER_URL" ]; then
        SUGGESTED_SERVER_URL="${SCHEME}://${DEFAULT_DOMAIN}"
        if [[ "$DEFAULT_DOMAIN" == "localhost" || "$DEFAULT_DOMAIN" == "127.0.0.1" ]]; then
            if [ "$SERVER_HOST_PORT" != "N/A" ]; then
                SUGGESTED_SERVER_URL="http://localhost:${SERVER_HOST_PORT}"
            else
                SUGGESTED_SERVER_URL="http://localhost:8080"
            fi
        fi
        prompt_input "Enter Shlink Server URL" "$SUGGESTED_SERVER_URL" SHLINK_SERVER_URL
    fi

    SHLINK_SERVER_NAME=${SHLINK_SERVER_NAME_VAL:-""}
    if [ -z "$SHLINK_SERVER_NAME" ]; then
        prompt_input "Enter Shlink Server Display Name in UI" "Local Shlink" SHLINK_SERVER_NAME
    fi

    SHLINK_UI_URL=${SHLINK_UI_URL_VAL:-""}
    if [ -z "$SHLINK_UI_URL" ]; then
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
        prompt_input "Enter Shlink Web UI Access URL" "$SUGGESTED_UI_URL" SHLINK_UI_URL
    fi

    echo -e "\n${BLUE}>>> Step 5: Network Settings${NC}"
    CLOUDFLARE_NET=""
    if [ -z "$CLOUDFLARE_NET_VAL" ]; then
        prompt_yes_no "Do you want to connect to an external Docker network (e.g. Cloudflare proxy-net)?" "y" USE_EXT_NET
        if [[ "$USE_EXT_NET" =~ ^[Yy]$ ]]; then
            log_info "Detecting active Docker networks on host..."
            if docker network ls >/dev/null 2>&1; then
                echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
                docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
                echo ""
            fi
            prompt_input "Enter the name of your external docker network" "proxy-net" CLOUDFLARE_NET
            
            if ! docker network inspect "$CLOUDFLARE_NET" >/dev/null 2>&1; then
                log_warning "Docker network '${CLOUDFLARE_NET}' does not exist."
                prompt_yes_no "Would you like to create the '${CLOUDFLARE_NET}' network now?" "y" CREATE_NET
                if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
                    docker network create "$CLOUDFLARE_NET"
                    log_success "Created external docker network: ${CLOUDFLARE_NET}"
                else
                    log_warning "Skipping network creation. Docker compose may fail if it is missing."
                fi
            fi
        fi
    else
        if [ "$CLOUDFLARE_NET_VAL" != "none" ] && [ "$CLOUDFLARE_NET_VAL" != "false" ]; then
            CLOUDFLARE_NET="$CLOUDFLARE_NET_VAL"
            if ! docker network inspect "$CLOUDFLARE_NET" >/dev/null 2>&1; then
                log_info "Creating external network $CLOUDFLARE_NET as specified by options..."
                docker network create "$CLOUDFLARE_NET"
            fi
        fi
    fi

    log_info "Creating deployment directory at: ${TARGET_DIR}"
    if [ -d "$TARGET_DIR" ]; then
        log_warning "Directory ${TARGET_DIR} already exists."
        prompt_yes_no "Would you like to overwrite it?" "n" OVERWRITE_DIR
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
SHLINK_CONTAINER_NAME=${SHLINK_CONTAINER_NAME}
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

    # Write docker-compose.yml
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

    DEPLOY_CONFIRM="y"
    if [ -z "$DEPLOY_CONFIRM_VAL" ]; then
        prompt_yes_no "Deploy the Shlink containers now?" "y" DEPLOY_CONFIRM
    else
        DEPLOY_CONFIRM="$DEPLOY_CONFIRM_VAL"
    fi

    if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ || "$DEPLOY_CONFIRM" = "true" ]]; then
        log_info "Deploying containers..."
        local_log=$(mktemp)
        (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d) >"$local_log" 2>&1 &
        show_spinner $!
        if ! wait $!; then
            log_error "Deployment failed! Output:"
            cat "$local_log"
            rm -f "$local_log"
            exit 1
        fi
        rm -f "$local_log"
        
        # Verify Service Health
        if [ "$DB_DRIVER" == "postgres" ]; then
            verify_container_health "${SHLINK_CONTAINER_NAME}-db" "$PG_HOST_PORT"
        fi
        verify_container_health "${SHLINK_CONTAINER_NAME}" "$SERVER_HOST_PORT"
        verify_container_health "${SHLINK_CONTAINER_NAME}-ui" "$UI_HOST_PORT"
    else
        log_warning "Deployment skipped by user."
    fi

    # Print Summary Box
    local HOST_IP
    HOST_IP=$(detect_ip)
    
    local srv_access_str="No ports exposed"
    if [[ "$SERVER_HOST_PORT" != "N/A" ]]; then
        srv_access_str="http://localhost:${SERVER_HOST_PORT} (IP: http://${HOST_IP}:${SERVER_HOST_PORT})"
    fi
    local ui_access_str="No ports exposed"
    if [[ "$UI_HOST_PORT" != "N/A" ]]; then
        ui_access_str="http://localhost:${UI_HOST_PORT} (IP: http://${HOST_IP}:${UI_HOST_PORT})"
    fi
    local pg_access_str="No ports exposed"
    if [ "$DB_DRIVER" == "postgres" ] && [[ "$PG_HOST_PORT" != "N/A" ]]; then
        pg_access_str="localhost:${PG_HOST_PORT} (IP: ${HOST_IP}:${PG_HOST_PORT})"
    fi

    echo -e "\n"
    box_message "Deployment Summary" \
        "Default Domain:      ${DEFAULT_DOMAIN}" \
        "Initial API Key:     ${INITIAL_API_KEY}" \
        "Shlink Server Local: ${srv_access_str}" \
        "Shlink Web UI Local: ${ui_access_str}" \
        "Shlink Web UI URL:   ${SHLINK_UI_URL}" \
        "Database Driver:     ${DB_DRIVER}" \
        "PostgreSQL DB/User:  ${DB_NAME}/${DB_USER} (${pg_access_str})" \
        "Install Directory:   ${TARGET_DIR}"

    echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
    echo -e "To configure access via Cloudflare Zero Trust Tunnels (if using external network):"
    echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
    echo -e "  2. Edit the active Tunnel servicing this network."
    echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
    echo -e "     - Subdomain/Domain: ${GREEN}${DEFAULT_DOMAIN}${NC}"
    echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
    echo -e "     - URL:              ${YELLOW}http://${SHLINK_CONTAINER_NAME}:8080${NC} (Internal Docker DNS)"
    if [ -n "$CLOUDFLARE_NET" ]; then
        echo -e "  4. (Optional) For the Web Client UI, add another public hostname (e.g. shlink-ui.example.com):"
        echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
        echo -e "     - URL:              ${YELLOW}http://${SHLINK_CONTAINER_NAME}-ui:8080${NC} (Internal Docker DNS)"
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
}

main "$@"
