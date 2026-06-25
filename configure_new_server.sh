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

# --- Resolve Invoking User ---
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "root")}

# --- Header ---
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== VPS & Laptop Server Auto-Configuration Utility ===${NC}\n"
}

# --- System Stats ---
show_system_stats() {
    echo -e "${BLUE}=== Host System Statistics ===${NC}"
    # OS Name
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "OS:          ${GREEN}${NAME} ${VERSION:-}${NC}"
    fi
    # Kernel
    echo -e "Kernel:      ${NC}$(uname -r)"
    # CPU Model
    if command -v lscpu >/dev/null 2>&1; then
        CPU_MODEL=$(lscpu | grep "Model name:" | sed -e 's/Model name:\s*//g' || echo "Unknown")
        echo -e "CPU Model:   ${NC}${CPU_MODEL}"
    fi
    # BIOS
    local bios_vendor bios_version
    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "")
    bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "")
    if [ -n "$bios_vendor" ] || [ -n "$bios_version" ]; then
        echo -e "BIOS:        ${NC}${bios_vendor} ${bios_version}"
    fi
    # RAM
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    echo -e "RAM (Total): ${GREEN}${TOTAL_RAM}${NC} (Free: ${FREE_RAM})"
    # Storage
    echo -e "Disk Storage:"
    df -h | grep -E '^/dev/' | while read -r line; do
        local dev size used avail percent mount
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        percent=$(echo "$line" | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')
        echo -e "  - ${dev} (${mount}): Total: ${size} | Free: ${GREEN}${avail}${NC} (Used: ${percent})"
    done
    echo -e "${BLUE}===========================================${NC}\n"
}

# Ensure script is run with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
    show_header
    log_error "This setup script requires administrative privileges. Please run with sudo:"
    echo -e "  ${YELLOW}sudo $0${NC}"
    exit 1
fi

# ==========================================
# SYSTEM & SECURITY SETUP FUNCTIONS
# ==========================================

# 11. Update and Upgrade
do_update_upgrade() {
    log_info "Updating package lists and upgrading all packages..."
    apt-get update -y
    apt-get upgrade -y
    
    log_info "Installing essential utility packages (curl, wget, git, htop, btop, tmux, build-essential)..."
    apt-get install -y curl wget git htop btop tmux build-essential || log_warning "Some packages failed to install."
    
    log_success "System packages updated, upgraded, and utility tools installed successfully."
}

# 12. Create Sudo User
do_create_sudo_user() {
    log_info "Creating a new sudo user..."
    read -rp "Enter Username: " NEW_USER
    while [ -z "$NEW_USER" ]; do
        log_error "Username cannot be empty."
        read -rp "Enter Username: " NEW_USER
    done

    # Check if user already exists
    if id "$NEW_USER" >/dev/null 2>&1; then
        log_warning "User '${NEW_USER}' already exists."
        return 0
    fi

    # Read password securely
    read -rsp "Enter Password for ${NEW_USER}: " NEW_PASS
    echo ""
    read -rsp "Confirm Password: " NEW_PASS_CONFIRM
    echo ""

    if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
        log_error "Passwords do not match."
        return 1
    fi

    # Create user with bash shell and home folder
    useradd -m -s /bin/bash "$NEW_USER"
    echo "${NEW_USER}:${NEW_PASS}" | chpasswd
    usermod -aG sudo "$NEW_USER"
    log_success "User '${NEW_USER}' created and added to the sudo group."
    
    # Switch to user immediately if requested
    read -rp "Switch to user '${NEW_USER}' now? (y/n) [y]: " SWITCH_NOW
    SWITCH_NOW=${SWITCH_NOW:-y}
    if [[ "$SWITCH_NOW" =~ ^[Yy]$ ]]; then
        log_info "Switching session to '${NEW_USER}'. Type 'exit' to return to configuration utility."
        su - "$NEW_USER"
    fi
}

