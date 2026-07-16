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
cleanup() {
    tput cnorm 2>/dev/null || printf "\033[?25h" # Restore cursor
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
    echo -e "${BLUE}=== Antigravity Workspace Auto-Setup ===${NC}\n"
}

# --- Default Network Interface Detection ---
detect_interface() {
    ip route show | awk '/default/ {print $5}' | head -n 1 || echo "eth0"
}

# --- Arguments Parsing ---
NON_INTERACTIVE=false
FOLDER_CHOICE=""
PROJECT_NAME=""
OVERWRITE_CONFIRM=false
START_AGY=""

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -y, --yes                Run non-interactively (use defaults)"
    echo "  -d, --directory CHOICE   Choose folder option: 1 (current) or 2 (new subfolder)"
    echo "  -n, --name NAME          Specify the project folder/project name (for option 2)"
    echo "  -o, --overwrite          Automatically overwrite existing files/directories"
    echo "  -s, --start-agy CHOICE   Start agy now: y (yes) or n (no)"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -y|--yes) NON_INTERACTIVE=true; shift ;;
        -d|--directory) FOLDER_CHOICE="$2"; shift 2 ;;
        -n|--name) PROJECT_NAME="$2"; shift 2 ;;
        -o|--overwrite) OVERWRITE_CONFIRM=true; shift ;;
        -s|--start-agy) START_AGY="$2"; shift 2 ;;
        *) log_error "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

show_header

# 1. System Dependency Checks
log_info "Verifying system requirements..."
sleep 1 &
show_spinner $!

if ! command -v agy >/dev/null 2>&1; then
    log_error "Antigravity CLI ('agy') is not installed on this system."
    log_info "You can install it by running:"
    echo -e "    ${YELLOW}curl -fsSL https://antigravity.google/cli/install.sh | bash${NC}\n"
    exit 1
fi
log_success "Antigravity CLI ('agy') detected."

# 2. Information Gathering
if [ "$NON_INTERACTIVE" = true ]; then
    FOLDER_CHOICE=${FOLDER_CHOICE:-1}
else
    if [ -z "$FOLDER_CHOICE" ]; then
        echo -e "\n${BLUE}>>> Step 1: Configure Workspace Folder${NC}"
        echo -e "Choose where to set up the Antigravity project:"
        echo -e "  [1] Current directory ($(pwd))"
        echo -e "  [2] Create a new directory inside the current directory"
        while true; do
            read -rp "Enter choice (1 or 2) [1]: " FOLDER_CHOICE
            FOLDER_CHOICE=${FOLDER_CHOICE:-1}
            if [[ "$FOLDER_CHOICE" == "1" || "$FOLDER_CHOICE" == "2" ]]; then
                break
            else
                log_error "Invalid choice. Please enter 1 or 2."
            fi
        done
    fi
fi

if [[ "$FOLDER_CHOICE" == "1" ]]; then
    TARGET_DIR="$(pwd)"
    PROJECT_NAME="$(basename "$TARGET_DIR")"
    log_info "Setting up project in the current directory: ${TARGET_DIR}"
    
    # Check if target files/folders already exist to protect them
    EXISTING_FILES=()
    for item in ".agents" "AGENTS.md" ".gitignore"; do
        if [ -e "${TARGET_DIR}/${item}" ]; then
            EXISTING_FILES+=("${item}")
        fi
    done
    
    if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
        do_overwrite=$OVERWRITE_CONFIRM
        if [ "$NON_INTERACTIVE" = false ] && [ "$do_overwrite" = false ]; then
            log_warning "The following project files/folders already exist in this directory: ${EXISTING_FILES[*]}"
            read -rp "Would you like to overwrite them? (y/n) [n]: " OVERWRITE_FILES
            OVERWRITE_FILES=${OVERWRITE_FILES:-n}
            if [[ "$OVERWRITE_FILES" =~ ^[Yy]$ ]]; then
                do_overwrite=true
            fi
        fi
        
        if [ "$do_overwrite" = false ]; then
            log_error "Setup cancelled to prevent overwriting existing files."
            exit 1
        fi
    fi
