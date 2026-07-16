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
    echo -e "${BLUE}=== Ubuntu Server Initial Setup Utility ===${NC}\n"
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
        local cpu_model
        cpu_model=$(lscpu | grep "Model name:" | sed -e 's/Model name:\s*//g' || echo "Unknown")
        echo -e "CPU Model:   ${NC}${cpu_model}"
    fi
    # BIOS
    local bios_vendor bios_version
    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "")
    bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "")
    echo -e "BIOS:        ${NC}${bios_vendor} ${bios_version}"
    # RAM
    local total_ram free_ram
    total_ram=$(free -h | awk '/^Mem:/ {print $2}')
    free_ram=$(free -h | awk '/^Mem:/ {print $4}')
    echo -e "RAM (Total): ${GREEN}${total_ram}${NC} (Free: ${free_ram})"
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

# --- Parse Arguments ---
ACTION=""
NON_INTERACTIVE=false
TOKEN_VAL=""
USER_VAL=""
KEY_VAL=""

while getopts "yup:c:s:fidtw" opt; do
    case "$opt" in
        y) NON_INTERACTIVE=true ;;
        u) ACTION="update" ;;
        p) ACTION="pro"; TOKEN_VAL="$OPTARG" ;;
        c) ACTION="create_user"; USER_VAL="$OPTARG" ;;
        s) ACTION="ssh"; KEY_VAL="$OPTARG" ;;
        f) ACTION="firewall" ;;
        i) ACTION="static_ip" ;;
        d) ACTION="dns" ;;
        t) ACTION="timezone" ;;
        w) ACTION="swap" ;;
        *) echo "Usage: $0 [-y] [-u] [-p token] [-c user] [-s key] [-f] [-i] [-d] [-t] [-w]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# --- Network Interface Detection ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

# ==========================================
# ACTION FUNCTIONS
# ==========================================

# 1. Update and Upgrade
do_update_upgrade() {
    run_with_spinner "Updating package lists..." apt-get update -y
    run_with_spinner "Upgrading system packages..." apt-get upgrade -y
    log_success "System packages updated and upgraded successfully."
}

