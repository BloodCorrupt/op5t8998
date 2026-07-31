#!/bin/bash
# ============================================================
# Step 2: Integrate ReSukiSU into Kernel Source Tree
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Integrating ReSukiSU into Kernel Tree"

RESUKISU_PATH="${BUILDER_ROOT}/ReSukiSU"
DRIVER_DIR="${KERNEL_PATH}/drivers"
KSU_DRIVER_DIR="${DRIVER_DIR}/kernelsu"
DRIVER_MAKEFILE="${DRIVER_DIR}/Makefile"
DRIVER_KCONFIG="${DRIVER_DIR}/Kconfig"

# Verify sources exist
if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

if [ ! -d "$RESUKISU_PATH" ] || [ ! -d "$RESUKISU_PATH/kernel" ]; then
    error "ReSukiSU source not found at ${RESUKISU_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

# Check if already integrated
if [ -d "$KSU_DRIVER_DIR" ] && [ -f "$KSU_DRIVER_DIR/Kconfig" ]; then
    warn "ReSukiSU already integrated in kernel tree."
    if ! confirm "Re-integrate? This will replace the existing integration."; then
        info "Skipping integration."
        exit 0
    fi
    rm -rf "$KSU_DRIVER_DIR"
fi

# --- Clean up any pre-existing KSU artifacts ---
# Some kernel sources or previous integrations may leave behind dummy Kconfig
# files or stale references that conflict with ReSukiSU
substep "Cleaning up pre-existing KSU artifacts..."

# Remove dummy Kconfig files
for dummy in "$DRIVER_DIR"/Kconfig.ksu* "$DRIVER_DIR"/Kconfig.kernelsu*; do
    if [ -f "$dummy" ]; then
        warn "  Removing stale KSU artifact: $(basename "$dummy")"
        rm -f "$dummy"
    fi
done

# Remove stale KSU entries from drivers/Makefile (we'll re-add the correct one)
if grep -i -q "ksu" "$DRIVER_MAKEFILE" 2>/dev/null; then
    substep "Removing stale KSU entries from drivers/Makefile..."
    sed -i '/kernelsu/d' "$DRIVER_MAKEFILE"
    sed -i '/ksu.dummy/d' "$DRIVER_MAKEFILE"
    sed -i '/# ReSukiSU/d' "$DRIVER_MAKEFILE"
    sed -i '/# KernelSU/d' "$DRIVER_MAKEFILE"
fi

# Remove stale KSU entries from drivers/Kconfig
if grep -i -q "ksu" "$DRIVER_KCONFIG" 2>/dev/null; then
    substep "Removing stale KSU entries from drivers/Kconfig..."
    sed -i '/kernelsu/d' "$DRIVER_KCONFIG"
    sed -i '/ksu.dummy/d' "$DRIVER_KCONFIG"
    sed -i '/KSU_SRC/d' "$DRIVER_KCONFIG"
fi

# Clean the output directory .config to remove stale KSU configs
OUTPUT_CONFIG="${KERNEL_PATH}/${OUTPUT_DIR:-out}/.config"
if [ -f "$OUTPUT_CONFIG" ]; then
    substep "Removing stale KSU configs from .config..."
    sed -i '/CONFIG_KSU/d' "$OUTPUT_CONFIG"
fi

# --- Create symlink to ReSukiSU kernel module ---
substep "Creating symlink: drivers/kernelsu -> ReSukiSU/kernel"
ln -sf "${RESUKISU_PATH}/kernel" "$KSU_DRIVER_DIR"

if [ -L "$KSU_DRIVER_DIR" ] && [ -f "$KSU_DRIVER_DIR/Kconfig" ]; then
    success "Symlink created successfully."
else
    error "Failed to create symlink. Trying copy instead..."
    rm -f "$KSU_DRIVER_DIR"
    cp -r "${RESUKISU_PATH}/kernel" "$KSU_DRIVER_DIR"
    if [ -f "$KSU_DRIVER_DIR/Kconfig" ]; then
        success "Copied ReSukiSU kernel module."
    else
        error "Integration failed. Check paths."
        exit 1
    fi
fi

# --- Patch ReSukiSU Kconfig to remove 4.14-incompatible dependencies ---
substep "Patching ReSukiSU Kconfig dependencies for older kernels..."
if [ -f "$KSU_DRIVER_DIR/Kconfig" ]; then
    # kernel-4.14 doesn't define THREAD_INFO_IN_TASK, so KSU_SUSFS will silently drop if it depends on it.
    sed -i 's/depends on THREAD_INFO_IN_TASK/depends on/g' "$KSU_DRIVER_DIR/Kconfig"
    sed -i 's/depends on  &&/depends on/g' "$KSU_DRIVER_DIR/Kconfig"
    # Clean up empty depends on
    sed -i '/depends on$/d' "$KSU_DRIVER_DIR/Kconfig"
fi

# --- Update drivers/Makefile ---
substep "Updating drivers/Makefile..."
if grep -q "kernelsu" "$DRIVER_MAKEFILE"; then
    warn "drivers/Makefile already contains kernelsu entry. Skipping."
else
    echo "" >> "$DRIVER_MAKEFILE"
    echo "# ReSukiSU" >> "$DRIVER_MAKEFILE"
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$DRIVER_MAKEFILE"
    success "Added kernelsu to drivers/Makefile"
fi

# --- Update drivers/Kconfig ---
substep "Updating drivers/Kconfig..."
if grep -q "kernelsu" "$DRIVER_KCONFIG"; then
    warn "drivers/Kconfig already contains kernelsu entry. Skipping."
else
    # Insert before the last 'endmenu' line
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG"
    if grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG"; then
        success "Added kernelsu Kconfig to drivers/Kconfig"
    else
        # Fallback: just append before endmenu
        echo 'source "drivers/kernelsu/Kconfig"' >> "$DRIVER_KCONFIG"
        success "Added kernelsu Kconfig to drivers/Kconfig (appended)"
    fi
fi

# --- Verify integration ---
substep "Verifying integration..."
VERIFY_OK=true

if [ ! -f "$KSU_DRIVER_DIR/Kconfig" ]; then
    error "Kconfig not found in drivers/kernelsu/"
    VERIFY_OK=false
fi

if [ ! -f "$KSU_DRIVER_DIR/Makefile" ]; then
    error "Makefile not found in drivers/kernelsu/"
    VERIFY_OK=false
fi

if ! grep -q "kernelsu" "$DRIVER_MAKEFILE"; then
    error "kernelsu not found in drivers/Makefile"
    VERIFY_OK=false
fi

if ! grep -q "kernelsu" "$DRIVER_KCONFIG"; then
    error "kernelsu not found in drivers/Kconfig"
    VERIFY_OK=false
fi

if [ "$VERIFY_OK" = true ]; then
    success "ReSukiSU integration verified successfully!"
else
    error "Integration verification failed. Check errors above."
    exit 1
fi

mark_step_done "02-integrate-resukisu"
