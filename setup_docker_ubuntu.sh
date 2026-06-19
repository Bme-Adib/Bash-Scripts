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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Ubuntu Playground Container Auto-Setup ===${NC}\n"

# Helper function to check if a port is in use
check_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port "
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i :"$port" >/dev/null 2>&1
    else
        # Fallback check via bash TCP connection (fails if TCP connection is blocked/disabled, but great shell fallback)
        (echo > /dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
    fi
}

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
echo -e "\n${BLUE}>>> Step 1: Base Container Configuration${NC}"

# Ubuntu Version
read -rp "Select Ubuntu version (latest/24.04/22.04/20.04) [latest]: " UBUNTU_VERSION
UBUNTU_VERSION=${UBUNTU_VERSION:-latest}
while [[ ! "$UBUNTU_VERSION" =~ ^(latest|24\.04|22\.04|20\.04)$ ]]; do
    log_error "Invalid version. Choose from: latest, 24.04, 22.04, 20.04."
    read -rp "Select Ubuntu version (latest/24.04/22.04/20.04) [latest]: " UBUNTU_VERSION
    UBUNTU_VERSION=${UBUNTU_VERSION:-latest}
done

# Container Name
read -rp "Enter container name [ubuntu-playground]: " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-ubuntu-playground}
while [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; do
    log_error "Invalid container name. Use alphanumeric characters, hyphens, and underscores only."
    read -rp "Enter container name [ubuntu-playground]: " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-ubuntu-playground}
done

echo -e "\n${BLUE}>>> Step 2: Configure Access Method${NC}"
read -rp "Would you like to enable SSH access in this container? (y/n) [y]: " ENABLE_SSH
ENABLE_SSH=${ENABLE_SSH:-y}

SSH_PORT="2222"
SSH_USER_TYPE="root"
SSH_USER="root"
SSH_PASS="ubuntu"

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    # SSH Port
    PORT_VALIDATED=false
    while [ "$PORT_VALIDATED" = false ]; do
        read -rp "Enter host SSH port to map [2222]: " SSH_PORT
        SSH_PORT=${SSH_PORT:-2222}
        
        if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
            log_error "Invalid port. Must be an integer between 1 and 65535."
            continue
        fi
        
        if check_port_in_use "$SSH_PORT"; then
            log_warning "Port $SSH_PORT is already in use on the host system."
            read -rp "Would you like to use this port anyway? (y/n) [n]: " CONFIRM_PORT
            CONFIRM_PORT=${CONFIRM_PORT:-n}
            if [[ "$CONFIRM_PORT" =~ ^[Yy]$ ]]; then
                PORT_VALIDATED=true
            fi
        else
            PORT_VALIDATED=true
        fi
    done

    # User Type
    read -rp "Configure root or a standard non-root user? (root/user) [root]: " SSH_USER_TYPE
    SSH_USER_TYPE=${SSH_USER_TYPE:-root}
    while [[ ! "$SSH_USER_TYPE" =~ ^(root|user)$ ]]; do
        log_error "Invalid user type. Please enter 'root' or 'user'."
        read -rp "Configure root or a standard non-root user? (root/user) [root]: " SSH_USER_TYPE
        SSH_USER_TYPE=${SSH_USER_TYPE:-root}
    done

    if [ "$SSH_USER_TYPE" = "user" ]; then
        read -rp "Enter username [developer]: " SSH_USER
        SSH_USER=${SSH_USER:-developer}
        while [[ ! "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; do
            log_error "Invalid username. Must start with lowercase/underscore, followed by lowercase, numbers, hyphens or underscores."
            read -rp "Enter username [developer]: " SSH_USER
            SSH_USER=${SSH_USER:-developer}
        done
    else
        SSH_USER="root"
    fi

    # Password
    read -rsp "Enter password for '$SSH_USER' user [ubuntu]: " SSH_PASS
    echo ""
    SSH_PASS=${SSH_PASS:-ubuntu}
    while [ -z "$SSH_PASS" ]; do
        log_error "Password cannot be empty."
        read -rsp "Enter password for '$SSH_USER' user [ubuntu]: " SSH_PASS
        echo ""
        SSH_PASS=${SSH_PASS:-ubuntu}
    done
fi

echo -e "\n${BLUE}>>> Step 3: Configure Storage & Volume Mounts${NC}"
read -rp "Would you like to mount a host directory for persistent data? (y/n) [n]: " ENABLE_MOUNT
ENABLE_MOUNT=${ENABLE_MOUNT:-n}

HOST_DIR=""
CONTAINER_DIR=""
if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ ]]; then
    read -rp "Enter host directory to map (can be relative/absolute) [./data]: " HOST_DIR
    HOST_DIR=${HOST_DIR:-./data}
    read -rp "Enter container directory to map it to [/workspace]: " CONTAINER_DIR
    CONTAINER_DIR=${CONTAINER_DIR:-/workspace}
