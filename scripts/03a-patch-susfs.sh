#!/bin/bash
# ============================================================
# Step 3a: Apply SuSFS Patches to Kernel and ReSukiSU
# ============================================================
# Applies the upstream SuSFS patches from simonpunk/susfs4ksu
# for kernel 4.14 (non-GKI).
#
# This script:
#   Phase 0: Copy SuSFS source files into kernel tree
#   Phase 1: Patch ReSukiSU (KernelSU) to enable SuSFS
#   Phase 2: Apply kernel-level SuSFS patch
#   Phase 3: Add SuSFS defconfig flags
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

# Check if SuSFS is enabled
if [ "${SUSFS_ENABLED}" != "true" ]; then
    info "SuSFS is disabled in builder.conf. Skipping."
    exit 0
fi

step "Applying SuSFS Patches"

SUSFS_PATH="${BUILDER_ROOT}/susfs4ksu"
KSU_DRIVER_DIR="${KERNEL_PATH}/drivers/kernelsu"

# --- Verify prerequisites ---
if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

if [ ! -d "$SUSFS_PATH" ] || [ ! -d "$SUSFS_PATH/kernel_patches" ]; then
    error "SuSFS source not found at ${SUSFS_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

if [ ! -d "$KSU_DRIVER_DIR" ]; then
    error "ReSukiSU not integrated at ${KSU_DRIVER_DIR}"
    error "Run step 02 (Integrate ReSukiSU) first."
    exit 1
fi

cd "$KERNEL_PATH"

# Track results
APPLIED=0
SKIPPED=0
FAILED=0

apply_patch() {
    local patch_file="$1"
    local target_dir="$2"
    local patch_name
    patch_name="$(basename "$patch_file" .patch)"
    
    substep "Applying: ${patch_name}"
    
    if [ ! -f "$patch_file" ]; then
        error "  Patch file not found: ${patch_file}"
        FAILED=$((FAILED + 1))
        return 1
    fi

    # Create temporary LF-only patch file
    local clean_patch
    clean_patch=$(mktemp)
    tr -d '\r' < "$patch_file" > "$clean_patch"

    cd "$target_dir"
    
    # Check if already applied
    if git apply --check --reverse --ignore-whitespace "$clean_patch" 2>/dev/null; then
        warn "  Already applied: ${patch_name} (skipping)"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$clean_patch"
        cd "$KERNEL_PATH"
        return 0
    fi
    
    # 1. Try standard git apply
    if git apply --check "$clean_patch" 2>/dev/null; then
        git apply "$clean_patch"
        success "  Applied: ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        cd "$KERNEL_PATH"
        return 0
    fi

    # 2. Try git apply with whitespace tolerance
    if git apply --check --ignore-whitespace "$clean_patch" 2>/dev/null; then
        git apply --ignore-whitespace "$clean_patch"
        success "  Applied (whitespace ignored): ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        cd "$KERNEL_PATH"
        return 0
    fi
    
    # 3. Try 3-way merge
    if git apply --check --3way "$clean_patch" 2>/dev/null; then
        git apply --3way "$clean_patch"
        success "  Applied with 3-way merge: ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        cd "$KERNEL_PATH"
        return 0
    fi

    # 4. Fallback: try patch command with fuzz
    if patch -p1 --dry-run < "$clean_patch" &>/dev/null; then
        patch -p1 < "$clean_patch"
        success "  Applied with patch(1): ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        cd "$KERNEL_PATH"
        return 0
    fi
    
    # 5. Last resort: git apply --reject to show what failed
    git apply --reject "$clean_patch" 2>&1 || true
    find . -name "*.rej" -exec echo "REJECT FILE: {}" \; -exec cat {} \;
    find . -name "*.rej" -delete
    
    rm -f "$clean_patch"
    error "  FAILED to apply: ${patch_name}"
    error "  Patch file: ${patch_file}"
    FAILED=$((FAILED + 1))
    cd "$KERNEL_PATH"
    return 1
}

# ════════════════════════════════════════
# Phase 0: Copy SuSFS source files
# ════════════════════════════════════════
info "Phase 0: Copying SuSFS source files into kernel tree..."
separator

substep "Copying SuSFS fs/ source files..."
for f in "${SUSFS_PATH}/kernel_patches/fs/"*; do
    if [ -f "$f" ]; then
        cp -v "$f" "${KERNEL_PATH}/fs/"
    fi
done

if [ ! -f "${KERNEL_PATH}/fs/susfs.c" ]; then
    error "FATAL: SuSFS source files (fs/susfs.c) were not copied successfully!"
    error "Check if ${SUSFS_PATH}/kernel_patches/fs/ exists and contains the files."
    exit 1
fi

substep "Copying SuSFS header files..."
for f in "${SUSFS_PATH}/kernel_patches/include/linux/"*; do
    if [ -f "$f" ]; then
        cp -v "$f" "${KERNEL_PATH}/include/linux/"
    fi
done

success "SuSFS source files copied."

# ════════════════════════════════════════
# Phase 0.5: Append missing SuSFS stubs for ReSukiSU compat
# ════════════════════════════════════════
# ReSukiSU expects functions from SuSFS >= 1.5.x
# but susfs4ksu kernel-4.14 is based on ~1.4.x.
# We append real stub definitions to susfs.c so the linker
# can resolve them from sucompat.c, kernel_umount.c, dispatch.c.
SUSFS_C="${KERNEL_PATH}/fs/susfs.c"
SUSFS_COMPAT_MARKER="/* ReSukiSU compat stubs: missing in SuSFS 1.4.x */"

