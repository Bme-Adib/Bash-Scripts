#!/bin/bash
# --- Robust Safety & Error Handling ---
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
NC='\033[0m' # No Color

# --- Lock File (Single Instance) ---
LOCK_FILE="/tmp/$(basename "$0").lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo -e "${RED}[ERROR]${NC} Another instance of this script is running." >&2
    exit 1
fi

# --- Styled Log Helpers ---
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Smart Cleanup Trap ---
TEMP_ART_FILE=""
cleanup() {
    tput cnorm 2>/dev/null || printf "\033[?25h" # Restore cursor
    if [ -n "${TEMP_ART_FILE:-}" ] && [ -f "$TEMP_ART_FILE" ]; then
        rm -f "$TEMP_ART_FILE"
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
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Bash Script By Ghannams Academy (github.com/Bme-Adib)     ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${BLUE}=== Fish Shell & Starship Prompt Replicator ===${NC}\n"
}

# --- Default Network Interface Detection ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

# --- Arguments Parsing ---
NON_INTERACTIVE=false
SERVER_NAME=""
custom_server_name_flag=false

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -y, --yes            Run non-interactively (use defaults)"
    echo "  -s, --server NAME    Specify server name"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -y|--yes) NON_INTERACTIVE=true; shift ;;
        -s|--server) SERVER_NAME="$2"; custom_server_name_flag=true; shift 2 ;;
        *) log_error "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

# 1. Detect Host OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
    else
        OS_NAME="unknown"
    fi
    log_info "Detected OS: ${OS_NAME}"
}

# 2. Install Fish Shell
install_fish() {
    log_info "Installing Fish Shell..."
    local prefix=""
    if [ "$EUID" -ne 0 ]; then prefix="sudo"; fi

    case "$OS_NAME" in
        ubuntu|debian)
            $prefix apt-get update -y >/dev/null 2>&1 &
            show_spinner $!
            $prefix apt-get install -y fish gpg wget curl >/dev/null 2>&1 &
            show_spinner $!
            ;;
        centos|rhel|almalinux|rocky)
            $prefix dnf install -y epel-release >/dev/null 2>&1 &
            show_spinner $!
            $prefix dnf install -y fish curl wget tar >/dev/null 2>&1 &
            show_spinner $!
            ;;
        fedora)
            $prefix dnf install -y fish curl wget tar >/dev/null 2>&1 &
            show_spinner $!
            ;;
        arch)
            $prefix pacman -S --noconfirm fish curl wget tar >/dev/null 2>&1 &
            show_spinner $!
            ;;
        alpine)
            $prefix apk add fish curl wget tar >/dev/null 2>&1 &
            show_spinner $!
            ;;
        *)
            log_error "Unsupported OS for automatic Fish installation. Please install Fish shell manually."
            exit 1
            ;;
    esac
    log_success "Fish Shell installed successfully."
}

