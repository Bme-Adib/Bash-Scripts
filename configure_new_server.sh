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

# --- Resolve Invoking User ---
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "root")}

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
        local cpu_model
        cpu_model=$(lscpu | grep "Model name:" | sed -e 's/Model name:\s*//g' || echo "Unknown")
        echo -e "CPU Model:   ${NC}${cpu_model}"
    fi
    # BIOS
    local bios_vendor bios_version
    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "")
    bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "")
    if [ -n "$bios_vendor" ] || [ -n "$bios_version" ]; then
        echo -e "BIOS:        ${NC}${bios_vendor} ${bios_version}"
    fi
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

# --- Network Interface Detection ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

# --- Parse Arguments ---
NON_INTERACTIVE=false
MODULE_TO_RUN=""
NEW_USER_VAL=""
SSH_KEY_VAL=""
SSH_PORT_VAL=""
CF_TOKEN_VAL=""

while getopts "ym:u:k:p:t:" opt; do
    case "$opt" in
        y) NON_INTERACTIVE=true ;;
        m) MODULE_TO_RUN="$OPTARG" ;;
        u) NEW_USER_VAL="$OPTARG" ;;
        k) SSH_KEY_VAL="$OPTARG" ;;
        p) SSH_PORT_VAL="$OPTARG" ;;
        t) CF_TOKEN_VAL="$OPTARG" ;;
        *) echo "Usage: $0 [-y] [-m module_number] [-u username] [-k ssh_key] [-p ssh_port] [-t cf_token]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# --- User Confirmation Wrapper ---
