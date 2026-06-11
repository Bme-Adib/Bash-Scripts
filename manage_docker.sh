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
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Docker Management & Optimization Tool ===${NC}\n"
}

# Ensure script is run with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
    show_header
    log_error "This utility requires administrative privileges. Please run with sudo:"
    echo -e "  ${YELLOW}sudo $0${NC}"
    exit 1
fi

# ==========================================
# ACTION FUNCTIONS
# ==========================================

# 1. Install Docker & Compose V2
do_install_docker() {
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VER=$(docker --version)
        log_success "Docker is already installed: ${DOCKER_VER}"
        
        # Check if docker compose is also installed
        if docker compose version >/dev/null 2>&1; then
            log_success "Docker Compose V2 is already installed: $(docker compose version)"
        else
            log_warning "Docker Compose plugin is missing or not configured correctly."
        fi
        
        read -rp "Would you like to force reinstall/update Docker? (y/n) [n]: " FORCE_INSTALL
        FORCE_INSTALL=${FORCE_INSTALL:-n}
        if [[ ! "$FORCE_INSTALL" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_info "Detecting Operating System..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_CODENAME=${VERSION_CODENAME:-""}
    else
        log_error "Could not detect Operating System. /etc/os-release not found."
        return 1
    fi

    log_info "OS Detected: ${NAME} (${VERSION:-unknown})"

    # Confirm before installation
    read -rp "Would you like to proceed with installing Docker and Docker Compose? (y/n) [y]: " CONFIRM_INSTALL
    CONFIRM_INSTALL=${CONFIRM_INSTALL:-y}
    if [[ ! "$CONFIRM_INSTALL" =~ ^[Yy]$ ]]; then
        log_warning "Installation cancelled by user."
        return 0
    fi

    # Perform installation
    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "raspbian" ] || [ "$OS_ID" = "pop" ] || [ "$OS_ID" = "linuxmint" ]; then
        log_info "Starting Docker installation via apt repository..."
        apt-get update -y
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings

        # Determine GPG key url and repo url
        GPG_URL="https://download.docker.com/linux/${OS_ID}/gpg"
        REPO_URL="https://download.docker.com/linux/${OS_ID}"
        
        # Mint or Pop!_OS might map ID to mint/pop, we should point to ubuntu/debian base
        if [ "$OS_ID" = "pop" ] || [ "$OS_ID" = "linuxmint" ]; then
            GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
            REPO_URL="https://download.docker.com/linux/ubuntu"
            OS_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
        fi

        log_info "Adding Docker official GPG key..."
        curl -fsSL "$GPG_URL" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

        log_info "Adding Docker apt repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $REPO_URL \
          ${OS_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        log_info "Updating package lists again and installing Docker packages..."
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # Fallback to official convenience script for non-debian/ubuntu systems
        log_warning "Unsupported distribution for native apt install. Using official Docker convenience script..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm -f get-docker.sh
    fi

    log_info "Starting and enabling Docker service..."
    systemctl daemon-reload
    systemctl enable --now docker

    # Check if installation was successful
    if command -v docker >/dev/null 2>&1; then
        log_success "Docker installed successfully: $(docker --version)"
        log_success "Docker Compose installed successfully: $(docker compose version)"

        # Configure user permissions (optional but highly recommended)
        REAL_USER=${SUDO_USER:-""}
        if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
            log_info "Adding user '${REAL_USER}' to the docker group..."
            groupadd -f docker
            usermod -aG docker "$REAL_USER"
            log_success "User '${REAL_USER}' added to the 'docker' group."
            
            echo -e "\n${YELLOW}[IMPORTANT]${NC} To run docker commands without sudo, reload your session:"
            echo -e "  Option A: Log out and log back in."
            echo -e "  Option B: Run this command in your current terminal: ${BLUE}newgrp docker${NC}"
        fi
    else
        log_error "Installation completed, but the 'docker' command was not found in PATH."
    fi
}

# 2. Check Docker Service Status
do_check_status() {
    log_info "Checking Docker service daemon status..."
    if systemctl is-active --quiet docker; then
        log_success "Docker service is ACTIVE (running)."
    else
        log_warning "Docker service is INACTIVE (stopped)."
    fi
    echo ""
    # Output some basic server info
    if command -v docker >/dev/null 2>&1; then
        docker info | grep -E "Containers|Images|Server Version|Storage Driver|Kernel Version|Operating System" || true
    fi
}

# 3. Show Docker Disk Space Usage
do_disk_usage() {
    log_info "Docker disk space usage summary:"
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    docker system df
}

# 4. Stop All Running Containers
do_stop_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    local running_containers
    running_containers=$(docker ps -q)
    if [ -z "$running_containers" ]; then
        log_info "No running containers found."
        return 0
    fi
    log_warning "This will gracefully stop all currently running Docker containers!"
    read -rp "Are you sure you want to stop all containers? (y/n) [n]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Stopping containers..."
        docker stop $running_containers
        log_success "All running containers have been stopped."
    else
        log_info "Action cancelled."
    fi
}

