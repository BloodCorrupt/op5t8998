#!/usr/bin/env python3
"""
upgrade_kernel_hooks.py
=======================
The stable branch of x-ft_kernel_oneplus_msm8998 has OLD-STYLE KernelSU hooks
(ksu_vfs_read_hook, ksu_execveat_hook, ksu_input_hook) which ReSukiSU's
inline_hook_check.mk explicitly rejects as INCOMPATIBLE.

This script upgrades those old-style hooks in-place to the new-style hooks
that ReSukiSU requires, and also adds missing hooks (sys.c, reboot.c).
"""

import sys
import os
import re

def read_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)

kernel_dir = sys.argv[1]

# ===========================================================================
# 1. fs/read_write.c
#    OLD: ksu_vfs_read_hook guard on vfs_read()
#    NEW: ksu_handle_sys_read called from SYSCALL_DEFINE3(read, ...)
#         Signatures: int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr)
# ===========================================================================
rw_path = os.path.join(kernel_dir, 'fs', 'read_write.c')
content = read_file(rw_path)

if 'ksu_handle_sys_read' not in content:
    print("[read_write.c] Upgrading...")

    # Step 1: Remove the old vfs_read hook block (declaration + call together)
    # Old declaration before vfs_read:
    old_decl_block = re.compile(
        r'\n#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nint ksu_handle_vfs_read\(struct file \*\*file_ptr, char __user \*\*buf_ptr,\n\t\t\tsize_t \*count_ptr, loff_t \*\*pos\);\n#endif\n',
        re.MULTILINE
    )
    content, n = old_decl_block.subn('\n', content)
    if n:
        print("  [OK] Removed old ksu_handle_vfs_read declaration")
    else:
        # Looser removal
        content = re.sub(
            r'#ifdef CONFIG_KSU\s*\nextern bool ksu_vfs_read_hook[^\n]+\nint ksu_handle_vfs_read[^\n]+\n[^\n]+;\n#endif\s*\n',
            '',
            content
        )
        print("  [OK] Removed old ksu_handle_vfs_read declaration (loose)")

    # Step 2: Remove the old call inside vfs_read
    content = re.sub(
        r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_vfs_read_hook\)\)\s*\n\s*ksu_handle_vfs_read\([^;]+;\s*\n#endif\s*\n',
        '',
        content
    )
    print("  [OK] Removed old ksu_vfs_read_hook call from vfs_read")

    # Step 3: Add new declaration + call into SYSCALL_DEFINE3(read, ...)
    # Insert declaration before SYSCALL_DEFINE3(read, ...)
    old_syscall = 'SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)\n{'
    new_syscall = (
        '#ifdef CONFIG_KSU\n'
        'int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);\n'
        '#endif\n'
        'SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)\n'
        '{\n'
        '#ifdef CONFIG_KSU\n'
        '\tksu_handle_sys_read(fd, &buf, &count);\n'
        '#endif'
    )
    if old_syscall in content:
        content = content.replace(old_syscall, new_syscall, 1)
        print("  [OK] Added ksu_handle_sys_read to SYSCALL_DEFINE3(read)")
    else:
        print("  [WARN] Could not find SYSCALL_DEFINE3(read) - check manually")

    write_file(rw_path, content)
    print("[DONE] read_write.c upgraded")
else:
    print("[SKIP] read_write.c already has ksu_handle_sys_read")


# ===========================================================================
# 2. fs/exec.c
#    OLD: ksu_execveat_hook static_key guard
#    NEW: direct ksu_handle_execveat call (no static_key)
# ===========================================================================
exec_path = os.path.join(kernel_dir, 'fs', 'exec.c')
content = read_file(exec_path)

if 'ksu_execveat_hook' in content:
    print("[exec.c] Upgrading...")

    # Remove the 'extern bool ksu_execveat_hook __read_mostly;' line from declaration block
    content = re.sub(r'extern bool ksu_execveat_hook __read_mostly;\s*\n', '', content)
    # Remove the ksu_handle_execveat_sucompat declaration
    content = re.sub(
        r'extern int ksu_handle_execveat_sucompat\([^)]+\);\s*\n',
        '',
        content
    )

    # Replace the call block:
    # if (unlikely(ksu_execveat_hook))
    #     ksu_handle_execveat(...);
    # else
    #     ksu_handle_execveat_sucompat(...);
    old_call_re = re.compile(
        r'\tif \(unlikely\(ksu_execveat_hook\)\)\s*\n\t+ksu_handle_execveat\([^;]+;\s*\n\s*else\s*\n\t+ksu_handle_execveat_sucompat\([^;]+;\s*\n',
        re.DOTALL
    )
    new_call = '\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n'
    content, n = old_call_re.subn(new_call, content)
    if n:
        print("  [OK] Replaced ksu_execveat_hook call with direct ksu_handle_execveat")
    else:
        print("  [WARN] Could not find old execveat hook call block - check manually")

    write_file(exec_path, content)
    print("[DONE] exec.c upgraded")
else:
    print("[SKIP] exec.c already has no ksu_execveat_hook")


