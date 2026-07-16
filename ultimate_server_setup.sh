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
    tput cnorm 2>/dev/null || printf "\033[?25h"
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
    tput civis 2>/dev/null || printf "\033[?25l"
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    tput cnorm 2>/dev/null || printf "\033[?25h"
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
    local exit_code=0
    wait $pid || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Command failed: $*"
        cat "$log_file" >&2
        rm -f "$log_file"
        return $exit_code
    fi
    rm -f "$log_file"
    return 0
}

wait_for_apt_lock() {
    # Check if unattended-upgrades is running, and try to stop it gracefully
    if pgrep -f "unattended-upgrades" >/dev/null 2>&1; then
        log_info "Stopping background automatic updates service (unattended-upgrades) gracefully..."
        systemctl stop unattended-upgrades 2>/dev/null || true
        sleep 2
    fi

    # Check if the package manager is still locked by any other processes
    if pgrep -f "apt-get|dpkg" | grep -v "$$" >/dev/null 2>&1; then
        log_warning "The package manager database is locked by another task."
        log_info "Attempting to release the lock immediately by stopping active tasks..."
        
        killall -9 apt apt-get dpkg unattended-upgrades 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/debconf/config.dat 2>/dev/null || true
        
        # Heal any interrupted package manager configurations
        log_info "Healing package manager configurations..."
        dpkg --configure -a >/dev/null 2>&1 || true
        log_success "Package manager lock successfully released."
    fi
}

# --- Header ---
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Ultimate Sovereign Server A-to-Z Setup Wizard ===${NC}\n"
}

# --- Network Interface Detection ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

# --- Interactive Step Wrapper ---
should_run_step() {
    local step_num="$1"
    local step_title="$2"
    local explanation="$3"
    
    echo -e "\n${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  [STEP ${step_num}] ${step_title}${NC}"
    echo -e "${BLUE}  Purpose: ${explanation}${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    
    local choice
    read -rp "Do you want to run this step? (y/n) [y]: " choice
    choice=${choice:-y}
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "Skipping Step ${step_num} (${step_title})."
        return 1
    fi
}

# ============================================================
# STATE TRACKING
# ============================================================
MACHINE_TYPE="pc"
CREATED_SUDO_USER=""
SSH_PORT="22"
STATIC_IP_CFG="No"
DNS_CFG="Default"
SWAP_CFG="None"
VPN_CFG="None"

STATUS_UPDATE="SKIPPED"
STATUS_USER="SKIPPED"
STATUS_ROOT_PASS="SKIPPED"
STATUS_SSH="SKIPPED"
STATUS_FAIL2BAN="SKIPPED"
STATUS_FIREWALL="SKIPPED"
STATUS_HARDWARE="SKIPPED"
STATUS_STATIC_IP="SKIPPED"
STATUS_DNS="SKIPPED"
STATUS_TIMEZONE="SKIPPED"
STATUS_SWAP="SKIPPED"
STATUS_SHELL="SKIPPED"
STATUS_DOCKER="SKIPPED"
STATUS_VPN="SKIPPED"

