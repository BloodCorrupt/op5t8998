#!/bin/bash
# ============================================================
# ReSukiSU Kernel Builder - Shared Utilities
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

error() {
    echo -e "${RED}[✗]${NC} $*"
}

step() {
    echo -e "\n${MAGENTA}${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}${BOLD}  $*${NC}"
    echo -e "${MAGENTA}${BOLD}══════════════════════════════════════════${NC}\n"
}

substep() {
    echo -e "${CYAN}  → $*${NC}"
}

# Timer functions
timer_start() {
    TIMER_START=$(date +%s)
}

timer_end() {
    local elapsed=$(( $(date +%s) - TIMER_START ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))
    echo -e "${GREEN}  ⏱ Completed in ${minutes}m ${seconds}s${NC}"
}

# Error trap handler
on_error() {
    local exit_code=$?
    local line_no=$1
    error "Script failed at line ${line_no} with exit code ${exit_code}"
    error "Check the output above for details."
    exit $exit_code
}

# Confirmation prompt
confirm() {
    local prompt="${1:-Continue?}"
    echo -ne "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if a command exists
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        error "Required command '$1' not found."
        return 1
    fi
    return 0
}

# Get the builder root directory (parent of scripts/)
get_builder_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
    echo "$(dirname "$script_dir")"
}

# Load configuration
load_config() {
    local root
    root="$(get_builder_root)"
    local conf="${root}/config/builder.conf"
    
    if [ ! -f "$conf" ]; then
        error "Configuration file not found: $conf"
        error "Please copy config/builder.conf.example to config/builder.conf and edit it."
        exit 1
    fi
    
    # shellcheck source=/dev/null
    source "$conf"
    
    # Export commonly used paths
    export BUILDER_ROOT="$root"
    export KERNEL_PATH="${root}/${KERNEL_DIR}"
    export TOOLCHAIN_PATH="${root}/${TOOLCHAIN_DIR}"
    export OUTPUT_PATH="${root}/${OUTPUT_DIR}"
    export FINAL_OUTPUT_PATH="${root}/${FINAL_OUTPUT_DIR}"
    export PATCHES_PATH="${root}/patches"
}

# Check if a previous step was completed
check_step_done() {
    local step_name="$1"
    local state_dir="${BUILDER_ROOT}/.state"
    [ -f "${state_dir}/${step_name}.done" ]
}

# Mark a step as completed
mark_step_done() {
    local step_name="$1"
    local state_dir="${BUILDER_ROOT}/.state"
    mkdir -p "$state_dir"
    date > "${state_dir}/${step_name}.done"
}

# Reset a step (and all subsequent steps)
reset_step() {
    local step_name="$1"
    local state_dir="${BUILDER_ROOT}/.state"
    rm -f "${state_dir}/${step_name}.done"
}

# Reset all steps
reset_all_steps() {
    local state_dir="${BUILDER_ROOT}/.state"
    rm -rf "$state_dir"
}

# Print a separator line
separator() {
    echo -e "${WHITE}──────────────────────────────────────────${NC}"
}

# Print build environment info
print_env_info() {
    info "Build environment:"
    substep "Builder root:  ${BUILDER_ROOT}"
    substep "Kernel source: ${KERNEL_PATH}"
    substep "Toolchain:     ${TOOLCHAIN_PATH}"
    substep "Output:        ${FINAL_OUTPUT_PATH}"
    substep "Defconfig:     ${DEFCONFIG}"
    substep "Threads:       ${THREADS}"
    separator
}
