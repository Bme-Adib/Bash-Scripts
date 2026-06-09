#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "============================================="
echo "   SiYuan Note Docker Installer & Setup      "
echo "============================================="

# 1. Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "[-] Docker is not installed. Please install Docker first."
    echo "    On Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y docker.io"
    exit 1
fi

# 2. Check if Docker Compose is installed
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "[-] Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Determine compose command to use
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 3. Gather inputs
# Auto-detect timezone and current user credentials
DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
DETECTED_UID=$(id -u)
DETECTED_GID=$(id -g)

# Prompts
read -p "Enter installation directory [default: ./siyuan-workspace]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-"./siyuan-workspace"}

# Resolve to absolute path
mkdir -p "$INSTALL_DIR"
ABS_INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)

read -p "Enter port to bind [default: 6806]: " PORT
PORT=${PORT:-"6806"}

# Generate a random password as default
RANDOM_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 12 || echo "siyuan_secure_password")
read -p "Enter Access Authorization Code (password) [default: $RANDOM_PASS]: " AUTH_CODE
AUTH_CODE=${AUTH_CODE:-"$RANDOM_PASS"}

read -p "Enter Timezone [default: $DETECTED_TZ]: " TZ
TZ=${TZ:-"$DETECTED_TZ"}

read -p "Enter User ID (PUID) [default: $DETECTED_UID]: " PUID
PUID=${PUID:-"$DETECTED_UID"}

read -p "Enter Group ID (PGID) [default: $DETECTED_GID]: " PGID
PGID=${PGID:-"$DETECTED_GID"}

echo ""
echo "Configuration Summary:"
echo "----------------------"
echo "Installation Dir : $ABS_INSTALL_DIR"
echo "Port             : $PORT"
echo "Auth Code        : $AUTH_CODE"
echo "Timezone         : $TZ"
echo "PUID/PGID        : $PUID:$PGID"
echo "----------------------"

# Create workspace folder
WORKSPACE_DIR="$ABS_INSTALL_DIR/workspace"
echo "[+] Creating workspace folder at $WORKSPACE_DIR..."
mkdir -p "$WORKSPACE_DIR"

# Write docker-compose.yml
echo "[+] Writing docker-compose.yml..."
cat << EOF > "$ABS_INSTALL_DIR/docker-compose.yml"
version: "3.9"

services:
  siyuan:
    image: b3log/siyuan:latest
    container_name: siyuan
    command:
      - --workspace=/siyuan/workspace/
      - --accessAuthCode=$AUTH_CODE
    ports:
      - "$PORT:6806"
    volumes:
      - ./workspace:/siyuan/workspace
    environment:
      - TZ=$TZ
      - PUID=$PUID
      - PGID=$PGID
    restart: unless-stopped
EOF

# Adjust permissions if run as root
if [ "$DETECTED_UID" -eq 0 ]; then
    echo "[+] Adjusting workspace ownership to $PUID:$PGID..."
    chown -R "$PUID:$PGID" "$WORKSPACE_DIR"
fi

# Starting container
echo "[+] Starting SiYuan container..."
cd "$ABS_INSTALL_DIR"
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "============================================="
echo "[+] Success! SiYuan has been deployed."
echo "Access URL : http://localhost:$PORT (or http://<your-server-ip>:$PORT)"
echo "Auth Code  : $AUTH_CODE"
echo "============================================="
