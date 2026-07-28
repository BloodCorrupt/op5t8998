#!/bin/bash
# ============================================================
# Step 0: Install Build Dependencies
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Installing Build Dependencies"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
    info "Not running as root, will use sudo for package installation."
else
    SUDO=""
fi

substep "Updating package lists..."
$SUDO apt-get update -qq

substep "Installing essential build tools..."
$SUDO apt-get install -y --no-install-recommends \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    git \
    curl \
    wget \
    zip \
    unzip \
    python3 \
    python3-pip \
    ccache \
    lz4 \
    cpio \
    kmod \
    libncurses-dev \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    file \
    2>&1 | tail -1

# Ensure python -> python3 symlink
if ! command -v python &>/dev/null; then
    substep "Creating python -> python3 symlink..."
    $SUDO apt-get install -y --no-install-recommends python-is-python3 2>/dev/null || \
        $SUDO ln -sf /usr/bin/python3 /usr/bin/python
fi

# Setup ccache if enabled
if [ "$USE_CCACHE" = "true" ]; then
    substep "Configuring ccache..."
    ccache -M 10G 2>/dev/null || true
    success "ccache configured with 10G max cache size"
fi

# Verify essential tools
substep "Verifying installed tools..."
MISSING=""
for cmd in git make gcc bc bison flex python3; do
    if ! check_cmd "$cmd"; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    error "Missing required tools:${MISSING}"
    exit 1
fi

success "All build dependencies installed successfully!"
mark_step_done "00-install-deps"
