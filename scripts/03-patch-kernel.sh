#!/bin/bash
# ============================================================
# Step 3: Apply / Upgrade Kernel Hooks for ReSukiSU
# ============================================================
# Handles two cases:
#   1. Kernel has NO KSU hooks (base/stable) → apply patches
#   2. Kernel has OLD-STYLE KSU hooks (stable) → upgrade to new-style
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Applying / Upgrading Kernel Hooks"

if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

cd "$KERNEL_PATH"

# --- Detect kernel hook state ---
HAS_NEW_HOOKS=0
HAS_OLD_HOOKS=0

if grep -q "ksu_handle_execveat" fs/exec.c 2>/dev/null && ! grep -q "ksu_execveat_hook" fs/exec.c 2>/dev/null; then
    HAS_NEW_HOOKS=1
elif grep -q "ksu_execveat_hook" fs/exec.c 2>/dev/null \
  || grep -q "ksu_vfs_read_hook" fs/read_write.c 2>/dev/null \
  || grep -q "ksu_input_hook" drivers/input/input.c 2>/dev/null; then
    HAS_OLD_HOOKS=1
fi

if [ "$HAS_NEW_HOOKS" -eq 1 ]; then
    success "Kernel already has new-style ReSukiSU-compatible hooks."
    success "No hook patching needed."
    mark_step_done "03-patch-kernel"
    exit 0

elif [ "$HAS_OLD_HOOKS" -eq 1 ]; then
    # ---------------------------------------------------------------
    # Case 2: stable branch - has old-style KSU hooks
    # Upgrade them in-place to new-style ReSukiSU hooks
    # ---------------------------------------------------------------
    info "Detected OLD-STYLE KSU hooks (stable branch)."
    info "Upgrading to new-style ReSukiSU-compatible hooks..."
    substep "Running hook upgrade script..."
    python3 "${SCRIPT_DIR}/upgrade_kernel_hooks.py" "${KERNEL_PATH}"
    success "Hook upgrade complete."

else
    # ---------------------------------------------------------------
    # Case 3: base/stable or clean kernel - no hooks at all
    # Apply patches from the patches/ directory
    # ---------------------------------------------------------------
    info "No existing KSU hooks found. Applying manual hook patches..."

    substep "Ensuring clean kernel working tree for target patches..."
    git checkout -- fs/stat.c fs/exec.c fs/open.c kernel/reboot.c drivers/input/input.c fs/read_write.c kernel/sys.c arch/arm64/configs/msm8998_oneplus_android_defconfig 2>/dev/null || true

    APPLIED=0
    SKIPPED=0
    FAILED=0

    apply_patch() {
        local patch_file="$1"
        local patch_name
        patch_name="$(basename "$patch_file" .patch)"

        substep "Applying: ${patch_name}"

        if [ ! -f "$patch_file" ]; then
            error "Patch file not found: ${patch_file}"
            FAILED=$((FAILED + 1))
            return 1
        fi

        local clean_patch
        clean_patch=$(mktemp)
        tr -d '\r' < "$patch_file" > "$clean_patch"

        if git apply --check --reverse --ignore-whitespace "$clean_patch" 2>/dev/null; then
            warn "  Already applied: ${patch_name} (skipping)"
            SKIPPED=$((SKIPPED + 1))
            rm -f "$clean_patch"
            return 0
        fi

        if git apply --check "$clean_patch" 2>/dev/null; then
            git apply "$clean_patch"
            success "  Applied: ${patch_name}"
            APPLIED=$((APPLIED + 1))
            rm -f "$clean_patch"
            return 0
        fi

        if git apply --check --ignore-whitespace "$clean_patch" 2>/dev/null; then
            git apply --ignore-whitespace "$clean_patch"
            success "  Applied (whitespace ignored): ${patch_name}"
            APPLIED=$((APPLIED + 1))
            rm -f "$clean_patch"
            return 0
        fi

        if git apply --check --3way "$clean_patch" 2>/dev/null; then
            git apply --3way "$clean_patch"
            success "  Applied with 3-way merge: ${patch_name}"
            APPLIED=$((APPLIED + 1))
            rm -f "$clean_patch"
            return 0
        fi

        if patch -p1 --dry-run < "$clean_patch" &>/dev/null; then
            patch -p1 < "$clean_patch"
            success "  Applied with patch(1): ${patch_name}"
            APPLIED=$((APPLIED + 1))
            rm -f "$clean_patch"
            return 0
        fi

        rm -f "$clean_patch"
        error "  FAILED to apply: ${patch_name}"
        error "  Patch file: ${patch_file}"
        FAILED=$((FAILED + 1))
        return 1
    }

    info "Applying patches from: ${PATCHES_PATH}"
    separator

    PATCH_FILES=(
        "stat_hook.patch"
        "execve_hook.patch"
        "faccessat_hook.patch"
        "reboot_hook.patch"
        "input_hook.patch"
        "read_hook.patch"
        "setuid_hook.patch"
    )

    for pf in "${PATCH_FILES[@]}"; do
        apply_patch "${PATCHES_PATH}/${pf}" || true
    done

    separator
    info "Patch application summary:"
    success "  Applied:  ${APPLIED}"
    warn "  Skipped:  ${SKIPPED}"
    if [ "$FAILED" -gt 0 ]; then
        error "  Failed:   ${FAILED}"
        echo ""
        error "Some patches failed to apply. You may need to apply them"
        error "manually using the reference in manual-integrate.md"
        echo ""
        if ! confirm "Continue anyway?"; then
            exit 1
        fi
    else
        success "All patches applied successfully!"
    fi
fi

mark_step_done "03-patch-kernel"