if ! grep -q "$SUSFS_COMPAT_MARKER" "$SUSFS_C" 2>/dev/null; then
    substep "Appending ReSukiSU compat stubs to fs/susfs.c..."
    cat >> "$SUSFS_C" << 'SUSFS_STUBS_EOF'

/* ReSukiSU compat stubs: missing in SuSFS 1.4.x */
#include <linux/workqueue.h>
#include <linux/uaccess.h>
#include <linux/sched.h>

/* susfs_extra_works: scheduled work used by kernel_umount.c */
struct work_struct susfs_extra_works;
EXPORT_SYMBOL(susfs_extra_works);

/* Per-task umount tracking (used by sucompat.c and kernel_umount.c) */
bool susfs_is_current_proc_umounted(void)
{
    return false;
}
EXPORT_SYMBOL(susfs_is_current_proc_umounted);

void susfs_set_current_proc_umounted(void)
{
    /* no-op: feature not in SuSFS 1.4.x */
}
EXPORT_SYMBOL(susfs_set_current_proc_umounted);

/* Log and info commands (used by dispatch.c) */
void susfs_enable_log(void __user **user_info)
{
    /* no-op */
}
EXPORT_SYMBOL(susfs_enable_log);

void susfs_show_version(void __user **user_info)
{
    /* no-op */
}
EXPORT_SYMBOL(susfs_show_version);

void susfs_get_enabled_features(void __user **user_info)
{
    /* no-op */
}
EXPORT_SYMBOL(susfs_get_enabled_features);

void susfs_show_variant(void __user **user_info)
{
    /* no-op */
}
EXPORT_SYMBOL(susfs_show_variant);

void susfs_start_sdcard_monitor_fn(void)
{
    /* no-op */
}
EXPORT_SYMBOL(susfs_start_sdcard_monitor_fn);
SUSFS_STUBS_EOF
    success "ReSukiSU compat stubs appended to fs/susfs.c"
else
    warn "ReSukiSU compat stubs already present in fs/susfs.c (skipping)"
fi


# ════════════════════════════════════════
# Phase 1.5: ReSukiSU compatibility for older SuSFS
# ════════════════════════════════════════
info "Phase 1.5: Patching ReSukiSU for SuSFS 1.4.x compatibility..."
python3 "${SCRIPT_DIR}/fix_resukisu_susfs_compat.py" "${KSU_DRIVER_DIR}/supercall/dispatch.c" "${KSU_DRIVER_DIR}/supercall/supercall.c" || true

# ════════════════════════════════════════
# Phase 2: Apply kernel-level SuSFS patch
# ════════════════════════════════════════
info "Phase 2: Applying kernel-level SuSFS patch..."
separator

KERNEL_PATCH="${SUSFS_PATH}/kernel_patches/50_add_susfs_in_kernel-4.14.patch"
info "Applying kernel SuSFS patch..."
cd "$KERNEL_PATH"
# We use patch directly because we KNOW some hunks will be rejected on base/stable, 
# and we don't want apply_patch to print a scary red [FAILED] message.
patch -p1 --forward < "$KERNEL_PATCH" >/dev/null 2>&1 || true

# Run Python fixup script to manually apply rejected hunks for base/stable
info "Running manual fixup for base/stable kernel source..."
python3 "${SCRIPT_DIR}/fixup_susfs.py" "$KERNEL_PATH" || true
cd "${BUILDER_ROOT}"

# ════════════════════════════════════════
# Phase 3: Add SuSFS defconfig flags
# ════════════════════════════════════════
info "Phase 3: Adding SuSFS defconfig flags..."
separator

DEFCONFIG_FILE="${KERNEL_PATH}/arch/${ARCH}/configs/${DEFCONFIG}"

if [ ! -f "$DEFCONFIG_FILE" ]; then
    error "Defconfig not found: ${DEFCONFIG_FILE}"
else
    # Add SuSFS config flags if not already present
    SUSFS_CONFIGS=(
        "CONFIG_KSU_SUSFS=y"
        "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
        "CONFIG_KSU_SUSFS_SUS_PATH=y"
        "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
        "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
        "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
        "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
        "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
        "CONFIG_KSU_SUSFS_SUS_SU=n"
    )
    
    for cfg in "${SUSFS_CONFIGS[@]}"; do
        key="${cfg%%=*}"
        if grep -q "^${key}=" "$DEFCONFIG_FILE" 2>/dev/null; then
            warn "  ${key} already in defconfig (skipping)"
        else
            echo "$cfg" >> "$DEFCONFIG_FILE"
            success "  Added ${cfg}"
        fi
    done
fi

# ── Summary ──
separator
info "SuSFS patch application summary:"
success "  Applied:  ${APPLIED}"
warn "  Skipped:  ${SKIPPED}"
if [ "$FAILED" -gt 0 ]; then
    error "  Failed:   ${FAILED}"
    echo ""
    error "Some SuSFS patches failed to apply."
    error "You may need to apply them manually."
    echo ""
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
else
    success "All SuSFS patches applied successfully!"
fi

mark_step_done "03a-patch-susfs"