else
    if [ -z "$PROJECT_NAME" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            # Safe default name generation
            secure_suffix=$(tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 6 || echo "default")
            PROJECT_NAME="antigravity_project_${secure_suffix}"
            log_info "Auto-generating project folder name: ${PROJECT_NAME}"
        else
            while true; do
                read -rp "Enter Project Folder Name: " PROJECT_NAME
                # Trim leading/trailing spaces
                PROJECT_NAME="$(echo -e "${PROJECT_NAME}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                
                if [ -z "$PROJECT_NAME" ]; then
                    log_error "Folder name cannot be empty."
                elif [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                    log_error "Invalid folder name. Use only letters, numbers, dots, hyphens, and underscores (no spaces or paths)."
                else
                    break
                fi
            done
        fi
    fi

    TARGET_DIR="$(pwd)/${PROJECT_NAME}"
    log_info "Setting up folder at: ${TARGET_DIR}"

    if [ -d "$TARGET_DIR" ]; then
        do_overwrite=$OVERWRITE_CONFIRM
        if [ "$NON_INTERACTIVE" = false ] && [ "$do_overwrite" = false ]; then
            log_warning "Directory ${TARGET_DIR} already exists."
            read -rp "Would you like to overwrite it? (y/n) [n]: " OVERWRITE_DIR
            OVERWRITE_DIR=${OVERWRITE_DIR:-n}
            if [[ "$OVERWRITE_DIR" =~ ^[Yy]$ ]]; then
                do_overwrite=true
            fi
        fi
        
        if [ "$do_overwrite" = true ]; then
            log_info "Removing existing directory..."
            rm -rf "$TARGET_DIR"
        else
            log_error "Setup cancelled to prevent overwriting existing configuration."
            exit 1
        fi
    fi
fi

mkdir -p "$TARGET_DIR"

# 4. Generate Configuration Files
log_info "Generating configuration files..."
sleep 1 &
show_spinner $!

# Create agent workspace structure
mkdir -p "${TARGET_DIR}/.agents/skills/memory-bank"

# Write the Memory Bank Skill (SKILL.md)
cat << 'EOF' > "${TARGET_DIR}/.agents/skills/memory-bank/SKILL.md"
---
name: memory-bank
description: Use this skill to read, maintain, and update the project's Memory Bank (MEMORY_BANK.md) to ensure context persistence across agent sessions.
---

# Memory Bank Skill

This skill guides the agent in maintaining the project's state, context, and progress via the `MEMORY_BANK.md` file.

## Instructions

1. **Boot Protocol**: At the start of a session, check `.agents/MEMORY_BANK.md` to load the current project status, active tasks, and rules.
2. **Execution Protocol**: When performing tasks, update the "Active Context" section of `.agents/MEMORY_BANK.md` to reflect any new learnings, architectural decisions, or status changes.
3. **Closing Protocol**: Before concluding your turn, update the "Progress & Roadmap" and "Active Context" in `.agents/MEMORY_BANK.md` to summarize what was done and what the next steps are.
EOF
log_success "Created: ${TARGET_DIR}/.agents/skills/memory-bank/SKILL.md"

# Write the default MEMORY_BANK.md
cat << EOF > "${TARGET_DIR}/.agents/MEMORY_BANK.md"
# Project Memory Bank

This file serves as the core memory bank and single source of truth for AI agents working on this project.

## Project Brief
- **Project Name**: ${PROJECT_NAME}
- **Description**: [Brief description of the project and its core goals]

## System Architecture & Patterns
- **Tech Stack**: [Languages, frameworks, database, APIs]
- **Design Decisions**: [Architectural patterns, code style, conventions]

## Active Context
- **Current Task**: Initialize Antigravity project environment.
- **Recent Changes**: Created agent configuration files (\`.agents/\`), initialized Memory Bank skill, and created rules file (\`AGENTS.md\`).

## Progress & Roadmap
- [x] Create initialization script (\`setup_antigravity_project.sh\`)
- [x] Initialize \`.agents/\` structure and \`.agents/MEMORY_BANK.md\`
- [ ] Define project scope and start development
- [ ] Add project-specific files and dependencies
EOF
log_success "Created: ${TARGET_DIR}/.agents/MEMORY_BANK.md"

# Write the default AGENTS.md rule file
cat << 'EOF' > "${TARGET_DIR}/AGENTS.md"
## Core Rules

### 1. Context, State Management & Boundary Control
* **Strict Project Isolation**: You are strictly confined to the current project directory. **Do not read or scan any files, folders, hidden directories, or configuration logs outside of this project folder without explicitly asking for permission first.**
* **Memory Bank First**: Always read `.agents/MEMORY_BANK.md` before executing any task to absorb project context, architectural patterns, and active configurations.
* **Continuous Synchronization**: Update `MEMORY_BANK.md` immediately after completing any major modification, tracking architectural shifts, newly introduced environment variables, or updated port layers.
* **Progressive Disclosure**: When dealing with heavy infrastructure or specialized codebases, dynamically discover and call local skills (`.agents/skills/`) instead of bundling global instructions.

### 2. Architectural Integrity & Technical Decisions
* **Quality & Longevity Over Cost**: When making technical decisions, do not give weight to development cost or speed. Always prefer **uncompromising quality, simplicity, robustness, scalability, and long-term maintainability**.
* **Loose Coupling & High Cohesion**: Prioritize microservices, standalone container layers (Docker Compose), and centralized data structures (e.g., centralized connection pooling) over monolithic blocks.
* **Separation of Concerns**: Keep business logic completely decoupled from presentation layers and database operations.
* **Idempotency**: Ensure all configuration scripts, automation pipelines, and infrastructure adjustments can be safely run multiple times without corrupting state or duplicating data.

### 3. Absolute Engineering Excellence (Zero Tolerance for Debt)
* **The Boy Scout Rule for Technical Debt**: Maintain an absolute standard for engineering excellence regarding linting errors, test failures, and test flakiness. If you encounter an issue—**even if it was not caused by the task you are currently working on**—you are explicitly required to fix it before concluding your turn.
* **Dry Run Verification**: Prioritize checking configuration file syntax and running local linters or compiler tests before declaring a deployment complete.
* **State Preservation**: Never overwrite configuration parameters or environmental schemas without backing up the current operational baseline or verifying rollback safety.
* **Fail-Fast Error Handling**: Design applications and integrations to surface errors explicitly at the boundary layers rather than swallowing exceptions or letting failures cascade quietly.

### 4. Code Quality & Self-Documentation
* **Sovereign Maintainability**: Generate clean, self-documenting code featuring robust inline comments and expressive docstrings that match industry-standard style guides.
* **Expose APIs Declared**: Ensure database interactions or API configurations match the system's strict technical guidelines and authorization layouts.
EOF
log_success "Created: ${TARGET_DIR}/AGENTS.md"

# Write default .gitignore
cat << EOF > "${TARGET_DIR}/.gitignore"
# Local environment variables containing sensitive credentials
.env

# System files
.DS_Store
Thumbs.db
EOF
log_success "Created: ${TARGET_DIR}/.gitignore"

INIT_PROMPT="Please ask me for the missing description of the project and update .agents/MEMORY_BANK.md with the details, then explain what the project will develop."

echo ""
summary_lines=(
    "Project Directory: ${TARGET_DIR}"
    "Project Name:      ${PROJECT_NAME}"
    "Network Iface:     $(detect_interface)"
    "Created Files:"
    "  - .agents/skills/memory-bank/SKILL.md"
    "  - .agents/MEMORY_BANK.md"
    "  - AGENTS.md"
    "  - .gitignore"
    ""
    "Copy-paste initialization prompt to run in agy:"
    "  \"${INIT_PROMPT}\""
)
box_message "Antigravity Project Initialized" "${summary_lines[@]}"
echo ""

# --- Launch Choice ---
if [ -z "$START_AGY" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        START_AGY="n"
    else
        if [ "$(pwd)" = "$TARGET_DIR" ]; then
            read -rp "Start agy now? (y/n) [y]: " START_AGY
            START_AGY=${START_AGY:-y}
        else
            read -rp "Change directory and start agy now? (y/n) [y]: " START_AGY
            START_AGY=${START_AGY:-y}
        fi
    fi
fi

if [[ "$START_AGY" =~ ^[Yy]$ ]]; then
    if [ "$(pwd)" != "$TARGET_DIR" ]; then
        log_info "Entering directory ${TARGET_DIR} and starting agy..."
        cd "$TARGET_DIR" || exit 1
    else
        log_info "Starting agy..."
    fi
    exec agy
else
    log_warning "agy launch skipped. You can enter the directory and start it manually by running: cd ${TARGET_DIR} && agy"
fi