confirm_action() {
    local choice="$1"
    local desc=""
    
    case "$choice" in
        11) desc="Update package index, upgrade packages, and install CLI utilities (curl, wget, git, htop, btop, tmux, build-essential)." ;;
        12) desc="Scaffold a new administrative user account with sudo capabilities." ;;
        13) desc="Harden SSH by adding keys, changing the SSH port, and optionally disabling password/root login." ;;
        14) desc="Install and configure Fail2Ban to block brute-force attempts on the SSH service." ;;
        15) desc="Install and configure the UFW firewall, closing all incoming ports except standard and custom SSH ports." ;;
        16) desc="Disable laptop lid suspend action so the system remains awake when the lid is closed." ;;
        21) desc="Assign a static IP address to the primary network interface (Netplan)." ;;
        22) desc="Configure upstream DNS servers in systemd-resolved." ;;
        23) desc="Enable NTP network time synchronization and configure the local timezone." ;;
        24) desc="Install and configure VPN / Secure Tunneling services (Tailscale or Cloudflare Tunnel, native or Docker)." ;;
        31) desc="Create or resize a swap file and configure kernel swappiness to 10." ;;
        41) desc="Install Fish shell, Starship prompt binary, and the modern ls tool eza." ;;
        42) desc="Write custom shell settings, welcome banner art, telemetry command, and set Fish as the default shell." ;;
        51) desc="Install or update Docker Engine and Docker Compose V2, and configure docker group permissions." ;;
        52) desc="Inspect Docker service daemon telemetry, status, and container/image storage footprints." ;;
        53) desc="Prune stopped containers, unused networks, images, and docker volumes." ;;
        54) desc="Restart the systemd Docker daemon service." ;;
        *) return 0 ;; # Return immediately for exit/invalid selections
    esac

    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi

    echo -e "\n${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  PREPARING TO EXECUTE MODULE: ${choice}${NC}"
    echo -e "${BLUE}  Summary: ${desc}${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    
    local conf
    read -rp "Are you sure you want to proceed? (y/n) [y]: " conf
    conf=${conf:-y}
    if [[ "$conf" =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "Action cancelled by user. Returning to menu."
        return 1
    fi
}

# ==========================================
# SYSTEM & SECURITY SETUP FUNCTIONS
# ==========================================

# 11. Update and Upgrade
do_update_upgrade() {
    run_with_spinner "Updating package lists..." apt-get update -y
    run_with_spinner "Upgrading system packages..." apt-get upgrade -y
    run_with_spinner "Installing essential utility packages (curl, wget, git, htop, btop, tmux, build-essential)..." apt-get install -y curl wget git htop btop tmux build-essential
    log_success "System packages updated, upgraded, and utility tools installed successfully."
}

# 12. Create Sudo User
do_create_sudo_user() {
    log_info "Creating a new sudo user..."
    local new_user="${NEW_USER_VAL:-}"
    if [ -z "$new_user" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            new_user="adminuser"
        else
            read -rp "Enter Username: " new_user
            while [ -z "$new_user" ]; do
                log_error "Username cannot be empty."
                read -rp "Enter Username: " new_user
            done
        fi
    fi

    # Check if user already exists
    if id "$new_user" >/dev/null 2>&1; then
        log_warning "User '${new_user}' already exists."
        return 0
    fi

    local new_pass
    if [ "$NON_INTERACTIVE" = true ]; then
        new_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16 || echo "secure_pass_default")
    else
        read -rsp "Enter Password for ${new_user}: " new_pass
        echo ""
        local new_pass_confirm
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

    if [ "$NON_INTERACTIVE" = false ]; then
        local switch_now
        read -rp "Switch to user '${new_user}' now? (y/n) [y]: " switch_now
        switch_now=${switch_now:-y}
        if [[ "$switch_now" =~ ^[Yy]$ ]]; then
            log_info "Switching session to '${new_user}'. Type 'exit' to return to configuration utility."
            su - "$new_user"
        fi
    fi
}

# 13. Configure SSH (SSH Keys, Port, Disable Password/Root Login)
do_configure_ssh() {
    log_info "Configuring SSH Server Hardening..."
    
    # Install openssh-server if missing
    if ! dpkg -l | grep -q openssh-server; then
        run_with_spinner "Installing openssh-server..." bash -c "apt-get update && apt-get install -y openssh-server"
    fi
    
    systemctl enable --now ssh
    
    # Part A: Add SSH key
    local add_key
    if [ "$NON_INTERACTIVE" = true ]; then
        if [ -n "$SSH_KEY_VAL" ]; then
            add_key="y"
        else
            add_key="n"
        fi
    else
        read -rp "Would you like to add an Authorized SSH Public Key? (y/n) [y]: " add_key
        add_key=${add_key:-y}
    fi

    if [[ "$add_key" =~ ^[Yy]$ ]]; then
        local ssh_user
        if [ "$NON_INTERACTIVE" = true ]; then
            ssh_user=${NEW_USER_VAL:-$REAL_USER}
        else
            read -rp "For which user should we add the SSH key? [${REAL_USER}]: " ssh_user
            ssh_user=${ssh_user:-$REAL_USER}
        fi
        
        if ! id "$ssh_user" >/dev/null 2>&1; then
            log_error "User '$ssh_user' does not exist."
            return 1
        fi
        
        local user_home
        user_home=$(eval echo "~$ssh_user")
        
        local ssh_key="${SSH_KEY_VAL:-}"
        if [ -z "$ssh_key" ]; then
            if [ "$NON_INTERACTIVE" = true ]; then
                log_error "SSH public key must be provided with -k in non-interactive mode."
                return 1
            fi
            read -rp "Enter SSH Public Key (starts with ssh-rsa, ssh-ed25519, etc.): " ssh_key
        fi

        if [ -n "$ssh_key" ]; then
            mkdir -p "${user_home}/.ssh"
            chmod 700 "${user_home}/.ssh"
            echo "$ssh_key" >> "${user_home}/.ssh/authorized_keys"
            chmod 600 "${user_home}/.ssh/authorized_keys"
            chown -R "${ssh_user}:${ssh_user}" "${user_home}/.ssh"
            log_success "SSH key successfully appended to ${user_home}/.ssh/authorized_keys."
        else
            log_warning "Empty SSH key entered. Skipping key addition."
        fi
    fi

    # Part B: Change SSH Port
    local current_port
    current_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -n1 || echo "22")
    log_info "Current SSH Port is: ${current_port}"
    
    local change_port
    if [ "$NON_INTERACTIVE" = true ]; then
        if [ -n "$SSH_PORT_VAL" ]; then
            change_port="y"
        else
            change_port="n"
        fi
    else
        read -rp "Change default SSH Port? (y/n) [n]: " change_port
        change_port=${change_port:-n}
    fi

    local new_port="${current_port}"
    if [[ "$change_port" =~ ^[Yy]$ ]]; then
        local input_port
        if [ "$NON_INTERACTIVE" = true ]; then
            input_port=$SSH_PORT_VAL
        else
            read -rp "Enter new SSH Port (1-65535) [22]: " input_port
            input_port=${input_port:-22}
        fi
        if [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
            new_port="$input_port"
            log_info "Port target set to ${new_port}."
        else
            log_error "Invalid port number. Keeping current port ${current_port}."
        fi
    fi

    # Part C: Disable Root Login
    local disable_root
    if [ "$NON_INTERACTIVE" = true ]; then
        disable_root="y"
    else
        read -rp "Disable root SSH login? (y/n) [y]: " disable_root
        disable_root=${disable_root:-y}
    fi

    # Part D: Disable Password Authentication
    local disable_passwd
    if [ "$NON_INTERACTIVE" = true ]; then
        disable_passwd="n"
    else
        read -rp "Disable SSH password authentication (require SSH keys)? (y/n) [n]: " disable_passwd
        disable_passwd=${disable_passwd:-n}
    fi

    # Backup sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Configure SSH options
    sed -i '/^#\?Port/d' /etc/ssh/sshd_config
    sed -i '/^#\?PermitRootLogin/d' /etc/ssh/sshd_config
    sed -i '/^#\?PasswordAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^#\?PubkeyAuthentication/d' /etc/ssh/sshd_config

    # Append new configurations
    echo "Port ${new_port}" >> /etc/ssh/sshd_config
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    
    if [[ "$disable_root" =~ ^[Yy]$ ]]; then
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config
        log_info "PermitRootLogin set to no."
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        log_info "PermitRootLogin set to yes."
    fi

    if [[ "$disable_passwd" =~ ^[Yy]$ ]]; then
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

    # Verify SSH health on the target port
    log_info "Verifying SSH service health on port ${new_port}..."
    local ssh_healthy=false
    for i in {1..15}; do
        if ss -tlnp | grep -q ":${new_port} " || nc -z localhost "${new_port}" 2>/dev/null; then
            ssh_healthy=true
            break
        fi
        sleep 1
    done
    if [ "$ssh_healthy" = true ]; then
        log_success "SSH service is online and listening on port ${new_port}!"
    else
        log_warning "SSH service did not respond on port ${new_port} within 15 seconds."
    fi

    box_message "WARNING: TEST CONNECTION" \
        "Remember to open the new SSH port ${new_port} in your firewall!" \
        "CRITICAL: Do NOT close this terminal session yet." \
        "Open a NEW terminal window and test connecting via:" \
        "  ssh -p ${new_port} ${NEW_USER_VAL:-$REAL_USER}@<host-ip>" \
        "to ensure you are not locked out!"
}

# 14. Install & Configure Fail2Ban (Brute-force protection)
do_configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        run_with_spinner "Installing fail2ban..." bash -c "apt-get update && apt-get install -y fail2ban"
    fi
    
    # Retrieve current SSH port to configure jail
    local ssh_port
    ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -n1 || echo "22")
    
    local jail_path="/etc/fail2ban/jail.local"
    local create_jail=true
    if [ -f "$jail_path" ]; then
        local overwrite_jail
        if [ "$NON_INTERACTIVE" = true ]; then
            overwrite_jail="y"
        else
            read -rp "Fail2Ban configuration already exists at ${jail_path}. Re-initialize with default settings? (y/n) [n]: " overwrite_jail
            overwrite_jail=${overwrite_jail:-n}
        fi
        if [[ ! "$overwrite_jail" =~ ^[Yy]$ ]]; then
            create_jail=false
        fi
    fi

    if [ "$create_jail" = true ]; then
        cat <<EOF > "$jail_path"
