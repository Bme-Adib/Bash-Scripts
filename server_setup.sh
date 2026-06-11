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
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Ubuntu Server Initial Setup Utility ===${NC}\n"
}

# --- System Stats ---
show_system_stats() {
    echo -e "${BLUE}=== Host System Statistics ===${NC}"
    # OS Name
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "OS:          ${GREEN}${NAME} ${VERSION}${NC}"
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
    echo -e "BIOS:        ${NC}${bios_vendor} ${bios_version}"
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
# ACTION FUNCTIONS
# ==========================================

# 1. Update and Upgrade
do_update_upgrade() {
    log_info "Updating package lists and upgrading all packages..."
    apt-get update -y
    apt-get upgrade -y
    log_success "System packages updated and upgraded successfully."
}

# 2. Ubuntu Pro ESM
do_ubuntu_pro() {
    log_info "Enabling Ubuntu Pro ESM..."
    read -rp "Enter Ubuntu Pro Attach Token: " PRO_TOKEN
    if [ -z "$PRO_TOKEN" ]; then
        log_error "Token cannot be empty."
        return 1
    fi
    if command -v pro >/dev/null 2>&1; then
        pro attach "$PRO_TOKEN"
        log_success "Ubuntu Pro attached successfully."
    else
        log_error "The 'pro' (ubuntu-advantage) tool is not installed or not available."
    fi
}

# 3. Create Sudo User
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
        log_info "Switching session to '${NEW_USER}'..."
        su - "$NEW_USER"
    fi
}

# 4. Enable SSH and Add Authorized Key
do_enable_ssh() {
    log_info "Enabling SSH and adding authorized key..."
    
    # Install openssh-server if missing
    if ! dpkg -l | grep -q openssh-server; then
        log_info "Installing openssh-server..."
        apt-get update && apt-get install -y openssh-server
    fi
    
    systemctl enable --now ssh
    
    read -rp "For which user should we add the SSH key? [$(logname || echo "root")]: " SSH_USER
    SSH_USER=${SSH_USER:-$(logname || echo "root")}
    
    if ! id "$SSH_USER" >/dev/null 2>&1; then
        log_error "User '$SSH_USER' does not exist."
        return 1
    fi
    
    USER_HOME=$(eval echo "~$SSH_USER")
    
    read -rp "Enter SSH Public Key (starts with ssh-rsa, ssh-ed25519, etc.): " SSH_KEY
    if [ -z "$SSH_KEY" ]; then
        log_error "SSH Key cannot be empty."
        return 1
    fi
    
    mkdir -p "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    
    echo "$SSH_KEY" >> "${USER_HOME}/.ssh/authorized_keys"
    chmod 600 "${USER_HOME}/.ssh/authorized_keys"
    chown -R "${SSH_USER}:${SSH_USER}" "${USER_HOME}/.ssh"
    
    log_success "SSH key successfully appended to ${USER_HOME}/.ssh/authorized_keys."
}

# 5. Enable Firewall (UFW)
do_configure_firewall() {
    log_info "Configuring UFW Firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get install -y ufw
    fi
    
    # Set default behaviors
    ufw default deny incoming
    ufw default allow outgoing
    
    # Open default SSH port
    ufw allow 22/tcp
    
    # Enable firewall (force skips the confirmation prompt)
    ufw --force enable
    log_success "UFW firewall enabled. Closed all incoming traffic except port 22. All outgoing allowed."
}

# 6. Assign Static IP Address
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

# 7. Configure Upstream DNS
do_configure_dns() {
    log_info "Configuring systemd-resolved upstream DNS..."
    read -rp "Enter DNS Servers (space-separated) [8.8.8.8 8.8.4.4 1.1.1.1]: " DNS_LIST
    DNS_LIST=${DNS_LIST:-"8.8.8.8 8.8.4.4 1.1.1.1"}
    
    # Update configurations in systemd resolved.conf
    sed -i "s/^#\?DNS=.*/DNS=${DNS_LIST}/" /etc/systemd/resolved.conf
    
    systemctl restart systemd-resolved
    log_success "Upstream DNS servers configured to: ${DNS_LIST}"
}

# 8. Timezone & NTP Sync
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

# 9. Create Swap File & Swappiness
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
# INTERACTIVE LOOP
# ==========================================

while true; do
    show_header
    show_system_stats
    
    echo -e "${YELLOW}Available Actions:${NC}"
    echo -e "  1) Update and upgrade all packages"
    echo -e "  2) Attach Ubuntu Pro / ESM Token"
    echo -e "  3) Create Sudo User (with root privileges)"
    echo -e "  4) Enable SSH & Add Authorized SSH Key"
    echo -e "  5) Enable Firewall (UFW) with port 22 open"
    echo -e "  6) Assign Static IP Address (via Netplan)"
    echo -e "  7) Configure Upstream DNS (e.g. Google 8.8.8.8)"
    echo -e "  8) Enable NTP & Set Timezone"
    echo -e "  9) Create Swap File & Optimize Swappiness"
    echo -e "  0) Exit Setup"
    echo -e "============================================================\n"
    
    read -rp "Please enter your selection [0-9]: " MENU_CHOICE
    
    case "$MENU_CHOICE" in
        1)
            do_update_upgrade
            ;;
        2)
            do_ubuntu_pro
            ;;
        3)
            do_create_sudo_user
            ;;
        4)
            do_enable_ssh
            ;;
        5)
            do_configure_firewall
            ;;
        6)
            do_static_ip
            ;;
        7)
            do_configure_dns
            ;;
        8)
            do_timezone_ntp
            ;;
        9)
            do_swap_file
            ;;
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