# 5. Remove Unused Volumes
do_prune_volumes() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    log_warning "This will delete all unused local Docker volumes (volumes not attached to any container)."
    read -rp "Are you sure you want to proceed? (y/n) [n]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Pruning volumes..."
        docker volume prune -f
        log_success "Unused volumes cleared."
    else
        log_info "Action cancelled."
    fi
}

# 6. Remove Unused Images
do_prune_images() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    echo -e "\n${YELLOW}Choose Image Prune Scope:${NC}"
    echo "  1) Prune only dangling images (images without tags)"
    echo "  2) Prune all unused images (images not used by any container)"
    read -rp "Selection [1-2] [1]: " IMG_CHOICE
    IMG_CHOICE=${IMG_CHOICE:-1}
    
    read -rp "Are you sure you want to proceed? (y/n) [n]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        if [ "$IMG_CHOICE" = "2" ]; then
            log_info "Pruning all unused images..."
            docker image prune -a -f
        else
            log_info "Pruning dangling images..."
            docker image prune -f
        fi
        log_success "Unused images cleared."
    else
        log_info "Action cancelled."
    fi
}

# 7. Remove Unused Volumes & Images
do_prune_volumes_images() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    log_warning "This will delete all unused local volumes AND unused Docker images."
    read -rp "Are you sure you want to proceed? (y/n) [n]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Pruning local volumes..."
        docker volume prune -f
        log_info "Pruning unused images..."
        docker image prune -a -f
        log_success "Unused volumes and images successfully cleared."
      else
        log_info "Action cancelled."
    fi
}

# 8. Deep Clean System (System Prune)
do_system_prune() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    log_warning "This will delete ALL unused containers, networks, images (both dangling and unused), and local volumes!"
    log_warning "This is a complete deep clean of your Docker system."
    read -rp "Are you sure you want to proceed? (y/n) [n]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Executing deep system prune..."
        docker system prune -a --volumes -f
        log_success "Docker system fully pruned and cleaned!"
    else
        log_info "Action cancelled."
    fi
}

# 9. Restart Docker Service
do_restart_docker() {
    log_info "Restarting Docker daemon service..."
    systemctl restart docker
    log_success "Docker daemon service restarted successfully."
}

# ==========================================
# INTERACTIVE LOOP
# ==========================================

while true; do
    show_header
    
    echo -e "${YELLOW}Available Actions:${NC}"
    echo -e "  1) Install Docker & Docker Compose"
    echo -e "  2) Check Docker Service Status"
    echo -e "  3) Show Docker Disk Space Usage"
    echo -e "  4) Stop All Running Containers"
    echo -e "  5) Remove Unused Volumes (Volume Prune)"
    echo -e "  6) Remove Unused Images (Image Prune)"
    echo -e "  7) Remove Unused Volumes & Images"
    echo -e "  8) Deep Clean System (System Prune - All Unused Data)"
    echo -e "  9) Restart Docker Daemon Service"
    echo -e "  0) Exit Manager"
    echo -e "============================================================\n"
    
    read -rp "Please enter your selection [0-9]: " MENU_CHOICE
    
    case "$MENU_CHOICE" in
        1)
            do_install_docker
            ;;
        2)
            do_check_status
            ;;
        3)
            do_disk_usage
            ;;
        4)
            do_stop_containers
            ;;
        5)
            do_prune_volumes
            ;;
        6)
            do_prune_images
            ;;
        7)
            do_prune_volumes_images
            ;;
        8)
            do_system_prune
            ;;
        9)
            do_restart_docker
            ;;
        0)
            log_success "Exiting Docker Manager. Goodbye!"
            break
            ;;
        *)
            log_error "Invalid selection. Please try again."
            ;;
    esac
    
    echo -e "\nPress [ENTER] to return to the menu..."
    read -r _
done