[DEFAULT]
# Ban hosts for 1 hour after 5 failures in 10 minutes
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${ssh_port}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
    fi

    # Interactive edit option
    local edit_jail
    if [ "$NON_INTERACTIVE" = true ]; then
        edit_jail="n"
    else
        read -rp "Would you like to edit/review the Fail2Ban configuration (${jail_path}) now? (y/n) [n]: " edit_jail
        edit_jail=${edit_jail:-n}
    fi
    if [[ "$edit_jail" =~ ^[Yy]$ ]]; then
        local editor="${EDITOR:-nano}"
        if command -v "$editor" >/dev/null 2>&1; then
            "$editor" "$jail_path"
        else
            log_warning "Editor '${editor}' not found. Falling back to nano..."
            nano "$jail_path" || vi "$jail_path"
        fi
    fi

    systemctl daemon-reload
    systemctl enable --now fail2ban
    systemctl restart fail2ban &
    show_spinner $!
    
    log_success "Fail2Ban successfully configured and started."
}

# 15. Enable Firewall (UFW)
do_configure_firewall() {
    log_info "Configuring UFW Firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        run_with_spinner "Installing ufw..." apt-get install -y ufw
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

    # Explain about server visibility and tunnel requirements
    box_message "SECURITY NOTICE: FIREWALL ACCESSIBILITY" \
        "The server is NOT invisible to the network, but all incoming ports are CLOSED." \
        "Except port ${ssh_port} for SSH." \
        "To access other applications privately, set up a secure tunnel:" \
        "  1. Tailscale VPN (Access your server privately via VPN)" \
        "  2. Cloudflare Tunnel (Expose services securely behind cloudflare)" \
        "Both options can be configured from Option 24 on the main menu!"
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

# 24. Install VPN & Secure Tunnel (Tailscale / Cloudflare)
do_vpn_tunnel() {
    local net_choice
    if [ "$NON_INTERACTIVE" = true ]; then
        if [ -n "$CF_TOKEN_VAL" ]; then
            net_choice=2
        else
            net_choice=0
        fi
    else
        echo -e "\n${YELLOW}=== VPN & Secure Tunnel Options ===${NC}"
        echo "  1) Install Tailscale (VPN Mesh Network)"
        echo "  2) Configure Cloudflare Tunnel (Secure Web Access)"
        echo "  0) Return to main menu"
        read -rp "Please select [0-2]: " net_choice
    fi
    
    case "${net_choice:-0}" in
        1)
            log_info "Installing Tailscale natively on the host..."
            local install_script
            install_script=$(mktemp)
            curl -fsSL https://tailscale.com/install.sh -o "$install_script"
            if run_with_spinner "Installing Tailscale..." sh "$install_script"; then
                rm -f "$install_script"
                log_success "Tailscale installed natively on the host."
                systemctl enable --now tailscaled
                
                box_message "TAILSCALE INSTALLED SUCCESSFULLY" \
                    "To authenticate and log in:" \
                    "  sudo tailscale up" \
                    "To check connections and view peers:" \
                    "  tailscale status" \
                    "To find the Tailscale IP of your server:" \
                    "  tailscale ip -4" \
                    "To send a file using Taildrop:" \
                    "  tailscale file cp <path-to-file> <peer-node-name>:" \
                    "To receive files sent via Taildrop:" \
                    "  sudo tailscale file get /path/to/save/directory/"
            else
                rm -f "$install_script"
                log_error "Tailscale installation failed."
            fi
            ;;
        2)
            local cf_type
            if [ "$NON_INTERACTIVE" = true ]; then
                cf_type="A"
            else
                echo -e "\n${BLUE}>>> Cloudflare Tunnel Deployment Options:${NC}"
                echo -e "  [Option A] Run Cloudflare Tunnel inside a Docker Container (${GREEN}Recommended${NC})"
                echo -e "  [Option B] Install Cloudflare Tunnel natively on the Host"
                read -rp "Select deployment type (A/B) [A]: " cf_type
                cf_type=${cf_type:-A}
            fi
            
            if [[ "$cf_type" =~ ^[Aa]$ ]]; then
                if ! command -v docker >/dev/null 2>&1; then
                    log_error "Docker is required but not installed. Please install Docker first (Option 51)."
                    return 1
                fi
                log_info "Setting up Cloudflare Tunnel Docker container..."
                
                local cf_tunnel_name
                if [ "$NON_INTERACTIVE" = true ]; then
                    cf_tunnel_name="server-tunnel"
                else
                    read -rp "Enter Cloudflare Tunnel Name: " cf_tunnel_name
                    while [ -z "$cf_tunnel_name" ]; do
                        log_error "Tunnel Name cannot be empty."
                        read -rp "Enter Cloudflare Tunnel Name: " cf_tunnel_name
                    done
                fi
                
                local cf_token="${CF_TOKEN_VAL:-}"
                if [ -z "$cf_token" ]; then
                    if [ "$NON_INTERACTIVE" = true ]; then
                        log_error "Cloudflare token must be provided via -t in non-interactive mode."
                        return 1
                    fi
                    read -rp "Enter Cloudflare Tunnel Token: " cf_token
                    while [ -z "$cf_token" ]; do
                        log_error "Cloudflare Tunnel Token cannot be empty."
                        read -rp "Enter Cloudflare Tunnel Token: " cf_token
                    done
                fi
                
                local user_home
                user_home=$(eval echo "~$REAL_USER")
                local base_path
                if [ "$NON_INTERACTIVE" = true ]; then
                    base_path=$user_home
                else
                    read -rp "Enter base directory to place the tunnel folder [${user_home}]: " base_path
                    base_path=${base_path:-$user_home}
                fi
                
                # Resolve relative path or ~/
                if [[ "$base_path" =~ ^\~(/.*)?$ ]]; then
                    base_path="${user_home}${base_path#\~}"
                elif [[ ! "$base_path" =~ ^/ ]]; then
                    base_path="${user_home}/${base_path}"
                fi
                
                local target_dir="${base_path}/cloudflare-${cf_tunnel_name}"
                
                if [ ! -d "$target_dir" ]; then
                    log_info "Directory '${target_dir}' does not exist. Creating it now..."
                    mkdir -p "$target_dir"
                fi
                
                local cf_net
                if [ "$NON_INTERACTIVE" = true ]; then
                    cf_net="proxy-net"
                else
                    read -rp "Enter Docker Network name [proxy-net]: " cf_net
                    cf_net=${cf_net:-proxy-net}
                fi
                
                if ! docker network inspect "$cf_net" >/dev/null 2>&1; then
                    log_warning "Docker network '$cf_net' does not exist."
                    local create_net
                    if [ "$NON_INTERACTIVE" = true ]; then
                        create_net="y"
                    else
                        read -rp "Create it now? (y/n) [y]: " create_net
                        create_net=${create_net:-y}
                    fi
                    if [[ "$create_net" =~ ^[Yy]$ ]]; then
                        docker network create "$cf_net"
                        log_success "Created Docker network '$cf_net'."
                    fi
                fi
                
                cat <<EOF > "${target_dir}/docker-compose.yml"
