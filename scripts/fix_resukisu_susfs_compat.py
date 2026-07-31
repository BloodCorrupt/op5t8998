import os
import re
import sys

if len(sys.argv) < 2:
    print("Usage: python fix_resukisu_susfs_compat.py <path_to_dispatch.c>")
    exit(1)

dispatch_file = sys.argv[1]

if not os.path.exists(dispatch_file):
    print(f"File not found: {dispatch_file}")
    exit(1)

with open(dispatch_file, "r") as f:
    content = f.read()

# Define the cases to comment out
cases_to_remove = [
    r"case CMD_SUSFS_ADD_SUS_PATH_LOOP:\s*{\s*susfs_add_sus_path_loop\(arg\);\s*return 0;\s*}",
    r"case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS:\s*{\s*susfs_set_hide_sus_mnts_for_non_su_procs\(arg\);\s*return 0;\s*}",
    r"case CMD_SUSFS_ADD_SUS_MAP:\s*{\s*susfs_add_sus_map\(arg\);\s*return 0;\s*}",
    r"case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING:\s*{\s*susfs_set_avc_log_spoofing\(arg\);\s*return 0;\s*}"
]

for case in cases_to_remove:
    # Use regex to find and replace the whole case block with comments
    content = re.sub(case, r"/* \g<0> (Disabled for SuSFS 1.4.x compat) */", content)

with open(dispatch_file, "w", newline='\n') as f:
    f.write(content)

print("ReSukiSU dispatch.c patched for older SuSFS compatibility.")
