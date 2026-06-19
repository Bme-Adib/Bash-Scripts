#!/bin/bash
set -euo pipefail

# --- Redirect stdin to tty if piped ---
if [ ! -t 0 ]; then
    exec 0</dev/tty
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Header ---
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== System Information & Real-Time Monitor ===${NC}\n"
}

# --- Cleanup Trap ---
TEMP_DIR=""
cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT


# 1. Dependency Checks
log_info "Verifying system requirements..."
if ! command -v curl >/dev/null 2>&1; then
    log_warning "curl is not installed. Public IP detection and btop download might fail."
fi
log_success "System check complete."
sleep 1


# 2. Action Functions
show_os_info() {
    echo -e "${BLUE}=== [1] General System & OS Info ===${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "  OS Distribution: ${GREEN}${NAME} ${VERSION:-}${NC}"
    fi
    echo -e "  Kernel Version:  ${NC}$(uname -r)"
    echo -e "  System Uptime:   ${NC}$(uptime -p)"
    echo -e "  Logged Users:    ${NC}$(uptime | awk -F', ' '{print $2}' 2>/dev/null || uptime)"
}

show_cpu_info() {
    echo -e "${BLUE}=== [2] CPU & Processor Info ===${NC}"
    if command -v lscpu >/dev/null 2>&1; then
        local cpu_model cpu_cores cpu_threads
        cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//' || echo "Unknown")
        cpu_cores=$(lscpu | grep "^CPU(s):" | sed 's/CPU(s):\s*//' || echo "Unknown")
        cpu_threads=$(lscpu | grep "Thread(s) per core:" | sed 's/Thread(s) per core:\s*//' || echo "Unknown")
        echo -e "  CPU Model:       ${GREEN}${cpu_model}${NC}"
        echo -e "  Total Cores:     ${NC}${cpu_cores} (Threads/Core: ${cpu_threads})"
    else
        echo -e "  lscpu utility not available."
    fi
}

show_memory_info() {
    echo -e "${BLUE}=== [3] Memory (RAM) Info ===${NC}"
    free -h | awk '
    /Mem:/ { print "  Physical RAM:    Total: \033[0;32m" $2 "\033[0m | Used: " $3 " | Free: \033[0;32m" $4 "\033[0m" }
    /Swap:/ { print "  Swap Space:      Total: " $2 " | Used: " $3 " | Free: " $4 }
    ' || echo "  Failed to retrieve memory statistics."
}