version: "3"
services:
  cloudflare-tunnel-${cf_tunnel_name}:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel-${cf_tunnel_name}
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${cf_token}
    networks:
      - tunnel-net

networks:
  tunnel-net:
    external:
      name: ${cf_net}
EOF
                # Ensure the target user owns the created folder if they are not root
                if [ "${REAL_USER}" != "root" ]; then
                    chown -R "${REAL_USER}:${REAL_USER}" "$target_dir"
                fi
                
                log_success "Created Cloudflare Tunnel docker-compose.yml in ${target_dir}."
                
                local start_cf
                if [ "$NON_INTERACTIVE" = true ]; then
                    start_cf="y"
                else
                    read -rp "Start the Cloudflare Tunnel container now? (y/n) [y]: " start_cf
                    start_cf=${start_cf:-y}
                fi
                if [[ "$start_cf" =~ ^[Yy]$ ]]; then
                    docker compose -f "${target_dir}/docker-compose.yml" up -d &
                    show_spinner $!
                    log_success "Cloudflare Tunnel container 'cloudflare-tunnel-${cf_tunnel_name}' started successfully."
                fi
            else
                log_info "Installing Cloudflare Tunnel natively on host..."
                if [ -f /etc/debian_version ]; then
                    log_info "Adding Cloudflare package repository..."
                    mkdir -p --mode=0755 /usr/share/keyrings
                    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
                    if ! command -v lsb_release >/dev/null 2>&1; then
                        run_with_spinner "Installing lsb-release..." apt-get install -y lsb-release
                    fi
                    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
                    run_with_spinner "Updating package lists..." apt-get update
                    run_with_spinner "Installing cloudflared..." apt-get install -y cloudflared
                    log_success "cloudflared installed natively on host."
                    log_info "Configure your tunnel using: 'cloudflared tunnel login'"
                else
                    log_warning "Native installation only supported on Debian/Ubuntu via this script. Attempting generic install..."
                    if run_with_spinner "Downloading cloudflared binary..." curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64; then
                        chmod +x /usr/local/bin/cloudflared
                        log_success "cloudflared binary downloaded and placed in /usr/local/bin/cloudflared."
                    else
                        log_error "Failed to download cloudflared binary."
                    fi
                fi
            fi
            ;;
        *)
            log_info "Returning to main menu."
            ;;
    esac
}

