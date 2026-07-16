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
    local desc="$2"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number for $desc: '$port'. Must be between 1 and 65535."
        return 1
    fi
    if check_port_in_use "$port"; then
        log_warning "Port $port appears to be already in use on your host system!"
    fi
    return 0
}

create_placeholder_html() {
    local dir="$1"
    local title="$2"
    cat <<EOF > "${dir}/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #0f172a, #1e293b);
            color: #f8fafc;
            text-align: center;
        }
        .container {
            padding: 2rem;
            border-radius: 12px;
            background: rgba(255, 255, 255, 0.05);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
        }
        h1 { margin-top: 0; color: #38bdf8; }
        p { color: #94a3b8; }
        .credit {
            margin-top: 2rem;
            font-size: 0.85rem;
            color: #64748b;
        }
        .credit a {
            color: #38bdf8;
            text-decoration: none;
        }
        .credit a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>${title} Ready!</h1>
        <p>This is a placeholder page served from Nginx inside Docker.</p>
        <div class="credit">
            Bash Script By Ghannams Academy (<a href="https://github.com/Bme-Adib" target="_blank">https://github.com/Bme-Adib</a>)
        </div>
    </div>
</body>
</html>
EOF
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
    echo -e "${BLUE}=== Docker Compose Project Creator ===${NC}\n"
}

# --- Getopts Argument Parsing ---
NON_INTERACTIVE=false
PROJECT_NAME_VAL=""
PROJECT_TYPE_VAL=""
EXPOSE_PORT_VAL=""
BIZ_PORT_VAL=""
WEB_PORT_VAL=""
NET_NAME_VAL=""
DEPLOY_CONFIRM_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h             Show this help message"
    echo "  -y             Run non-interactively (use defaults)"
    echo "  -n NAME        Project name"
    echo "  -t TYPE        Project type: 1 (Biz card only), 2 (Website only), 3 (Both)"
    echo "  -p EXPOSE_BOOL Expose container ports to host system (y/n)"
    echo "  -a BIZ_PORT    Host port for business card"
    echo "  -b WEB_PORT    Host port for website"
    echo "  -w NET_NAME    Docker network name (or 'none')"
    echo "  -o DEPLOY_CONF Deploy containers automatically (y/n)"
}

while getopts "hyn:t:p:a:b:w:o:" opt; do
    case "$opt" in
        h) print_help; exit 0 ;;
        y) NON_INTERACTIVE=true ;;
        n) PROJECT_NAME_VAL="$OPTARG" ;;
        t) PROJECT_TYPE_VAL="$OPTARG" ;;
        p) EXPOSE_PORT_VAL="$OPTARG" ;;
        a) BIZ_PORT_VAL="$OPTARG" ;;
        b) WEB_PORT_VAL="$OPTARG" ;;
        w) NET_NAME_VAL="$OPTARG" ;;
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
    echo -e "\n${BLUE}>>> Step 1: Configure Project Name & Type${NC}"
    
    NAME=""
    while [ -z "$NAME" ]; do
        RAW_NAME=${PROJECT_NAME_VAL:-""}
        if [ -z "$RAW_NAME" ]; then
            prompt_input "Enter project name" "academy" RAW_NAME
        fi
        
        # Convert to lowercase and strip invalid characters
        NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')
        if [ -z "$NAME" ]; then
            log_error "Project name cannot be empty."
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        else
            if [ "$RAW_NAME" != "$NAME" ]; then
                log_warning "Sanitized name to '$NAME' for Docker compatibility."
            fi
        fi
    done

    PROJECT_DIR="$(pwd)/${NAME}"

    if [ -d "$PROJECT_DIR" ]; then
        log_warning "Directory ${PROJECT_DIR} already exists."
        prompt_yes_no "Would you like to overwrite it?" "n" OVERWRITE_DIR
        if [[ "$OVERWRITE_DIR" =~ ^[Yy]$ ]]; then
            log_info "Removing existing folder..."
            rm -rf "$PROJECT_DIR"
        else
            log_error "Setup cancelled to protect existing folder."
            exit 1
        fi
    fi

    TYPE=${PROJECT_TYPE_VAL:-""}
    if [ -z "$TYPE" ]; then
        while true; do
            echo -e "\nChoose project type:"
            echo "1) Business Card Only"
            echo "2) Website Only"
            echo "3) Business Card + Website"
            prompt_input "Selection [1-3]" "3" TYPE
            if [ "$TYPE" = "1" ] || [ "$TYPE" = "2" ] || [ "$TYPE" = "3" ]; then
                break
            fi
            log_error "Invalid selection. Please choose 1, 2, or 3."
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
    fi

    HAS_BIZ=false
    HAS_WEB=false
    if [ "$TYPE" = "1" ] || [ "$TYPE" = "3" ]; then
        HAS_BIZ=true
    fi
    if [ "$TYPE" = "2" ] || [ "$TYPE" = "3" ]; then
        HAS_WEB=true
    fi

    echo -e "\n${BLUE}>>> Step 2: Configure Port Exposure${NC}"
    EXPOSE_PORT=${EXPOSE_PORT_VAL:-""}
    if [ -z "$EXPOSE_PORT" ]; then
        prompt_yes_no "Would you like to expose the container ports to the host system?" "n" EXPOSE_PORT
    fi

    BIZ_PORT_BLOCK=""
    BIZ_PORT="N/A"
    if [ "$HAS_BIZ" = true ]; then
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ || "$EXPOSE_PORT" = "true" ]]; then
            BIZ_PORT=${BIZ_PORT_VAL:-""}
            while true; do
                if [ -z "$BIZ_PORT" ]; then
                    prompt_input "Enter host port for ${NAME}-biz" "8082" BIZ_PORT
                fi
                if validate_port "$BIZ_PORT" "${NAME}-biz"; then
                    break
                fi
                BIZ_PORT=""
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            BIZ_PORT_BLOCK="ports:
      - \"${BIZ_PORT}:80\""
        else
            BIZ_PORT_BLOCK="# ports:
    #   - \"8082:80\""
        fi
    fi

    WEB_PORT_BLOCK=""
    WEB_PORT="N/A"
    if [ "$HAS_WEB" = true ]; then
        if [[ "$EXPOSE_PORT" =~ ^[Yy]$ || "$EXPOSE_PORT" = "true" ]]; then
            WEB_PORT=${WEB_PORT_VAL:-""}
            DEFAULT_WEB_PORT="8083"
            if [ "$HAS_BIZ" = false ] || [ "${BIZ_PORT:-}" = "N/A" ] || [ -z "${BIZ_PORT:-}" ]; then
                DEFAULT_WEB_PORT="8082"
            fi
            
            while true; do
                if [ -z "$WEB_PORT" ]; then
                    prompt_input "Enter host port for ${NAME}-website" "$DEFAULT_WEB_PORT" WEB_PORT
                fi
                if [ -n "${BIZ_PORT:-}" ] && [ "$WEB_PORT" = "$BIZ_PORT" ] && [ "$BIZ_PORT" != "N/A" ]; then
                    log_error "Web port cannot be the same as business card port ($BIZ_PORT)!"
                    WEB_PORT=""
                    if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
                    continue
                fi
                if validate_port "$WEB_PORT" "${NAME}-website"; then
                    break
                fi
                WEB_PORT=""
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
            WEB_PORT_BLOCK="ports:
      - \"${WEB_PORT}:80\""
        else
            DEFAULT_WEB_PORT="8083"
            if [ "$HAS_BIZ" = false ]; then
                DEFAULT_WEB_PORT="8082"
            fi
            WEB_PORT_BLOCK="# ports:
    #   - \"${DEFAULT_WEB_PORT}:80\""
        fi
    fi

    echo -e "\n${BLUE}>>> Step 3: Configure Network${NC}"
    NET_NAME=""
    if [ -z "$NET_NAME_VAL" ]; then
        log_info "Detecting active Docker networks on host..."
        if docker network ls >/dev/null 2>&1; then
            echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
            docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
            echo ""
        fi
        prompt_input "Enter network name (leave empty for none)" "proxy-net" NET_NAME
        
        if [ -n "$NET_NAME" ]; then
            if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
                log_warning "Docker network '${NET_NAME}' does not exist."
                prompt_yes_no "Would you like to create the '${NET_NAME}' network now?" "y" CREATE_NET
                if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
                    docker network create "$NET_NAME"
                    log_success "Created external docker network: ${NET_NAME}"
                else
                    log_warning "Skipping network creation. Docker compose may fail if it is missing."
                fi
            fi
        fi
    else
        if [ "$NET_NAME_VAL" != "none" ] && [ "$NET_NAME_VAL" != "false" ]; then
            NET_NAME="$NET_NAME_VAL"
            if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
                log_info "Creating external network $NET_NAME as specified by options..."
                docker network create "$NET_NAME"
            fi
        fi
    fi

    # 3. Create Folders & Boilerplate HTML
    log_info "Creating project directories at: ${PROJECT_DIR}"
    mkdir -p "$PROJECT_DIR"

    BIZ_DIR="${PROJECT_DIR}/biz"
    WEB_DIR="${PROJECT_DIR}/website"

    if [ "$HAS_BIZ" = true ]; then
        mkdir -p "$BIZ_DIR"
        create_placeholder_html "$BIZ_DIR" "Business Card: ${NAME}"
        log_success "Created: ${BIZ_DIR}/index.html"
    fi

    if [ "$HAS_WEB" = true ]; then
        mkdir -p "$WEB_DIR"
        create_placeholder_html "$WEB_DIR" "Website: ${NAME}"
        log_success "Created: ${WEB_DIR}/index.html"
    fi

    # 4. Create docker-compose.yml
    log_info "Writing docker-compose.yml..."
    cat <<EOF > "${PROJECT_DIR}/docker-compose.yml"
