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
    local desc="$2"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number for $desc: '$port'. Must be between 1 and 65535."
        return 1
    fi
    if command -v ss &>/dev/null && ss -tln | grep -q ":${port} "; then
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
            Bash Script By Adib Builds (<a href="https://github.com/Bme-Adib" target="_blank">https://github.com/Bme-Adib</a>)
        </div>
    </div>
</body>
</html>
EOF
}

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Docker Compose Project Creator ===${NC}\n"

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
while true; do
    read -rp "Enter project name [adib]: " RAW_NAME
    RAW_NAME=${RAW_NAME:-adib}
    # Convert to lowercase and strip invalid characters
    NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')
    
    if [ -z "$NAME" ]; then
        log_error "Project name cannot be empty."
    else
        if [ "$RAW_NAME" != "$NAME" ]; then
            log_warning "Sanitized name to '$NAME' for Docker compatibility."
        fi
        break
    fi
done

# Parent project folder
PROJECT_DIR="$(pwd)/${NAME}"

# --- Check if Project Folder already exists ---
if [ -d "$PROJECT_DIR" ]; then
    log_warning "Directory ${PROJECT_DIR} already exists."
    read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE_DIR
    OVERWRITE_DIR=${OVERWRITE_DIR:-n}
    if [[ "$OVERWRITE_DIR" =~ ^[Yy]$ ]]; then
        log_info "Removing existing folder..."
        rm -rf "$PROJECT_DIR"
    else
        log_error "Setup cancelled to protect existing folder."
        exit 1
    fi
fi

while true; do
    echo -e "\nChoose project type:"
    echo "1) Business Card Only"
    echo "2) Website Only"
    echo "3) Business Card + Website"
    read -rp "Selection [1-3] [3]: " TYPE
    TYPE=${TYPE:-3}
    if [ "$TYPE" = "1" ] || [ "$TYPE" = "2" ] || [ "$TYPE" = "3" ]; then
        break
    else
        log_error "Invalid selection. Please choose 1, 2, or 3."
    fi
done

# Check which services are requested
HAS_BIZ=false
HAS_WEB=false
if [ "$TYPE" = "1" ] || [ "$TYPE" = "3" ]; then
    HAS_BIZ=true
fi
if [ "$TYPE" = "2" ] || [ "$TYPE" = "3" ]; then
    HAS_WEB=true
fi

# --- Gather Ports and Network ---
echo -e "\n${BLUE}>>> Step 2: Configure Port Exposure${NC}"
read -rp "Would you like to expose the container ports to the host system? (y/n) [n]: " EXPOSE_PORT
EXPOSE_PORT=${EXPOSE_PORT:-n}

BIZ_PORT_BLOCK=""
BIZ_PORT=""
if [ "$HAS_BIZ" = true ]; then
    if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
        while true; do
            read -rp "Enter host port for ${NAME}-biz [8082]: " BIZ_PORT
            BIZ_PORT=${BIZ_PORT:-8082}
            if validate_port "$BIZ_PORT" "${NAME}-biz"; then
                break
            fi
        done
        BIZ_PORT_BLOCK="ports:
      - \"${BIZ_PORT}:80\""
    else
        BIZ_PORT_BLOCK="# To expose this port to the host system, uncomment the lines below.
    # Change the port number before the colon (8082) to whatever port you want.
    # ports:
    #   - \"8082:80\""
    fi
fi

WEB_PORT_BLOCK=""
WEB_PORT=""
if [ "$HAS_WEB" = true ]; then
    if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
        DEFAULT_WEB_PORT="8083"
        if [ "$HAS_BIZ" = false ] || [ -z "${BIZ_PORT:-}" ]; then
            DEFAULT_WEB_PORT="8082"
        fi
        while true; do
            read -rp "Enter host port for ${NAME}-website [${DEFAULT_WEB_PORT}]: " WEB_PORT
            WEB_PORT=${WEB_PORT:-$DEFAULT_WEB_PORT}
            if [ -n "${BIZ_PORT:-}" ] && [ "$WEB_PORT" = "$BIZ_PORT" ]; then
                log_error "Web port cannot be the same as business card port ($BIZ_PORT)!"
                continue
            fi
            if validate_port "$WEB_PORT" "${NAME}-website"; then
                break
            fi
        done
        WEB_PORT_BLOCK="ports:
      - \"${WEB_PORT}:80\""
    else
        DEFAULT_WEB_PORT="8083"
        if [ "$HAS_BIZ" = false ]; then
            DEFAULT_WEB_PORT="8082"
        fi
        WEB_PORT_BLOCK="# To expose this port to the host system, uncomment the lines below.
    # Change the port number before the colon (${DEFAULT_WEB_PORT}) to whatever port you want.
    # ports:
    #   - \"${DEFAULT_WEB_PORT}:80\""
    fi
