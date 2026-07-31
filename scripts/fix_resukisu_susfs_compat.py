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

# ============================================================
# 1. dispatch.c - comment out missing CMD_SUSFS_* cases
# ============================================================
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

# ============================================================
# 2. supercall.c - inject SUSFS_MAGIC if missing
# ============================================================
with open(supercall_file, "r") as f:
    supercall_content = f.read()

if "SUSFS_MAGIC" in supercall_content and "#define SUSFS_MAGIC" not in supercall_content:
    supercall_content = supercall_content.replace(
        '#include "supercall/internal.h"',
        '#include "supercall/internal.h"\n\n#ifndef SUSFS_MAGIC\n#define SUSFS_MAGIC 0x5555\n#endif\n'
    )
    with open(supercall_file, "w", newline='\n') as f:
        f.write(supercall_content)

# ============================================================
# 3. dispatch.c - inject forward declarations at the TOP
#    (before the first use), not dummy implementations at the end.
#    This avoids "conflicting types" from implicit declarations.
#
#    Actual signatures from ReSukiSU source (ksud_integration.c,
#    supercall.c, dispatch.c context):
#      arg is void __user ** in ksu_handle_susfs_cmd
#      susfs_enable_log, susfs_get_enabled_features, etc take void __user **
# ============================================================
with open(dispatch_file, "r") as f:
    dispatch_content = f.read()

# Remove any old dummy function DEFINITIONS appended at the end (cleanup)
dummy_marker = "/* SuSFS 1.4.x Compatibility Dummy Functions */"
if dummy_marker in dispatch_content:
    # Strip everything from the marker to end
    dispatch_content = dispatch_content[:dispatch_content.index(dummy_marker)].rstrip() + "\n"
    with open(dispatch_file, "w", newline='\n') as f:
        f.write(dispatch_content)
    print("Removed old appended dummy functions from dispatch.c")

# Now inject forward declarations right after the last #include block
# Find the right injection point: after the includes, before the first function
SUSFS_COMPAT_GUARD = "/* SuSFS 1.4.x compat forward declarations */"

if SUSFS_COMPAT_GUARD not in dispatch_content:
    # Find the last #include line
    include_re = re.compile(r'^#include\s+[<"][^\n]+', re.MULTILINE)
    matches = list(include_re.finditer(dispatch_content))
    if matches:
        last_include_end = matches[-1].end()
        fwd_decls = f"""

{SUSFS_COMPAT_GUARD}
#ifndef CONFIG_KSU_SUSFS
#include <linux/workqueue.h>
struct work_struct susfs_extra_works;
static inline bool susfs_is_current_proc_umounted(void) {{ return false; }}
static inline void susfs_set_current_proc_umounted(void) {{}}
static inline void susfs_start_sdcard_monitor_fn(void) {{}}
static inline void susfs_enable_log(void __user **arg) {{}}
static inline long susfs_get_enabled_features(void __user **arg) {{ return 0; }}
static inline long susfs_show_variant(void __user **arg) {{ return 0; }}
static inline long susfs_show_version(void __user **arg) {{ return 0; }}
#endif /* !CONFIG_KSU_SUSFS */
"""
        dispatch_content = (
            dispatch_content[:last_include_end]
            + fwd_decls
            + dispatch_content[last_include_end:]
        )
        with open(dispatch_file, "w", newline='\n') as f:
            f.write(dispatch_content)
        print("Injected SuSFS 1.4.x compat forward declarations into dispatch.c")
    else:
        print("WARNING: Could not find #include block in dispatch.c")
else:
    print("SuSFS compat declarations already present in dispatch.c")

print("ReSukiSU patched for older SuSFS compatibility.")