# 13. Configure SSH (SSH Keys, Port, Disable Password/Root Login)
do_configure_ssh() {
    log_info "Configuring SSH Server Hardening..."
    
    # Install openssh-server if missing
    if ! dpkg -l | grep -q openssh-server; then
        log_info "Installing openssh-server..."
        apt-get update && apt-get install -y openssh-server
    fi
    
    systemctl enable --now ssh
    
    # Part A: Add SSH key
    read -rp "Would you like to add an Authorized SSH Public Key? (y/n) [y]: " ADD_KEY
    ADD_KEY=${ADD_KEY:-y}
    if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
        read -rp "For which user should we add the SSH key? [${REAL_USER}]: " SSH_USER
        SSH_USER=${SSH_USER:-$REAL_USER}
        
        if ! id "$SSH_USER" >/dev/null 2>&1; then
            log_error "User '$SSH_USER' does not exist."
            return 1
        fi
        
        local user_home
        user_home=$(eval echo "~$SSH_USER")
        
        read -rp "Enter SSH Public Key (starts with ssh-rsa, ssh-ed25519, etc.): " SSH_KEY
        if [ -n "$SSH_KEY" ]; then
            mkdir -p "${user_home}/.ssh"
            chmod 700 "${user_home}/.ssh"
            echo "$SSH_KEY" >> "${user_home}/.ssh/authorized_keys"
            chmod 600 "${user_home}/.ssh/authorized_keys"
            chown -R "${SSH_USER}:${SSH_USER}" "${user_home}/.ssh"
            log_success "SSH key successfully appended to ${user_home}/.ssh/authorized_keys."
        else
            log_warning "Empty SSH key entered. Skipping key addition."
        fi
    fi

    # Part B: Change SSH Port
    local current_port
    current_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -n1 || echo "22")
    log_info "Current SSH Port is: ${current_port}"
    read -rp "Change default SSH Port? (y/n) [n]: " CHANGE_PORT
    CHANGE_PORT=${CHANGE_PORT:-n}
    local new_port="${current_port}"
    if [[ "$CHANGE_PORT" =~ ^[Yy]$ ]]; then
        read -rp "Enter new SSH Port (1-65535) [22]: " INPUT_PORT
        INPUT_PORT=${INPUT_PORT:-22}
        if [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PORT" -ge 1 ] && [ "$INPUT_PORT" -le 65535 ]; then
            new_port="$INPUT_PORT"
            log_info "Port target set to ${new_port}."
        else
            log_error "Invalid port number. Keeping current port ${current_port}."
        fi
    fi

    # Part C: Disable Root Login
    read -rp "Disable root SSH login? (y/n) [y]: " DISABLE_ROOT
    DISABLE_ROOT=${DISABLE_ROOT:-y}

    # Part D: Disable Password Authentication
    read -rp "Disable SSH password authentication (require SSH keys)? (y/n) [n]: " DISABLE_PASSWD
    DISABLE_PASSWD=${DISABLE_PASSWD:-n}

    # Backup sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Configure SSH options
    # Remove existing definitions first to avoid duplicate entries
    sed -i '/^#\?Port/d' /etc/ssh/sshd_config
    sed -i '/^#\?PermitRootLogin/d' /etc/ssh/sshd_config
    sed -i '/^#\?PasswordAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^#\?PubkeyAuthentication/d' /etc/ssh/sshd_config

    # Append new configurations
    echo "Port ${new_port}" >> /etc/ssh/sshd_config
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    
    if [[ "$DISABLE_ROOT" =~ ^[Yy]$ ]]; then
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config
        log_info "PermitRootLogin set to no."
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        log_info "PermitRootLogin set to yes."
    fi

    if [[ "$DISABLE_PASSWD" =~ ^[Yy]$ ]]; then
        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
        log_info "PasswordAuthentication set to no."
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
        log_info "PasswordAuthentication set to yes."
    fi

    # Restart ssh/sshd service
    local restarted=false
    if systemctl restart ssh 2>/dev/null; then
        restarted=true
    elif systemctl restart sshd 2>/dev/null; then
        restarted=true
    fi

    if [ "$restarted" = true ]; then
        log_success "SSH service restarted and configured on port ${new_port}."
    else
        log_warning "Could not restart SSH service automatically. Please run 'sudo systemctl restart ssh' manually."
    fi

    if [ "$new_port" != "22" ]; then
        log_warning "IMPORTANT: Remember to open the new SSH port ${new_port} in your firewall (e.g. UFW) before logging out!"
    fi
    log_warning "CRITICAL: Do NOT close this terminal session yet. Open a NEW terminal window and test connecting via: 'ssh -p ${new_port} user@host' to ensure you are not locked out!"
}

# 14. Install & Configure Fail2Ban (Brute-force protection)
do_configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "Installing fail2ban..."
        apt-get update && apt-get install -y fail2ban
    fi
    
    # Retrieve current SSH port to configure jail
    local ssh_port
    ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -n1 || echo "22")
    
    # Create custom jail.local configuration
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${ssh_port}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

    systemctl daemon-reload
    systemctl enable --now fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2Ban successfully configured to monitor SSH on port ${ssh_port}."
}