fi

echo -e "\n${BLUE}>>> Step 3: Configure Network${NC}"
# Show existing networks on the host
log_info "Detecting active Docker networks on host..."
if docker network ls >/dev/null 2>&1; then
    echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
    docker network ls --format "  - {{.Name}}" | grep -vE "bridge|host|none" || echo "  No custom networks found."
    echo ""
fi

read -rp "Enter network name (leave empty for none) [proxy-net]: " NET_NAME
NET_NAME=${NET_NAME:-proxy-net}

if [ -n "$NET_NAME" ]; then
    # Check and prompt to create network if missing
    if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
        log_warning "Docker network '${NET_NAME}' does not exist."
        read -rp "Would you like to create the '${NET_NAME}' network now? (y/n) [y]: " CREATE_NET
        CREATE_NET=${CREATE_NET:-y}
        if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
            docker network create "$NET_NAME"
            log_success "Created external docker network: ${NET_NAME}"
        else
            log_warning "Skipping network creation. Docker compose may fail if it is missing."
        fi
    fi
fi

# --- Create Folders & Boilerplate HTML ---
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

# --- Create docker-compose.yml ---
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

# --- Review & Deploy ---
echo -e "\n${BLUE}>>> Step 4: Review Configuration${NC}"
echo -e "${GREEN}============================================================${NC}"
cat "${PROJECT_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the ${NAME} containers now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Deploying containers..."
    (cd "$PROJECT_DIR" && $DOCKER_COMPOSE_CMD up -d)
    log_success "Containers are running!"
else
    log_warning "Deployment skipped by user."
fi

# --- Print Summary & Cloudflare Integration Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Connection Details ===${NC}"
if [ "$HAS_BIZ" = true ]; then
    echo -e "Business Card Container: ${GREEN}${NAME}-biz${NC}"
    if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
        echo -e "Local Access:            ${YELLOW}http://localhost:${BIZ_PORT}${NC}"
    else
        echo -e "Local Access:            ${YELLOW}No ports exposed on host (Access via Tunnel only)${NC}"
    fi
fi
if [ "$HAS_WEB" = true ]; then
    echo -e "Website Container:       ${GREEN}${NAME}-website${NC}"
    if [[ "$EXPOSE_PORT" =~ ^[Yy]$ ]]; then
        echo -e "Local Access:            ${YELLOW}http://localhost:${WEB_PORT}${NC}"
    else
        echo -e "Local Access:            ${YELLOW}No ports exposed on host (Access via Tunnel only)${NC}"
    fi
fi

if [ -n "$NET_NAME" ]; then
    echo -e "\n${BLUE}=== Cloudflare Tunnel Integration Instructions ===${NC}"
    echo -e "To configure access via Cloudflare Zero Trust Tunnels:"
    echo -e "  1. Log in to your Cloudflare Dashboard and navigate to ${GREEN}Access -> Tunnels${NC}."
    echo -e "  2. Edit the active Tunnel servicing this network."
    echo -e "  3. Click ${YELLOW}Add a public hostname${NC} and enter:"
    if [ "$HAS_BIZ" = true ]; then
        echo -e "     - Subdomain/Domain: e.g., ${GREEN}biz.${NAME}.example.com${NC}"
        echo -e "     - Service Type:     ${YELLOW}HTTP${NC}"
        echo -e "     - URL:              ${YELLOW}http://${NAME}-biz:80${NC}"
    fi
    if [ "$HAS_WEB" = true ]; then
        echo -e "     - Subdomain/Domain: e.g., ${GREEN}www.${NAME}.example.com${NC}"
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