# ==========================================
# NETWORK & TIME SETTINGS FUNCTIONS
# ==========================================

# 21. Assign Static IP Address
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

# 22. Configure Upstream DNS
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

# 23. Timezone & NTP Sync
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
            run_with_spinner "Updating package lists..." apt-get update -y
            run_with_spinner "Installing Fish, GPG, wget, curl..." apt-get install -y fish gpg wget curl
            ;;
        centos|rhel|almalinux|rocky)
            run_with_spinner "Installing EPEL repository..." bash -c "dnf install -y epel-release || true"
            run_with_spinner "Installing Fish, curl, wget, tar..." dnf install -y fish curl wget tar
            ;;
        fedora)
            run_with_spinner "Installing Fish, curl, wget, tar..." dnf install -y fish curl wget tar
            ;;
        arch)
            run_with_spinner "Installing Fish, curl, wget, tar..." pacman -S --noconfirm fish curl wget tar
            ;;
        alpine)
            run_with_spinner "Installing Fish, curl, wget, tar..." apk add fish curl wget tar
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

    local install_script
    install_script=$(mktemp)
    curl -sS https://starship.rs/install.sh -o "$install_script"
    if run_with_spinner "Installing Starship..." sh "$install_script" -y; then
        rm -f "$install_script"
        log_success "Starship installed successfully."
    else
        rm -f "$install_script"
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
            run_with_spinner "Downloading GPG key..." bash -c "wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg"
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de/debian stable main" | tee /etc/apt/sources.list.d/gierens.list >/dev/null
            run_with_spinner "Updating package lists..." apt-get update
            if run_with_spinner "Installing eza..." apt-get install -y eza; then
                log_success "eza installed successfully via gierens repository."
                return 0
            fi
            ;;
        fedora)
            run_with_spinner "Installing eza..." dnf install -y eza && log_success "eza installed from dnf" && return 0
            ;;
        centos|rhel|almalinux|rocky)
            if run_with_spinner "Installing eza..." dnf install -y eza; then
                log_success "eza installed from EPEL repository."
                return 0
            fi
            ;;
        arch)
            run_with_spinner "Installing eza..." pacman -S --noconfirm eza && log_success "eza installed from pacman" && return 0
            ;;
        alpine)
            run_with_spinner "Installing eza..." apk add eza && log_success "eza installed from apk" && return 0
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
    if run_with_spinner "Downloading static eza binary..." wget -qO /tmp/eza_install/eza.tar.gz "$latest_url" || run_with_spinner "Downloading static eza binary (curl)..." curl -sSL -o /tmp/eza_install/eza.tar.gz "$latest_url"; then
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
    
    local target_user
    if [ "$NON_INTERACTIVE" = true ]; then
        target_user=${NEW_USER_VAL:-$REAL_USER}
    else
        read -rp "Configure Fish & Starship for which user? [${REAL_USER}]: " target_user
        target_user=${target_user:-$REAL_USER}
    fi
    
    if ! id "$target_user" >/dev/null 2>&1; then
        log_error "User '$target_user' does not exist."
        return 1
    fi
    
    local user_home
    user_home=$(eval echo "~$target_user")
    
    # 1. Configure Server Identity
    local server_name
    if [ "$NON_INTERACTIVE" = true ]; then
        server_name="MyServer"
    else
        read -rp "Enter the name of this server [MyServer]: " server_name
        server_name=${server_name:-MyServer}
    fi
    
    # 2. Configure Welcome Banner (ASCII Art)
    local temp_art
    temp_art=$(mktemp)
    if [ "$NON_INTERACTIVE" = true ]; then
        cat << EOF > "$temp_art"
 ==========================================
   Welcome to ${server_name}
 ==========================================
