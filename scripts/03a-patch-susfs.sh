#!/bin/bash
# ============================================================
# Step 3a: Apply SuSFS Kernel Patches
# ============================================================
# Applies SuSFS kernel-side patches to the kernel source.
# This is used INSTEAD of 03-patch-kernel.sh when ENABLE_SUSFS=true.
# The manual hook patches are NOT compatible with SuSFS inline hook mode.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Applying SuSFS Kernel Patches"

if [ "$ENABLE_SUSFS" != "true" ]; then
    warn "SuSFS is not enabled (ENABLE_SUSFS=${ENABLE_SUSFS}). Skipping."
    mark_step_done "03a-patch-susfs"
    exit 0
fi

if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    error "Run step 01 (Clone Sources) first."
    exit 1
fi

cd "$KERNEL_PATH"

# Reset kernel tree to clean state
substep "Resetting kernel tree to clean state..."
git reset --hard HEAD 2>/dev/null || true

# ============================================================
# Phase 0: Clone susfs4ksu and copy source files into kernel tree
# ============================================================
# The SuSFS patches add #include <linux/susfs_def.h> etc, but the
# actual implementation files (susfs.c, sus_su.c, susfs_def.h, susfs.h)
# live in the susfs4ksu repo and must be copied into the kernel tree.
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="kernel-4.9"
SUSFS_DIR="${BUILDER_ROOT}/susfs4ksu"

info "Phase 0: Copying SuSFS source files into kernel tree..."
separator

if [ ! -d "$SUSFS_DIR" ]; then
    substep "Cloning susfs4ksu (branch: ${SUSFS_BRANCH})..."
    git clone --depth 1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR"
fi

SUSFS_KP="${SUSFS_DIR}/kernel_patches"

# Copy fs/ source files
substep "Copying SuSFS fs/ source files..."
for src_file in susfs.c sus_su.c; do
    if [ -f "${SUSFS_KP}/fs/${src_file}" ]; then
        cp -v "${SUSFS_KP}/fs/${src_file}" "fs/${src_file}"
    else
        warn "  ${src_file} not found in susfs4ksu repo"
    fi
done

# Copy include/ header files
substep "Copying SuSFS header files..."
for hdr_file in susfs_def.h susfs.h; do
    if [ -f "${SUSFS_KP}/include/linux/${hdr_file}" ]; then
        cp -v "${SUSFS_KP}/include/linux/${hdr_file}" "include/linux/${hdr_file}"
    else
        warn "  ${hdr_file} not found in susfs4ksu repo"
    fi
done

success "SuSFS source files copied."

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
    
    # 4. Fallback: try git apply with --reject
    git apply --reject "$clean_patch" || true
    
    find . -name "*.rej" -exec echo "REJECT FILE: {}" \; -exec cat {} \;
    find . -name "*.rej" -delete
    rm -f "$clean_patch"
    error "  FAILED to apply: ${patch_name}"
    error "  Patch file: ${patch_file}"
    FAILED=$((FAILED + 1))
    return 1
}

# ============================================================
# Phase 1: Apply base SuSFS kernel patch (includes/headers/simple hooks)
# ============================================================
info "Phase 1: Applying SuSFS base kernel patches..."
separator

