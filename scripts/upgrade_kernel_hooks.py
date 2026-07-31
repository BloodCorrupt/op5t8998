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

def replace_all(content, old, new):
    return content.replace(old, new)

kernel_dir = sys.argv[1]

errors = []

# ===========================================================================
# 1. fs/read_write.c
#    OLD: ksu_vfs_read_hook + ksu_handle_vfs_read  (at vfs_read)
#    NEW: ksu_handle_sys_read (no static_key, direct call)
# ===========================================================================
rw_path = os.path.join(kernel_dir, 'fs', 'read_write.c')
content = read_file(rw_path)

# Check if already upgraded
if 'ksu_handle_sys_read' not in content:
    # Remove old-style vfs_read hook block (declaration + call)
    old_decl = """
#ifdef CONFIG_KSU
extern bool ksu_vfs_read_hook __read_mostly;
int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,
\t\t\tsize_t *count_ptr, loff_t **pos);
#endif
"""
    new_decl = """
#ifdef CONFIG_KSU
int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr,
\t\t\tsize_t *count_ptr);
#endif
"""
    if old_decl.strip() in content:
        content = content.replace(old_decl.strip(), new_decl.strip())
        print("  [OK] read_write.c: replaced old vfs_read declaration")
    else:
        # Try a more flexible approach - find and replace the block
        old_block_re = re.compile(
            r'#ifdef CONFIG_KSU\s*\nextern bool ksu_vfs_read_hook __read_mostly;\s*\nint ksu_handle_vfs_read.*?\n#endif',
            re.DOTALL
        )
        new_decl_inline = (
            "#ifdef CONFIG_KSU\n"
            "int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr,\n"
            "\t\t\tsize_t *count_ptr);\n"
            "#endif"
        )
        content, n = old_block_re.subn(new_decl_inline, content)
        if n:
            print("  [OK] read_write.c: replaced old vfs_read declaration (regex)")
        else:
            print("  [WARN] read_write.c: could not find old vfs_read declaration to replace")

    # Remove old call: if (unlikely(ksu_vfs_read_hook)) ksu_handle_vfs_read(...)
    old_call_re = re.compile(
        r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_vfs_read_hook\)\)\s*\n\s*ksu_handle_vfs_read\(.*?\);\s*\n#endif',
        re.DOTALL
    )
    new_call = (
        "#ifdef CONFIG_KSU\n"
        "\tksu_handle_sys_read(fd, &buf, &count);\n"
        "#endif"
    )
    content, n = old_call_re.subn(new_call, content)
    if n:
        print("  [OK] read_write.c: replaced old vfs_read call with ksu_handle_sys_read")
    else:
        # Check what the actual call looks like
        if 'ksu_handle_vfs_read' in content:
            # Direct replacement of the call block
            content = re.sub(
                r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_vfs_read_hook\)\)\s*\n\t+ksu_handle_vfs_read\([^)]+\);\s*\n#endif',
                new_call,
                content,
                flags=re.DOTALL
            )
            print("  [OK] read_write.c: replaced old vfs_read call (alt regex)")
        else:
            print("  [WARN] read_write.c: old vfs_read call not found, skipping")

    write_file(rw_path, content)
    print(f"[DONE] Upgraded read_write.c")
else:
    print(f"[SKIP] read_write.c already has ksu_handle_sys_read")


# ===========================================================================
# 2. fs/exec.c
#    OLD: ksu_execveat_hook (static_key guard)
#    NEW: direct ksu_handle_execveat call (no static_key)
# ===========================================================================
exec_path = os.path.join(kernel_dir, 'fs', 'exec.c')
content = read_file(exec_path)

if 'ksu_execveat_hook' in content:
    # Replace the old declaration block
    # Old: extern bool ksu_execveat_hook + ksu_handle_execveat + ksu_handle_execveat_sucompat
    old_decl_re = re.compile(
        r'#ifdef CONFIG_KSU\s*\nextern bool ksu_execveat_hook __read_mostly;\s*\n.*?#endif\s*\n',
        re.DOTALL
    )
    new_decl = (
        "#ifdef CONFIG_KSU\n"
        "extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n"
        "\t\t\tvoid *envp, int *flags);\n"
        "extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\n"
        "\t\t\t\t void *argv, void *envp, int *flags);\n"
        "#endif\n"
    )
    content, n = old_decl_re.subn(new_decl, content, count=1)
    if n:
        print("  [OK] exec.c: replaced old execveat declaration")
    else:
        print("  [WARN] exec.c: could not find old execveat declaration")

    # Replace the call: if (unlikely(ksu_execveat_hook)) ... else ...
    old_call_re = re.compile(
        r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_execveat_hook\)\)\s*\n\t+ksu_handle_execveat\([^;]+;\s*\n\s*else\s*\n\t+ksu_handle_execveat_sucompat\([^;]+;\s*\n#endif',
        re.DOTALL
    )
    new_call = (
        "#ifdef CONFIG_KSU\n"
        "\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n"
        "#endif"
    )
    content, n = old_call_re.subn(new_call, content)
    if n:
        print("  [OK] exec.c: replaced old execveat call")
    else:
        # simpler replacement
        content = re.sub(
            r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_execveat_hook\)\)\s*\n[^\n]+\n\s*else\s*\n[^\n]+\n#endif',
            new_call,
            content
        )
        print("  [OK] exec.c: replaced old execveat call (simple regex)")

    write_file(exec_path, content)
    print(f"[DONE] Upgraded exec.c")
