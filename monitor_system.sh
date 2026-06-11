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
echo -e "${BLUE}=== Real-Time System Monitor Setup (btop) ===${NC}\n"

# Check if btop is already installed
if command -v btop >/dev/null 2>&1; then
    log_success "btop is already installed on your system."
    log_info "Launching btop System Monitor..."
    sleep 1
    exec btop
fi

# If not installed, we need root/sudo privileges to install it
if [ "$EUID" -ne 0 ]; then
    log_error "btop is not installed. Administrative privileges (sudo) are required to install it."
    echo -e "Please re-run this script with sudo:"
    echo -e "  ${YELLOW}sudo $0${NC}"
    exit 1
fi

log_info "btop system monitor is not installed. Starting automatic installation..."

# Try installing via native package manager
if command -v apt-get >/dev/null 2>&1; then
    log_info "Installing btop via apt-get..."
    apt-get update -y
    apt-get install -y btop
elif command -v dnf >/dev/null 2>&1; then
    log_info "Installing btop via dnf..."
    dnf install -y btop
elif command -v pacman >/dev/null 2>&1; then
    log_info "Installing btop via pacman..."
    pacman -S --noconfirm btop
elif command -v snap >/dev/null 2>&1; then
    log_info "Installing btop via snap..."
    snap install btop
else
    # Fallback to official GitHub static release binary
    log_warning "No native package manager found. Attempting to download static release from GitHub..."
    
    TEMP_DIR=$(mktemp -d)
    cleanup() {
        rm -rf "$TEMP_DIR"
    }
    trap cleanup EXIT

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
        # Try running their installation script, or copy directly
        if [ -f install.sh ]; then
            chmod +x install.sh
            ./install.sh || cp bin/btop /usr/local/bin/btop
        else
            cp bin/btop /usr/local/bin/btop
        fi
    else
        log_error "Could not fetch download link from GitHub. Please install btop manually."
        exit 1
    fi
fi

# Verify installation
if command -v btop >/dev/null 2>&1; then
    log_success "btop system monitor installed successfully!"
    log_info "Launching btop System Monitor..."
    sleep 1
    exec btop
else
    log_error "Installation finished but btop command was not found in PATH."
    exit 1
fi
