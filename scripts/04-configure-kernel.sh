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

CONFIG_FILE="${OUTPUT_PATH}/.config"

# --- Force KSU configs using scripts/config ---
# This is the reliable way to set kernel configs, especially for choice blocks
substep "Setting KSU configuration flags..."

# Enable KSU
./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU

# Set the hooking method choice to MANUAL_HOOK
./scripts/config --file "$CONFIG_FILE" --disable CONFIG_KSU_TRACEPOINT_HOOK
./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_MANUAL_HOOK

# Disable debug mode
./scripts/config --file "$CONFIG_FILE" --disable CONFIG_KSU_DEBUG

# Enable KALLSYMS (required dependency)
./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KALLSYMS
./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KALLSYMS_ALL

# --- Force SuSFS configs if enabled ---
if [ "${SUSFS_ENABLED}" = "true" ]; then
    substep "Setting SuSFS configuration flags..."

    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_SUS_PATH
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_SUS_MOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_TRY_UMOUNT
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_SPOOF_UNAME
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_ENABLE_LOG
    ./scripts/config --file "$CONFIG_FILE" --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT
    ./scripts/config --file "$CONFIG_FILE" --disable CONFIG_KSU_SUSFS_SUS_SU
fi

# Run olddefconfig to resolve all dependencies
substep "Running olddefconfig to normalize configuration..."
make O="$OUTPUT_PATH" ARCH="$ARCH" "${HOST_FLAGS[@]}" olddefconfig

# --- Final verification ---
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
    error "Dumping KSU-related configs from .config for debugging:"
    grep -i "KSU\|KALLSYMS\|OVERLAY_FS" "$CONFIG_FILE" | head -30 || true
    error "Check that drivers/kernelsu symlink exists and points to ReSukiSU/kernel."
    error "Check that drivers/Kconfig sources drivers/kernelsu/Kconfig."
    exit 1
fi

# --- Optional: menuconfig ---
if [ "${1:-}" = "--menuconfig" ]; then
    substep "Opening menuconfig for manual tweaks..."
    make O="$OUTPUT_PATH" ARCH="$ARCH" "${HOST_FLAGS[@]}" menuconfig
fi

success "Kernel configured successfully with ReSukiSU support!"
mark_step_done "04-configure-kernel"