# ===========================================================================
# 3. drivers/input/input.c
#    OLD: ksu_input_hook static_key guard
#    NEW: direct ksu_handle_input_handle_event call
# ===========================================================================
input_path = os.path.join(kernel_dir, 'drivers', 'input', 'input.c')
content = read_file(input_path)

if 'ksu_input_hook' in content:
    print("[input.c] Upgrading...")

    # Remove 'extern bool ksu_input_hook __read_mostly;' line
    content = re.sub(r'extern bool ksu_input_hook __read_mostly;\s*\n', '', content)

    # Replace call:
    # if (unlikely(ksu_input_hook))
    #     ksu_handle_input_handle_event(...);
    old_call_re = re.compile(
        r'\tif \(unlikely\(ksu_input_hook\)\)\s*\n\t+ksu_handle_input_handle_event\([^;]+;\s*\n'
    )
    new_call = '\tksu_handle_input_handle_event(&type, &code, &value);\n'
    content, n = old_call_re.subn(new_call, content)
    if n:
        print("  [OK] Replaced ksu_input_hook call with direct ksu_handle_input_handle_event")
    else:
        print("  [WARN] Could not find old input hook call block - check manually")

    write_file(input_path, content)
    print("[DONE] input.c upgraded")
else:
    print("[SKIP] input.c already has no ksu_input_hook")


# ===========================================================================
# 4. kernel/sys.c
#    MISSING: ksu_handle_setresuid
#    Signature: int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)
#    Inject at start of SYSCALL_DEFINE3(setresuid, ...) body
# ===========================================================================
sys_path = os.path.join(kernel_dir, 'kernel', 'sys.c')
content = read_file(sys_path)

if 'ksu_handle_setresuid' not in content:
    print("[sys.c] Adding ksu_handle_setresuid...")

    old_syscall = 'SYSCALL_DEFINE3(setresuid, uid_t, ruid, uid_t, euid, uid_t, suid)\n{'
    new_syscall = (
        '#ifdef CONFIG_KSU\n'
        'int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\n'
        '#endif\n'
        'SYSCALL_DEFINE3(setresuid, uid_t, ruid, uid_t, euid, uid_t, suid)\n'
        '{\n'
        '#ifdef CONFIG_KSU\n'
        '\tksu_handle_setresuid(ruid, euid, suid);\n'
        '#endif'
    )
    if old_syscall in content:
        content = content.replace(old_syscall, new_syscall, 1)
        write_file(sys_path, content)
        print("[DONE] sys.c: Added ksu_handle_setresuid")
    else:
        print("  [WARN] Could not find SYSCALL_DEFINE3(setresuid) - check manually")
else:
    print("[SKIP] sys.c already has ksu_handle_setresuid")


# ===========================================================================
# 5. kernel/reboot.c
#    MISSING: ksu_handle_sys_reboot
#    Signature: int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg)
#    Inject after magic check (after LINUX_REBOOT_MAGIC2C check returns -EINVAL)
# ===========================================================================
reboot_path = os.path.join(kernel_dir, 'kernel', 'reboot.c')
content = read_file(reboot_path)

if 'ksu_handle_sys_reboot' not in content:
    print("[reboot.c] Adding ksu_handle_sys_reboot...")

    # Inject declaration before SYSCALL_DEFINE4(reboot, ...)
    # Inject call right after the magic check block (after the '\t\treturn -EINVAL;' for bad magic)
    old_syscall = 'SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,\n\t\tvoid __user *, arg)\n{'
    new_syscall = (
        '#ifdef CONFIG_KSU\n'
        'int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n'
        '#endif\n'
        'SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,\n'
        '\t\tvoid __user *, arg)\n'
        '{'
    )

    if old_syscall in content:
        content = content.replace(old_syscall, new_syscall, 1)

        # Now inject the call after the magic validation block
        # The block ends with: \t\treturn -EINVAL;\n (after LINUX_REBOOT_MAGIC2C check)
        old_after_magic = '\t\treturn -EINVAL;\n\n\t/*\n\t * If pid namespaces'
        new_after_magic = (
            '\t\treturn -EINVAL;\n'
            '\n'
            '#ifdef CONFIG_KSU\n'
            '\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n'
            '#endif\n'
            '\n'
            '\t/*\n\t * If pid namespaces'
        )
        if old_after_magic in content:
            content = content.replace(old_after_magic, new_after_magic, 1)
            print("  [OK] Injected ksu_handle_sys_reboot call after magic check")
        else:
            print("  [WARN] Could not find exact injection point for call - trying loose match")
            # Loose: inject after the second return -EINVAL in the magic block
            content = content.replace(
                '\t\treturn -EINVAL;\n\n\t/*\n\t * If pid',
                '\t\treturn -EINVAL;\n\n#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, arg);\n#endif\n\n\t/*\n\t * If pid',
                1
            )

        write_file(reboot_path, content)
        print("[DONE] reboot.c: Added ksu_handle_sys_reboot")
    else:
        print("  [WARN] Could not find SYSCALL_DEFINE4(reboot) - check manually")
else:
    print("[SKIP] reboot.c already has ksu_handle_sys_reboot")


print("\n[COMPLETE] Kernel hooks upgrade finished.")
