import os
import re
import sys

if len(sys.argv) < 3:
    print("Usage: python fix_resukisu_susfs_compat.py <path_to_dispatch.c> <path_to_supercall.c>")
    exit(1)

dispatch_file = sys.argv[1]
supercall_file = sys.argv[2]

if not os.path.exists(dispatch_file):
    print(f"File not found: {dispatch_file}")
    exit(1)

if not os.path.exists(supercall_file):
    print(f"File not found: {supercall_file}")
    exit(1)

with open(dispatch_file, "r") as f:
    content = f.read()

if "Disabled for SuSFS 1.4.x compat" not in content:
    cases_to_remove = [
        r"case CMD_SUSFS_ADD_SUS_PATH_LOOP:\s*{\s*susfs_add_sus_path_loop\(arg\);\s*return 0;\s*}",
        r"case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS:\s*{\s*susfs_set_hide_sus_mnts_for_non_su_procs\(arg\);\s*return 0;\s*}",
        r"case CMD_SUSFS_ADD_SUS_MAP:\s*{\s*susfs_add_sus_map\(arg\);\s*return 0;\s*}",
        r"case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING:\s*{\s*susfs_set_avc_log_spoofing\(arg\);\s*return 0;\s*}"
    ]

    for case in cases_to_remove:
        content = re.sub(case, r"/* \g<0> (Disabled for SuSFS 1.4.x compat) */", content)

    with open(dispatch_file, "w", newline='\n') as f:
        f.write(content)

with open(supercall_file, "r") as f:
    supercall_content = f.read()

if "SUSFS_MAGIC" in supercall_content and "#define SUSFS_MAGIC" not in supercall_content:
    supercall_content = supercall_content.replace(
        '#include "supercall/internal.h"',
        '#include "supercall/internal.h"\n\n#ifndef SUSFS_MAGIC\n#define SUSFS_MAGIC 0x5555\n#endif\n'
    )
    with open(supercall_file, "w", newline='\n') as f:
        f.write(supercall_content)

print("ReSukiSU patched for older SuSFS compatibility.")
