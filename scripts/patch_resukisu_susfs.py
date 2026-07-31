import sys
import re

patch_file = sys.argv[1]
with open(patch_file, 'r') as f:
    content = f.read()

replacements = {
    r'\bapply_kernelsu_rules\b': 'ksu_apply_kernelsu_rules',
    r'\bgetenforce\b': 'ksu_getenforce',
    r'\bhandle_sepolicy\b': 'ksu_handle_sepolicy',
    r'\bsetup_selinux\b': 'ksu_setup_selinux',
    r'\bsetenforce\b': 'ksu_setenforce',
    r'\bis_ksu_domain\b': 'ksu_is_ksu_domain',
    r'\bis_zygote\b': 'ksu_is_zygote',
}

for k, v in replacements.items():
    content = re.sub(k, v, content)

with open(patch_file, 'w', newline='\n') as f:
    f.write(content)