# 3. Install Starship
install_starship() {
    log_info "Installing Starship Prompt..."
    if command -v starship >/dev/null 2>&1; then
        log_success "Starship is already installed: $(starship --version | head -n 1)"
        return
    fi

    # Use the official installer script
    local prefix=""
    if [ "$EUID" -ne 0 ]; then prefix="sudo"; fi

    (curl -sS https://starship.rs/install.sh | $prefix sh -s -- -y) >/dev/null 2>&1 &
    show_spinner $!

    if command -v starship >/dev/null 2>&1; then
        log_success "Starship installed successfully."
    else
        log_error "Starship installation failed."
        exit 1
    fi
}

# 4. Install eza (Modern replacement for ls)
install_eza() {
    log_info "Installing eza (modern ls)..."
    if command -v eza >/dev/null 2>&1; then
        log_success "eza is already installed: $(eza --version | head -n 1)"
        return
    fi

    local prefix=""
    if [ "$EUID" -ne 0 ]; then prefix="sudo"; fi

    case "$OS_NAME" in
        ubuntu|debian)
            # Try installing from official repositories (newer distros)
            $prefix apt-get install -y eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed from standard apt repositories."
                return
            fi
            
            # If not in standard repos, register gierens repo
            log_info "eza not found in standard apt repos. Registering gierens repository..."
            $prefix mkdir -p /etc/apt/keyrings
            (wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | $prefix gpg --dearmor -o /etc/apt/keyrings/gierens.gpg) >/dev/null 2>&1 &
            show_spinner $!
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de/debian stable main" | $prefix tee /etc/apt/sources.list.d/gierens.list >/dev/null
            $prefix apt-get update -y >/dev/null 2>&1 &
            show_spinner $!
            $prefix apt-get install -y eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed successfully via gierens repository."
                return
            fi
            ;;
        fedora)
            $prefix dnf install -y eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed from dnf."
                return
            fi
            ;;
        centos|rhel|almalinux|rocky)
            $prefix dnf install -y eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed from EPEL repository."
                return
            fi
            ;;
        arch)
            $prefix pacman -S --noconfirm eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed from pacman."
                return
            fi
            ;;
        alpine)
            $prefix apk add eza >/dev/null 2>&1 &
            show_spinner $!
            if command -v eza >/dev/null 2>&1; then
                log_success "eza installed from apk."
                return
            fi
            ;;
    esac

    # Fallback: Download latest precompiled x86_64 binary from GitHub
    log_info "Attempting to download latest eza static binary from GitHub releases..."
    local latest_url
    latest_url=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep "browser_download_url.*eza_x86_64-unknown-linux-gnu.tar.gz" | cut -d '"' -f 4 || echo "")
    if [ -z "$latest_url" ]; then
        latest_url="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
    fi

    mkdir -p /tmp/eza_install
    (wget -qO /tmp/eza_install/eza.tar.gz "$latest_url" || curl -sSL -o /tmp/eza_install/eza.tar.gz "$latest_url") >/dev/null 2>&1 &
    show_spinner $!
    
    (tar -xzf /tmp/eza_install/eza.tar.gz -C /tmp/eza_install && \
     $prefix mv /tmp/eza_install/eza /usr/local/bin/eza && \
     $prefix chmod +x /usr/local/bin/eza) >/dev/null 2>&1 &
    show_spinner $!
    rm -rf /tmp/eza_install

    if command -v eza >/dev/null 2>&1; then
        log_success "eza static binary installed to /usr/local/bin/eza."
    else
        log_warning "Could not install eza. The alias 'ls' will still be configured but will fall back to normal ls if eza is missing."
    fi
}

# 5. Write Configuration Files
write_configs() {
    log_info "Writing custom configuration files..."
    
    # Create configuration directories
    mkdir -p "$HOME/.config/fish/functions"
    mkdir -p "$HOME/.config/fish/conf.d"

    # Write starship.toml
    cat << 'EOF' > "$HOME/.config/starship.toml"
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
    # Perform custom server name mapping in starship config
    sed -i "s|__SERVER_NAME__|${SERVER_NAME}|g" "$HOME/.config/starship.toml"
    log_success "Created starship settings: $HOME/.config/starship.toml"

    # Write config.fish
    cat << 'EOF' > "$HOME/.config/fish/config.fish"
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
    log_success "Created fish configuration: $HOME/.config/fish/config.fish"

    # Write ascii_art.txt
    cp "$TEMP_ART_FILE" "$HOME/.config/fish/ascii_art.txt"
    log_success "Created welcome artwork: $HOME/.config/fish/ascii_art.txt"

    # Write fish_greeting.fish
    cat << 'EOF' > "$HOME/.config/fish/functions/fish_greeting.fish"
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
    log_success "Created fish greeting: $HOME/.config/fish/functions/fish_greeting.fish"

    # Write sysstat.fish
    cat << 'EOF' > "$HOME/.config/fish/functions/sysstat.fish"
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
    log_success "Created sysstat command: $HOME/.config/fish/functions/sysstat.fish"
}

