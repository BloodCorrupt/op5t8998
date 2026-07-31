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

if ! check_config "CONFIG_KSU_MANUAL_HOOK" "y"; then
    warn "Adding CONFIG_KSU_MANUAL_HOOK=y to .config"
    echo "# CONFIG_KSU_TRACEPOINT_HOOK is not set" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
    CONFIG_OK=false
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

for cfg in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK; do
    if ! grep -q "^${cfg}=y" "$CONFIG_FILE"; then
        error "  ${cfg} is NOT enabled in final .config!"
        FINAL_OK=false
    else
        success "  ${cfg}=y ✓"
    fi
done

if [ "${SUSFS_ENABLED}" = "true" ]; then
    substep "Checking SuSFS configuration..."
    for cfg in CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_MOUNT; do
        if ! grep -q "^${cfg}=y" "$CONFIG_FILE"; then
            error "  ${cfg} is NOT enabled in final .config! (SuSFS features might be missing)"
            FINAL_OK=false
        else
            success "  ${cfg}=y ✓"
        fi
    done
fi

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

success "Kernel configured successfully with ReSukiSU support!"
mark_step_done "04-configure-kernel"
