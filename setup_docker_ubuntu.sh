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
    echo -e "${BLUE}=== Ubuntu Playground Container Auto-Setup ===${NC}\n"
}

# --- Getopts Argument Parsing ---
NON_INTERACTIVE=false
UBUNTU_VERSION_VAL=""
CONTAINER_NAME_VAL=""
ENABLE_SSH_VAL=""
SSH_PORT_VAL=""
SSH_USER_TYPE_VAL=""
SSH_USER_VAL=""
SSH_PASS_VAL=""
ENABLE_MOUNT_VAL=""
HOST_DIR_VAL=""
CONTAINER_DIR_VAL=""
EXTRA_PACKAGES_VAL=""
ENABLE_DOCKER_VAL=""
DOCKER_NET_VAL=""
ENABLE_LIMITS_VAL=""
CPU_LIMIT_VAL=""
MEM_LIMIT_VAL=""
DEPLOY_CONFIRM_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h             Show this help message"
    echo "  -y             Run non-interactively (use defaults)"
    echo "  -v VERSION     Ubuntu Version (latest/24.04/22.04/20.04)"
    echo "  -c NAME        Container name"
    echo "  -s SSH_BOOL    Enable SSH access (y/n)"
    echo "  -p PORT        Host SSH port mapping"
    echo "  -t USER_TYPE   SSH user type (root/user)"
    echo "  -u USERNAME    SSH username"
    echo "  -w PASSWORD    SSH password"
    echo "  -m MOUNT_BOOL  Enable volume mount (y/n)"
    echo "  -i HOST_DIR    Host directory to mount"
    echo "  -r CONT_DIR    Container directory to map mount to"
    echo "  -k PACKAGES    Extra apt packages to pre-install (space-separated)"
    echo "  -e DOCKER_BOOL Enable Docker-in-Docker socket mounting (y/n)"
    echo "  -n NET_NAME    Docker network name"
    echo "  -l LIMITS_BOOL Enable resource limits (y/n)"
    echo "  -x CPU         CPU core limit (e.g., 1.5)"
    echo "  -g MEM         Memory limit (e.g., 512m)"
    echo "  -o DEPLOY_CONF Deploy container automatically (y/n)"
}