services:
EOF

    if [ "$HAS_BIZ" = true ]; then
        cat <<EOF >> "${PROJECT_DIR}/docker-compose.yml"
  biz:
    image: nginx:alpine
    container_name: ${NAME}-biz
    restart: unless-stopped
    ${BIZ_PORT_BLOCK}
    volumes:
      - ./biz:/usr/share/nginx/html
EOF
        if [ -n "$NET_NAME" ]; then
            cat <<EOF >> "${PROJECT_DIR}/docker-compose.yml"
    networks:
      - ${NET_NAME}
EOF
        fi
    fi

    if [ "$HAS_WEB" = true ]; then
        cat <<EOF >> "${PROJECT_DIR}/docker-compose.yml"
  website:
    image: nginx:alpine
    container_name: ${NAME}-website
    restart: unless-stopped
    ${WEB_PORT_BLOCK}
    volumes:
      - ./website:/usr/share/nginx/html
EOF
        if [ -n "$NET_NAME" ]; then
            cat <<EOF >> "${PROJECT_DIR}/docker-compose.yml"
    networks:
      - ${NET_NAME}
EOF
        fi
    fi

    if [ -n "$NET_NAME" ]; then
        cat <<EOF >> "${PROJECT_DIR}/docker-compose.yml"

networks:
  ${NET_NAME}:
    external: true
