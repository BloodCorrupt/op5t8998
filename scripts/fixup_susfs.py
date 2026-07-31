import os
import sys

def insert_after(file_path, search_str, insert_str):
    with open(file_path, 'r') as f:
        lines = f.read().splitlines()
    for i, line in enumerate(lines):
        if search_str in line:
            lines.insert(i + 1, insert_str)
            with open(file_path, 'w', newline='\n') as f:
                f.write('\n'.join(lines) + '\n')
            print(f"Fixed {file_path}")
            return True
    return False

def insert_before(file_path, search_str, insert_str):
    with open(file_path, 'r') as f:
        lines = f.read().splitlines()
    for i, line in enumerate(lines):
        if search_str in line:
            lines.insert(i, insert_str)
            with open(file_path, 'w', newline='\n') as f:
                f.write('\n'.join(lines) + '\n')
            print(f"Fixed {file_path}")
            return True
    return False

kernel_dir = sys.argv[1]

# 1. fs/dcache.c
dcache = os.path.join(kernel_dir, 'fs', 'dcache.c')
if not insert_after(dcache, '#include <linux/list_lru.h>', '#ifdef CONFIG_KSU_SUSFS_SUS_PATH\n#include <linux/susfs_def.h>\n#endif'):
    print("Warning: Failed to fix fs/dcache.c")

# 2. fs/proc/task_mmu.c
task_mmu = os.path.join(kernel_dir, 'fs', 'proc', 'task_mmu.c')
if not insert_after(task_mmu, '#include <linux/mm_inline.h>', '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n#include <linux/susfs_def.h>\n#endif'):
    print("Warning: Failed to fix fs/proc/task_mmu.c")

# 3. kernel/sys.c
sys_c = os.path.join(kernel_dir, 'kernel', 'sys.c')
if not insert_before(sys_c, 'SYSCALL_DEFINE1(newuname, struct new_utsname __user *, name)', '#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif'):
    print("Warning: Failed to fix kernel/sys.c part 1")

if not insert_before(sys_c, 'up_read(&uts_sem);', '#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tsusfs_spoof_uname(&tmp);\n#endif'):
    print("Warning: Failed to fix kernel/sys.c part 2")
