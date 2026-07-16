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
    echo -e "${BLUE}=== Postgres 16 Alpine & PostgREST Auto-Setup ===${NC}\n"
}

# --- Getopts Argument Parsing ---
NON_INTERACTIVE=false
TARGET_DIR=""
DB_NAME_VAL=""
DB_USER_VAL=""
DB_PASS_VAL=""
PG_PORT_VAL=""
PGRST_PORT_VAL=""
ADMINER_PORT_VAL=""
PGRST_SCHEMA_VAL=""
PGRST_ANON_ROLE_VAL=""
SUBDOMAIN=""
ADMINER_SUBDOMAIN=""
CLOUDFLARE_NET_VAL=""
DEPLOY_CONFIRM_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h             Show this help message"
    echo "  -y             Run non-interactively (use defaults)"
    echo "  -d DIR         Target deployment directory"
    echo "  -n DB_NAME     Postgres database name"
    echo "  -u DB_USER     Postgres database user"
    echo "  -p DB_PASS     Postgres database password"
    echo "  -g PG_PORT     Postgres host port (or 'none')"
    echo "  -r PGRST_PORT  PostgREST host port (or 'none')"
    echo "  -a ADMIN_PORT  Adminer host port (or 'none')"
    echo "  -s SCHEMA      PostgREST schema (e.g. public)"
    echo "  -l ROLE        PostgREST anonymous role (e.g. anon)"
    echo "  -k SUBDOMAIN   PostgREST API subdomain (required)"
    echo "  -m ADMIN_SUB   Adminer subdomain (optional)"
    echo "  -e NET_NAME    Cloudflare external docker network (or 'none')"
    echo "  -o DEPLOY_CONF Deploy containers automatically (y/n)"
}