fi

echo -e "\n${BLUE}>>> Step 4: Packages & Utility Configuration${NC}"
read -rp "Enter extra apt packages to pre-install (space-separated) [curl git wget vim sudo]: " EXTRA_PACKAGES
EXTRA_PACKAGES=${EXTRA_PACKAGES:-curl git wget vim sudo}

read -rp "Would you like to enable Docker command execution inside the container? (y/n) [n]: " ENABLE_DOCKER
ENABLE_DOCKER=${ENABLE_DOCKER:-n}

echo -e "\n${BLUE}>>> Step 5: Network & Limits Configuration${NC}"
# Network Configuration
log_info "Detecting active Docker networks on host..."
if docker network ls >/dev/null 2>&1; then
    echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
    docker network ls --format "  - {{.Name}}" | grep -vE "host|none" || echo "  No custom networks found."
    echo ""
fi

read -rp "Enter the name of your docker network [bridge]: " DOCKER_NET
DOCKER_NET=${DOCKER_NET:-bridge}

if [ "$DOCKER_NET" != "bridge" ]; then
    if ! docker network inspect "$DOCKER_NET" >/dev/null 2>&1; then
        log_warning "Docker network '${DOCKER_NET}' does not exist."
        read -rp "Would you like to create the '${DOCKER_NET}' network now? (y/n) [y]: " CREATE_NET
        CREATE_NET=${CREATE_NET:-y}
        if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
            docker network create "$DOCKER_NET"
            log_success "Created external docker network: ${DOCKER_NET}"
        else
            log_warning "Skipping network creation. Docker compose may fail if it is missing."
        fi
    fi
fi

# Resource Limits
read -rp "Would you like to set CPU or Memory limits? (y/n) [n]: " ENABLE_LIMITS
ENABLE_LIMITS=${ENABLE_LIMITS:-n}

CPU_LIMIT=""
MEM_LIMIT=""
LIMITS_BLOCK=""
if [[ "$ENABLE_LIMITS" =~ ^[Yy]$ ]]; then
    read -rp "Enter CPU limit (e.g. 1.5 for 1.5 cores, leave empty for no limit): " CPU_LIMIT
    read -rp "Enter Memory limit (e.g. 512m, 2g, leave empty for no limit): " MEM_LIMIT
    
    if [ -n "$CPU_LIMIT" ] || [ -n "$MEM_LIMIT" ]; then
        LIMITS_BLOCK="deploy:
  resources:
    limits:"
        if [ -n "$CPU_LIMIT" ]; then
            LIMITS_BLOCK="${LIMITS_BLOCK}
      cpus: '${CPU_LIMIT}'"
        fi
        if [ -n "$MEM_LIMIT" ]; then
            LIMITS_BLOCK="${LIMITS_BLOCK}
      memory: ${MEM_LIMIT}"
        fi
    fi
fi

# 3. Create Deployment Directory
TARGET_DIR="$(pwd)/${CONTAINER_NAME}Container"
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

# Handle volume folder creation to avoid root ownership issues on auto-create
if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ ]]; then
    if [[ "$HOST_DIR" =~ ^\./ ]]; then
        mkdir -p "${TARGET_DIR}/${HOST_DIR#./}"
        log_info "Created local storage directory: ${TARGET_DIR}/${HOST_DIR#./}"
    elif [[ "$HOST_DIR" =~ ^/ ]]; then
        mkdir -p "$HOST_DIR"
        log_info "Created storage directory: ${HOST_DIR}"
    else
        mkdir -p "${TARGET_DIR}/${HOST_DIR}"
        log_info "Created local storage directory: ${TARGET_DIR}/${HOST_DIR}"
    fi
fi

# 4. Generate Dockerfile
log_info "Generating Dockerfile..."
cat <<EOF > "${TARGET_DIR}/Dockerfile"
FROM ubuntu:${UBUNTU_VERSION}

# Avoid interactive package installation dialogues
ENV DEBIAN_FRONTEND=noninteractive