# 15. Enable Firewall (UFW)
do_configure_firewall() {
    log_info "Configuring UFW Firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get install -y ufw
    fi
    
    # Set default behaviors
    ufw default deny incoming
    ufw default allow outgoing
    
    # Detect configured SSH port
    local ssh_port
    ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -n1 || echo "22")
    
    log_info "Allowing SSH connection on port ${ssh_port}..."
    ufw allow "${ssh_port}/tcp"
    
    # Also open standard port 22 just to prevent lockout during transition
    if [ "$ssh_port" != "22" ]; then
        ufw allow 22/tcp
        log_info "Standard SSH port 22 opened as a backup."
    fi
    
    # Enable firewall (force skips the confirmation prompt)
    ufw --force enable
    log_success "UFW firewall enabled. Closed all incoming traffic except port ${ssh_port}. All outgoing allowed."
}

# 16. Laptop Server: Disable Suspend on Lid Close
do_laptop_lid_action() {
    log_info "Configuring Laptop Server: Disabling suspend on lid close..."
    
    local logind_conf="/etc/systemd/logind.conf"
    if [ -f "$logind_conf" ]; then
        # Backup
        cp "$logind_conf" "${logind_conf}.bak"
        
        # Replace or add keys
        sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$logind_conf"
        sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$logind_conf"
        sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$logind_conf"
        
        # Verify if they were added (if not replaced)
        if ! grep -q "^HandleLidSwitch=" "$logind_conf"; then
            echo "HandleLidSwitch=ignore" >> "$logind_conf"
        fi
        if ! grep -q "^HandleLidSwitchExternalPower=" "$logind_conf"; then
            echo "HandleLidSwitchExternalPower=ignore" >> "$logind_conf"
        fi
        if ! grep -q "^HandleLidSwitchDocked=" "$logind_conf"; then
            echo "HandleLidSwitchDocked=ignore" >> "$logind_conf"
        fi
        
        log_info "Restarting systemd-logind service to apply changes..."
        systemctl restart systemd-logind || log_warning "Could not restart systemd-logind automatically. Please reboot to apply."
        log_success "Laptop lid close suspend behavior disabled. The server will now remain running when screen is closed."
    else
        log_error "/etc/systemd/logind.conf not found. This does not look like a systemd system."
    fi
}

# ==========================================
# NETWORK & TIME SETTINGS FUNCTIONS
# ==========================================