# 6. Change Default Shell to Fish
set_default_shell() {
    log_info "Configuring Fish as default shell..."
    local fish_path
    fish_path=$(command -v fish)
    
    if [ -z "$fish_path" ]; then
        log_error "Fish path not found. Cannot change default shell."
        return
    fi
    
    # Add Fish to /etc/shells if not already present
    if ! grep -Fxq "$fish_path" /etc/shells; then
        echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
    fi
    
    local CHANGE_SHELL
    if [ "$NON_INTERACTIVE" = true ]; then
        CHANGE_SHELL="n"
    else
        read -rp "Would you like to make Fish your default login shell? (y/n) [y]: " CHANGE_SHELL
        CHANGE_SHELL=${CHANGE_SHELL:-y}
    fi
    
    if [[ "$CHANGE_SHELL" =~ ^[Yy]$ ]]; then
        if chsh -s "$fish_path"; then
            log_success "Default shell changed to Fish. Please log out and back in for changes to take effect."
        else
            if sudo chsh -s "$fish_path" "$USER"; then
                log_success "Default shell changed to Fish (via sudo)."
            else
                log_warning "Failed to change default shell automatically. You can do it manually by running: chsh -s $fish_path"
            fi
        fi
    else
        log_info "Skipping default shell change."
    fi
}

# Run replication
show_header

# Verify/cache sudo privileges if not root
if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        log_info "Sudo privileges required for installation. Authenticating..."
        sudo -v
    else
        log_error "This script requires root or sudo privileges."
        exit 1
    fi
fi

detect_os

# 1. Configure Server Identity
if [ "$custom_server_name_flag" = false ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        SERVER_NAME="MyServer"
    else
        echo -e "\n${BLUE}>>> Step 1: Configure Server Identity${NC}"
        read -rp "Enter the name of this server [MyServer]: " SERVER_NAME
        SERVER_NAME=${SERVER_NAME:-MyServer}
    fi
fi

# 2. Configure Welcome Banner (ASCII Art)
TEMP_ART_FILE=$(mktemp)
if [ "$NON_INTERACTIVE" = true ]; then
    # Write default banner
    cat << EOF > "$TEMP_ART_FILE"
 ==========================================
   Welcome to ${SERVER_NAME}
 ==========================================
EOF
else
    echo -e "\n${BLUE}>>> Step 2: Configure Welcome Banner (ASCII Art)${NC}"
    echo -e "You can create custom ASCII Art at: ${YELLOW}https://patorjk.com/software/taag/#p=display&f=Coder+Mini&t=Ghannams+Academy&x=none&v=4&h=4&w=80&we=false${NC}"
    echo -e "Please paste your ASCII Art below, then press ${GREEN}Ctrl+D${NC} on a new line to finish."
    echo -e "(Or leave empty to use a simple text welcome banner)"
    
    # We will read it directly into a temp file to avoid escaping and shell variable expansion issues
    cat > "$TEMP_ART_FILE"

    # Check if the user pasted anything substantial
    if ! grep -q '[^[:space:]]' "$TEMP_ART_FILE"; then
        # Write default banner
        cat << EOF > "$TEMP_ART_FILE"
 ==========================================
   Welcome to ${SERVER_NAME}
 ==========================================
EOF
    fi
fi

if ! command -v fish >/dev/null 2>&1; then
    install_fish
else
    log_success "Fish Shell is already installed: $(fish --version)"
fi

install_starship
install_eza
write_configs
set_default_shell

echo ""
summary_lines=(
    "Server Name:       ${SERVER_NAME}"
    "Default Interface: $(detect_interface)"
    "Fish Shell:        $(command -v fish || echo 'Not installed')"
    "Starship:          $(command -v starship || echo 'Not installed')"
    "eza (modern ls):   $(command -v eza || echo 'Not installed')"
    ""
    "To launch Fish immediately, run: fish"
    "To check system telemetry, run: sysstat"
)
box_message "Fish & Starship Setup Complete" "${summary_lines[@]}"
echo ""