# Update apt repositories and install specified base packages
RUN apt-get update && apt-get install -y \\
    ${EXTRA_PACKAGES} \\
    && rm -rf /var/lib/apt/lists/*
EOF

if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ ]]; then
    cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Install Docker CLI and Docker Compose
RUN apt-get update && \\
    (apt-get install -y docker.io docker-compose-v2 || apt-get install -y docker.io docker-compose) && \\
    rm -rf /var/lib/apt/lists/*
EOF
fi

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    # Append SSH installation and user configuration to Dockerfile
    cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Install and configure SSH server
RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*
RUN mkdir /var/run/sshd
EOF

    if [ "$SSH_USER_TYPE" = "user" ]; then
        cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Create standard user with passwordless sudo permissions
RUN useradd -rm -d /home/${SSH_USER} -s /bin/bash -g root -G sudo -u 1000 ${SSH_USER}
RUN echo "${SSH_USER}:${SSH_PASS}" | chpasswd
RUN echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF
        if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ ]]; then
            cat <<EOF >> "${TARGET_DIR}/Dockerfile"
RUN usermod -aG docker ${SSH_USER}
EOF
        fi
    else
        cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Configure root access and permit root password login
RUN echo "root:${SSH_PASS}" | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
EOF
    fi

    cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# PAM sshd login fix (otherwise SSH disconnects immediately on connection)
RUN sed 's@session\\s*required\\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
EOF
else
    # Non-SSH container setup: keep container running in background
    cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Keep container running in the background indefinitely
CMD ["sleep", "infinity"]
EOF
fi
log_success "Generated: ${TARGET_DIR}/Dockerfile"

# 5. Generate docker-compose.yml
log_info "Generating docker-compose.yml..."
cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  ${CONTAINER_NAME}:
    build: .
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
EOF

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
    ports:
      - "${SSH_PORT}:22"
EOF
else
    cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
    stdin_open: true
    tty: true
EOF
fi

if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ ]] || [[ "$ENABLE_DOCKER" =~ ^[Yy]$ ]]; then
    cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
    volumes:
EOF
    if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ ]]; then
        cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
      - "${HOST_DIR}:${CONTAINER_DIR}"
EOF
    fi
    if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ ]]; then
        cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
      - "/var/run/docker.sock:/var/run/docker.sock"
EOF
    fi
fi

if [ "$DOCKER_NET" != "bridge" ]; then
    cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
    networks:
      - ${DOCKER_NET}
EOF
fi

if [ -n "$LIMITS_BLOCK" ]; then
    while IFS= read -r line; do
        echo "    $line" >> "${TARGET_DIR}/docker-compose.yml"
    done <<< "$LIMITS_BLOCK"
fi

if [ "$DOCKER_NET" != "bridge" ]; then
    cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"

networks:
  ${DOCKER_NET}:
    external: true
EOF
fi
log_success "Generated: ${TARGET_DIR}/docker-compose.yml"

# 6. Review Configuration & Deploy
echo -e "\n${BLUE}>>> Step 6: Review Generated Configuration${NC}"
echo -e "${GREEN}====================== docker-compose.yml ====================${NC}"
cat "${TARGET_DIR}/docker-compose.yml"
echo -e "${GREEN}============================================================${NC}"

read -rp "Deploy the Ubuntu container now? (y/n) [y]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-y}

if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "Building and starting container..."
    (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d --build)
    log_success "Ubuntu Container '${CONTAINER_NAME}' is now running!"
    
    if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
        log_info "Clearing host SSH key registry for port ${SSH_PORT} to prevent host key verification conflicts..."
        ssh-keygen -R "[localhost]:${SSH_PORT}" >/dev/null 2>&1 || true
    fi
else
    log_warning "Deployment skipped. You can manually launch it later."
fi

# --- Print Summary & Connection Instructions ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                    Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"

echo -e "\n${BLUE}=== Container Summary ===${NC}"
echo -e "Container Name:   ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "Ubuntu Version:   ${GREEN}${UBUNTU_VERSION}${NC}"

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    echo -e "SSH Access:       ${GREEN}Enabled${NC}"
    echo -e "Host SSH Port:    ${YELLOW}${SSH_PORT}${NC}"
    echo -e "SSH User:         ${GREEN}${SSH_USER}${NC}"
    echo -e "SSH Password:     ${GREEN}${SSH_PASS}${NC}"
    echo -e "\nOnce you run that, try to SSH again:\n"
    echo -e "  ${YELLOW}ssh ${SSH_USER}@localhost -p ${SSH_PORT}${NC}"
else
    echo -e "SSH Access:       ${RED}Disabled${NC}"
    echo -e "Shell Access:     ${YELLOW}docker exec -it ${CONTAINER_NAME} bash${NC}"
fi

if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ ]]; then
    echo -e "Host Directory:   ${GREEN}${HOST_DIR}${NC}"
    echo -e "Container Mount:  ${GREEN}${CONTAINER_DIR}${NC}"
fi

if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ ]]; then
    echo -e "Docker Access:    ${GREEN}Enabled (Socket Mounted)${NC}"
else
    echo -e "Docker Access:    ${RED}Disabled${NC}"
fi

echo -e "\n${BLUE}=== Management Commands ===${NC}"
echo -e "View Container Logs:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} logs -f${NC}"
echo -e "Stop Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} down${NC}"
echo -e "Start Container:"
echo -e "  ${YELLOW}cd ${TARGET_DIR} && ${DOCKER_COMPOSE_CMD} up -d${NC}"
echo -e "Access Shell Directly (Docker Exec):"
echo -e "  ${YELLOW}docker exec -it ${CONTAINER_NAME} bash${NC}"
echo -e "============================================================\n"