# 21. Assign Static IP Address
do_static_ip() {
    log_info "Configuring Static IP Address..."
    
    # Detect default network interface
    local active_iface
    active_iface=$(ip route | grep default | awk '{print $5}' | head -n1 || echo "")
    if [ -z "$active_iface" ]; then
        active_iface=$(ip -br link show | grep -v "lo" | awk '{print $1}' | head -n1 || echo "")
    fi
    
    read -rp "Enter Network Interface Name [$active_iface]: " IFACE
    IFACE=${IFACE:-$active_iface}
    
    read -rp "Enter Static IP with Subnet Mask (e.g. 192.168.1.100/24): " IP_ADDR
    while [[ ! "$IP_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; do
        log_error "Invalid format. Please use CIDR notation (e.g. 192.168.1.100/24)."
        read -rp "Enter Static IP with Subnet Mask: " IP_ADDR
    done
    
    read -rp "Enter Default Gateway IP (e.g. 192.168.1.1): " GATEWAY
    while [[ ! "$GATEWAY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        log_error "Invalid IP format."
        read -rp "Enter Default Gateway IP: " GATEWAY
    done
    
    read -rp "Enter DNS Servers (comma-separated) [8.8.8.8,8.8.4.4]: " DNS_SERVERS
    DNS_SERVERS=${DNS_SERVERS:-"8.8.8.8,8.8.4.4"}
    
    local formatted_dns
    formatted_dns=$(echo "$DNS_SERVERS" | sed 's/\s*,\s*/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    # Backup current netplan configurations
    mkdir -p /etc/netplan/backup
    cp -r /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
    
    # Disable cloud-init network config if active to prevent overrides
    if [ -d /etc/cloud/cloud.cfg.d ]; then
        echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg || true
    fi
    
    # Clear out other configs in netplan directory to avoid interference (moved to backup)
    mv /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
    
    # Generate static configuration
    local netplan_file="/etc/netplan/99-static-ip.yaml"
    cat <<EOF > "$netplan_file"
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${IP_ADDR}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: ${formatted_dns}
EOF
    
    chmod 600 "$netplan_file"
    log_info "Applying netplan configuration..."
    netplan apply
    log_success "Static IP successfully configured and applied!"
}

# 22. Configure Upstream DNS
do_configure_dns() {
    log_info "Configuring systemd-resolved upstream DNS..."
    read -rp "Enter DNS Servers (space-separated) [8.8.8.8 8.8.4.4 1.1.1.1]: " DNS_LIST
    DNS_LIST=${DNS_LIST:-"8.8.8.8 8.8.4.4 1.1.1.1"}
    
    # Update configurations in systemd resolved.conf
    sed -i "s/^#\?DNS=.*/DNS=${DNS_LIST}/" /etc/systemd/resolved.conf
    
    systemctl restart systemd-resolved
    log_success "Upstream DNS servers configured to: ${DNS_LIST}"
}

# 23. Timezone & NTP Sync
do_timezone_ntp() {
    log_info "Configuring timezone and system clock synchronization..."
    
    if command -v timedatectl >/dev/null 2>&1; then
        # Enable NTP synchronization
        timedatectl set-ntp true
        log_info "NTP sync enabled."
        
        # Select timezone
        read -rp "Enter Timezone [Asia/Kuala_Lumpur]: " TZ_INPUT
        TZ_INPUT=${TZ_INPUT:-"Asia/Kuala_Lumpur"}
        
        if timedatectl set-timezone "$TZ_INPUT" 2>/dev/null; then
            log_success "System timezone configured to: $TZ_INPUT"
        else
            log_error "Failed to set timezone to '${TZ_INPUT}'."
        fi
    else
        log_error "timedatectl utility not found."
    fi
}

# ==========================================
# MEMORY & STORAGE FUNCTIONS
# ==========================================

# 31. Create Swap File & Swappiness
do_swap_file() {
    log_info "Configuring Swap File & Swappiness..."
    
    # Read total RAM in KB
    local mem_total_kb mem_total_gb
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_total_gb=$(echo "scale=2; $mem_total_kb/1024/1024" | bc 2>/dev/null || awk "BEGIN {print $mem_total_kb/1048576}")
    
    log_info "Total System RAM: ${mem_total_gb} GB"
    
    # Suggest swap sizes
    local suggested_swap="4G"
    if [ "$mem_total_kb" -gt 8388608 ]; then
        suggested_swap="2G"
    fi
    
    read -rp "Enter Swap File size (e.g. 2G, 4G, 8G) [$suggested_swap]: " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$suggested_swap}
    
    while [[ ! "$SWAP_SIZE" =~ ^[0-9]+[GM]$ ]]; do
        log_error "Invalid format. Enter numbers followed by G or M (e.g. 4G, 512M)."
        read -rp "Enter Swap File size: " SWAP_SIZE
    done
    
    local swap_path="/swapfile"
    
    # Decommission old swap if present
    if [ -f "$swap_path" ]; then
        log_warning "Swap file already exists at ${swap_path}."
        read -rp "Overwrite and recreate it? (y/n) [n]: " OVERWRITE_SWAP
        OVERWRITE_SWAP=${OVERWRITE_SWAP:-n}
        if [[ ! "$OVERWRITE_SWAP" =~ ^[Yy]$ ]]; then
            log_info "Skipping swap creation."
            return 0
        fi
        swapoff "$swap_path" || true
        rm -f "$swap_path"
    fi
    
    # Allocate and setup swap space
    log_info "Allocating ${SWAP_SIZE} for swapfile..."
    fallocate -l "$SWAP_SIZE" "$swap_path" || dd if=/dev/zero of="$swap_path" bs=1M count=$(echo "$SWAP_SIZE" | sed 's/G/*1024/;s/M//' | bc)
    
    chmod 600 "$swap_path"
    mkswap "$swap_path"
    swapon "$swap_path"
    
    # Register swap in fstab
    if ! grep -q "${swap_path}" /etc/fstab; then
        echo "${swap_path} none swap sw 0 0" >> /etc/fstab
    fi
    
    # Optimize swappiness setting
    log_info "Optimizing kernel swappiness to 10..."
    if grep -q "^vm.swappiness=" /etc/sysctl.conf; then
        sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    else
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
    sysctl -p
    
    log_success "Swap of ${SWAP_SIZE} configured. Swappiness set to 10."
}

# ==========================================
# SHELL & CLI REPLICA FUNCTIONS
# ==========================================

OS_NAME="unknown"
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
    else
        OS_NAME="unknown"
    fi
    log_info "Detected OS: ${OS_NAME}"
}

# 41. Install Fish, Starship, eza
install_fish() {
    log_info "Installing Fish Shell..."
    case "$OS_NAME" in
        ubuntu|debian)
            apt-get update
            apt-get install -y fish gpg wget curl
            ;;
        centos|rhel|almalinux|rocky)
            dnf install -y epel-release || true
            dnf install -y fish curl wget tar
            ;;
        fedora)
            dnf install -y fish curl wget tar
            ;;
        arch)
            pacman -S --noconfirm fish curl wget tar
            ;;
        alpine)
            apk add fish curl wget tar
            ;;
        *)
            log_error "Unsupported OS for automatic Fish installation. Please install Fish shell manually."
            return 1
            ;;
    esac
    log_success "Fish Shell installed successfully."
}

