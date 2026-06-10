#!/bin/bash

# Exit immediately if a command exits with a non-zero status
# Treat unset variables as an error
# Prevent errors in a pipeline from being masked
set -euo pipefail

# --- Color Codes for UX ---
RED='\033;0;31m'
GREEN='\033;0;32m'
YELLOW='\033;0;33m'
BLUE='\033;0;34m'
NC='\033[0m' # No Color

# --- Cleanup Helper ---
# No global temp blocks needed anymore since we write the file directly

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

validate_port() {
    local port="$1"
    local desc="$2"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number for $desc: '$port'. Must be between 1 and 65535."
        return 1
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

# --- 1. Gather & Sanitize Project Information ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Docker Compose Project Creator ===${NC}\n"

while true; do
    read -p "Enter project name (e.g., adib): " RAW_NAME < /dev/tty
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
PROJECT_DIR="${NAME}"

# --- Check if Project Folder / Config already exists ---
if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    log_warning "Project directory '${PROJECT_DIR}' already contains a docker-compose.yml file."
    read -p "Do you want to overwrite it? (y/N): " CONFIRM < /dev/tty
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        log_info "Operation aborted."
        exit 0
    fi
fi

while true; do
    echo -e "\nChoose project type:"
    echo "1) Business Card Only"
    echo "2) Website Only"
    echo "3) Business Card + Website"
    read -p "Selection [1-3]: " TYPE < /dev/tty
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

# --- 2. Gather Ports and Network ---
BIZ_PORT=""
if [ "$HAS_BIZ" = true ]; then
    while true; do
        read -p "Enter port for ${NAME}-biz: " BIZ_PORT < /dev/tty
        if validate_port "$BIZ_PORT" "${NAME}-biz"; then
            break
        fi
    done
fi

WEB_PORT=""
if [ "$HAS_WEB" = true ]; then
    while true; do
        read -p "Enter port for ${NAME}-website: " WEB_PORT < /dev/tty
        if [ -n "$BIZ_PORT" ] && [ "$WEB_PORT" = "$BIZ_PORT" ]; then
            log_error "Web port cannot be the same as business card port ($BIZ_PORT)!"
            continue
        fi
        if validate_port "$WEB_PORT" "${NAME}-website"; then
            break
        fi
    done
fi

read -p "Enter network name (leave empty for none): " NET_NAME < /dev/tty
# Trim whitespace from network name
NET_NAME=$(echo "$NET_NAME" | xargs)

# --- Create Folders & Boilerplate HTML ---
log_info "Creating project directories..."
mkdir -p "$PROJECT_DIR"

BIZ_DIR="${PROJECT_DIR}/biz"
WEB_DIR="${PROJECT_DIR}/website"

if [ "$HAS_BIZ" = true ]; then
    mkdir -p "$BIZ_DIR"
    create_placeholder_html "$BIZ_DIR" "Business Card: ${NAME}"
fi

if [ "$HAS_WEB" = true ]; then
    mkdir -p "$WEB_DIR"
    create_placeholder_html "$WEB_DIR" "Website: ${NAME}"
fi

# --- 3. Create docker-compose.yml ---
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
    ports:
      - "${BIZ_PORT}:80"
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
    ports:
      - "${WEB_PORT}:80"
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

log_success "Project directory '${PROJECT_DIR}' and configuration are ready!"

# --- 4. Smart Editor Launch (Before execution) ---
read -p "Would you like to open/review docker-compose.yml before running the services? (y/N): " OPEN_EDITOR < /dev/tty
if [[ "$OPEN_EDITOR" =~ ^[yY]$ ]]; then
    # Use system EDITOR, fallback to nano, then vi
    EDITOR_CMD="${EDITOR:-$(which nano 2>/dev/null || which vi 2>/dev/null || echo "")}"
    if [ -n "$EDITOR_CMD" ]; then
        $EDITOR_CMD "${PROJECT_DIR}/docker-compose.yml"
    else
        log_warning "No text editor found (nano/vi). Displaying file instead:"
        cat "${PROJECT_DIR}/docker-compose.yml"
    fi
fi

# --- 5. Prompt to start services ---
read -p "Do you want to start the services now with 'docker compose up -d'? (y/N): " START_SERVICES < /dev/tty
if [[ "$START_SERVICES" =~ ^[yY]$ ]]; then
    log_info "Navigating to ${PROJECT_DIR} and starting containers..."
    (cd "$PROJECT_DIR" && docker compose up -d)
    log_success "Services started successfully!"
fi

echo -e "\nTo manage this project, run:"
echo -e "${GREEN}cd ${PROJECT_DIR}${NC}"
echo -e "To start: ${BLUE}docker compose up -d${NC}"
echo -e "To stop:  ${BLUE}docker compose down${NC}"