EOF
    else
        echo -e "Please paste your welcome ASCII Art below, then press ${GREEN}Ctrl+D${NC} on a new line to finish."
        echo -e "(Or leave empty to use a simple text welcome banner)"
        cat > "$temp_art"
        
        # Check if user pasted anything substantial
        if ! grep -q '[^[:space:]]' "$temp_art"; then
            cat << EOF > "$temp_art"
 ==========================================
   Welcome to ${server_name}
 ==========================================
EOF
        fi
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
success_symbol = "[⚡ ❯](bold green)" # Green bolt for "System Ready"
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
    sed -i "s|__SERVER_NAME__|${server_name}|g" "${user_home}/.config/starship.toml"
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
    chown -R "${target_user}:${target_user}" "${user_home}/.config"

    # Set Default Shell
    local fish_path
    fish_path=$(command -v fish)
    if [ -n "$fish_path" ]; then
        if ! grep -Fxq "$fish_path" /etc/shells; then
            echo "$fish_path" | tee -a /etc/shells >/dev/null
        fi
        
        local change_shell
        if [ "$NON_INTERACTIVE" = true ]; then
            change_shell="y"
        else
            read -rp "Make Fish default login shell for '${target_user}'? (y/n) [y]: " change_shell
            change_shell=${change_shell:-y}
        fi
        if [[ "$change_shell" =~ ^[Yy]$ ]]; then
            chsh -s "$fish_path" "$target_user"
            log_success "Default shell changed to Fish for user '${target_user}'."
        fi
    else
        log_warning "Fish shell binary not found. Please install Fish shell first (Option 41)."
    fi

    local fish_config="${user_home}/.config/fish/config.fish"
    local starship_config="${user_home}/.config/starship.toml"
    
    log_info "Fish configuration is stored at: ${fish_config}"
    log_info "Starship configuration is stored at: ${starship_config}"
    
    local edit_fish
    if [ "$NON_INTERACTIVE" = true ]; then
        edit_fish="n"
    else
        read -rp "Would you like to edit the Fish configuration file now? (y/n) [n]: " edit_fish
        edit_fish=${edit_fish:-n}
    fi
    if [[ "$edit_fish" =~ ^[Yy]$ ]]; then
        nano "$fish_config"
    fi
    
    local edit_starship
    if [ "$NON_INTERACTIVE" = true ]; then
        edit_starship="n"
    else
        read -rp "Would you like to edit the Starship configuration file now? (y/n) [n]: " edit_starship
        edit_starship=${edit_starship:-n}
    fi
    if [[ "$edit_starship" =~ ^[Yy]$ ]]; then
        nano "$starship_config"
    fi

    log_success "Shell and custom telemetry replication configuration complete."
    log_warning "IMPORTANT: You MUST log out of your terminal session and log back in for all changes to take full effect!"
}