install_starship() {
    log_info "Installing Starship Prompt..."
    if command -v starship >/dev/null 2>&1; then
        log_success "Starship is already installed: $(starship --version | head -n 1)"
        return 0
    fi

    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        log_success "Starship installed successfully."
    else
        log_error "Starship installation failed."
        return 1
    fi
}

install_eza() {
    log_info "Installing eza (modern ls)..."
    if command -v eza >/dev/null 2>&1; then
        log_success "eza is already installed: $(eza --version | head -n 1)"
        return 0
    fi

    case "$OS_NAME" in
        ubuntu|debian)
            if apt-get install -y eza >/dev/null 2>&1; then
                log_success "eza installed from standard apt repositories."
                return 0
            fi
            
            log_info "eza not found in standard apt repos. Registering gierens repository..."
            mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de/debian stable main" | tee /etc/apt/sources.list.d/gierens.list
            apt-get update
            if apt-get install -y eza; then
                log_success "eza installed successfully via gierens repository."
                return 0
            fi
            ;;
        fedora)
            dnf install -y eza && log_success "eza installed from dnf" && return 0
            ;;
        centos|rhel|almalinux|rocky)
            if dnf install -y eza >/dev/null 2>&1; then
                log_success "eza installed from EPEL repository."
                return 0
            fi
            ;;
        arch)
            pacman -S --noconfirm eza && log_success "eza installed from pacman" && return 0
            ;;
        alpine)
            apk add eza && log_success "eza installed from apk" && return 0
            ;;
    esac

    # Fallback: Download precompiled static binary
    log_info "Attempting to download latest eza static binary from GitHub releases..."
    local latest_url
    latest_url=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep "browser_download_url.*eza_x86_64-unknown-linux-gnu.tar.gz" | cut -d '"' -f 4 || echo "")
    if [ -z "$latest_url" ]; then
        latest_url="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
    fi

    mkdir -p /tmp/eza_install
    if wget -qO /tmp/eza_install/eza.tar.gz "$latest_url" || curl -sSL -o /tmp/eza_install/eza.tar.gz "$latest_url"; then
        tar -xzf /tmp/eza_install/eza.tar.gz -C /tmp/eza_install
        mv /tmp/eza_install/eza /usr/local/bin/eza
        chmod +x /usr/local/bin/eza
        rm -rf /tmp/eza_install
        log_success "eza static binary installed to /usr/local/bin/eza."
    else
        log_warning "Could not install eza. The alias 'ls' will still be configured but will fall back to normal ls if eza is missing."
    fi
}

do_install_shell_tools() {
    detect_os
    install_fish
    install_starship
    install_eza
}

# 42. Configure Shell Replica (welcome banner, starship, configs)
do_configure_shell_replica() {
    log_info "Configuring Fish shell, Starship theme, and Welcome Banner..."
    
    read -rp "Configure Fish & Starship for which user? [${REAL_USER}]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-$REAL_USER}
    
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        log_error "User '$TARGET_USER' does not exist."
        return 1
    fi
    
    local user_home
    user_home=$(eval echo "~$TARGET_USER")
    
    # 1. Configure Server Identity
    read -rp "Enter the name of this server [MyServer]: " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-MyServer}
    
    # 2. Configure Welcome Banner (ASCII Art)
    echo -e "Please paste your welcome ASCII Art below, then press ${GREEN}Ctrl+D${NC} on a new line to finish."
    echo -e "(Or leave empty to use a simple text welcome banner)"
    
    local temp_art
    temp_art=$(mktemp)
    cat > "$temp_art"
    
    # Check if user pasted anything substantial
    if ! grep -q '[^[:space:]]' "$temp_art"; then
        cat << EOF > "$temp_art"
 ==========================================
   Welcome to ${SERVER_NAME}
 ==========================================
EOF
    fi
    
    # Create configuration directories
    mkdir -p "${user_home}/.config/fish/functions"
    mkdir -p "${user_home}/.config/fish/conf.d"
    
    # Write starship.toml
    cat << 'EOF' > "${user_home}/.config/starship.toml"
# Get editor completions
"$schema" = 'https://starship.rs/config-schema.json'

add_newline = true

# THE HUD LAYOUT (Optimized for 12GB RAM Server)
# Added $username and $memory_usage to the top line for quick status checks.
format = """
[┌─](bold cyan)$os$username$hostname [at ](bold purple)$time [in ](bold cyan)$directory$git_branch$git_status
[└─](bold cyan)$character$docker_context$nodejs$python$php$java$dart$flutter$package"""

right_format = "$cmd_duration$status"

[os]
disabled = false
format = "[$symbol]($style) "

[os.symbols]
Ubuntu = " "
Linux = " "

[username]
show_always = true
style_user = "bold white"
style_root = "bold red"
format = "[$user]($style) "