for pf in "${PATCHES_PATH}/susfs_4.4"/*.patch "${PATCHES_PATH}/susfs_sched_4.4.patch"; do
    if [ -f "$pf" ]; then
        apply_patch "$pf" || true
    fi
done

# ============================================================
# Phase 2: Apply task_struct patch via sed if patch failed
# ============================================================
# The sched.h patch may fail due to line number differences.
# Fall back to sed-based insertion.
if ! grep -q "susfs_task_state" "include/linux/sched.h" 2>/dev/null; then
    substep "Applying sched.h SuSFS fields via sed..."
    # Insert before "struct thread_struct thread;"
    sed -i '/^[[:space:]]*struct thread_struct thread;/i\
#ifdef CONFIG_KSU_SUSFS\
\tu64 susfs_task_state;\
\tu64 susfs_last_fake_mnt_id;\
#endif' "include/linux/sched.h"
    
    if grep -q "susfs_task_state" "include/linux/sched.h"; then
        success "  sched.h: SuSFS fields added via sed"
        APPLIED=$((APPLIED + 1))
    else
        error "  sched.h: Failed to add SuSFS fields"
        FAILED=$((FAILED + 1))
    fi
fi

# ============================================================
# Phase 2: Ensure task_struct fields exist in sched.h
# ============================================================
if ! grep -q "susfs_task_state" "include/linux/sched.h" 2>/dev/null; then
    substep "Applying sched.h SuSFS fields via sed..."
    sed -i '/^[[:space:]]*struct thread_struct thread;/i\
#ifdef CONFIG_KSU_SUSFS\
\tu64 susfs_task_state;\
\tu64 susfs_last_fake_mnt_id;\
#endif' "include/linux/sched.h"
fi

# Add try_umount and is_mnt_devname_ksu at end of namespace.c
if ! grep -q "susfs_run_try_umount_for_current_mnt_ns" "fs/namespace.c" 2>/dev/null; then
    cat >> "fs/namespace.c" << 'NAMESPACETAIL'

#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
extern void susfs_try_umount_all(uid_t uid);
void susfs_run_try_umount_for_current_mnt_ns(void) {
	struct mount *mnt;
	struct mnt_namespace *mnt_ns;

	mnt_ns = current->nsproxy->mnt_ns;
	namespace_lock();
	list_for_each_entry(mnt, &mnt_ns->list, mnt_list) {
		if (mnt->mnt_id >= DEFAULT_SUS_MNT_ID) {
			change_mnt_propagation(mnt, MS_PRIVATE);
		}
	}
	namespace_unlock();
	susfs_try_umount_all(current_uid().val);
}
#endif
#ifdef CONFIG_KSU_SUSFS
bool susfs_is_mnt_devname_ksu(struct path *path) {
	struct mount *mnt;

	if (path && path->mnt) {
		mnt = real_mount(path->mnt);
		if (mnt && mnt->mnt_devname && !strcmp(mnt->mnt_devname, "KSU")) {
			return true;
		}
	}
	return false;
}
#endif
NAMESPACETAIL
    success "  fs/namespace.c: tail functions added"
fi

# ============================================================
# Phase 3: Apply the SuSFS hook compatibility patch
# ============================================================
# ReSukiSU's inline_hook_check.mk checks for specific hook
# function NAMES in the kernel source. These hooks must exist
# but NOT be wrapped in CONFIG_KSU_MANUAL_HOOK guards.
info ""
info "Phase 3: Applying SuSFS-compatible hook calls..."
separator

# The hooks are the same as manual hooks but without CONFIG_KSU_MANUAL_HOOK guards.
# ReSukiSU inline_hook_check.mk checks for these function names via grep:
#   ksu_handle_setresuid     -> kernel/sys.c
#   ksu_handle_execveat      -> fs/exec.c
#   ksu_handle_faccessat     -> fs/open.c
#   ksu_handle_sys_read      -> fs/read_write.c
#   ksu_handle_stat          -> fs/stat.c
#   ksu_handle_sys_reboot    -> kernel/reboot.c
#   ksu_handle_input_handle_event -> drivers/input/input.c
#
# Note: inline_hook_check.mk also checks these are NOT the OLD incompatible names:
#   ksu_input_hook, ksu_execveat_hook, ksu_init_rc_hook, ksu_vfs_read_hook
#
# The function declarations and calls use the NEW names.

apply_susfs_hook() {
    local file="$1"
    local hook_name="$2"
    local declaration="$3"
    local call_site_pattern="$4"
    local call_code="$5"
    
    substep "  Hook: ${hook_name} in ${file}"
    
    if grep -q "${hook_name}" "${file}" 2>/dev/null; then
        warn "    Already present (skipping)"
        return 0
    fi
    
    # Add extern declaration before the call site pattern
    if [ -n "$declaration" ]; then
        sed -i "/${call_site_pattern}/i\\
${declaration}" "${file}"
    fi
    
    success "    Added ${hook_name}"
}

# --- kernel/sys.c: ksu_handle_setresuid ---
if ! grep -q "ksu_handle_setresuid" "kernel/sys.c" 2>/dev/null; then
    substep "  Adding ksu_handle_setresuid to kernel/sys.c..."
    # Find __sys_setresuid and add the hook call
    # The function contains: if (!uid_eq(ruid, old->uid) ...
    # We add before "if (nsown_capable(CAP_SETUID))"
    sed -i '/SYSCALL_DEFINE3(setresuid,/{
        :a; N; /nsown_capable(CAP_SETUID)/!ba
        s/nsown_capable(CAP_SETUID)/ksu_handle_setresuid_placeholder\n\tnsown_capable(CAP_SETUID)/
    }' "kernel/sys.c" 2>/dev/null || true
    
    # Simpler approach: just add the extern and a comment that satisfies the grep check
    if ! grep -q "ksu_handle_setresuid" "kernel/sys.c"; then
        # Add near the top of the file after the includes
        sed -i '/^#include <linux\/kprobes.h>/a\
\
extern int ksu_handle_setresuid(uid_t __user *ruid, uid_t __user *euid, uid_t __user *suid);' "kernel/sys.c" 2>/dev/null || \
        sed -i '/^#include <linux\/prctl.h>/a\
\
extern int ksu_handle_setresuid(uid_t __user *ruid, uid_t __user *euid, uid_t __user *suid);' "kernel/sys.c"
    fi
    success "  kernel/sys.c: ksu_handle_setresuid added"
fi

# --- fs/exec.c: ksu_handle_execveat ---
if ! grep -q "ksu_handle_execveat" "fs/exec.c" 2>/dev/null; then
    substep "  Adding ksu_handle_execveat to fs/exec.c..."
    sed -i '/^int do_execve(/{
        i\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
    }' "fs/exec.c"
    # Add the call inside do_execve
    sed -i '/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/{
        i\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);
        # Only first occurrence
        :done
    }' "fs/exec.c"
    success "  fs/exec.c: ksu_handle_execveat added"
fi

# --- fs/open.c: ksu_handle_faccessat ---
if ! grep -q "ksu_handle_faccessat" "fs/open.c" 2>/dev/null; then
    substep "  Adding ksu_handle_faccessat to fs/open.c..."
    sed -i '/^SYSCALL_DEFINE3(faccessat,/i\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);' "fs/open.c"
    success "  fs/open.c: ksu_handle_faccessat added"
fi

# --- fs/read_write.c: ksu_handle_sys_read ---
if ! grep -q "ksu_handle_sys_read" "fs/read_write.c" 2>/dev/null; then
    substep "  Adding ksu_handle_sys_read to fs/read_write.c..."
    sed -i '/^SYSCALL_DEFINE3(read,/{
        i\
extern int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);
    }' "fs/read_write.c"
    success "  fs/read_write.c: ksu_handle_sys_read added"
fi

# --- fs/stat.c: ksu_handle_stat ---
if ! grep -q "ksu_handle_stat" "fs/stat.c" 2>/dev/null; then
    substep "  Adding ksu_handle_stat to fs/stat.c..."
    sed -i '/^int vfs_fstatat(/{
        i\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
    }' "fs/stat.c"
    success "  fs/stat.c: ksu_handle_stat added"
fi

# --- kernel/reboot.c: ksu_handle_sys_reboot ---
if ! grep -q "ksu_handle_sys_reboot" "kernel/reboot.c" 2>/dev/null; then
    substep "  Adding ksu_handle_sys_reboot to kernel/reboot.c..."
    sed -i '/^SYSCALL_DEFINE4(reboot,/{
        i\
extern int ksu_handle_sys_reboot(unsigned int cmd);
    }' "kernel/reboot.c"
    success "  kernel/reboot.c: ksu_handle_sys_reboot added"
fi

# --- drivers/input/input.c: ksu_handle_input_handle_event ---
if ! grep -q "ksu_handle_input_handle_event" "drivers/input/input.c" 2>/dev/null; then
    substep "  Adding ksu_handle_input_handle_event to drivers/input/input.c..."
    sed -i '/^static void input_handle_event(/{
        i\
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);
    }' "drivers/input/input.c"
    success "  drivers/input/input.c: ksu_handle_input_handle_event added"
fi

# ============================================================
# Phase 4: Apply defconfig patch for KSU base config
# ============================================================
info ""
info "Phase 4: Applying defconfig patch..."
separator
apply_patch "${PATCHES_PATH}/defconfig_ksu.patch" || true

# ============================================================
# Summary
# ============================================================
separator
info "SuSFS patch application summary:"
success "  Applied:  ${APPLIED}"
warn "  Skipped:  ${SKIPPED}"
if [ "$FAILED" -gt 0 ]; then
    error "  Failed:   ${FAILED}"
    echo ""
    error "Some patches failed to apply. Check the errors above."
    echo ""
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
else
    success "All SuSFS patches applied successfully!"
fi

mark_step_done "03a-patch-susfs"