# 2. Ubuntu Pro ESM
do_ubuntu_pro() {
    log_info "Enabling Ubuntu Pro ESM..."
    local pro_token="${TOKEN_VAL}"
    if [ -z "$pro_token" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log_error "Token cannot be empty in non-interactive mode."
            return 1
        fi
        read -rp "Enter Ubuntu Pro Attach Token: " pro_token
    fi
    if [ -z "$pro_token" ]; then
        log_error "Token cannot be empty."
        return 1
    fi
    if command -v pro >/dev/null 2>&1; then
        pro attach "$pro_token"
        log_success "Ubuntu Pro attached successfully."
    else
        log_error "The 'pro' (ubuntu-advantage) tool is not installed or not available."
    fi
}

# 3. Create Sudo User
do_create_sudo_user() {
    log_info "Creating a new sudo user..."
    local new_user="${USER_VAL}"
    if [ -z "$new_user" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log_error "Username must be provided with -c in non-interactive mode."
            return 1
        fi
        read -rp "Enter Username: " new_user
        while [ -z "$new_user" ]; do
            log_error "Username cannot be empty."
            read -rp "Enter Username: " new_user
        done
    fi

    # Check if user already exists
    if id "$new_user" >/dev/null 2>&1; then
        log_warning "User '${new_user}' already exists."
        return 0
    fi

    local new_pass new_pass_confirm
    if [ "$NON_INTERACTIVE" = true ]; then
        # Generate random password
        new_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "secure_pass_default")
    else
        # Read password securely
        read -rsp "Enter Password for ${new_user}: " new_pass
        echo ""
        read -rsp "Confirm Password: " new_pass_confirm
        echo ""

        if [ "$new_pass" != "$new_pass_confirm" ]; then
            log_error "Passwords do not match."
            return 1
        fi
    fi

    # Create user with bash shell and home folder
    useradd -m -s /bin/bash "$new_user"
    echo "${new_user}:${new_pass}" | chpasswd
    usermod -aG sudo "$new_user"
    
    box_message "SUDO USER CREATED" \
        "Username: ${new_user}" \
        "Password: ${new_pass}" \
        "Group:    sudo" \
        "Shell:    /bin/bash"

    # Switch to user immediately if requested
    if [ "$NON_INTERACTIVE" = false ]; then
        local switch_now
        read -rp "Switch to user '${new_user}' now? (y/n) [y]: " switch_now
        switch_now=${switch_now:-y}
        if [[ "$switch_now" =~ ^[Yy]$ ]]; then
            log_info "Switching session to '${new_user}'..."
            su - "$new_user"
        fi
    fi
}

# 4. Enable SSH and Add Authorized Key
do_enable_ssh() {
    log_info "Enabling SSH and adding authorized key..."
    
    # Install openssh-server if missing
    if ! dpkg -l | grep -q openssh-server; then
        run_with_spinner "Installing openssh-server..." bash -c "apt-get update && apt-get install -y openssh-server"
    fi
    
    systemctl enable --now ssh
    
    local ssh_user
    if [ "$NON_INTERACTIVE" = true ]; then
        ssh_user=$(logname 2>/dev/null || echo "root")
    else
        read -rp "For which user should we add the SSH key? [$(logname || echo "root")]: " ssh_user
        ssh_user=${ssh_user:-$(logname || echo "root")}
    fi
    
    if ! id "$ssh_user" >/dev/null 2>&1; then
        log_error "User '$ssh_user' does not exist."
        return 1
    fi
    
    local user_home
    user_home=$(eval echo "~$ssh_user")
    
    local ssh_key="${KEY_VAL}"
    if [ -z "$ssh_key" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log_error "SSH public key must be provided via -s in non-interactive mode."
            return 1
        fi
        read -rp "Enter SSH Public Key (starts with ssh-rsa, ssh-ed25519, etc.): " ssh_key
    fi
    if [ -z "$ssh_key" ]; then
        log_error "SSH Key cannot be empty."
        return 1
    fi
    
    mkdir -p "${user_home}/.ssh"
    chmod 700 "${user_home}/.ssh"
    
    echo "$ssh_key" >> "${user_home}/.ssh/authorized_keys"
    chmod 600 "${user_home}/.ssh/authorized_keys"
    chown -R "${ssh_user}:${ssh_user}" "${user_home}/.ssh"
    
    log_success "SSH key successfully appended to ${user_home}/.ssh/authorized_keys."

    # Verify SSH is running and listening on port 22
    log_info "Verifying SSH service health..."
    local ssh_healthy=false
    for i in {1..15}; do
        if ss -tlnp | grep -q ":22 " || nc -z localhost 22 2>/dev/null; then
            ssh_healthy=true
            break
        fi
        sleep 1
    done
    if [ "$ssh_healthy" = true ]; then
        log_success "SSH service is online and listening on port 22!"
    else
        log_warning "SSH service did not respond on port 22 within 15 seconds."
    fi
}

# 5. Enable Firewall (UFW)
do_configure_firewall() {
    log_info "Configuring UFW Firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        run_with_spinner "Installing ufw..." apt-get install -y ufw
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
    
    local active_iface
    active_iface=$(detect_interface)
    
    if [ "$NON_INTERACTIVE" = true ]; then
        log_error "Static IP configuration is not supported in non-interactive mode."
        return 1
    fi

    local iface
    read -rp "Enter Network Interface Name [$active_iface]: " iface
    iface=${iface:-$active_iface}
    
    local ip_addr
    read -rp "Enter Static IP with Subnet Mask (e.g. 192.168.1.100/24): " ip_addr
    while [[ ! "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; do
        log_error "Invalid format. Please use CIDR notation (e.g. 192.168.1.100/24)."
        read -rp "Enter Static IP with Subnet Mask: " ip_addr
    done
    
    local gateway
    read -rp "Enter Default Gateway IP (e.g. 192.168.1.1): " gateway
    while [[ ! "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        log_error "Invalid IP format."
        read -rp "Enter Default Gateway IP: " gateway
    done
    
    local dns_servers
    read -rp "Enter DNS Servers (comma-separated) [8.8.8.8,8.8.4.4]: " dns_servers
    dns_servers=${dns_servers:-"8.8.8.8,8.8.4.4"}
    
    local formatted_dns
    formatted_dns=$(echo "$dns_servers" | sed 's/\s*,\s*/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
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
    ${iface}:
      dhcp4: no
      addresses:
        - ${ip_addr}
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses: ${formatted_dns}
EOF
    
    chmod 600 "$netplan_file"
    log_info "Applying netplan configuration..."
    netplan apply &
    show_spinner $!
    log_success "Static IP successfully configured and applied!"
}

# 7. Configure Upstream DNS
do_configure_dns() {
    log_info "Configuring systemd-resolved upstream DNS..."
    local dns_list
    if [ "$NON_INTERACTIVE" = true ]; then
        dns_list="8.8.8.8 8.8.4.4 1.1.1.1"
    else
        read -rp "Enter DNS Servers (space-separated) [8.8.8.8 8.8.4.4 1.1.1.1]: " dns_list
        dns_list=${dns_list:-"8.8.8.8 8.8.4.4 1.1.1.1"}
    fi
    
    # Update configurations in systemd resolved.conf
    sed -i "s/^#\?DNS=.*/DNS=${dns_list}/" /etc/systemd/resolved.conf
    
    systemctl restart systemd-resolved &
    show_spinner $!
    log_success "Upstream DNS servers configured to: ${dns_list}"
}

# 8. Timezone & NTP Sync
do_timezone_ntp() {
    log_info "Configuring timezone and system clock synchronization..."
    
    if command -v timedatectl >/dev/null 2>&1; then
        # Enable NTP synchronization
        timedatectl set-ntp true
        log_info "NTP sync enabled."
        
        local default_tz
        default_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Asia/Kuala_Lumpur")
        [ -z "$default_tz" ] && default_tz="Asia/Kuala_Lumpur"

        # Select timezone
        local tz_input
        if [ "$NON_INTERACTIVE" = true ]; then
            tz_input=$default_tz
        else
            read -rp "Enter Timezone [$default_tz]: " tz_input
            tz_input=${tz_input:-$default_tz}
        fi
        
        if timedatectl set-timezone "$tz_input" 2>/dev/null; then
            log_success "System timezone configured to: $tz_input"
        else
            log_error "Failed to set timezone to '${tz_input}'."
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
    
    local swap_size
    if [ "$NON_INTERACTIVE" = true ]; then
        swap_size=$suggested_swap
    else
        read -rp "Enter Swap File size (e.g. 2G, 4G, 8G) [$suggested_swap]: " swap_size
        swap_size=${swap_size:-$suggested_swap}
    fi
    
    while [[ ! "$swap_size" =~ ^[0-9]+[GM]$ ]]; do
        log_error "Invalid format. Enter numbers followed by G or M (e.g. 4G, 512M)."
        read -rp "Enter Swap File size: " swap_size
    done
    
    local swap_path="/swapfile"
    
    # Decommission old swap if present
    if [ -f "$swap_path" ]; then
        log_warning "Swap file already exists at ${swap_path}."
        local overwrite_swap
        if [ "$NON_INTERACTIVE" = true ]; then
            overwrite_swap="y"
        else
            read -rp "Overwrite and recreate it? (y/n) [n]: " overwrite_swap
            overwrite_swap=${overwrite_swap:-n}
        fi
        if [[ ! "$overwrite_swap" =~ ^[Yy]$ ]]; then
            log_info "Skipping swap creation."
            return 0
        fi
        swapoff "$swap_path" || true
        rm -f "$swap_path"
    fi
    
    # Allocate and setup swap space
    log_info "Allocating ${swap_size} for swapfile..."
    local dd_count
    dd_count=$(echo "$swap_size" | sed 's/G/*1024/;s/M//' | bc)
    fallocate -l "$swap_size" "$swap_path" >/dev/null 2>&1 || dd if=/dev/zero of="$swap_path" bs=1M count="$dd_count" >/dev/null 2>&1 &
    show_spinner $!
    
    chmod 600 "$swap_path"
    mkswap "$swap_path" >/dev/null &
    show_spinner $!
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
    sysctl -p >/dev/null
    
    log_success "Swap of ${swap_size} configured. Swappiness set to 10."
}

# ==========================================
# MAIN EXECUTION
# ==========================================
main() {
    # Ensure script is run with sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        show_header
        log_error "This setup script requires administrative privileges. Please run with sudo:"
        echo -e "  ${YELLOW}sudo $0${NC}"
        exit 1
    fi

    if [ -n "$ACTION" ]; then
        case "$ACTION" in
            update) do_update_upgrade ;;
            pro) do_ubuntu_pro ;;
            create_user) do_create_sudo_user ;;
            ssh) do_enable_ssh ;;
            firewall) do_configure_firewall ;;
            static_ip) do_static_ip ;;
            dns) do_configure_dns ;;
            timezone) do_timezone_ntp ;;
            swap) do_swap_file ;;
        esac
        exit 0
    fi

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
            1) do_update_upgrade ;;
            2) do_ubuntu_pro ;;
            3) do_create_sudo_user ;;
            4) do_enable_ssh ;;
            5) do_configure_firewall ;;
            6) do_static_ip ;;
            7) do_configure_dns ;;
            8) do_timezone_ntp ;;
            9) do_swap_file ;;
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
}

main "$@"