[hostname]
ssh_only = false
format = "[__SERVER_NAME__](bold yellow) "

[directory]
style = "bold cyan"
truncation_length = 3
truncate_to_repo = true # Keeps context of which stack you are in
format = "[$path]($style) "
repo_root_style = "bold emerald" # Emerald Green for project roots

[time]
disabled = false
time_format = "%R" 
style = "bold purple"
format = "[$time]($style) "

[git_status]
style = "bold red"
format = '([\[$all_status$ahead_behind\]]($style) )'
conflicted = "󰯓 "
ahead = "󰶣 "
behind = "󰶡 "
diverged = "󰹹 "
untracked = "󰔓 "
stashed = "󰏗 "
modified = "󰏫 "
staged = "󰐖 "
renamed = "󰑕 "
deleted = "󰗨 "

[status]
disabled = false
symbol = "✘"
style = "bold red"
format = "exit [$symbol$int]($style) "

[character]
success_symbol = "[👍 ❯](bold emerald)" # Emerald Green for "System Ready"
error_symbol = "[❯](bold ruby)"    # Ruby Red for "System Error"

# LANGUAGE MODULES (Relevant to your stacks)
[nodejs]
symbol = "󰎙 "
style = "bold emerald"
format = "via [$symbol($version )]($style)"

[python]
symbol = "󱔎 "
style = "bold yellow"
format = "via [$symbol($version )]($style)"

[php]
symbol = "󰂄 "
style = "bold blue"
format = "via [$symbol($version )]($style)"

[docker_context]
symbol = " "
style = "bold blue"
format = "via [$symbol$context]($style) "

# CUSTOM PALETTE (Matching GEMINI.md)
[palettes.biomedical]
ruby = "#E0115F"
emerald = "#50C878"
EOF
    # Perform custom server name mapping in starship config
    sed -i "s|__SERVER_NAME__|${SERVER_NAME}|g" "${user_home}/.config/starship.toml"
    log_success "Created starship settings: ${user_home}/.config/starship.toml"
    
    # Write config.fish
    cat << 'EOF' > "${user_home}/.config/fish/config.fish"
if status is-interactive
    # Commands to run in interactive sessions can go here
    alias ll='ls -alF'
    alias la='ls -A'
    if command -v eza >/dev/null 2>&1
        alias ls='eza -hg --icons --git --group-directories-first'
    end
end

starship init fish | source

# Path additions
if test -d "$HOME/.local/bin"
    set -gx PATH "$HOME/.local/bin" $PATH
end
EOF
    log_success "Created fish configuration: ${user_home}/.config/fish/config.fish"

    # Copy welcome artwork
    cp "$temp_art" "${user_home}/.config/fish/ascii_art.txt"
    rm -f "$temp_art"
    log_success "Created welcome artwork: ${user_home}/.config/fish/ascii_art.txt"

    # Write fish_greeting.fish
    cat << 'EOF' > "${user_home}/.config/fish/functions/fish_greeting.fish"