EOF
    fi
    log_success "Created: ${PROJECT_DIR}/docker-compose.yml"

    # 5. Review & Deploy
    echo -e "\n${BLUE}>>> Step 4: Review Configuration${NC}"
    echo -e "${GREEN}============================================================${NC}"
    cat "${PROJECT_DIR}/docker-compose.yml"
    echo -e "${GREEN}============================================================${NC}"

    DEPLOY_CONFIRM="y"
    if [ -z "$DEPLOY_CONFIRM_VAL" ]; then
        prompt_yes_no "Deploy the ${NAME} containers now?" "y" DEPLOY_CONFIRM
    else
        DEPLOY_CONFIRM="$DEPLOY_CONFIRM_VAL"
    fi

    if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ || "$DEPLOY_CONFIRM" = "true" ]]; then
        log_info "Deploying containers..."
        local_log=$(mktemp)
        (cd "$PROJECT_DIR" && $DOCKER_COMPOSE_CMD up -d) >"$local_log" 2>&1 &
        show_spinner $!
        if ! wait $!; then
            log_error "Deployment failed! Output:"
            cat "$local_log"
            rm -f "$local_log"
            exit 1
        fi
        rm -f "$local_log"
        
        # Verify Service Health
        if [ "$HAS_BIZ" = true ]; then
            verify_container_health "${NAME}-biz" "$BIZ_PORT"
        fi
        if [ "$HAS_WEB" = true ]; then
            verify_container_health "${NAME}-website" "$WEB_PORT"
        fi
    else
        log_warning "Deployment skipped by user."
    fi

    # Print Summary Box
    local HOST_IP
    HOST_IP=$(detect_ip)
    
    local biz_access_str="Disabled/Not Exposed"
    if [ "$HAS_BIZ" = true ]; then
        if [[ "$BIZ_PORT" != "N/A" ]]; then
            biz_access_str="http://localhost:${BIZ_PORT} (IP: http://${HOST_IP}:${BIZ_PORT})"
        else
            biz_access_str="Enabled (No ports exposed on host)"
        fi
    fi

    local web_access_str="Disabled/Not Exposed"
    if [ "$HAS_WEB" = true ]; then
        if [[ "$WEB_PORT" != "N/A" ]]; then
            web_access_str="http://localhost:${WEB_PORT} (IP: http://${HOST_IP}:${WEB_PORT})"
        else
            web_access_str="Enabled (No ports exposed on host)"
        fi
    fi

    echo -e "\n"
    box_message "Deployment Summary" \
        "Project Name:     ${NAME}" \
        "Business Card:    ${biz_access_str}" \
        "Main Website:     ${web_access_str}" \
        "Docker Network:   ${NET_NAME:-default (bridge)}" \
        "Project Directory:${PROJECT_DIR}"

    if [ -n "$NET_NAME" ]; then
        echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
        echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
        echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
        echo -e "  2. Edit the active Tunnel servicing this network."
        echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
        if [ "$HAS_BIZ" = true ]; then
            echo -e "     - Subdomain/Domain: e.g., ${GREEN}biz.${NAME}.yourdomain.com${NC}"
            echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
            echo -e "     - URL:              ${YELLOW}http://${NAME}-biz:80${NC}"
        fi
        if [ "$HAS_WEB" = true ]; then
            echo -e "     - Subdomain/Domain: e.g., ${GREEN}www.${NAME}.yourdomain.com${NC}"
            echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
            echo -e "     - URL:              ${YELLOW}http://${NAME}-website:80${NC}"
        fi
        echo -e "  4. Save Hostname. Cloudflare will route traffic securely to the container(s)."
    fi

    echo -e "\n${BLUE}=== Management Commands ===${NC}"
    echo -e "View Container Logs:"
    echo -e "  ${YELLOW}cd ${PROJECT_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
    echo -e "Shutdown Containers:"
    echo -e "  ${YELLOW}cd ${PROJECT_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
    echo -e "Restart Containers:"
    echo -e "  ${YELLOW}cd ${PROJECT_DIR} && ${DOCKER_COMPOSE_CMD} restart${NC}"
    echo -e "============================================================\n"
}

main "$@"