# ==========================================
# DOCKER CONTROL FUNCTIONS
# ==========================================

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

# 51. Install/Update Docker & Docker Compose V2
do_install_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker --version)
        log_success "Docker is already installed: ${docker_ver}"
        
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

        local gpg_url="https://download.docker.com/linux/${os_id}/gpg"
        local repo_url="https://download.docker.com/linux/${os_id}"
        
        if [ "$os_id" = "pop" ] || [ "$os_id" = "linuxmint" ]; then
            gpg_url="https://download.docker.com/linux/ubuntu/gpg"
            repo_url="https://download.docker.com/linux/ubuntu"
            os_codename=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
        fi

        run_with_spinner "Adding Docker GPG Key..." bash -c "curl -fsSL '$gpg_url' | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg"

        log_info "Adding Docker apt repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url \
          ${os_codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        run_with_spinner "Updating package lists (Docker repository)..." apt-get update -y
        run_with_spinner "Installing Docker engine..." apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # Fallback to official convenience script
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
        # Configure user permissions
        if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
            log_info "Adding user '${REAL_USER}' to the docker group..."
            groupadd -f docker
            usermod -aG docker "${REAL_USER}"
            
            box_message "DOCKER USER GROUP CONFIGURED" \
                "User '${REAL_USER}' added to the 'docker' group." \
                "To run docker commands without sudo, reload your session:" \
                "  Option A: Log out and log back in." \
                "  Option B: Run: newgrp docker"
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
    
    local prune_choice
    if [ "$NON_INTERACTIVE" = true ]; then
        prune_choice=4
    else
        echo -e "\n${YELLOW}Docker Prune Operations:${NC}"
        echo "  1) Remove Unused Volumes (Volume Prune)"
        echo "  2) Remove Unused Images (Image Prune)"
        echo "  3) Remove Unused Volumes & Images"
        echo "  4) Deep Clean System (System Prune - All Unused Data)"
        echo "  0) Cancel"
        read -rp "Please select prune scope [0-4]: " prune_choice
    fi
    
    case "${prune_choice:-0}" in
        1)
            local conf
            read -rp "Are you sure? (y/n) [n]: " conf
            if [[ "${conf:-n}" =~ ^[Yy]$ ]]; then
                docker volume prune -f >/dev/null 2>&1 &
                show_spinner $!
                log_success "Unused volumes cleared."
            fi
            ;;
        2)
            local img_choice conf
            echo -e "\n${YELLOW}Choose Image Prune Scope:${NC}"
            echo "  1) Prune only dangling images (images without tags)"
            echo "  2) Prune all unused images (images not used by any container)"
            read -rp "Selection [1-2] [1]: " img_choice
            read -rp "Are you sure? (y/n) [n]: " conf
            if [[ "${conf:-n}" =~ ^[Yy]$ ]]; then
                if [ "${img_choice:-1}" = "2" ]; then
                    docker image prune -a -f >/dev/null 2>&1 &
                    show_spinner $!
                else
                    docker image prune -f >/dev/null 2>&1 &
                    show_spinner $!
                fi
                log_success "Unused images cleared."
            fi
            ;;
        3)
            local conf
            read -rp "Are you sure? (y/n) [n]: " conf
            if [[ "${conf:-n}" =~ ^[Yy]$ ]]; then
                docker volume prune -f >/dev/null 2>&1 &
                show_spinner $!
                docker image prune -a -f >/dev/null 2>&1 &
                show_spinner $!
                log_success "Unused volumes and images successfully cleared."
            fi
            ;;
        4)
            local conf
            if [ "$NON_INTERACTIVE" = true ]; then
                conf="y"
            else
                log_warning "This will delete ALL unused containers, networks, images (both dangling and unused), and local volumes!"
                log_warning "This is a complete deep clean of your Docker system."
                read -rp "Are you sure? (y/n) [n]: " conf
            fi
            if [[ "${conf:-n}" =~ ^[Yy]$ ]]; then
                docker system prune -a --volumes -f >/dev/null 2>&1 &
                show_spinner $!
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
    systemctl restart docker &
    show_spinner $!
    verify_docker_health
}