function fish_greeting
    clear
    
    # 1. Print Host System Statistics
    set_color cyan
    echo "=== Host System Statistics ==="
    set_color normal
    
    # OS Name
    if test -f /etc/os-release
        set -l os_name (grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
        if test -z "$os_name"
            set os_name (grep -E "^NAME=" /etc/os-release | cut -d'"' -f2)
        end
        echo "OS:          $os_name"
    end
    
    # Kernel
    echo "Kernel:      "(uname -r)
    
    # CPU Model
    if test -f /proc/cpuinfo
        set -l cpu_model (grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | string trim)
        echo "CPU Model:   $cpu_model"
    end
    
    # BIOS
    set -l bios_vendor (cat /sys/class/dmi/id/bios_vendor 2>/dev/null; or echo "")
    set -l bios_version (cat /sys/class/dmi/id/bios_version 2>/dev/null; or echo "")
    if test -n "$bios_vendor"; or test -n "$bios_version"
        echo "BIOS:        $bios_vendor $bios_version"
    end
    
    # RAM
    if command -sq free
        set -l total_ram (free -h | awk '/^Mem:/ {print $2}')
        set -l free_ram (free -h | awk '/^Mem:/ {print $4}')
        echo "RAM (Total): $total_ram (Free: $free_ram)"
    end
    
    # Disk Storage
    echo "Disk Storage:"
    df -h | grep -E '^/dev/' | while read -l dev size used avail percent mount
        echo "  - $dev ($mount): Total: $size | Free: $avail (Used: $percent)"
    end
    
    # Two empty lines
    echo ""
    echo ""
    
    # Print the ASCII welcome art
    cat ~/.config/fish/ascii_art.txt 2>/dev/null
end
EOF
    log_success "Created fish greeting: ${user_home}/.config/fish/functions/fish_greeting.fish"

    # Write sysstat.fish
    cat << 'EOF' > "${user_home}/.config/fish/functions/sysstat.fish"
function sysstat --description 'Show system telemetry (CPU, RAM, Disk in GB)'
    set_color -o cyan
    echo "================================================"
    echo "               SYSTEM TELEMETRY                 "
    echo "================================================"
    set_color normal

    # 1. CPU Usage
    set_color -o yellow
    echo "[CPU USAGE]"
    set_color normal
    set cpu_usage (LC_ALL=C top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    echo "Total CPU Load: $cpu_usage%"
    echo ""

    # 2. RAM Usage
    set_color -o yellow
    echo "[RAM USAGE]"
    set_color normal
    free -h
    echo ""

    # 3. Disk Usage
    set_color -o yellow
    echo "[DISK STORAGE (GB)]"
    set_color normal
    df -BG -x tmpfs -x devtmpfs -x squashfs -x loop
    
    set_color -o cyan
    echo "================================================"
    set_color normal
end
EOF
    log_success "Created sysstat command: ${user_home}/.config/fish/functions/sysstat.fish"

    # Fix permissions to ensure targeted user owns their configs
    chown -R "${TARGET_USER}:${TARGET_USER}" "${user_home}/.config"

    # Set Default Shell
    local fish_path
    fish_path=$(command -v fish)
    if [ -n "$fish_path" ]; then
        if ! grep -Fxq "$fish_path" /etc/shells; then
            echo "$fish_path" | tee -a /etc/shells >/dev/null
        fi
        
        read -rp "Make Fish default login shell for '${TARGET_USER}'? (y/n) [y]: " CHANGE_SHELL
        CHANGE_SHELL=${CHANGE_SHELL:-y}
        if [[ "$CHANGE_SHELL" =~ ^[Yy]$ ]]; then
            chsh -s "$fish_path" "$TARGET_USER"
            log_success "Default shell changed to Fish for user '${TARGET_USER}'."
        fi
    else
        log_warning "Fish shell binary not found. Please install Fish shell first (Option 41)."
    fi

    log_success "Shell and custom telemetry replication configuration complete."
}

# ==========================================
# DOCKER CONTROL FUNCTIONS
# ==========================================

# 51. Install/Update Docker & Docker Compose V2
do_install_docker() {
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VER=$(docker --version)
        log_success "Docker is already installed: ${DOCKER_VER}"
        
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

        local gpg_url="https://download.docker.com/linux/${OS_ID}/gpg"
        local repo_url="https://download.docker.com/linux/${OS_ID}"
        
        if [ "$OS_ID" = "pop" ] || [ "$OS_ID" = "linuxmint" ]; then
            gpg_url="https://download.docker.com/linux/ubuntu/gpg"
            repo_url="https://download.docker.com/linux/ubuntu"
            OS_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
        fi

        log_info "Adding Docker official GPG key..."
        curl -fsSL "$gpg_url" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

        log_info "Adding Docker apt repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url \
          ${OS_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        log_info "Updating package lists again and installing Docker packages..."
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # Fallback to official convenience script
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

        # Configure user permissions
        if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
            log_info "Adding user '${REAL_USER}' to the docker group..."
            groupadd -f docker
            usermod -aG docker "${REAL_USER}"
            log_success "User '${REAL_USER}' added to the 'docker' group."
            
            echo -e "\n${YELLOW}[IMPORTANT]${NC} To run docker commands without sudo, reload your session:"
            echo -e "  Option A: Log out and log back in."
            echo -e "  Option B: Run this command in your current terminal: ${BLUE}newgrp docker${NC}"
        fi
    else
        log_error "Installation completed, but the 'docker' command was not found in PATH."
    fi
}

# 52. Docker Diagnostics
do_docker_diagnostics() {
    log_info "Docker service status:"
    if systemctl is-active --quiet docker; then
        log_success "Docker service is ACTIVE (running)."
    else
        log_warning "Docker service is INACTIVE (stopped)."
    fi
    echo ""
    if command -v docker >/dev/null 2>&1; then
        docker info | grep -E "Containers|Images|Server Version|Storage Driver|Kernel Version|Operating System" || true
        echo ""
        log_info "Docker disk space usage summary:"
        docker system df
    else
        log_error "Docker is not installed."
    fi
}

# 53. Docker Prune Operations
do_docker_pruning() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed."
        return 1
    fi
    
    echo -e "\n${YELLOW}Docker Prune Operations:${NC}"
    echo "  1) Remove Unused Volumes (Volume Prune)"
    echo "  2) Remove Unused Images (Image Prune)"
    echo "  3) Remove Unused Volumes & Images"
    echo "  4) Deep Clean System (System Prune - All Unused Data)"
    echo "  0) Cancel"
    read -rp "Please select prune scope [0-4]: " PRUNE_CHOICE
    
    case "$PRUNE_CHOICE" in
        1)
            log_warning "This will delete all unused local Docker volumes (not attached to any container)."
            read -rp "Are you sure? (y/n) [n]: " CONF
            if [[ "${CONF:-n}" =~ ^[Yy]$ ]]; then
                docker volume prune -f
                log_success "Unused volumes cleared."
            fi
            ;;
        2)
            echo -e "\n${YELLOW}Choose Image Prune Scope:${NC}"
            echo "  1) Prune only dangling images (images without tags)"
            echo "  2) Prune all unused images (images not used by any container)"
            read -rp "Selection [1-2] [1]: " IMG_CHOICE
            read -rp "Are you sure? (y/n) [n]: " CONF
            if [[ "${CONF:-n}" =~ ^[Yy]$ ]]; then
                if [ "${IMG_CHOICE:-1}" = "2" ]; then
                    docker image prune -a -f
                else
                    docker image prune -f
                fi
                log_success "Unused images cleared."
            fi
            ;;
        3)
            log_warning "This will delete all unused local volumes AND unused Docker images."
            read -rp "Are you sure? (y/n) [n]: " CONF
            if [[ "${CONF:-n}" =~ ^[Yy]$ ]]; then
                docker volume prune -f
                docker image prune -a -f
                log_success "Unused volumes and images successfully cleared."
            fi
            ;;
        4)
            log_warning "This will delete ALL unused containers, networks, images (both dangling and unused), and local volumes!"
            log_warning "This is a complete deep clean of your Docker system."
            read -rp "Are you sure? (y/n) [n]: " CONF
            if [[ "${CONF:-n}" =~ ^[Yy]$ ]]; then
                docker system prune -a --volumes -f
                log_success "Docker system fully pruned and cleaned!"
            fi
            ;;
        *)
            log_info "Pruning cancelled."
            ;;
    esac
}

