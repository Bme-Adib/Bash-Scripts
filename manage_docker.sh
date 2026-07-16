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

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Log Helpers ---
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
    local delay=0.15
    local spinstr='|/-\'
    tput civis 2>/dev/null || printf "\033[?25l" # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    tput cnorm 2>/dev/null || printf "\033[?25h" # Restore cursor
    printf "\b\b\b\b\b"
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

run_with_spinner() {
    local desc="$1"
    shift
    log_info "$desc"
    local log_file
    log_file=$(mktemp)
    "$@" >"$log_file" 2>&1 &
    local pid=$!
    show_spinner $pid
    wait $pid
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Command failed: $*"
        cat "$log_file" >&2
        rm -f "$log_file"
        return $exit_code
    fi
    rm -f "$log_file"
    return 0
}

# --- Header ---
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Docker Management & Optimization Tool ===${NC}\n"
}

# --- Parse Arguments ---
ACTION=""
NON_INTERACTIVE=false

while getopts "yisdtvmcur" opt; do
    case "$opt" in
        y) NON_INTERACTIVE=true ;;
        i) ACTION="install" ;;
        s) ACTION="status" ;;
        d) ACTION="disk" ;;
        t) ACTION="stop" ;;
        v) ACTION="prune_volumes" ;;
        m) ACTION="prune_images" ;;
        u) ACTION="prune_all" ;;
        c) ACTION="clean" ;;
        r) ACTION="restart" ;;
        *) echo "Usage: $0 [-y] [-i|-s|-d|-t|-v|-m|-u|-c|-r]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# --- Verification & Health Check ---
verify_docker_health() {
    log_info "Verifying Docker daemon health..."
    local docker_healthy=false
    for i in {1..15}; do
        if docker info >/dev/null 2>&1; then
            docker_healthy=true
            break
        fi
        sleep 1
    done
    if [ "$docker_healthy" = true ]; then
        log_success "Docker daemon is active and responding!"
        return 0
    else
        log_warning "Docker daemon failed to respond within 15 seconds."
        return 1
    fi
}

# ==========================================
# ACTION FUNCTIONS
# ==========================================

