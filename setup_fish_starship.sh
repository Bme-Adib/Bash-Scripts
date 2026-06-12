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

# --- Header ---
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Bash Script By Adib Builds (https://github.com/Bme-Adib)  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}=== Fish Shell & Starship Prompt Replicator ===${NC}\n"

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
    case "$OS_NAME" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y fish gpg wget curl
            ;;
        centos|rhel|almalinux|rocky)
            sudo dnf install -y epel-release || true
            sudo dnf install -y fish curl wget tar
            ;;
        fedora)
            sudo dnf install -y fish curl wget tar
            ;;
        arch)
            sudo pacman -S --noconfirm fish curl wget tar
            ;;
        alpine)
            sudo apk add fish curl wget tar
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
    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
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

    case "$OS_NAME" in
        ubuntu|debian)
            # Try installing from official repositories (newer distros)
            if sudo apt-get install -y eza >/dev/null 2>&1; then
                log_success "eza installed from standard apt repositories."
                return
            fi
            
            # If not in standard repos, register gierens repo
            log_info "eza not found in standard apt repos. Registering gierens repository..."
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de/debian stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
            sudo apt-get update
            if sudo apt-get install -y eza; then
                log_success "eza installed successfully via gierens repository."
                return
            fi
            ;;
        fedora)
            sudo dnf install -y eza && log_success "eza installed from dnf" && return
            ;;
        centos|rhel|almalinux|rocky)
            # EPEL repo check
            if sudo dnf install -y eza >/dev/null 2>&1; then
                log_success "eza installed from EPEL repository."
                return
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm eza && log_success "eza installed from pacman" && return
            ;;
        alpine)
            sudo apk add eza && log_success "eza installed from apk" && return
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
    if wget -qO /tmp/eza_install/eza.tar.gz "$latest_url" || curl -sSL -o /tmp/eza_install/eza.tar.gz "$latest_url"; then
        tar -xzf /tmp/eza_install/eza.tar.gz -C /tmp/eza_install
        sudo mv /tmp/eza_install/eza /usr/local/bin/eza
        sudo chmod +x /usr/local/bin/eza
        rm -rf /tmp/eza_install
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
format = "[$hostname](bold yellow) "

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
    cat << 'EOF' > "$HOME/.config/fish/ascii_art.txt"
 _______           _______  _        _        _______  _______        _______  _______  _______           _______  _______ 
(  ____ \|\     /|(  ___  )( (    /|( (    /|(  ___  )(       )      (  ____ \(  ____ \(  ____ )|\     /|(  ____ \(  ____ )
| (    \/| )   ( || (   ) ||  \  ( ||  \  ( || (   ) || () () |      | (    \/| (    \/| (    )|| )   ( || (    \/| (    )|
| |      | (___) || (___) ||   \ | ||   \ | || (___) || || || |      | (_____ | (__    | (____)|| |   | || (__    | (____)|
| | ____ |  ___  ||  ___  || (\ \) || (\ \) ||  ___  || |(_)| |      (_____  )|  __)   |     __)( (   ) )|  __)   |     __)
| | \_  )| (   ) || (   ) || | \   || | \   || (   ) || |   | |            ) || (      | (\ (    \ \_/ / | (      | (\ (   
| (___) || )   ( || )   ( || )  \  || )  \  || )  \  || )   ( |      /\____) || (____/\| ) \ \__  \   /  | (____/\| ) \ \__
(_______)|/     \||/     \||/    )_)|/    )_)|/     \||/     \|      \_______)(_______/|/   \__/   \_/   (_______/|/   \__/
EOF
    log_success "Created welcome artwork: $HOME/.config/fish/ascii_art.txt"

    # Write fish_greeting.fish
    cat << 'EOF' > "$HOME/.config/fish/functions/fish_greeting.fish"
function fish_greeting
    cat ~/.config/fish/ascii_art.txt 2>/dev/null || echo "Welcome back, Mr. Ghannam"
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
    
    # Change default shell
    read -rp "Would you like to make Fish your default login shell? (y/n) [y]: " CHANGE_SHELL
    CHANGE_SHELL=${CHANGE_SHELL:-y}
    
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
detect_os
if ! command -v fish >/dev/null 2>&1; then
    install_fish
else
    log_success "Fish Shell is already installed: $(fish --version)"
fi

install_starship
install_eza
write_configs
set_default_shell

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}               Replication Setup Complete!                  ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "To launch your new shell immediately, run:"
echo -e "  ${YELLOW}fish${NC}"
echo -e "Inside the Fish shell, you can check telemetry using:"
echo -e "  ${YELLOW}sysstat${NC}"
echo -e "============================================================\n"