# 54. Restart Docker
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
    show_system_stats
    
    echo -e "${YELLOW}Available Configuration Modules:${NC}"
    echo -e "  [1] System & Security Setup:"
    echo -e "    11) Update & Upgrade packages & Install CLI Tools"
    echo -e "    12) Create Sudo User"
    echo -e "    13) Configure SSH (SSH Keys, Custom Port, Hardening)"
    echo -e "    14) Install & Configure Fail2Ban (Brute-force protection)"
    echo -e "    15) Enable Firewall (UFW)"
    echo -e "    16) Laptop Server: Disable Suspend on Lid Close"
    echo -e ""
    echo -e "  [2] Network & Time Settings:"
    echo -e "    21) Configure Static IP Address (Netplan)"
    echo -e "    22) Configure Upstream DNS (resolved.conf)"
    echo -e "    23) Enable NTP & Set Timezone"
    echo -e ""
    echo -e "  [3] Memory & Storage:"
    echo -e "    31) Create Swap File & Optimize Swappiness"
    echo -e ""
    echo -e "  [4] Shell & CLI Replica:"
    echo -e "    41) Install Fish Shell, Starship Prompt, & eza"
    echo -e "    42) Configure Shell, Welcome Banner, & Telemetry (sysstat)"
    echo -e ""
    echo -e "  [5] Docker Control:"
    echo -e "    51) Install/Update Docker & Docker Compose V2"
    echo -e "    52) Docker Diagnostics (Status & Disk Space)"
    echo -e "    53) Docker Prune Operations"
    echo -e "    54) Restart Docker Daemon Service"
    echo -e ""
    echo -e "  [0] Exit Configuration Utility"
    echo -e "============================================================\n"
    
    read -rp "Please enter your selection: " MENU_CHOICE
    
    case "$MENU_CHOICE" in
        11) do_update_upgrade ;;
        12) do_create_sudo_user ;;
        13) do_configure_ssh ;;
        14) do_configure_fail2ban ;;
        15) do_configure_firewall ;;
        16) do_laptop_lid_action ;;
        21) do_static_ip ;;
        22) do_configure_dns ;;
        23) do_timezone_ntp ;;
        31) do_swap_file ;;
        41) do_install_shell_tools ;;
        42) do_configure_shell_replica ;;
        51) do_install_docker ;;
        52) do_docker_diagnostics ;;
        53) do_docker_pruning ;;
        54) do_restart_docker ;;
        0)
            log_success "Exiting setup utility. Goodbye!"
            break
            ;;
        *)
            log_error "Invalid selection. Please try again."
            ;;
    esac
    
    echo -e "\nPress [ENTER] to return to the menu..."
    read -r _
done
