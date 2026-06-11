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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Docker & Docker Compose Installer ===${NC}\n"

# 1. Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
    DOCKER_VER=$(docker --version)
    log_success "Docker is already installed: ${DOCKER_VER}"
    
    # Check if docker compose is also installed
    if docker compose version >/dev/null 2>&1; then
        log_success "Docker Compose V2 is already installed: $(docker compose version)"
    else
        log_warning "Docker Compose plugin is missing or not configured correctly."
    fi
    exit 0
fi

# 2. Check if running with root/sudo privileges (required for installation)
if [ "$EUID" -ne 0 ]; then
    log_error "This installation script requires root privileges. Please run with sudo:"
    echo -e "  ${YELLOW}sudo $0${NC}"
    exit 1
fi

# 3. Detect OS
log_info "Detecting Operating System..."
if [ -f /etc/os-release ]; then
    # Load variables from os-release
    . /etc/os-release
    OS_ID=$ID
    OS_CODENAME=${VERSION_CODENAME:-""}
else
    log_error "Could not detect Operating System. /etc/os-release not found."
    exit 1
fi

log_info "OS Detected: ${NAME} (${VERSION:-unknown})"

# Confirm before installation
read -rp "Would you like to proceed with installing Docker and Docker Compose? (y/n) [y]: " CONFIRM_INSTALL
CONFIRM_INSTALL=${CONFIRM_INSTALL:-y}

if [[ ! "$CONFIRM_INSTALL" =~ ^[Yy]$ ]]; then
    log_warning "Installation cancelled by user."
    exit 0
fi

# 4. Perform installation
if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "raspbian" ] || [ "$OS_ID" = "pop" ] || [ "$OS_ID" = "linuxmint" ]; then
    log_info "Starting Docker installation via apt repository..."
    
    # Update package index and install initial prerequisites
    log_info "Updating package lists and installing pre-requisites..."
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # Create keyrings directory
    mkdir -p /etc/apt/keyrings

    # Determine GPG key url and repo url
    GPG_URL="https://download.docker.com/linux/${OS_ID}/gpg"
    REPO_URL="https://download.docker.com/linux/${OS_ID}"
    
    # Mint or Pop!_OS might map ID to mint/pop, we should point to ubuntu/debian base
    if [ "$OS_ID" = "pop" ] || [ "$OS_ID" = "linuxmint" ]; then
        # Use ubuntu as base
        GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
        REPO_URL="https://download.docker.com/linux/ubuntu"
        # We need the parent OS version codename
        OS_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
    fi

    # Add Docker's official GPG key
    log_info "Adding Docker official GPG key..."
    curl -fsSL "$GPG_URL" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    log_info "Adding Docker apt repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $REPO_URL \
      ${OS_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker engines
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

# 5. Enable and start Docker service
log_info "Starting and enabling Docker service..."
systemctl daemon-reload
systemctl enable --now docker

# Check if installation was successful
if command -v docker >/dev/null 2>&1; then
    log_success "Docker installed successfully: $(docker --version)"
    log_success "Docker Compose installed successfully: $(docker compose version)"
    
    # 6. Configure user permissions (optional but highly recommended)
    # Get the real user if run via sudo
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
    exit 1
fi

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}                 Docker Installation Finished!              ${NC}"
echo -e "${GREEN}============================================================${NC}\n"
