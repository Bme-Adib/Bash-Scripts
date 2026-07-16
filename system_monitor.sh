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

# --- Log Helpers ---
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Lock File (Single Instance) ---
LOCK_FILE="/tmp/$(basename "$0").lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo -e "${RED}[ERROR]${NC} Another instance of this script is running." >&2
    exit 1
fi

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

# --- Header ---
show_header() {
    clear
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== System Information & Real-Time Monitor ===${NC}\n"
}

# --- Network Interface & Service Helpers ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

check_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port "
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i :"$port" >/dev/null 2>&1
    else
        (echo > /dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
    fi
}

verify_service_health() {
    local port=$1
    local url="http://localhost:${port}"
    log_info "Verifying service health at $url..."
    for i in {1..15}; do
        if curl -sSf "$url" &>/dev/null; then
            log_success "Service is online and responding!"
            return 0
        fi
        sleep 1
    done
    log_warning "Service failed to respond on port $port within 15 seconds."
    return 1
}

# --- Action Functions ---
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
    echo -e "  Default Interface: ${GREEN}$(detect_interface)${NC}"
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

show_summary_box() {
    log_info "Collecting summary data..."
    local public_ip
    public_ip=$(curl -sS --max-time 3 ifconfig.me 2>/dev/null || curl -sS --max-time 3 icanhazip.com 2>/dev/null || echo "Offline/Unreachable") &
    show_spinner $!
    wait $! 2>/dev/null || true
    
    local lines=(
        "OS Distribution: $([ -f /etc/os-release ] && (. /etc/os-release && echo "${NAME} ${VERSION:-}") || echo "Unknown")"
        "Kernel Version:  $(uname -r)"
        "System Uptime:   $(uptime -p)"
        "Default Net Iface: $(detect_interface)"
        "Public IP:       $public_ip"
    )
    box_message "System Telemetry Summary" "${lines[@]}"
}

install_btop() {
    local prefix=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            prefix="sudo"
            log_info "Sudo privileges needed. Validating credentials..."
            $prefix -v
        else
            log_error "Sudo is not available. Please run this script as root to install btop."
            exit 1
        fi
    fi

    # Perform installation
    if command -v apt-get >/dev/null 2>&1; then
        log_info "Installing btop via apt-get..."
        $prefix apt-get update -y >/dev/null 2>&1 &
        show_spinner $!
        $prefix apt-get install -y btop >/dev/null 2>&1 &
        show_spinner $!
    elif command -v dnf >/dev/null 2>&1; then
        log_info "Installing btop via dnf..."
        $prefix dnf install -y btop >/dev/null 2>&1 &
        show_spinner $!
    elif command -v pacman >/dev/null 2>&1; then
        log_info "Installing btop via pacman..."
        $prefix pacman -S --noconfirm btop >/dev/null 2>&1 &
        show_spinner $!
    elif command -v snap >/dev/null 2>&1; then
        log_info "Installing btop via snap..."
        $prefix snap install btop >/dev/null 2>&1 &
        show_spinner $!
    else
        log_warning "No native package manager found. Attempting to download static release from GitHub..."
        TEMP_DIR=$(mktemp -d)
        
        # Fetch download URL
        log_info "Fetching latest download URL..."
        DOWNLOAD_URL=$(curl -sSL https://api.github.com/repos/aristocratos/btop/releases/latest \
          | grep "browser_download_url.*x86_64-linux-musl.tbz" \
          | cut -d : -f 2,3 \
          | tr -d \" \
          | xargs || echo "")
        
        if [ -n "$DOWNLOAD_URL" ]; then
            log_info "Downloading static btop binary..."
            curl -sSL "$DOWNLOAD_URL" -o "$TEMP_DIR/btop.tbz" >/dev/null 2>&1 &
            show_spinner $!
            
            log_info "Extracting archive..."
            mkdir -p "$TEMP_DIR/btop_extracted"
            tar -xjf "$TEMP_DIR/btop.tbz" -C "$TEMP_DIR/btop_extracted" >/dev/null 2>&1 &
            show_spinner $!
            
            log_info "Installing btop binary..."
            cd "$TEMP_DIR/btop_extracted"
            if [ -f install.sh ]; then
                chmod +x install.sh
                $prefix ./install.sh >/dev/null 2>&1 &
                show_spinner $!
            else
                $prefix cp bin/btop /usr/local/bin/btop >/dev/null 2>&1 &
                show_spinner $!
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
    log_success "btop installed successfully!"
}

# --- Arguments Parsing ---
NON_INTERACTIVE=false
MENU_CHOICE=""
PORT_VAL=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -y, --yes            Run non-interactively (use defaults)"
    echo "  -c, --choice CHOICE  Run a specific menu option directly without entering menu"
    echo "  -p, --port PORT      Verify health of a target port"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -y|--yes) NON_INTERACTIVE=true; shift ;;
        -c|--choice) MENU_CHOICE="$2"; shift 2 ;;
        -p|--port) PORT_VAL="$2"; shift 2 ;;
        *) log_error "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

execute_choice() {
    local choice=$1
    case "$choice" in
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
        9)
            if [ -z "${PORT_VAL:-}" ]; then
                if [ "$NON_INTERACTIVE" = true ]; then
                    log_error "Non-interactive mode requires specifying a port via -p/--port."
                    exit 1
                fi
                read -rp "Enter port number to check: " PORT_VAL
            fi
            if check_port_in_use "$PORT_VAL"; then
                log_success "Port $PORT_VAL is in use!"
                verify_service_health "$PORT_VAL"
            else
                log_warning "Port $PORT_VAL is NOT in use."
            fi
            PORT_VAL="" # Reset after checking
            ;;
        s|summary)
            show_summary_box
            ;;
        0)
            log_success "Exiting System Monitor. Goodbye!"
            exit 0
            ;;
        *)
            log_error "Invalid selection: $choice"
            if [ "$NON_INTERACTIVE" = true ]; then
                exit 1
            fi
            ;;
    esac
}

# --- Main Logic ---
log_info "Verifying system requirements..."
if ! command -v curl >/dev/null 2>&1; then
    log_warning "curl is not installed. Public IP detection and btop download might fail."
fi
log_success "System check complete."
sleep 1

if [ -n "$MENU_CHOICE" ]; then
    show_header
    execute_choice "$MENU_CHOICE"
    exit 0
fi

if [ "$NON_INTERACTIVE" = true ]; then
    show_header
    show_summary_box
    exit 0
fi

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
    echo -e "  9) Check Port/Service Health"
    echo -e "  s) Show Beautiful Summary Box"
    echo -e "  0) Exit Utility"
    echo -e "============================================================\n"
    
    read -rp "Please enter your selection [0-9, s]: " MENU_CHOICE
    echo ""
    
    execute_choice "$MENU_CHOICE"
    
    echo -e "\nPress [ENTER] to return to the menu..."
    read -r _
done