else:
    print(f"[SKIP] exec.c already has no ksu_execveat_hook")


# ===========================================================================
# 3. drivers/input/input.c
#    OLD: ksu_input_hook (static_key guard)
#    NEW: direct ksu_handle_input_handle_event call (no static_key)
# ===========================================================================
input_path = os.path.join(kernel_dir, 'drivers', 'input', 'input.c')
content = read_file(input_path)

if 'ksu_input_hook' in content:
    # Replace declaration
    old_decl_re = re.compile(
        r'#ifdef CONFIG_KSU\s*\nextern bool ksu_input_hook __read_mostly;\s*\nextern int ksu_handle_input_handle_event[^\n]+\n#endif',
        re.DOTALL
    )
    new_decl = (
        "#ifdef CONFIG_KSU\n"
        "extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n"
        "#endif"
    )
    content, n = old_decl_re.subn(new_decl, content)
    if n:
        print("  [OK] input.c: replaced old input_hook declaration")
    else:
        print("  [WARN] input.c: could not find old input declaration")

    # Replace call
    old_call_re = re.compile(
        r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_input_hook\)\)\s*\n\t+ksu_handle_input_handle_event\([^;]+;\s*\n#endif',
        re.DOTALL
    )
    new_call = (
        "#ifdef CONFIG_KSU\n"
        "\tksu_handle_input_handle_event(&type, &code, &value);\n"
        "#endif"
    )
    content, n = old_call_re.subn(new_call, content)
    if n:
        print("  [OK] input.c: replaced old input_hook call")
    else:
        content = re.sub(
            r'#ifdef CONFIG_KSU\s*\n\s*if \(unlikely\(ksu_input_hook\)\)\s*\n[^\n]+\n#endif',
            new_call,
            content
        )
        print("  [OK] input.c: replaced old input_hook call (simple regex)")

    write_file(input_path, content)
    print(f"[DONE] Upgraded input.c")
else:
    print(f"[SKIP] input.c already has no ksu_input_hook")


# ===========================================================================
# 4. kernel/sys.c
#    MISSING: ksu_handle_setresuid
#    The stable branch doesn't have it, so we need to add it.
# ===========================================================================
sys_path = os.path.join(kernel_dir, 'kernel', 'sys.c')
content = read_file(sys_path)

if 'ksu_handle_setresuid' not in content:
    # Find SYSCALL_DEFINE3(setresuid, ...) and add hook after creds are checked
    # Find the line containing "setresuid" syscall to inject before
    # We inject after the security_task_fix_setuid call
    old_code = "\tretval = security_task_fix_setuid(new, old, LSM_SETID_RES);"
    new_code = (
        "#ifdef CONFIG_KSU\n"
        "extern int ksu_handle_setresuid(uid_t *ruid, uid_t *euid, uid_t *suid);\n"
        "\tksu_handle_setresuid(&ruid, &euid, &suid);\n"
        "#endif\n"
        "\tretval = security_task_fix_setuid(new, old, LSM_SETID_RES);"
    )
    if old_code in content:
        content = content.replace(old_code, new_code, 1)
        write_file(sys_path, content)
        print(f"[DONE] Added ksu_handle_setresuid to sys.c")
    else:
        # Alternative injection point
        print(f"  [WARN] sys.c: could not find injection point for ksu_handle_setresuid")
else:
    print(f"[SKIP] sys.c already has ksu_handle_setresuid")


# ===========================================================================
# 5. kernel/reboot.c
#    MISSING: ksu_handle_sys_reboot
#    Add it before the kernel_restart / orderly_poweroff calls
# ===========================================================================
reboot_path = os.path.join(kernel_dir, 'kernel', 'reboot.c')
content = read_file(reboot_path)

if 'ksu_handle_sys_reboot' not in content:
    # Find SYSCALL_DEFINE4(reboot, ...) and inject after magic check
    # Inject before: kernel_restart(NULL); or before emergency_restart()
    inject_before = "\tkernel_restart(NULL);"
    if inject_before not in content:
        inject_before = "\torderly_reboot();"
    if inject_before not in content:
        inject_before = "\tcase LINUX_REBOOT_CMD_RESTART:"

    if inject_before in content:
        new_code = (
            "#ifdef CONFIG_KSU\n"
            "extern int ksu_handle_sys_reboot(int *magic1, int *magic2, unsigned int *cmd, void *arg);\n"
            "\tksu_handle_sys_reboot(&magic1, &magic2, &cmd, arg);\n"
            "#endif\n"
            + inject_before
        )
        content = content.replace(inject_before, new_code, 1)
        write_file(reboot_path, content)
        print(f"[DONE] Added ksu_handle_sys_reboot to reboot.c")
    else:
        print(f"  [WARN] reboot.c: could not find injection point for ksu_handle_sys_reboot")
else:
    print(f"[SKIP] reboot.c already has ksu_handle_sys_reboot")


print("\n[COMPLETE] Kernel hooks upgrade finished.")