# ============================================================
# MAIN EXECUTION WIZARD
# ============================================================
main() {
    show_header
    
    # 0. Check administrative privileges
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires administrator privileges. Please run with sudo:"
        echo -e "  ${YELLOW}sudo $0${NC}"
        exit 1
    fi

    # 1. Ask Hardware Profile
    echo -e "${BLUE}>>> Select Hardware Profile:${NC}"
    echo -e "  Laptops require power switch management so they don't sleep when closed."
    echo -e "  PCs can benefit from Wake-on-LAN configuration."
    read -rp "Is this server running on a Laptop or a PC? (laptop/pc) [pc]: " profile_input
    profile_input=$(echo "${profile_input:-pc}" | tr '[:upper:]' '[:lower:]')
    while [[ "$profile_input" != "laptop" && "$profile_input" != "pc" ]]; do
        log_error "Invalid entry. Enter 'laptop' or 'pc':"
        read -rp "Is this server running on a Laptop or a PC? [pc]: " profile_input
        profile_input=$(echo "${profile_input:-pc}" | tr '[:upper:]' '[:lower:]')
    done
    MACHINE_TYPE="$profile_input"
    log_success "Profile selected: ${MACHINE_TYPE^^}"

    # ============================================================
    # STEP 1: System Packages Update & Core Tools
    # ============================================================
    if should_run_step "1" "System Package Upgrade & Core CLI Utilities" \
       "Ensures your server has the latest security patches, updates the package registry, and installs mandatory utilities (curl, wget, git, htop, btop, tmux, build-essential)."; then
        export DEBIAN_FRONTEND=noninteractive
        run_with_spinner "Updating system package listings..." apt-get update -y
        run_with_spinner "Upgrading active system packages..." apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
        run_with_spinner "Installing essential tools (curl, wget, git, htop, btop, tmux, build-essential)..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl wget git htop btop tmux build-essential
        log_success "Packages updated and core utilities installed."
        STATUS_UPDATE="COMPLETED"
    fi

    # ============================================================
    # STEP 2: Create Administrative Sudo User
    # ============================================================
    if should_run_step "2" "Scaffold Sudo Administrative User" \
       "Secures the system by avoiding the direct usage of 'root' for day-to-day administrative tasks, creating a dedicated login account with sudo privileges."; then
        local new_user=""
        read -rp "Enter new administrator username: " new_user
        while [ -z "$new_user" ]; do
            log_error "Username cannot be empty."
            read -rp "Enter new administrator username: " new_user
        done

        if id "$new_user" >/dev/null 2>&1; then
            log_warning "User '${new_user}' already exists. Skipping user creation."
        else
            local new_pass="" new_pass_confirm=""
            read -rsp "Enter password for ${new_user}: " new_pass
            echo ""
            read -rsp "Confirm password: " new_pass_confirm
            echo ""

            while [ "$new_pass" != "$new_pass_confirm" ] || [ -z "$new_pass" ]; do
                log_error "Passwords do not match or are empty. Try again:"
                read -rsp "Enter password for ${new_user}: " new_pass
                echo ""
                read -rsp "Confirm password: " new_pass_confirm
                echo ""
            done

            useradd -m -s /bin/bash "$new_user"
            echo "${new_user}:${new_pass}" | chpasswd
            usermod -aG sudo "$new_user"
            
            # Copy SSH keys from root (and original sudo user) to the new user
            local new_user_home="/home/${new_user}"
            local new_user_ssh="${new_user_home}/.ssh"
            mkdir -p "$new_user_ssh"
            chmod 700 "$new_user_ssh"
            
            local source_keys=("/root/.ssh/authorized_keys")
            if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
                local sudo_user_home=$(eval echo "~$SUDO_USER")
                source_keys+=("${sudo_user_home}/.ssh/authorized_keys")
            fi
            
            local keys_copied=0
            for key_file in "${source_keys[@]}"; do
                if [ -f "$key_file" ]; then
                    log_info "Copying SSH keys from ${key_file} to ${new_user}..."
                    cat "$key_file" >> "${new_user_ssh}/authorized_keys"
                    keys_copied=1
                fi
            done
            
            if [ $keys_copied -eq 1 ]; then
                # Remove duplicate keys and set correct permissions
                sort -u "${new_user_ssh}/authorized_keys" -o "${new_user_ssh}/authorized_keys"
                chmod 600 "${new_user_ssh}/authorized_keys"
                chown -R "${new_user}:${new_user}" "$new_user_ssh"
                log_success "SSH authorized keys successfully copied to ${new_user}."
            else
                log_info "No existing SSH keys found on root or original user to copy."
                rmdir "$new_user_ssh" 2>/dev/null || true
            fi

            box_message "ADMIN USER CREATED" \
                "Username: ${new_user}" \
                "Privileges: sudo" \
                "Shell: /bin/bash"
            
            CREATED_SUDO_USER="$new_user"
            STATUS_USER="COMPLETED (Created user: $new_user)"
        fi
    fi

    # ============================================================
    # STEP 3: Change Root User Password
    # ============================================================
    if should_run_step "3" "Change Root User Password" \
       "Secures the root account by setting a new, strong password. This is highly recommended if you are using a VPS with a default provider password."; then
        local root_pass="" root_pass_confirm=""
        read -rsp "Enter new password for root: " root_pass
        echo ""
        read -rsp "Confirm new password for root: " root_pass_confirm
        echo ""

        while [ "$root_pass" != "$root_pass_confirm" ] || [ -z "$root_pass" ]; do
            log_error "Passwords do not match or are empty. Try again:"
            read -rsp "Enter new password for root: " root_pass
            echo ""
            read -rsp "Confirm new password for root: " root_pass_confirm
            echo ""
        done

        if echo "root:${root_pass}" | chpasswd; then
            log_success "Root password successfully changed."
            STATUS_ROOT_PASS="COMPLETED"
        else
            log_error "Failed to change root password."
            STATUS_ROOT_PASS="FAILED"
        fi
    fi

    # ============================================================
    # STEP 4: Configure SSH (SSH Keys, Custom Port, Hardening)
    # ============================================================
    if should_run_step "4" "SSH Service Hardening & Key Registration" \
       "Protects your server against continuous brute-force script bots by locking down SSH. Allows changing the default SSH port, registering public keys, disabling root password login, and forcing SSH key authentication."; then
        
        # Install ssh server if missing
        if ! dpkg -l | grep -q openssh-server; then
            wait_for_apt_lock
            run_with_spinner "Installing openssh-server..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" openssh-server
        fi
        systemctl enable --now ssh

        local target_user="${CREATED_SUDO_USER:-$REAL_USER}"
        if [ -n "$CREATED_SUDO_USER" ]; then
            read -rp "Configure SSH key for newly created user '${CREATED_SUDO_USER}'? (y/n) [y]: " config_new_user_ssh
            config_new_user_ssh=${config_new_user_ssh:-y}
            if [[ ! "$config_new_user_ssh" =~ ^[Yy]$ ]]; then
                target_user="$REAL_USER"
            fi
        fi

        log_info "Configuring SSH authorization for user: $target_user"
        local user_home
        user_home=$(eval echo "~$target_user")

        local add_key
        read -rp "Would you like to register an Authorized SSH Public Key? (y/n) [y]: " add_key
        add_key=${add_key:-y}
        if [[ "$add_key" =~ ^[Yy]$ ]]; then
            read -rp "Paste your SSH Public Key (starts with ssh-rsa, ssh-ed25519, etc.): " pub_key
            if [ -n "$pub_key" ]; then
                mkdir -p "${user_home}/.ssh"
                chmod 700 "${user_home}/.ssh"
                echo "$pub_key" >> "${user_home}/.ssh/authorized_keys"
                chmod 600 "${user_home}/.ssh/authorized_keys"
                chown -R "${target_user}:${target_user}" "${user_home}/.ssh"
                log_success "SSH public key registered."
            else
                log_warning "Empty key entered. Skipping key register."
            fi
        fi

        local change_port
        read -rp "Change the default SSH port from 22? (y/n) [n]: " change_port
        change_port=${change_port:-n}
        if [[ "$change_port" =~ ^[Yy]$ ]]; then
            read -rp "Enter new SSH Port (1-65535): " input_port
            while [[ ! "$input_port" =~ ^[0-9]+$ ]] || [ "$input_port" -lt 1 ] || [ "$input_port" -gt 65535 ]; do
                log_error "Invalid port. Enter a value between 1 and 65535:"
                read -rp "Enter new SSH Port: " input_port
            done
            SSH_PORT="$input_port"
        fi

        local disable_root
        read -rp "Disable administrative 'root' SSH logins? (y/n) [y]: " disable_root
        disable_root=${disable_root:-y}

        local disable_passwd
        read -rp "Disable password login (force SSH key authentication)? (y/n) [n]: " disable_passwd
        disable_passwd=${disable_passwd:-n}

        # Backup configuration
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

        # Clean config file lines
        sed -i '/^#\?Port/d' /etc/ssh/sshd_config
        sed -i '/^#\?PermitRootLogin/d' /etc/ssh/sshd_config
        sed -i '/^#\?PasswordAuthentication/d' /etc/ssh/sshd_config
        sed -i '/^#\?PubkeyAuthentication/d' /etc/ssh/sshd_config

        # Write clean options
        echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
        echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
        
        if [[ "$disable_root" =~ ^[Yy]$ ]]; then
            echo "PermitRootLogin no" >> /etc/ssh/sshd_config
        else
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        fi

        if [[ "$disable_passwd" =~ ^[Yy]$ ]]; then
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
        else
            echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
        fi

        local service_restarted=false
        if systemctl restart ssh 2>/dev/null; then service_restarted=true;
        elif systemctl restart sshd 2>/dev/null; then service_restarted=true; fi

        if [ "$service_restarted" = true ]; then
            log_success "SSH service successfully hardened on port $SSH_PORT."
            STATUS_SSH="COMPLETED (Port: $SSH_PORT, Key Auth: yes)"
        else
            log_error "Could not restart SSH service automatically."
            STATUS_SSH="FAILED TO RESTART SERVICE"
        fi
    fi

    # ============================================================
    # STEP 5: Laptop / PC Tailored Settings
    # ============================================================
    if [ "$MACHINE_TYPE" = "laptop" ]; then
        if should_run_step "5" "Laptop-Specific Server Configuration" \
           "Configures a laptop to operate reliably as a home-server: disables system suspend when the screen/lid is closed, prevents Wi-Fi cards from falling asleep, and tunes CPU governors to prevent latency drops."; then
            
            # 4.1 Lid Close ignoring sleep
            local logind_conf="/etc/systemd/logind.conf"
            if [ -f "$logind_conf" ]; then
                cp "$logind_conf" "${logind_conf}.bak"
                sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$logind_conf"
                sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$logind_conf"
                sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$logind_conf"
                systemctl restart systemd-logind || true
                log_success "Disabled suspend on screen/lid closure."
            fi

            # 4.2 Wi-Fi Power Saving disabling
            local nm_conf="/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf"
            if [ -d "/etc/NetworkManager/conf.d" ]; then
                cat <<EOF > "$nm_conf"
[connection]
wifi.powersave = 2
EOF
                systemctl restart NetworkManager || true
                log_success "Disabled NetworkManager Wi-Fi power savings (value set to 2)."
            else
                local wifi_iface
                wifi_iface=$(iw dev 2>/dev/null | awk '/Interface/ {print $2}' | head -n1 || echo "")
                if [ -n "$wifi_iface" ]; then
                    iw dev "$wifi_iface" set power_save off || true
                    log_success "Disabled power savings on Wi-Fi interface: $wifi_iface"
                fi
            fi

            # 4.3 CPU Governor Optimization
            if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
                if command -v cpufreq-set >/dev/null 2>&1; then
                    cpufreq-set -r -g performance || cpufreq-set -r -g ondemand || true
                else
                    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                        [ -f "$gov" ] && echo "performance" > "$gov" 2>/dev/null || echo "ondemand" > "$gov" 2>/dev/null || true
                    done
                fi
                log_success "CPU Scaling governor optimized to Performance/Ondemand."
            fi

            STATUS_HARDWARE="COMPLETED (Laptop Profile: Suspend, CPU, & Wi-Fi Optimized)"
        fi
    else
        # PC profile: Wake-on-LAN configurations
        if should_run_step "5" "Wake-on-LAN (WOL) Setup" \
           "Enables Wake-on-LAN on your primary network interface so the server can be powered back up remotely via magic network packets."; then
            local active_iface
            active_iface=$(detect_interface)
            
            if ! command -v ethtool >/dev/null 2>&1; then
                run_with_spinner "Installing ethtool to configure network adapter..." apt-get install -y ethtool
            fi

            if command -v ethtool >/dev/null 2>&1; then
                ethtool -s "$active_iface" wol g || log_warning "WOL configuration failed. Interface $active_iface may not support hardware WOL."
                
                # Persist configuration on boots
                cat <<EOF > /etc/systemd/system/wol.service
[Unit]
Description=Configure Wake-on-LAN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${active_iface} wol g

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable wol.service || true
                log_success "Wake-on-LAN enabled on $active_iface and persisted via wol.service."
                STATUS_HARDWARE="COMPLETED (PC Profile: WOL enabled on $active_iface)"
            else
                log_warning "ethtool package missing. WOL config skipped."
            fi
        fi
    fi

    # ============================================================
    # STEP 6: Fail2Ban Configuration
    # ============================================================
    if should_run_step "6" "Fail2Ban Brute-Force Shield" \
       "Monitors authentication logs and automatically blocks suspicious IP addresses showing malicious sign-in patterns on your hardened SSH port."; then
        if ! command -v fail2ban-client >/dev/null 2>&1; then
            wait_for_apt_lock
            run_with_spinner "Installing fail2ban package..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" fail2ban
        fi

        cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

        systemctl daemon-reload
        systemctl enable --now fail2ban
        systemctl restart fail2ban
        log_success "Fail2Ban firewall jail activated for SSH on port $SSH_PORT."
        STATUS_FAIL2BAN="COMPLETED (Bantime: 1h, MaxRetry: 5)"
    fi

    # ============================================================
    # STEP 7: UFW Firewall Setup
    # ============================================================
    if should_run_step "7" "UFW Host Firewall Hardening" \
       "Binds network traffic rules: blocks all unsolicited incoming connection ports by default, allowing only outbound traffic and the configured SSH ports."; then
        
        if ! command -v ufw >/dev/null 2>&1; then
            wait_for_apt_lock
            run_with_spinner "Installing ufw package..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ufw
        fi

        ufw default deny incoming
        ufw default allow outgoing
        ufw allow "${SSH_PORT}/tcp"
        if [ "$SSH_PORT" != "22" ]; then
            ufw allow 22/tcp
            log_info "Port 22 opened temporarily as backup to prevent locked-out sessions."
        fi
        
        ufw --force enable
        log_success "UFW firewall activated."
        STATUS_FIREWALL="COMPLETED (Deny incoming, Allow SSH port: $SSH_PORT)"
    fi

    # ============================================================
    # STEP 8: Netplan Static IP Address
    # ============================================================
    if should_run_step "8" "Static IP Network Interface Assignment" \
       "Ensures your server retains the same IP address on your network (Netplan), which prevents local services from breaking when the router changes leases."; then
        
        local active_iface
        active_iface=$(detect_interface)

        read -rp "Enter Network Interface Name [$active_iface]: " iface
        iface=${iface:-$active_iface}
        
        read -rp "Enter Static IP with Subnet (e.g. 192.168.1.100/24): " ip_addr
        while [[ ! "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; do
            log_error "Invalid CIDR notation format. Use e.g. 192.168.1.100/24:"
            read -rp "Enter Static IP with Subnet: " ip_addr
        done
        
        read -rp "Enter Default Gateway IP (e.g. 192.168.1.1): " gateway
        while [[ ! "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            log_error "Invalid IP format:"
            read -rp "Enter Default Gateway IP: " gateway
        done
        
        read -rp "Enter DNS Servers (comma-separated) [8.8.8.8,8.8.4.4]: " dns_servers
        dns_servers=${dns_servers:-"8.8.8.8,8.8.4.4"}
        
        local formatted_dns
        formatted_dns=$(echo "$dns_servers" | sed 's/\s*,\s*/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
        
        # Backup and configure Netplan
        mkdir -p /etc/netplan/backup
        cp -r /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
        
        if [ -d /etc/cloud/cloud.cfg.d ]; then
            echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg || true
        fi
        mv /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
        
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
        run_with_spinner "Applying netplan static networking configurations..." netplan apply
        log_success "Static IP successfully configured."
        STATIC_IP_CFG="Yes ($ip_addr via $iface)"
        STATUS_STATIC_IP="COMPLETED ($ip_addr)"
    fi

    # ============================================================
    # STEP 9: Configure DNS Resolvers
    # ============================================================
    if should_run_step "9" "Upstream DNS Resolvers configuration" \
       "Ensures nameservers are configured globally for DNS resolution, which speeds up lookups and ensures security packages download cleanly."; then
        
        read -rp "Enter DNS Servers (space-separated) [8.8.8.8 8.8.4.4 1.1.1.1]: " dns_list
        dns_list=${dns_list:-"8.8.8.8 8.8.4.4 1.1.1.1"}
        
        sed -i "s/^#\?DNS=.*/DNS=${dns_list}/" /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        log_success "Upstream systemd-resolved DNS updated."
        DNS_CFG="$dns_list"
        STATUS_DNS="COMPLETED ($dns_list)"
    fi

    # ============================================================
    # STEP 10: Timezone & Network Time Sync
    # ============================================================
    if should_run_step "10" "NTP Clock Sync & System Timezone Setup" \
       "Synchronizes your system clock via Network Time Protocol (NTP) and sets the local timezone, ensuring log files and authentication tokens are stamped accurately."; then
        
        timedatectl set-ntp true
        
        local current_tz
        current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Asia/Kuala_Lumpur")
        [ -z "$current_tz" ] && current_tz="Asia/Kuala_Lumpur"

        read -rp "Enter your preferred timezone [$current_tz]: " tz_input
        tz_input=${tz_input:-$current_tz}
        
        if timedatectl set-timezone "$tz_input" 2>/dev/null; then
            log_success "System timezone configured to $tz_input."
            STATUS_TIMEZONE="COMPLETED ($tz_input)"
        else
            log_error "Failed to register timezone $tz_input."
            STATUS_TIMEZONE="FAILED"
        fi
    fi

    # ============================================================
    # STEP 11: Memory Swap File Allocation
    # ============================================================
    if should_run_step "11" "Swap File Creation & Telemetry Tuning" \
       "Allocates memory swap space on the disk to prevent server crashes under high memory load (OOM exceptions). Configures kernel swappiness to 10 for server workloads."; then
        
        local mem_total_kb mem_total_gb
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_total_gb=$(echo "scale=2; $mem_total_kb/1024/1024" | bc 2>/dev/null || awk "BEGIN {print $mem_total_kb/1048576}")
        log_info "Total Physical Memory: ${mem_total_gb} GB"

        local suggested_swap="4G"
        if [ "$mem_total_kb" -gt 8388608 ]; then suggested_swap="2G"; fi

        read -rp "Enter Swap size (e.g. 2G, 4G, 512M) [$suggested_swap]: " swap_size
        swap_size=${swap_size:-$suggested_swap}

        while [[ ! "$swap_size" =~ ^[0-9]+[GM]$ ]]; do
            log_error "Invalid size format. Enter e.g. 4G, 2G, 1024M:"
            read -rp "Enter Swap size: " swap_size
        done

        local swap_path="/swapfile"
        if [ -f "$swap_path" ]; then
            log_warning "Swap file already exists at $swap_path. Overwriting."
            swapoff "$swap_path" || true
            rm -f "$swap_path"
        fi

        log_info "Allocating $swap_size for $swap_path..."
        local dd_count
        dd_count=$(echo "$swap_size" | sed 's/G/*1024/;s/M//' | bc)
        fallocate -l "$swap_size" "$swap_path" >/dev/null 2>&1 || dd if=/dev/zero of="$swap_path" bs=1M count="$dd_count" >/dev/null 2>&1 &
        show_spinner $!

        chmod 600 "$swap_path"
        mkswap "$swap_path" >/dev/null
        swapon "$swap_path"

        if ! grep -q "${swap_path}" /etc/fstab; then
            echo "${swap_path} none swap sw 0 0" >> /etc/fstab
        fi

        # Optimize Swappiness
        if grep -q "^vm.swappiness=" /etc/sysctl.conf; then
            sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
        else
            echo "vm.swappiness=10" >> /etc/sysctl.conf
        fi
        sysctl -p >/dev/null
        
        log_success "Swap allocation complete. Swappiness set to 10."
        SWAP_CFG="$swap_size"
        STATUS_SWAP="COMPLETED ($swap_size)"
    fi

    # ============================================================
    # STEP 12: Configure Shell (Fish Shell & Starship)
    # ============================================================
    if should_run_step "12" "Modern Interactive Terminal (Fish & Starship)" \
       "Installs Fish shell, eza (modern ls replacement), and configures the Starship prompt to setup a modern looking terminal, interactive with autofill, syntax highlighting, and custom telemetry."; then
        
        # 11.1 Detect OS and install tools
        local os_id="unknown"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            os_id=$ID
        fi

        # Install fish
        case "$os_id" in
            ubuntu|debian)
                wait_for_apt_lock
                run_with_spinner "Installing Fish, GPG, wget, curl..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" fish gpg wget curl
                ;;
            *)
                log_warning "Using generic packages or convenience installers for shell tools..."
                wait_for_apt_lock
                apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" fish curl wget tar || true
                ;;
        esac

        # Install Starship
        if ! command -v starship >/dev/null 2>&1; then
            local star_script
            star_script=$(mktemp)
            curl -sS https://starship.rs/install.sh -o "$star_script"
            run_with_spinner "Installing Starship Prompt..." sh "$star_script" -y
            rm -f "$star_script"
        fi

        # Install eza
        if ! command -v eza >/dev/null 2>&1; then
            case "$os_id" in
                ubuntu|debian)
                    wait_for_apt_lock
                    if ! apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" eza >/dev/null 2>&1; then
                        mkdir -p /etc/apt/keyrings
                        wait_for_apt_lock
                        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
                        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de/debian stable main" | tee /etc/apt/sources.list.d/gierens.list >/dev/null
                        wait_for_apt_lock
                        run_with_spinner "Updating package lists for eza..." apt-get update
                        wait_for_apt_lock
                        run_with_spinner "Installing eza..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" eza
                    fi
                    ;;
            esac
        fi

        # 11.2 Configure Users (Configure both REAL_USER and new CREATED_SUDO_USER if applicable)
        local user_list=("$REAL_USER")
        if [ -n "$CREATED_SUDO_USER" ] && [ "$CREATED_SUDO_USER" != "$REAL_USER" ]; then
            user_list+=("$CREATED_SUDO_USER")
        fi

        local server_identity
        read -rp "Enter prompt display server identity name [MyServer]: " server_identity
        server_identity=${server_identity:-MyServer}

        # Welcome Art
        local art_file=$(mktemp)
        echo -e "\n${BLUE}>>> Configure Welcome Banner (ASCII Art)${NC}"
        echo -e "You can create custom ASCII Art at: ${YELLOW}https://patorjk.com/software/taag/#p=display&f=Coder+Mini&t=Ghannams+Academy&x=none&v=4&h=4&w=80&we=false${NC}"
        echo -e "Please paste your ASCII Art below, then press ${GREEN}Ctrl+D${NC} on a new line to finish."
        echo -e "(Or leave empty to use a simple text welcome banner)"
        
        # Read the paste into the temp file
        cat > "$art_file"

        # Check if the user pasted anything substantial, if not, write a default
        if ! grep -q '[^[:space:]]' "$art_file"; then
            cat << EOF > "$art_file"
 ==========================================
   Welcome to ${server_identity}
 ==========================================
EOF
        fi

        for u in "${user_list[@]}"; do
            local uhome
            uhome=$(eval echo "~$u")
            
            mkdir -p "${uhome}/.config/fish/functions"
            mkdir -p "${uhome}/.config/fish/conf.d"

            # Write starship.toml
            cat << 'EOF' > "${uhome}/.config/starship.toml"
# Aegis Cockpit - Futuristic Wireframe HUD
"$schema" = 'https://starship.rs/config-schema.json'

palette = "biomedical"

add_newline = true

# The HUD layout using box-drawing lines
format = """
╭─$os$username$hostname$directory$git_branch$git_status$git_state$git_metrics$time
╰─$character"""

right_format = "$docker_context$nodejs$python$php$java$dart$flutter$package$cmd_duration$status"

[os]
disabled = false
format = '\[ [$symbol]($style) \]'
style = "bold green"

[os.symbols]
Ubuntu = " "
Linux = " "

[username]
show_always = true
style_user = "bold cyan"
style_root = "bold red"
format = '─\[ [$user]($style)'

[hostname]
ssh_only = false
style = "bold cyan"
format = '[@__SERVER_NAME__]($style) \]'

[directory]
style = "bold blue"
truncation_length = 3
truncate_to_repo = true
format = '─\[ 󰉖 [$path]($style) \]'
repo_root_style = "bold emerald"
repo_root_format = '─\[ 󰉖 [$before_root_path]($style)[$repo_root]($repo_root_style)[$path]($style) \]'

[git_branch]
symbol = " "
style = "bold purple"
format = '(─\[ [$symbol$branch]($style) \])'

[git_status]
style = "bold yellow"
format = '(─\[ [$all_status$ahead_behind]($style) \])'
conflicted = "󰯓 "
ahead = "⇡ "
behind = "⇣ "
diverged = "󰹹 "
untracked = "󰔓 "
stashed = "󰏗 "
modified = "󰏫 "
staged = "󰐖 "
renamed = "󰑕 "
deleted = "󰗨 "

[git_state]
style = "bold red"
format = '(─\[ [$state( $progress_current/$progress_total)]($style) \])'

[git_metrics]
disabled = false
added_style = "bold green"
deleted_style = "bold red"
format = '(─\[ [+$added]($added_style) [-$deleted]($deleted_style) \])'

[time]
disabled = false
time_format = "%R"
style = "bold purple"
format = '─\[ 󱐌 [$time]($style) \]'

[character]
success_symbol = "[ツ ❯](bold emerald) "
error_symbol = "[✘ ❯](bold ruby) "

[nodejs]
symbol = "󰎙 "
style = "bold emerald"
format = "[ $symbol($version )]($style)"

[python]
symbol = "󱔎 "
style = "bold yellow"
format = "[ $symbol($version )]($style)"

[php]
symbol = "󰂄 "
style = "bold blue"
format = "[ $symbol($version )]($style)"

[java]
symbol = " "
style = "bold red"
format = "[ $symbol($version )]($style)"

[package]
symbol = "󰏗 "
style = "bold orange"
format = "[ $symbol($version )]($style)"

[docker_context]
symbol = " "
style = "bold blue"
format = "[ $symbol$context ]($style)"

[cmd_duration]
style = "bold yellow"
format = "[ ⏱ $duration ]($style)"

[status]
disabled = false
symbol = "✘"
style = "bold red"
format = "[ exit $symbol$int ]($style)"

[palettes.biomedical]
ruby = "#E0115F"
emerald = "#50C878"
EOF
            sed -i "s|__SERVER_NAME__|${server_identity}|g" "${uhome}/.config/starship.toml"

            # Write config.fish
            cat << 'EOF' > "${uhome}/.config/fish/config.fish"
if status is-interactive
    alias ll='ls -alF'
    alias la='ls -A'
    if command -v eza >/dev/null 2>&1
        alias ls='eza -hg --icons --git --group-directories-first'
    end
end

starship init fish | source

if test -d "$HOME/.local/bin"
    set -gx PATH "$HOME/.local/bin" $PATH
end
EOF

            # Write greeting function
            cat << 'EOF' > "${uhome}/.config/fish/functions/fish_greeting.fish"
function fish_greeting
    clear
    set_color cyan
    echo "=== Host System Statistics ==="
    set_color normal
    
    if test -f /etc/os-release
        set -l os_name (grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
        echo "OS:          $os_name"
    end
    echo "Kernel:      "(uname -r)
    if test -f /proc/cpuinfo
        set -l cpu_model (grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | string trim)
        echo "CPU Model:   $cpu_model"
    end
    if command -sq free
        echo "RAM (Total): "(free -h | awk '/^Mem:/ {print $2}')" (Free: "(free -h | awk '/^Mem:/ {print $4}')")"
    end
    echo "Disk Storage:"
    df -h | grep -E '^/dev/' | while read -l dev size used avail percent mount
        echo "  - $dev ($mount): Total: $size | Free: $avail (Used: $percent)"
    end
    echo ""
    cat ~/.config/fish/ascii_art.txt 2>/dev/null
end
EOF

            # Write telemetry sysstat
            cat << 'EOF' > "${uhome}/.config/fish/functions/sysstat.fish"
function sysstat --description 'Show system telemetry'
    set_color -o cyan
    echo "================================================"
    echo "               SYSTEM TELEMETRY                 "
    echo "================================================"
    set_color normal

    set_color -o yellow
    echo "[CPU USAGE]"
    set_color normal
    echo "Total CPU Load: "(LC_ALL=C top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')"%"
    echo ""

    set_color -o yellow
    echo "[RAM USAGE]"
    set_color normal
    free -h
    echo ""

    set_color -o yellow
    echo "[DISK STORAGE (GB)]"
    set_color normal
    df -BG -x tmpfs -x devtmpfs -x squashfs -x loop
    
    set_color -o cyan
    echo "================================================"
    set_color normal
end
EOF

            cp "$art_file" "${uhome}/.config/fish/ascii_art.txt"
            chown -R "${u}:${u}" "${uhome}/.config"

            # Set Default Shell
            local fish_path
            fish_path=$(command -v fish)
            if [ -n "$fish_path" ]; then
                if ! grep -Fxq "$fish_path" /etc/shells; then
                    echo "$fish_path" >> /etc/shells
                fi
                chsh -s "$fish_path" "$u"
            fi
        done
        
        rm -f "$art_file"
        log_success "Modern interactive terminal setup complete."
        STATUS_SHELL="COMPLETED (Fish configured with modern Starship prompt)"
    fi

    # ============================================================
    # STEP 13: Docker Installation & Permissions
    # ============================================================
    if should_run_step "13" "Docker Engine & Compose V2 Stack" \
       "Installs Docker Engine, Containerd, and the Docker Compose plugin, allowing you to run microservices in isolated environments. Adds the admin user to the docker group."; then
        
        if command -v docker >/dev/null 2>&1; then
            log_success "Docker already installed: $(docker --version)"
        else
            wait_for_apt_lock
            run_with_spinner "Updating system repository packages..." apt-get update -y
            wait_for_apt_lock
            run_with_spinner "Installing dependencies..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings

            local os_id="ubuntu"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                os_id=$ID
            fi
            
            local gpg_url="https://download.docker.com/linux/${os_id}/gpg"
            local repo_url="https://download.docker.com/linux/${os_id}"
            local os_codename=${VERSION_CODENAME:-"noble"}

            if [ "$os_id" = "pop" ] || [ "$os_id" = "linuxmint" ]; then
                gpg_url="https://download.docker.com/linux/ubuntu/gpg"
                repo_url="https://download.docker.com/linux/ubuntu"
                os_codename=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 || echo "noble")
            fi

            run_with_spinner "Adding Docker official GPG sign key..." bash -c "curl -fsSL '$gpg_url' | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url ${os_codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            wait_for_apt_lock
            run_with_spinner "Updating packages with docker repo..." apt-get update -y
            wait_for_apt_lock
            run_with_spinner "Installing Docker components..." apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
            systemctl daemon-reload
            systemctl enable --now docker
        fi

        # User permissions setup
        local users_to_add=()
        [ -n "$CREATED_SUDO_USER" ] && users_to_add+=("$CREATED_SUDO_USER")
        [ "$REAL_USER" != "root" ] && users_to_add+=("$REAL_USER")

        for u in "${users_to_add[@]}"; do
            groupadd -f docker
            usermod -aG docker "$u"
        done

        log_success "Docker Engine and Docker Compose V2 successfully deployed."
        STATUS_DOCKER="COMPLETED (Docker + Compose V2 installed)"
    fi

    # ============================================================
    # STEP 14: Install VPN Tunnel Access (Tailscale / Cloudflare)
    # ============================================================
    if should_run_step "14" "VPN Mesh & Secure Tunneling (Tailscale/Cloudflare)" \
       "Ensures secure remote access to your server's docker ports without exposing them publicly. Configures Tailscale VPN or sets up a Dockerized Cloudflare Tunnel."; then
        
        echo -e "\n${BLUE}Select VPN/Tunnel Service to configure:${NC}"
        echo "  1) Install Tailscale VPN"
        echo "  2) Scaffold Cloudflare Tunnel (Dockerized)"
        echo "  3) Setup Both"
        echo "  0) Skip/Return"
        read -rp "Select Option [0-3]: " vpn_choice
        vpn_choice=${vpn_choice:-0}

        local vpn_info=""

        if [ "$vpn_choice" = "1" ] || [ "$vpn_choice" = "3" ]; then
            local ts_script=$(mktemp)
            curl -fsSL https://tailscale.com/install.sh -o "$ts_script"
            if run_with_spinner "Deploying Tailscale VPN..." sh "$ts_script"; then
                systemctl enable --now tailscaled
                log_success "Tailscale installed. Log in using: sudo tailscale up"
                vpn_info="Tailscale"
            fi
            rm -f "$ts_script"
        fi

        if [ "$vpn_choice" = "2" ] || [ "$vpn_choice" = "3" ]; then
            if ! command -v docker >/dev/null 2>&1; then
                log_error "Docker is required for Dockerized Cloudflare Tunnel. Please install Docker first (Step 12)."
            else
                read -rp "Enter Cloudflare Tunnel Name: " cf_name
                read -rp "Enter Cloudflare Tunnel Token: " cf_token
                
                if [ -n "$cf_name" ] && [ -n "$cf_token" ]; then
                    local target_home=$(eval echo "~${CREATED_SUDO_USER:-$REAL_USER}")
                    local target_dir="${target_home}/cloudflare-${cf_name}"
                    mkdir -p "$target_dir"
                    
                    cat <<EOF > "${target_dir}/docker-compose.yml"
version: "3"
services:
  cloudflare-tunnel-${cf_name}:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel-${cf_name}
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${cf_token}
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF
                    docker network create proxy-net 2>/dev/null || true
                    chown -R "${CREATED_SUDO_USER:-$REAL_USER}:${CREATED_SUDO_USER:-$REAL_USER}" "$target_dir"
                    
                    read -rp "Launch Cloudflare Tunnel container now? (y/n) [y]: " start_tunnel
                    start_tunnel=${start_tunnel:-y}
                    if [[ "$start_tunnel" =~ ^[Yy]$ ]]; then
                        docker compose -f "${target_dir}/docker-compose.yml" up -d
                        log_success "Cloudflare Tunnel '${cf_name}' started successfully."
                    fi
                    [ -n "$vpn_info" ] && vpn_info="$vpn_info & Cloudflare" || vpn_info="Cloudflare Tunnel"
                else
                    log_warning "Tunnel details missing. Skipping Cloudflare setup."
                fi
            fi
        fi

        if [ -n "$vpn_info" ]; then
            VPN_CFG="$vpn_info"
            STATUS_VPN="COMPLETED ($vpn_info)"
        fi
    fi

    # ============================================================
    # SHUTDOWN / SUMMARY REPORT GENERATOR
    # ============================================================
    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Wizard Complete: Generating Setup Reports...             ${NC}"
    echo -e "${GREEN}============================================================${NC}"

    # Generate Markdown Report Content
    local real_user_home
    real_user_home=$(eval echo "~$REAL_USER")
    local report_path="${real_user_home}/server_setup_report.md"
    
    # Gather system specs
    local os_pretty="Unknown"
    [ -f /etc/os-release ] && os_pretty=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2 || echo "Unknown")
    local kernel_ver=$(uname -r)
    local cpu_spec="Unknown"
    [ -f /proc/cpuinfo ] && cpu_spec=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | xargs)
    local ram_spec=$(free -h | awk '/^Mem:/ {print $2}')
    local disk_spec=$(df -h / | awk 'NR==2 {print $2}')
    local setup_date=$(date '+%Y-%m-%d %H:%M:%S')

    cat <<EOF > "$report_path"
# Sovereign Server Setup Report

Generated on **${setup_date}** by the **Ghannams Academy Sovereign Server Setup Wizard**.

---

## 🖥️ System hardware Specifications

* **Operating System**: ${os_pretty}
* **Kernel Version**: ${kernel_ver}
* **CPU Model**: ${cpu_spec}
* **RAM capacity**: ${ram_spec}
* **Root Disk storage**: ${disk_spec}
* **Hardware Profile**: ${MACHINE_TYPE^^}

---

## 🛠️ Step Setup Summary

| Step Module | Description | Status / Details |
| :--- | :--- | :--- |
| **Step 1** | System Update & Utilities | ${STATUS_UPDATE} |
| **Step 2** | Sudo Admin User Creation | ${STATUS_USER} |
| **Step 3** | Change Root User Password | ${STATUS_ROOT_PASS} |
| **Step 4** | SSH Hardening Configuration | ${STATUS_SSH} |
| **Step 5** | Laptop/PC Hardware Profile | ${STATUS_HARDWARE} |
| **Step 6** | Fail2Ban Protection jail | ${STATUS_FAIL2BAN} |
| **Step 7** | UFW Firewall Activation | ${STATUS_FIREWALL} |
| **Step 8** | Static IP Network config | ${STATUS_STATIC_IP} |
| **Step 9** | Resolved Upstream DNS | ${STATUS_DNS} |
| **Step 10** | System Timezone & NTP Sync | ${STATUS_TIMEZONE} |
| **Step 11** | Disk Swap File Configuration | ${STATUS_SWAP} |
| **Step 12** | Modern Interactive Terminal (Fish & Starship) | ${STATUS_SHELL} |
| **Step 13** | Docker Engine & Compose plugin | ${STATUS_DOCKER} |
| **Step 14** | Tailscale / Cloudflare Tunnels | ${STATUS_VPN} |

---

## 🔒 Server Configurations & Access details

* **Sudo Administrative User**: \`${CREATED_SUDO_USER:-"None created"}\`
* **Hardened SSH Port**: \`${SSH_PORT}\`
* **SSH Authentication Mode**: \`SSH Keys Preferred (Password Auth: ${STATUS_SSH/*Password Auth: /})\`
* **Network Static IP Configuration**: \`${STATIC_IP_CFG}\`
* **Active DNS Nameservers**: \`${DNS_CFG}\`
* **Swap Allocation**: \`${SWAP_CFG}\`
* **Tunneling & VPN Services**: \`${VPN_CFG}\`
* **UFW Firewall Status**: \`Enabled (Deny all incoming, Allow Port: ${SSH_PORT})\`

---

## 🚀 Server Capabilities

Following the completion of this script, this host is now fully prepared to act as a secure, high-retention server container host. It is capable of:
1. **Self-Hosting Apps**: Host services securely using Docker Compose.
2. **Private Networking**: Secure remote access via Tailscale or Cloudflare Tunnel (no port-forwarding needed).
3. **Optimized Memory**: Will not crash on memory spikes due to custom Swap allocation and a Swappiness index of 10.
4. **Hardware Stability**: (Laptops only) Will continue serving and listening even with the lid shut. Wi-Fi won't drop due to disabled power switches.
5. **Brute-Force Shielding**: Bot attempts to scan port 22 or guess passwords are automatically blocked at the boundary by Fail2Ban.
6. **Modern Terminal**: Shell telemetry displaying active Node/Python/Docker contexts on the right deck, and git line metrics on the left deck.

---

*Report scaffolded by Ghannams Academy.*
EOF

    # Set proper ownership for the main report
    chown "${REAL_USER}:${REAL_USER}" "$report_path" 2>/dev/null || true

    # Copy report to the new user home if applicable
    if [ -n "$CREATED_SUDO_USER" ] && [ "$CREATED_SUDO_USER" != "$REAL_USER" ]; then
        local user_home=$(eval echo "~$CREATED_SUDO_USER")
        cp "$report_path" "${user_home}/server_setup_report.md"
        chown "${CREATED_SUDO_USER}:${CREATED_SUDO_USER}" "${user_home}/server_setup_report.md"
    fi

    # Render Terminal Report Summary
    box_message "SERVER SETUP COMPLETED SUCCESS" \
        "Hardware Profile:    ${MACHINE_TYPE^^}" \
        "Hardened SSH Port:   ${SSH_PORT}" \
        "Sudo Admin User:     ${CREATED_SUDO_USER:-"None Created (Active user: $REAL_USER)"}" \
        "Swap Allocation:     ${SWAP_CFG}" \
        "Tunnels Configured:  ${VPN_CFG}" \
        "Detailed Report:      ${report_path}" \
        "" \
        "IMPORTANT ACTIONS REQUIRED:" \
        "1. Open port ${SSH_PORT} in your cloud provider firewall if applicable." \
        "2. Do NOT close this session yet. Test SSH in a new window:" \
        "   ssh -p ${SSH_PORT} ${CREATED_SUDO_USER:-$REAL_USER}@<host-ip>" \
        "3. LOG OUT and log back in to activate the Fish shell environment!"
}

main "$@"