show_storage_info() {
    echo -e "${BLUE}=== [4] Storage (Disk) Space ===${NC}"
    echo -e "  Mountpoints Usage:"
    df -h | grep -E '^/dev/' | while read -r line; do
        local dev size used avail percent mount
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        percent=$(echo "$line" | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')
        echo -e "    - ${mount} (${dev}): Total: ${size} | Free: ${GREEN}${avail}${NC} (Used: ${percent})"
    done || true
    echo -e "\n  Block Devices Listing:"
    lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINTS 2>/dev/null | sed 's/^/    /' || echo "  lsblk utility not available."
}

show_network_info() {
    echo -e "${BLUE}=== [5] Network Information ===${NC}"
    echo -e "  Local Network Interfaces:"
    if command -v ip >/dev/null 2>&1; then
        ip -br a 2>/dev/null | sed 's/^/    - /' || ip a | grep "inet " | sed 's/^/    - /'
    else
        echo "    - ip command not found."
    fi
    
    log_info "Detecting Public IP address..."
    local public_ip
    public_ip=$(curl -sS --max-time 3 ifconfig.me 2>/dev/null || curl -sS --max-time 3 icanhazip.com 2>/dev/null || echo "Offline/Unreachable")
    echo -e "  Public IP:       ${GREEN}${public_ip}${NC}"
}

show_hardware_info() {
    echo -e "${BLUE}=== [6] Hardware Summary (Detailed) ===${NC}"
    if [ "$EUID" -ne 0 ]; then
        log_warning "Detailed hardware summary requires administrative privileges (sudo/root)."
        return 0
    fi
    if command -v lshw >/dev/null 2>&1; then
        lshw -short | sed 's/^/    /' || true
    else
        echo -e "  lshw is not installed."
    fi
}

show_all_stats() {
    show_os_info
    echo ""
    show_cpu_info
    echo ""
    show_memory_info
    echo ""
    show_storage_info
    echo ""
    show_network_info
    echo ""
    show_hardware_info
}


# 3. Resource Setup Functions
install_btop() {
    # Try installing via native package manager (prefixed with sudo if not root)
    local prefix=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            prefix="sudo"
        else
            log_error "Sudo is not available. Please run this script as root to install btop."
            exit 1
        fi
    fi

    # Perform installation
    if command -v apt-get >/dev/null 2>&1; then
        log_info "Installing btop via apt-get..."
        $prefix apt-get update -y
        $prefix apt-get install -y btop
    elif command -v dnf >/dev/null 2>&1; then
        log_info "Installing btop via dnf..."
        $prefix dnf install -y btop
    elif command -v pacman >/dev/null 2>&1; then
        log_info "Installing btop via pacman..."
        $prefix pacman -S --noconfirm btop
    elif command -v snap >/dev/null 2>&1; then
        log_info "Installing btop via snap..."
        $prefix snap install btop
    else
        # Fallback to official GitHub static release binary
        log_warning "No native package manager found. Attempting to download static release from GitHub..."
        
        TEMP_DIR=$(mktemp -d)

        # Fetch latest release download URL for static linux x86_64 binary
        DOWNLOAD_URL=$(curl -sSL https://api.github.com/repos/aristocratos/btop/releases/latest \
          | grep "browser_download_url.*x86_64-linux-musl.tbz" \
          | cut -d : -f 2,3 \
          | tr -d \" \
          | xargs || echo "")

        if [ -n "$DOWNLOAD_URL" ]; then
            log_info "Downloading static btop binary from: ${DOWNLOAD_URL}"
            curl -sSL "$DOWNLOAD_URL" -o "$TEMP_DIR/btop.tbz"
            
            log_info "Extracting archive..."
            mkdir -p "$TEMP_DIR/btop_extracted"
            tar -xjf "$TEMP_DIR/btop.tbz" -C "$TEMP_DIR/btop_extracted"
            
            log_info "Installing btop binary to /usr/local/bin..."
            cd "$TEMP_DIR/btop_extracted"
            if [ -f install.sh ]; then
                chmod +x install.sh
                $prefix ./install.sh || $prefix cp bin/btop /usr/local/bin/btop
            else
                $prefix cp bin/btop /usr/local/bin/btop
            fi
        else
            log_error "Could not fetch download link from GitHub. Please install btop manually."
            exit 1
        fi
    fi

    # Verify installation
    if ! command -v btop >/dev/null 2>&1; then
        log_error "Installation finished but btop command was not found in PATH."
        exit 1
    fi
}


# 4. Interactive UX Flow & Option Selection
while true; do
    show_header
    
    echo -e "${YELLOW}Available Options:${NC}"
    echo -e "  1) Run All Diagnostics (Summary)"
    echo -e "  2) Show General System & OS Info"
    echo -e "  3) Show CPU & Processor Info"
    echo -e "  4) Show Memory (RAM) Info"
    echo -e "  5) Show Storage (Disk) Space"
    echo -e "  6) Show Network Information"
    echo -e "  7) Show Hardware Summary (Detailed)"
    echo -e "  8) Launch Real-Time Resource Monitor (btop)"
    echo -e "  0) Exit Utility"
    echo -e "============================================================\n"
    
    read -rp "Please enter your selection [0-8]: " MENU_CHOICE
    echo ""
    
    case "$MENU_CHOICE" in
        1)
            show_all_stats
            ;;
        2)
            show_os_info
            ;;
        3)
            show_cpu_info
            ;;
        4)
            show_memory_info
            ;;
        5)
            show_storage_info
            ;;
        6)
            show_network_info
            ;;
        7)
            show_hardware_info
            ;;
        8)
            if ! command -v btop >/dev/null 2>&1; then
                log_info "btop System Monitor is not installed."
                install_btop
            fi
            log_success "Launching btop System Monitor..."
            sleep 1
            exec btop
            ;;
        0)
            log_success "Exiting System Monitor. Goodbye!"
            break
            ;;
        *)
            log_error "Invalid selection. Please try again."
            ;;
    esac
    
    echo -e "\nPress [ENTER] to return to the menu..."
    read -r _
done
