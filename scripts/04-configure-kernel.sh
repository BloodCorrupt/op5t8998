#!/bin/bash
# ============================================================
# Step 4: Configure Kernel with ReSukiSU Flags
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Configuring Kernel"

if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    exit 1
fi

cd "$KERNEL_PATH"

# Ensure drivers/Kconfig and drivers/Makefile have ReSukiSU integration active
DRIVER_MAKEFILE="drivers/Makefile"
DRIVER_KCONFIG="drivers/Kconfig"

if ! grep -q "kernelsu" "$DRIVER_MAKEFILE" 2>/dev/null; then
    substep "Re-enabling ReSukiSU in drivers/Makefile..."
    echo "" >> "$DRIVER_MAKEFILE"
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$DRIVER_MAKEFILE"
fi

if ! grep -q "kernelsu" "$DRIVER_KCONFIG" 2>/dev/null; then
    substep "Re-enabling ReSukiSU in drivers/Kconfig..."
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG" 2>/dev/null || echo 'source "drivers/kernelsu/Kconfig"' >> "$DRIVER_KCONFIG"
fi

# Setup output directory
mkdir -p "$OUTPUT_PATH"

# --- Host toolchain flags (force system GCC/ld for host binaries on Ubuntu 24.04/26.04) ---
HOST_FLAGS=(
    HOSTCC=gcc
    HOSTCXX=g++
    HOSTLD=/usr/bin/ld
    HOSTLDFLAGS="-B/usr/bin"
)

# --- Fix ReSukiSU Kconfig recursive dependency bug ---
# ReSukiSU's Kconfig has KSU_SUSFS depend on KSU_MANUAL_HOOK while both
# are in the same choice block. This creates an unresolvable cycle.
# We must fix this BEFORE any make command parses Kconfig.
if grep -q "depends on KSU_MANUAL_HOOK" "drivers/kernelsu/Kconfig" 2>/dev/null; then
    warn "Patching ReSukiSU Kconfig to fix recursive dependency..."
    sed -i '/config KSU_SUSFS/,/help/{/depends on KSU_MANUAL_HOOK/d}' "drivers/kernelsu/Kconfig"
fi

# --- Generate defconfig ---
substep "Generating defconfig: ${DEFCONFIG}"
make O="$OUTPUT_PATH" ARCH="$ARCH" "${HOST_FLAGS[@]}" "$DEFCONFIG"
success "Defconfig generated."

# --- Verify KSU config flags ---
substep "Verifying KSU configuration flags..."
CONFIG_FILE="${OUTPUT_PATH}/.config"

check_config() {
    local key="$1"
    local expected="$2"
    if grep -q "^${key}=${expected}" "$CONFIG_FILE"; then
        success "  ${key}=${expected}"
        return 0
    elif grep -q "^# ${key} is not set" "$CONFIG_FILE"; then
        warn "  ${key} is NOT set (expected ${expected})"
        return 1
    elif grep -q "^${key}=" "$CONFIG_FILE"; then
        local actual
        actual=$(grep "^${key}=" "$CONFIG_FILE" | cut -d= -f2)
        warn "  ${key}=${actual} (expected ${expected})"
        return 1
    else
        warn "  ${key} not found in .config"
        return 1
    fi
}

CONFIG_OK=true

if ! check_config "CONFIG_KSU" "y"; then
    warn "Adding CONFIG_KSU=y to .config"
    echo "CONFIG_KSU=y" >> "$CONFIG_FILE"
    CONFIG_OK=false
fi

# KSU_MANUAL_HOOK, KSU_SUSFS, and KSU_TRACEPOINT_HOOK are mutually exclusive
# (they belong to the same Kconfig choice block). Only one may be enabled.
echo "# CONFIG_KSU_TRACEPOINT_HOOK is not set" >> "$CONFIG_FILE"

if [ "$ENABLE_SUSFS" = "true" ]; then
    substep "Configuring SuSFS Inline Hook mode..."
    if ! check_config "CONFIG_KSU_SUSFS" "y"; then
        warn "Setting CONFIG_KSU_SUSFS=y in .config"
        echo "# CONFIG_KSU_MANUAL_HOOK is not set" >> "$CONFIG_FILE"
        echo "CONFIG_KSU_SUSFS=y" >> "$CONFIG_FILE"
        # Disable MNT_ID_REORDER — known to cause bootloops on non-GKI
        echo "# CONFIG_KSU_SUSFS_MNT_ID_REORDER is not set" >> "$CONFIG_FILE"
        CONFIG_OK=false
    fi
else
    substep "Configuring Manual Hook mode..."
    if ! check_config "CONFIG_KSU_MANUAL_HOOK" "y"; then
        warn "Setting CONFIG_KSU_MANUAL_HOOK=y in .config"
        echo "# CONFIG_KSU_SUSFS is not set" >> "$CONFIG_FILE"
        echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
        CONFIG_OK=false
    fi
fi

# KALLSYMS_ALL should already be set
check_config "CONFIG_KALLSYMS_ALL" "y" || true

# If we modified .config, re-run olddefconfig to normalize
if [ "$CONFIG_OK" = false ]; then
    substep "Re-running olddefconfig to normalize configuration..."
    make O="$OUTPUT_PATH" ARCH="$ARCH" "${HOST_FLAGS[@]}" olddefconfig
fi

# Final verification
separator
substep "Final configuration check..."
FINAL_OK=true

VERIFY_CONFIGS=(CONFIG_KSU)
if [ "$ENABLE_SUSFS" = "true" ]; then
    VERIFY_CONFIGS+=(CONFIG_KSU_SUSFS)
else
    VERIFY_CONFIGS+=(CONFIG_KSU_MANUAL_HOOK)
fi

for cfg in "${VERIFY_CONFIGS[@]}"; do
    if ! grep -q "^${cfg}=y" "$CONFIG_FILE"; then
        error "  ${cfg} is NOT enabled in final .config!"
        FINAL_OK=false
    else
        success "  ${cfg}=y ✓"
    fi
done

if [ "$FINAL_OK" = false ]; then
    error "Configuration verification failed."
    error "Check that drivers/kernelsu symlink exists in kernel_source/drivers/."
    exit 1
fi

# --- Optional: menuconfig ---
if [ "${1:-}" = "--menuconfig" ]; then
    substep "Opening menuconfig for manual tweaks..."
    make O="$OUTPUT_PATH" ARCH="$ARCH" "${HOST_FLAGS[@]}" menuconfig
fi

if [ "$ENABLE_SUSFS" = "true" ]; then
    success "Kernel configured successfully with ReSukiSU + SuSFS support!"
else
    success "Kernel configured successfully with ReSukiSU (Manual Hook) support!"
fi
mark_step_done "04-configure-kernel"