# ==========================================
# INTERACTIVE LOOP
# ==========================================
main() {
    # Ensure script is run with sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        show_header
        log_error "This setup script requires administrative privileges. Please run with sudo:"
        echo -e "  ${YELLOW}sudo $0${NC}"
        exit 1
    fi

    if [ -n "$MODULE_TO_RUN" ]; then
        case "$MODULE_TO_RUN" in
            11) if confirm_action 11; then do_update_upgrade; fi ;;
            12) if confirm_action 12; then do_create_sudo_user; fi ;;
            13) if confirm_action 13; then do_configure_ssh; fi ;;
            14) if confirm_action 14; then do_configure_fail2ban; fi ;;
            15) if confirm_action 15; then do_configure_firewall; fi ;;
            16) if confirm_action 16; then do_laptop_lid_action; fi ;;
            21) if confirm_action 21; then do_static_ip; fi ;;
            22) if confirm_action 22; then do_configure_dns; fi ;;
            23) if confirm_action 23; then do_timezone_ntp; fi ;;
            24) if confirm_action 24; then do_vpn_tunnel; fi ;;
            31) if confirm_action 31; then do_swap_file; fi ;;
            41) if confirm_action 41; then do_install_shell_tools; fi ;;
            42) if confirm_action 42; then do_configure_shell_replica; fi ;;
            51) if confirm_action 51; then do_install_docker; fi ;;
            52) if confirm_action 52; then do_docker_diagnostics; fi ;;
            53) if confirm_action 53; then do_docker_pruning; fi ;;
            54) if confirm_action 54; then do_restart_docker; fi ;;
            *) log_error "Invalid module number: ${MODULE_TO_RUN}" ;;
        esac
        exit 0
    fi

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
        echo -e "    24) Install VPN & Secure Tunnel (Tailscale / Cloudflare)"
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
            11) if confirm_action 11; then do_update_upgrade; fi ;;
            12) if confirm_action 12; then do_create_sudo_user; fi ;;
            13) if confirm_action 13; then do_configure_ssh; fi ;;
            14) if confirm_action 14; then do_configure_fail2ban; fi ;;
            15) if confirm_action 15; then do_configure_firewall; fi ;;
            16) if confirm_action 16; then do_laptop_lid_action; fi ;;
            21) if confirm_action 21; then do_static_ip; fi ;;
            22) if confirm_action 22; then do_configure_dns; fi ;;
            23) if confirm_action 23; then do_timezone_ntp; fi ;;
            24) if confirm_action 24; then do_vpn_tunnel; fi ;;
            31) if confirm_action 31; then do_swap_file; fi ;;
            41) if confirm_action 41; then do_install_shell_tools; fi ;;
            42) if confirm_action 42; then do_configure_shell_replica; fi ;;
            51) if confirm_action 51; then do_install_docker; fi ;;
            52) if confirm_action 52; then do_docker_diagnostics; fi ;;
            53) if confirm_action 53; then do_docker_pruning; fi ;;
            54) if confirm_action 54; then do_restart_docker; fi ;;
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