while getopts "hyd:n:u:p:g:r:a:s:l:k:m:e:o:" opt; do
    case "$opt" in
        h) print_help; exit 0 ;;
        y) NON_INTERACTIVE=true ;;
        d) TARGET_DIR="$OPTARG" ;;
        n) DB_NAME_VAL="$OPTARG" ;;
        u) DB_USER_VAL="$OPTARG" ;;
        p) DB_PASS_VAL="$OPTARG" ;;
        g) PG_PORT_VAL="$OPTARG" ;;
        r) PGRST_PORT_VAL="$OPTARG" ;;
        a) ADMINER_PORT_VAL="$OPTARG" ;;
        s) PGRST_SCHEMA_VAL="$OPTARG" ;;
        l) PGRST_ANON_ROLE_VAL="$OPTARG" ;;
        k) SUBDOMAIN="$OPTARG" ;;
        m) ADMINER_SUBDOMAIN="$OPTARG" ;;
        e) CLOUDFLARE_NET_VAL="$OPTARG" ;;
        o) DEPLOY_CONFIRM_VAL="$OPTARG" ;;
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

    # 2. Gather Configuration Settings
    echo -e "\n${BLUE}>>> Step 1: Database Settings${NC}"
    DB_NAME=${DB_NAME_VAL:-""}
    if [ -z "$DB_NAME" ]; then
        prompt_input "Enter Database Name" "app_db" DB_NAME
    fi

    DB_USER=${DB_USER_VAL:-""}
    if [ -z "$DB_USER" ]; then
        prompt_input "Enter Database User" "db_user" DB_USER
    fi

    RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "pg_secure_password")
    DB_PASS=${DB_PASS_VAL:-""}
    if [ -z "$DB_PASS" ]; then
        prompt_input "Enter Database Password" "$RANDOM_PASS" DB_PASS
    fi

    echo -e "\n${BLUE}>>> Step 2: Port Exposure${NC}"
    
    # Postgres Port
    PG_PORT_MAPPING_BLOCK="# Ports not exposed"
    PG_HOST_PORT="N/A"
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

    # PostgREST Port
    PGRST_PORT_MAPPING_BLOCK="# Ports not exposed"
    PGRST_HOST_PORT="N/A"
    if [ -z "$PGRST_PORT_VAL" ]; then
        prompt_yes_no "Expose PostgREST API port (3000) to the host system?" "y" EXPOSE_PGRST
        if [[ "$EXPOSE_PGRST" =~ ^[Yy]$ ]]; then
            while true; do
                prompt_input "Enter host port for PostgREST API" "3000" PGRST_HOST_PORT
                if validate_port "$PGRST_HOST_PORT"; then
                    break
                fi
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            PGRST_PORT_MAPPING_BLOCK="ports:
      - ${PGRST_HOST_PORT}:3000"
        fi
    else
        if [ "$PGRST_PORT_VAL" != "none" ] && [ "$PGRST_PORT_VAL" != "false" ]; then
            PGRST_HOST_PORT="$PGRST_PORT_VAL"
            if ! validate_port "$PGRST_HOST_PORT" && [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            PGRST_PORT_MAPPING_BLOCK="ports:
      - ${PGRST_HOST_PORT}:3000"
        fi
    fi

    # Adminer Port
    ADMINER_PORT_MAPPING_BLOCK="# Ports not exposed"
    ADMINER_HOST_PORT="N/A"
    if [ -z "$ADMINER_PORT_VAL" ]; then
        prompt_yes_no "Expose Adminer port (8080) to the host system?" "y" EXPOSE_ADMINER
        if [[ "$EXPOSE_ADMINER" =~ ^[Yy]$ ]]; then
            while true; do
                prompt_input "Enter host port for Adminer" "8080" ADMINER_HOST_PORT
                if validate_port "$ADMINER_HOST_PORT"; then
                    break
                fi
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            ADMINER_PORT_MAPPING_BLOCK="ports:
      - ${ADMINER_HOST_PORT}:8080"
        fi
    else
        if [ "$ADMINER_PORT_VAL" != "none" ] && [ "$ADMINER_PORT_VAL" != "false" ]; then
            ADMINER_HOST_PORT="$ADMINER_PORT_VAL"
            if ! validate_port "$ADMINER_HOST_PORT" && [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            ADMINER_PORT_MAPPING_BLOCK="ports:
      - ${ADMINER_HOST_PORT}:8080"
        fi
    fi

    echo -e "\n${BLUE}>>> Step 3: PostgREST Settings${NC}"
    PGRST_SCHEMA=${PGRST_SCHEMA_VAL:-""}
    if [ -z "$PGRST_SCHEMA" ]; then
        prompt_input "Enter PostgREST Schema" "public" PGRST_SCHEMA
    fi

    PGRST_ANON_ROLE=${PGRST_ANON_ROLE_VAL:-""}
    if [ -z "$PGRST_ANON_ROLE" ]; then
        prompt_input "Enter PostgREST Anonymous Role" "anon" PGRST_ANON_ROLE
    fi

    echo -e "\n${BLUE}>>> Step 4: Configure Cloudflare Subdomain & Network${NC}"
    if [ -z "$SUBDOMAIN" ]; then
        while true; do
            if [ "$NON_INTERACTIVE" = "true" ]; then
                log_error "Subdomain is required in non-interactive mode."
                exit 1
            fi
            read -rp "Enter subdomain for PostgREST API (e.g. api.example.com): " SUBDOMAIN
            if [ -n "$SUBDOMAIN" ]; then
                break
            fi
            log_error "Subdomain cannot be empty."
        done
    fi

    if [ -z "$ADMINER_SUBDOMAIN" ] && [ "$NON_INTERACTIVE" = "false" ]; then
        prompt_input "Enter subdomain for Adminer (e.g. db.example.com) [Skip]" "Skip" ADMINER_SUBDOMAIN
    else
        ADMINER_SUBDOMAIN=${ADMINER_SUBDOMAIN:-"Skip"}
    fi

    CLOUDFLARE_NET=""
    if [ -z "$CLOUDFLARE_NET_VAL" ]; then
        log_info "Detecting active Docker networks on host..."
        if docker network ls >/dev/null 2>&1; then
            echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
            docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
            echo ""
        fi
        prompt_input "Enter the name of your Cloudflare docker network" "proxy-net" CLOUDFLARE_NET
        
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
    else
        if [ "$CLOUDFLARE_NET_VAL" != "none" ] && [ "$CLOUDFLARE_NET_VAL" != "false" ]; then
            CLOUDFLARE_NET="$CLOUDFLARE_NET_VAL"
            if ! docker network inspect "$CLOUDFLARE_NET" >/dev/null 2>&1; then
                log_info "Creating external network $CLOUDFLARE_NET as specified by options..."
                docker network create "$CLOUDFLARE_NET"
            fi
        fi
    fi

    # 3. Create Folder and Configuration Files
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$(pwd)/postgres-postgrest"
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
      PGRST_DB_URI: postgres://\${POSTGRES_USER}:\\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
      PGRST_DB_SCHEMA: \${PGRST_DB_SCHEMA}
      PGRST_DB_ANON_ROLE: \${PGRST_DB_ANON_ROLE}
    depends_on:
      - postgres
    ${PGRST_PORT_MAPPING_BLOCK}
    networks:
      - ${CLOUDFLARE_NET}

  adminer:
    image: adminer:4.11.0
    container_name: adminer
    restart: unless-stopped
    depends_on:
      - postgres
    ${ADMINER_PORT_MAPPING_BLOCK}
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

    DEPLOY_CONFIRM="y"
    if [ -z "$DEPLOY_CONFIRM_VAL" ]; then
        prompt_yes_no "Deploy the Postgres & PostgREST containers now?" "y" DEPLOY_CONFIRM
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
        verify_container_health "postgres" "$PG_HOST_PORT"
        verify_container_health "postgrest" "$PGRST_HOST_PORT"
        verify_container_health "adminer" "$ADMINER_HOST_PORT"
    else
        log_warning "Deployment skipped by user."
    fi

    # Print Summary Box
    local HOST_IP
    HOST_IP=$(detect_ip)
    
    local pg_access_str="No ports exposed"
    if [[ "$PG_HOST_PORT" != "N/A" ]]; then
        pg_access_str="localhost:${PG_HOST_PORT} (IP: ${HOST_IP}:${PG_HOST_PORT})"
    fi
    local pgrst_access_str="No ports exposed"
    if [[ "$PGRST_HOST_PORT" != "N/A" ]]; then
        pgrst_access_str="http://localhost:${PGRST_HOST_PORT} (IP: http://${HOST_IP}:${PGRST_HOST_PORT})"
    fi
    local admin_access_str="No ports exposed"
    if [[ "$ADMINER_HOST_PORT" != "N/A" ]]; then
        admin_access_str="http://localhost:${ADMINER_HOST_PORT} (IP: http://${HOST_IP}:${ADMINER_HOST_PORT})"
    fi

    echo -e "\n"
    box_message "Deployment Summary" \
        "PostgreSQL Database: ${DB_NAME}" \
        "PostgreSQL User:     ${DB_USER}" \
        "PostgreSQL Password: ${DB_PASS}" \
        "PostgreSQL Local:    ${pg_access_str}" \
        "PostgREST API Local: ${pgrst_access_str}" \
        "Adminer Local:       ${admin_access_str}" \
        "Install Directory:   ${TARGET_DIR}"

    # Cloudflare Integration
    echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
    echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
    echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
    echo -e "  2. Edit the active Tunnel servicing this network."
    echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
    echo -e "     - Subdomain/Domain: ${GREEN}${SUBDOMAIN}${NC}"
    echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
    echo -e "     - URL:              ${YELLOW}http://postgrest:3000${NC} (Internal Docker DNS)"
    if [ -n "$ADMINER_SUBDOMAIN" ] && [ "$ADMINER_SUBDOMAIN" != "Skip" ]; then
        echo -e "  4. Add another public hostname for Adminer:"
        echo -e "     - Subdomain/Domain: ${GREEN}${ADMINER_SUBDOMAIN}${NC}"
        echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
        echo -e "     - URL:              ${YELLOW}http://adminer:8080${NC} (Internal Docker DNS)"
        echo -e "  5. Save Hostnames. Cloudflare will route traffic securely to the API and Adminer."
    else
        echo -e "  4. Save Hostname. Cloudflare will route traffic securely to the API."
    fi

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