# 1. Install Docker & Compose V2
do_install_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker --version)
        log_success "Docker is already installed: ${docker_ver}"
        
        # Check if docker compose is also installed
        if docker compose version >/dev/null 2>&1; then
            log_success "Docker Compose V2 is already installed: $(docker compose version)"
        else
            log_warning "Docker Compose plugin is missing or not configured correctly."
        fi
        
        local force_install
        if [ "$NON_INTERACTIVE" = true ]; then
            force_install="n"
        else
            read -rp "Would you like to force reinstall/update Docker? (y/n) [n]: " force_install
            force_install=${force_install:-n}
        fi
        if [[ ! "$force_install" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_info "Detecting Operating System..."
    local os_id os_codename name version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_id=$ID
        os_codename=${VERSION_CODENAME:-""}
    else
        log_error "Could not detect Operating System. /etc/os-release not found."
        return 1
    fi

    log_info "OS Detected: ${NAME} (${VERSION:-unknown})"

    local confirm_install
    if [ "$NON_INTERACTIVE" = true ]; then
        confirm_install="y"
    else
        read -rp "Would you like to proceed with installing Docker and Docker Compose? (y/n) [y]: " confirm_install
        confirm_install=${confirm_install:-y}
    fi
    if [[ ! "$confirm_install" =~ ^[Yy]$ ]]; then
        log_warning "Installation cancelled by user."
        return 0
    fi

    # Perform installation
    if [ "$os_id" = "ubuntu" ] || [ "$os_id" = "debian" ] || [ "$os_id" = "raspbian" ] || [ "$os_id" = "pop" ] || [ "$os_id" = "linuxmint" ]; then
        run_with_spinner "Updating package lists..." apt-get update -y
        run_with_spinner "Installing transport dependencies..." apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings

        # Determine GPG key url and repo url
        local gpg_url="https://download.docker.com/linux/${os_id}/gpg"
        local repo_url="https://download.docker.com/linux/${os_id}"
        
        # Mint or Pop!_OS might map ID to mint/pop, we should point to ubuntu/debian base
        if [ "$os_id" = "pop" ] || [ "$os_id" = "linuxmint" ]; then
            gpg_url="https://download.docker.com/linux/ubuntu/gpg"
            repo_url="https://download.docker.com/linux/ubuntu"
            os_codename=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
        fi

        run_with_spinner "Adding Docker official GPG key..." bash -c "curl -fsSL '$gpg_url' | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg"

        log_info "Adding Docker apt repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url \
          ${os_codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        run_with_spinner "Updating package lists (Docker repository)..." apt-get update -y
        run_with_spinner "Installing Docker engine packages..." apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # Fallback to official convenience script for non-debian/ubuntu systems
        log_warning "Unsupported distribution for native apt install. Using official Docker convenience script..."
        local temp_script
        temp_script=$(mktemp)
        curl -fsSL https://get.docker.com -o "$temp_script"
        run_with_spinner "Installing Docker via convenience script..." sh "$temp_script"
        rm -f "$temp_script"
    fi

    log_info "Starting and enabling Docker service..."
    systemctl daemon-reload
    systemctl enable --now docker

    verify_docker_health

    # Check if installation was successful
    if command -v docker >/dev/null 2>&1; then
        # Configure user permissions (optional but highly recommended)
        local real_user
        real_user=${SUDO_USER:-$(logname 2>/dev/null || echo "root")}
        if [ -n "$real_user" ] && [ "$real_user" != "root" ]; then
            log_info "Adding user '${real_user}' to the docker group..."
            groupadd -f docker
            usermod -aG docker "$real_user"
            
            box_message "DOCKER USER GROUP CONFIGURED" \
                "User '${real_user}' added to the 'docker' group." \
                "To run docker commands without sudo, reload your session:" \
                "  Option A: Log out and log back in." \
                "  Option B: Run: newgrp docker"
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
    
    local confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        confirm="y"
    else
        log_warning "This will gracefully stop all currently running Docker containers!"
        read -rp "Are you sure you want to stop all containers? (y/n) [n]: " confirm
        confirm=${confirm:-n}
    fi

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Stopping containers..."
        docker stop $running_containers &
        show_spinner $!
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
    
    local confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        confirm="y"
    else
        log_warning "This will delete all unused local Docker volumes (volumes not attached to any container)."
        read -rp "Are you sure you want to proceed? (y/n) [n]: " confirm
        confirm=${confirm:-n}
    fi

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Pruning volumes..."
        docker volume prune -f >/dev/null 2>&1 &
        show_spinner $!
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
    
    local img_choice confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        img_choice=1
        confirm="y"
    else
        echo -e "\n${YELLOW}Choose Image Prune Scope:${NC}"
        echo "  1) Prune only dangling images (images without tags)"
        echo "  2) Prune all unused images (images not used by any container)"
        read -rp "Selection [1-2] [1]: " img_choice
        img_choice=${img_choice:-1}
        
        read -rp "Are you sure you want to proceed? (y/n) [n]: " confirm
        confirm=${confirm:-n}
    fi
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ "$img_choice" = "2" ]; then
            log_info "Pruning all unused images..."
            docker image prune -a -f >/dev/null 2>&1 &
            show_spinner $!
        else
            log_info "Pruning dangling images..."
            docker image prune -f >/dev/null 2>&1 &
            show_spinner $!
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
    
    local confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        confirm="y"
    else
        log_warning "This will delete all unused local volumes AND unused Docker images."
        read -rp "Are you sure you want to proceed? (y/n) [n]: " confirm
        confirm=${confirm:-n}
    fi

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Pruning local volumes..."
        docker volume prune -f >/dev/null 2>&1 &
        show_spinner $!
        log_info "Pruning unused images..."
        docker image prune -a -f >/dev/null 2>&1 &
        show_spinner $!
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
    
    local confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        confirm="y"
    else
        log_warning "This will delete ALL unused containers, networks, images (both dangling and unused), and local volumes!"
        log_warning "This is a complete deep clean of your Docker system."
        read -rp "Are you sure you want to proceed? (y/n) [n]: " confirm
        confirm=${confirm:-n}
    fi

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Executing deep system prune..."
        docker system prune -a --volumes -f >/dev/null 2>&1 &
        show_spinner $!
        log_success "Docker system fully pruned and cleaned!"
    else
        log_info "Action cancelled."
    fi
}

# 9. Restart Docker Service
do_restart_docker() {
    log_info "Restarting Docker daemon service..."
    systemctl restart docker &
    show_spinner $!
    verify_docker_health
}

# ==========================================
# MAIN EXECUTION
# ==========================================
main() {
    # Ensure script is run with sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        show_header
        log_error "This utility requires administrative privileges. Please run with sudo:"
        echo -e "  ${YELLOW}sudo $0${NC}"
        exit 1
    fi

    if [ -n "$ACTION" ]; then
        case "$ACTION" in
            install) do_install_docker ;;
            status) do_check_status ;;
            disk) do_disk_usage ;;
            stop) do_stop_containers ;;
            prune_volumes) do_prune_volumes ;;
            prune_images) do_prune_images ;;
            prune_all) do_prune_volumes_images ;;
            clean) do_system_prune ;;
            restart) do_restart_docker ;;
        esac
        exit 0
    fi

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
            1) do_install_docker ;;
            2) do_check_status ;;
            3) do_disk_usage ;;
            4) do_stop_containers ;;
            5) do_prune_volumes ;;
            6) do_prune_images ;;
            7) do_prune_volumes_images ;;
            8) do_system_prune ;;
            9) do_restart_docker ;;
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
}

main "$@"
