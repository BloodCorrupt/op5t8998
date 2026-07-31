#!/bin/bash
# ============================================================
# Step 3: Apply Manual Hook Patches to Kernel Source
# ============================================================
# These patches add ReSukiSU hooks to the kernel source.
# For kernel 4.4.x (non-GKI), manual hooks are required.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Applying Manual Hook Patches"

if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

cd "$KERNEL_PATH"

# Reset only target patch files to ensure clean application without undoing Kconfig integration
substep "Ensuring clean kernel working tree for target patches..."
git checkout -- fs/stat.c fs/exec.c fs/open.c kernel/reboot.c drivers/input/input.c fs/read_write.c kernel/sys.c arch/arm64/configs/msm8998_oneplus_android_defconfig 2>/dev/null || true

# Track results
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

    # Create temporary LF-only patch file to avoid Windows CRLF issues
    local clean_patch
    clean_patch=$(mktemp)
    tr -d '\r' < "$patch_file" > "$clean_patch"
    
    # Check if already applied (reverse check)
    if git apply --check --reverse --ignore-whitespace "$clean_patch" 2>/dev/null; then
        warn "  Already applied: ${patch_name} (skipping)"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$clean_patch"
        return 0
    fi
    
    # 1. Try standard git apply
    if git apply --check "$clean_patch" 2>/dev/null; then
        git apply "$clean_patch"
        success "  Applied: ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        return 0
    fi

    # 2. Try git apply with whitespace tolerance
    if git apply --check --ignore-whitespace "$clean_patch" 2>/dev/null; then
        git apply --ignore-whitespace "$clean_patch"
        success "  Applied (whitespace ignored): ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        return 0
    fi
    
    # 3. Try 3-way merge
    if git apply --check --3way "$clean_patch" 2>/dev/null; then
        git apply --3way "$clean_patch"
        success "  Applied with 3-way merge: ${patch_name}"
        APPLIED=$((APPLIED + 1))
        rm -f "$clean_patch"
        return 0
    fi
    
    # 4. Fallback: try patch command with fuzz
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

# Apply all patches in order
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
    "defconfig_ksu.patch"
)

for pf in "${PATCH_FILES[@]}"; do
    apply_patch "${PATCHES_PATH}/${pf}" || true
done

# --- Summary ---
separator
info "Patch application summary:"
success "  Applied:  ${APPLIED}"
warn "  Skipped:  ${SKIPPED}"
if [ "$FAILED" -gt 0 ]; then
    error "  Failed:   ${FAILED}"
    echo ""
    error "Some patches failed to apply. This usually means the kernel source"
    error "has different formatting than expected. You may need to apply them"
    error "manually using the reference in manual-integrate.md"
    echo ""
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
else
    success "All patches applied successfully!"
fi

mark_step_done "03-patch-kernel"
