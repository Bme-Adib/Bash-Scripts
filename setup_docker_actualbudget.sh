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
    printf "${GREEN}│${NC}  ${BLUE}%-%s${max_len}s${NC}  ${GREEN}│${NC}\n" "$title"
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

validate_numeric() {
    local val="$1"
    local desc="$2"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        log_error "Invalid $desc: '$val'. Must be a numeric value."
        return 1
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
    echo -e "${BLUE}=== Actual Budget Docker Installer & Setup ===${NC}\n"
}

# --- Getopts Argument Parsing ---
NON_INTERACTIVE=false
INSTALL_DIR=""
PORT_VAL=""
ENABLE_SSL_VAL=""
SSL_KEY_VAL=""
SSL_CERT_VAL=""
UPLOAD_LIMIT_VAL=""
ENCRYPTED_LIMIT_VAL=""
CLOUDFLARE_NET_VAL=""
DEPLOY_CONFIRM_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h             Show this help message"
    echo "  -y             Run non-interactively (use defaults)"
    echo "  -d DIR         Installation directory"
    echo "  -p PORT        Exposed host port (or 'none')"
    echo "  -s SSL_BOOL    Enable built-in SSL (y/n)"
    echo "  -k KEY_PATH    SSL private key path"
    echo "  -c CERT_PATH   SSL certificate path"
    echo "  -u LIMIT       Sync file upload limit (MB)"
    echo "  -e LIMIT       Encrypted sync upload limit (MB)"
    echo "  -n NET_NAME    External Docker network name (or 'none')"
    echo "  -o DEPLOY_CONF  Deploy container automatically (y/n)"
}