while getopts "hyv:c:s:p:t:u:w:m:i:r:k:e:n:l:x:g:o:" opt; do
    case "$opt" in
        h) print_help; exit 0 ;;
        y) NON_INTERACTIVE=true ;;
        v) UBUNTU_VERSION_VAL="$OPTARG" ;;
        c) CONTAINER_NAME_VAL="$OPTARG" ;;
        s) ENABLE_SSH_VAL="$OPTARG" ;;
        p) SSH_PORT_VAL="$OPTARG" ;;
        t) SSH_USER_TYPE_VAL="$OPTARG" ;;
        u) SSH_USER_VAL="$OPTARG" ;;
        w) SSH_PASS_VAL="$OPTARG" ;;
        m) ENABLE_MOUNT_VAL="$OPTARG" ;;
        i) HOST_DIR_VAL="$OPTARG" ;;
        r) CONTAINER_DIR_VAL="$OPTARG" ;;
        k) EXTRA_PACKAGES_VAL="$OPTARG" ;;
        e) ENABLE_DOCKER_VAL="$OPTARG" ;;
        n) DOCKER_NET_VAL="$OPTARG" ;;
        l) ENABLE_LIMITS_VAL="$OPTARG" ;;
        x) CPU_LIMIT_VAL="$OPTARG" ;;
        g) MEM_LIMIT_VAL="$OPTARG" ;;
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
    echo -e "\n${BLUE}>>> Step 1: Base Container Configuration${NC}"
    
    UBUNTU_VERSION=${UBUNTU_VERSION_VAL:-""}
    if [ -z "$UBUNTU_VERSION" ]; then
        while true; do
            prompt_input "Select Ubuntu version (latest/24.04/22.04/20.04)" "latest" UBUNTU_VERSION
            if [[ "$UBUNTU_VERSION" =~ ^(latest|24\.04|22\.04|20\.04)$ ]]; then
                break
            fi
            log_error "Invalid version. Choose from: latest, 24.04, 22.04, 20.04."
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
    fi

    CONTAINER_NAME=${CONTAINER_NAME_VAL:-""}
    if [ -z "$CONTAINER_NAME" ]; then
        while true; do
            prompt_input "Enter container name" "ubuntu-playground" CONTAINER_NAME
            if [[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                break
            fi
            log_error "Invalid container name. Use alphanumeric characters, hyphens, and underscores only."
            if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
        done
    fi

    echo -e "\n${BLUE}>>> Step 2: Configure Access Method${NC}"
    ENABLE_SSH=${ENABLE_SSH_VAL:-""}
    if [ -z "$ENABLE_SSH" ]; then
        prompt_yes_no "Would you like to enable SSH access in this container?" "y" ENABLE_SSH
    fi

    SSH_PORT="2222"
    SSH_USER_TYPE="root"
    SSH_USER="root"
    SSH_PASS="ubuntu"

    if [[ "$ENABLE_SSH" =~ ^[Yy]$ || "$ENABLE_SSH" = "true" ]]; then
        ENABLE_SSH="y"
        
        # SSH Port
        PORT_VALIDATED=false
        if [ -n "$SSH_PORT_VAL" ]; then
            SSH_PORT="$SSH_PORT_VAL"
            PORT_VALIDATED=true
        fi
        
        while [ "$PORT_VALIDATED" = false ]; do
            prompt_input "Enter host SSH port to map" "2222" SSH_PORT
            if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
                log_error "Invalid port. Must be an integer between 1 and 65535."
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
                continue
            fi
            
            if check_port_in_use "$SSH_PORT"; then
                log_warning "Port $SSH_PORT is already in use on the host system."
                prompt_yes_no "Would you like to use this port anyway?" "n" CONFIRM_PORT
                if [[ "$CONFIRM_PORT" =~ ^[Yy]$ ]]; then
                    PORT_VALIDATED=true
                fi
            else
                PORT_VALIDATED=true
            fi
        done

        # User Type
        SSH_USER_TYPE=${SSH_USER_TYPE_VAL:-""}
        if [ -z "$SSH_USER_TYPE" ]; then
            while true; do
                prompt_input "Configure root or a standard non-root user? (root/user)" "root" SSH_USER_TYPE
                if [[ "$SSH_USER_TYPE" =~ ^(root|user)$ ]]; then
                    break
                fi
                log_error "Invalid user type. Please enter 'root' or 'user'."
                if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
            done
        fi

        if [ "$SSH_USER_TYPE" = "user" ]; then
            SSH_USER=${SSH_USER_VAL:-""}
            if [ -z "$SSH_USER" ]; then
                while true; do
                    prompt_input "Enter username" "developer" SSH_USER
                    if [[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
                        break
                    fi
                    log_error "Invalid username. Must start with lowercase/underscore, followed by lowercase, numbers, hyphens or underscores."
                    if [ "$NON_INTERACTIVE" = "true" ]; then exit 1; fi
                done
            fi
        else
            SSH_USER="root"
        fi

        # Password
        SSH_PASS=${SSH_PASS_VAL:-""}
        if [ -z "$SSH_PASS" ]; then
            if [ "$NON_INTERACTIVE" = "true" ]; then
                SSH_PASS="ubuntu"
            else
                read -rsp "Enter password for '$SSH_USER' user [ubuntu]: " SSH_PASS
                echo ""
                SSH_PASS=${SSH_PASS:-ubuntu}
            fi
        fi
    else
        ENABLE_SSH="n"
    fi

    echo -e "\n${BLUE}>>> Step 3: Configure Storage & Volume Mounts${NC}"
    ENABLE_MOUNT=${ENABLE_MOUNT_VAL:-""}
    if [ -z "$ENABLE_MOUNT" ]; then
        prompt_yes_no "Would you like to mount a host directory for persistent data?" "n" ENABLE_MOUNT
    fi

    HOST_DIR=""
    CONTAINER_DIR=""
    if [[ "$ENABLE_MOUNT" =~ ^[Yy]$ || "$ENABLE_MOUNT" = "true" ]]; then
        ENABLE_MOUNT="y"
        HOST_DIR=${HOST_DIR_VAL:-""}
        if [ -z "$HOST_DIR" ]; then
            prompt_input "Enter host directory to map (can be relative/absolute)" "./data" HOST_DIR
        fi
        CONTAINER_DIR=${CONTAINER_DIR_VAL:-""}
        if [ -z "$CONTAINER_DIR" ]; then
            prompt_input "Enter container directory to map it to" "/workspace" CONTAINER_DIR
        fi
    else
        ENABLE_MOUNT="n"
    fi

    echo -e "\n${BLUE}>>> Step 4: Packages & Utility Configuration${NC}"
    EXTRA_PACKAGES=${EXTRA_PACKAGES_VAL:-""}
    if [ -z "$EXTRA_PACKAGES" ]; then
        prompt_input "Enter extra apt packages to pre-install (space-separated)" "curl git wget vim sudo" EXTRA_PACKAGES
    fi

    ENABLE_DOCKER=${ENABLE_DOCKER_VAL:-""}
    if [ -z "$ENABLE_DOCKER" ]; then
        prompt_yes_no "Would you like to enable Docker command execution inside the container?" "n" ENABLE_DOCKER
    fi

    echo -e "\n${BLUE}>>> Step 5: Network & Limits Configuration${NC}"
    DOCKER_NET=""
    if [ -z "$DOCKER_NET_VAL" ]; then
        log_info "Detecting active Docker networks on host..."
        if docker network ls >/dev/null 2>&1; then
            echo -e "${YELLOW}Existing Docker Networks on this server:${NC}"
            docker network ls --format "  - {{.Name}}" | grep -vE "host|none" || echo "  No custom networks found."
            echo ""
        fi
        prompt_input "Enter the name of your docker network" "bridge" DOCKER_NET
        
        if [ "$DOCKER_NET" != "bridge" ]; then
            if ! docker network inspect "$DOCKER_NET" >/dev/null 2>&1; then
                log_warning "Docker network '${DOCKER_NET}' does not exist."
                prompt_yes_no "Would you like to create the '${DOCKER_NET}' network now?" "y" CREATE_NET
                if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
                    docker network create "$DOCKER_NET"
                    log_success "Created external docker network: ${DOCKER_NET}"
                else
                    log_warning "Skipping network creation. Docker compose may fail if it is missing."
                fi
            fi
        fi
    else
        DOCKER_NET="$DOCKER_NET_VAL"
        if [ "$DOCKER_NET" != "bridge" ] && ! docker network inspect "$DOCKER_NET" >/dev/null 2>&1; then
            log_info "Creating network $DOCKER_NET as specified by options..."
            docker network create "$DOCKER_NET"
        fi
    fi

    # Resource Limits
    ENABLE_LIMITS=${ENABLE_LIMITS_VAL:-""}
    if [ -z "$ENABLE_LIMITS" ]; then
        prompt_yes_no "Would you like to set CPU or Memory limits?" "n" ENABLE_LIMITS
    fi

    CPU_LIMIT=""
    MEM_LIMIT=""
    LIMITS_BLOCK=""
    if [[ "$ENABLE_LIMITS" =~ ^[Yy]$ || "$ENABLE_LIMITS" = "true" ]]; then
        ENABLE_LIMITS="y"
        CPU_LIMIT=${CPU_LIMIT_VAL:-""}
        if [ -z "$CPU_LIMIT_VAL" ] && [ "$NON_INTERACTIVE" = "false" ]; then
            read -rp "Enter CPU limit (e.g. 1.5 for 1.5 cores, leave empty for no limit): " CPU_LIMIT
        fi
        
        MEM_LIMIT=${MEM_LIMIT_VAL:-""}
        if [ -z "$MEM_LIMIT_VAL" ] && [ "$NON_INTERACTIVE" = "false" ]; then
            read -rp "Enter Memory limit (e.g. 512m, 2g, leave empty for no limit): " MEM_LIMIT
        fi
        
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
    else
        ENABLE_LIMITS="n"
    fi

    # 3. Create Deployment Directory
    TARGET_DIR="$(pwd)/${CONTAINER_NAME}Container"
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

    if [[ "$ENABLE_MOUNT" = "y" ]]; then
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

    if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ || "$ENABLE_DOCKER" = "true" ]]; then
        cat <<EOF >> "${TARGET_DIR}/Dockerfile"

# Install Docker CLI and Docker Compose
RUN apt-get update && \\
    (apt-get install -y docker.io docker-compose-v2 || apt-get install -y docker.io docker-compose) && \\
    rm -rf /var/lib/apt/lists/*
EOF
    fi

    if [[ "$ENABLE_SSH" = "y" ]]; then
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
            if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ || "$ENABLE_DOCKER" = "true" ]]; then
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

    if [[ "$ENABLE_SSH" = "y" ]]; then
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

    if [[ "$ENABLE_MOUNT" = "y" ]] || [[ "$ENABLE_DOCKER" =~ ^[Yy]$ || "$ENABLE_DOCKER" = "true" ]]; then
        cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
    volumes:
EOF
        if [[ "$ENABLE_MOUNT" = "y" ]]; then
            cat <<EOF >> "${TARGET_DIR}/docker-compose.yml"
      - "${HOST_DIR}:${CONTAINER_DIR}"
EOF
        fi
        if [[ "$ENABLE_DOCKER" =~ ^[Yy]$ || "$ENABLE_DOCKER" = "true" ]]; then
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

    DEPLOY_CONFIRM="y"
    if [ -z "$DEPLOY_CONFIRM_VAL" ]; then
        prompt_yes_no "Deploy the Ubuntu container now?" "y" DEPLOY_CONFIRM
    else
        DEPLOY_CONFIRM="$DEPLOY_CONFIRM_VAL"
    fi

    if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ || "$DEPLOY_CONFIRM" = "true" ]]; then
        log_info "Building and starting container..."
        local_log=$(mktemp)
        (cd "$TARGET_DIR" && $DOCKER_COMPOSE_CMD up -d --build) >"$local_log" 2>&1 &
        show_spinner $!
        if ! wait $!; then
            log_error "Deployment failed! Output:"
            cat "$local_log"
            rm -f "$local_log"
            exit 1
        fi
        rm -f "$local_log"
        
        # Verify Service Health
        verify_container_health "$CONTAINER_NAME" "N/A"
        
        if [[ "$ENABLE_SSH" = "y" ]]; then
            log_info "Clearing host SSH key registry for port ${SSH_PORT} to prevent host key verification conflicts..."
            ssh-keygen -R "[localhost]:${SSH_PORT}" >/dev/null 2>&1 || true
        fi
    else
        log_warning "Deployment skipped. You can manually launch it later."
    fi

    # Print Summary Box
    local HOST_IP
    HOST_IP=$(detect_ip)
    
    local ssh_status="Disabled"
    if [[ "$ENABLE_SSH" = "y" ]]; then
        ssh_status="Enabled (Host Port: ${SSH_PORT})"
    fi

    echo -e "\n"
    box_message "Deployment Summary" \
        "Container Name:   ${CONTAINER_NAME}" \
        "Ubuntu Version:   ${UBUNTU_VERSION}" \
        "SSH Access:       ${ssh_status}" \
        "SSH User/Pass:    ${SSH_USER}/${SSH_PASS}" \
        "Docker Socket:    ${ENABLE_DOCKER}" \
        "Install Directory:${TARGET_DIR}"

    if [[ "$ENABLE_SSH" = "y" ]]; then
        echo -e "\nTo log in via SSH, run:\n"
        echo -e "  ${YELLOW}ssh ${SSH_USER}@${HOST_IP} -p ${SSH_PORT}${NC}  (or localhost)"
    else
        echo -e "\nTo access the container shell via docker exec, run:\n"
        echo -e "  ${YELLOW}docker exec -it ${CONTAINER_NAME} bash${NC}"
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
}

main "$@"