while getopts "hyd:p:s:k:c:u:e:n:o:" opt; do
    case "$opt" in
        h) print_help; exit 0 ;;
        y) NON_INTERACTIVE=true ;;
        d) INSTALL_DIR="$OPTARG" ;;
        p) PORT_VAL="$OPTARG" ;;
        s) ENABLE_SSL_VAL="$OPTARG" ;;
        k) SSL_KEY_VAL="$OPTARG" ;;
        c) SSL_CERT_VAL="$OPTARG" ;;
        u) UPLOAD_LIMIT_VAL="$OPTARG" ;;
        e) ENCRYPTED_LIMIT_VAL="$OPTARG" ;;
        n) CLOUDFLARE_NET_VAL="$OPTARG" ;;
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
    DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
    DETECTED_UID=$(id -u)
    DETECTED_GID=$(id -g)

    echo -e "\n${BLUE}>>> Step 1: Configure Installation Directory${NC}"
    if [ -z "$INSTALL_DIR" ]; then
        while true; do
            prompt_input "Enter installation directory" "./actualbudget-deployment" INSTALL_DIR
            mkdir -p "$INSTALL_DIR"
            ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
            
            if [ -f "$ABS_INSTALL_DIR/docker-compose.yml" ]; then
                log_warning "A docker-compose.yml already exists in '$ABS_INSTALL_DIR'."
                prompt_yes_no "Would you like to overwrite it?" "n" OVERWRITE
                if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
                    log_info "Please choose a different directory."
                    INSTALL_DIR=""
                    if [ "$NON_INTERACTIVE" = "true" ]; then
                        log_error "Overwrite denied in non-interactive mode. Exiting."
                        exit 1
                    fi
                    continue
                fi
            fi
            break
        done
    else
        mkdir -p "$INSTALL_DIR"
        ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)
    fi

    echo -e "\n${BLUE}>>> Step 2: Configure Port Exposure${NC}"
    PORT_MAPPING_BLOCK=""
    PORT="N/A"
    if [ -z "$PORT_VAL" ]; then
        prompt_yes_no "Would you like to expose the Actual Budget port to the host system?" "y" EXPOSE_PORT
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
            while true; do
                prompt_input "Enter host port to bind to Actual Budget" "5006" PORT
                if validate_port "$PORT"; then
                    break
                fi
                if [ "$NON_INTERACTIVE" = "true" ]; then
                    log_error "Port validation failed in non-interactive mode."
                    exit 1
                fi
            done
            PORT_MAPPING_BLOCK="ports:
      - \"$PORT:5006\""
        fi
    else
        if [ "$PORT_VAL" != "none" ] && [ "$PORT_VAL" != "false" ]; then
            PORT="$PORT_VAL"
            if ! validate_port "$PORT" && [ "$NON_INTERACTIVE" = "true" ]; then
                log_error "Port validation failed for $PORT."
                exit 1
            fi
            PORT_MAPPING_BLOCK="ports:
      - \"$PORT:5006\""
        fi
    fi

    echo -e "\n${BLUE}>>> Step 3: SSL / HTTPS Configuration${NC}"
    log_info "Actual Budget uses Web Cryptography APIs, which requires HTTPS on non-localhost client access."
    log_info "You can configure built-in HTTPS with your certificates or run behind a reverse proxy (recommended)."
    
    ENABLE_SSL="n"
    SSL_ENV_BLOCK=""
    SSL_KEY_PATH=""
    SSL_CERT_PATH=""

    if [ -z "$ENABLE_SSL_VAL" ]; then
        prompt_yes_no "Would you like to configure built-in HTTPS?" "n" ENABLE_SSL
    else
        ENABLE_SSL="$ENABLE_SSL_VAL"
    fi

    if [[ "$ENABLE_SSL" =~ ^[Yy]$ || "$ENABLE_SSL" = "true" ]]; then
        ENABLE_SSL="y"
        SSL_KEY_PATH=${SSL_KEY_VAL:-""}
        SSL_CERT_PATH=${SSL_CERT_VAL:-""}
        
        if [ -z "$SSL_KEY_PATH" ]; then
            while true; do
                if [ "$NON_INTERACTIVE" = "true" ]; then
                    log_error "SSL key path is required in SSL mode."
                    exit 1
                fi
                read -rp "Enter path to SSL private key file (PEM format): " SSL_KEY_PATH
                if [ -n "$SSL_KEY_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
                    break
                else
                    log_error "File not found or empty: '$SSL_KEY_PATH'. Please enter a valid path."
                fi
            done
        elif [ ! -f "$SSL_KEY_PATH" ]; then
            log_error "SSL key file not found: '$SSL_KEY_PATH'."
            exit 1
        fi

        if [ -z "$SSL_CERT_PATH" ]; then
            while true; do
                if [ "$NON_INTERACTIVE" = "true" ]; then
                    log_error "SSL cert path is required in SSL mode."
                    exit 1
                fi
                read -rp "Enter path to SSL certificate file (PEM format): " SSL_CERT_PATH
                if [ -n "$SSL_CERT_PATH" ] && [ -f "$SSL_CERT_PATH" ]; then
                    break
                else
                    log_error "File not found or empty: '$SSL_CERT_PATH'. Please enter a valid path."
                fi
            done
        elif [ ! -f "$SSL_CERT_PATH" ]; then
            log_error "SSL cert file not found: '$SSL_CERT_PATH'."
            exit 1
        fi
    else
        ENABLE_SSL="n"
    fi

    echo -e "\n${BLUE}>>> Step 4: Configure Limits & Variables${NC}"
    UPLOAD_LIMIT=${UPLOAD_LIMIT_VAL:-""}
    if [ -z "$UPLOAD_LIMIT" ]; then
        while true; do
            prompt_input "Enter maximum sync file upload limit (in MB)" "20" UPLOAD_LIMIT
            if validate_numeric "$UPLOAD_LIMIT" "Upload Limit"; then
                break
            fi
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
    fi

    ENCRYPTED_LIMIT=${ENCRYPTED_LIMIT_VAL:-""}
    if [ -z "$ENCRYPTED_LIMIT" ]; then
        while true; do
            prompt_input "Enter maximum encrypted file sync upload limit (in MB)" "50" ENCRYPTED_LIMIT
            if validate_numeric "$ENCRYPTED_LIMIT" "Encrypted Upload Limit"; then
                break
            fi
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
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

    # 3. Create Folder and Configuration Files
    log_info "Creating deployment directory at: ${ABS_INSTALL_DIR}"
    mkdir -p "$ABS_INSTALL_DIR/actual-data"

    if [[ "$ENABLE_SSL" = "y" ]]; then
        mkdir -p "$ABS_INSTALL_DIR/actual-data/ssl"
        cp "$SSL_KEY_PATH" "$ABS_INSTALL_DIR/actual-data/ssl/key.pem"
        cp "$SSL_CERT_PATH" "$ABS_INSTALL_DIR/actual-data/ssl/cert.pem"
        SSL_ENV_BLOCK="
      - ACTUAL_HTTPS_KEY=/data/ssl/key.pem
      - ACTUAL_HTTPS_CERT=/data/ssl/cert.pem"
    fi

    if [ "$DETECTED_UID" -eq 0 ]; then
        log_info "Running as root. Setting ownership of data folder to UID: $DETECTED_UID..."
    fi
    chown -R "$DETECTED_UID:$DETECTED_GID" "$ABS_INSTALL_DIR/actual-data"

    log_info "Writing docker-compose.yml..."
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

    DEPLOY_CONFIRM="y"
    if [ -z "$DEPLOY_CONFIRM_VAL" ]; then
        prompt_yes_no "Deploy the Actual Budget container now?" "y" DEPLOY_CONFIRM
    else
        DEPLOY_CONFIRM="$DEPLOY_CONFIRM_VAL"
    fi

    if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ || "$DEPLOY_CONFIRM" = "true" ]]; then
        log_info "Deploying container..."
        local_log=$(mktemp)
        (cd "$ABS_INSTALL_DIR" && $DOCKER_COMPOSE_CMD up -d) >"$local_log" 2>&1 &
        show_spinner $!
        if ! wait $!; then
            log_error "Deployment failed! Output:"
            cat "$local_log"
            rm -f "$local_log"
            exit 1
        fi
        rm -f "$local_log"
        
        # Verify Service Health
        verify_container_health "actualbudget" "$PORT"
    else
        log_warning "Deployment skipped by user."
    fi

    # Print Summary Box
    local HOST_IP
    HOST_IP=$(detect_ip)
    
    SCHEME_STR="http"
    if [[ "$ENABLE_SSL" = "y" ]]; then
        SCHEME_STR="https"
    fi

    local access_str="No ports exposed on host"
    if [[ "$PORT" != "N/A" ]]; then
        access_str="${SCHEME_STR}://${HOST_IP}:${PORT} (or localhost:${PORT})"
    fi

    echo -e "\n"
    box_message "Deployment Summary" \
        "Container Name:      actualbudget" \
        "Local Access:        ${access_str}" \
        "Install Directory:   ${ABS_INSTALL_DIR}" \
        "Docker Network:      ${CLOUDFLARE_NET:-default (bridge)}"

    # Cloudflare details
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
}

main "$@"
