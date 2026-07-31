import os
import subprocess

def run_cmd(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, shell=True, check=True)

# 1. Fix execve
with open("kernel_source/fs/exec.c", "r") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "static int do_execveat_common(int fd, struct filename *filename," in line:
        for j in range(i, i+10):
            if lines[j].strip() == "{":
                lines.insert(j+1, "extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);\n")
                break
        break

for i, line in enumerate(lines):
    if "if (IS_ERR(filename))" in line:
        for j in range(i, i+5):
            if "return PTR_ERR(filename);" in lines[j]:
                lines.insert(j+2, "\n\tksu_handle_execveat(&fd, &filename, NULL, NULL, &flags);\n")
                break
        break

with open("kernel_source/fs/exec.c", "w", newline='\n') as f:
    f.writelines(lines)

# 2. Fix read_write
with open("kernel_source/fs/read_write.c", "r") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)" in line:
        for j in range(i, i+10):
            if lines[j].strip() == "{":
                lines.insert(j+1, "#ifdef CONFIG_KSU\nextern int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);\n#endif\n")
                break
        break

for i, line in enumerate(lines):
    if "struct fd f = fdget_pos(fd);" in line:
        for j in range(i, i+10):
            if "ssize_t ret = -EBADF;" in lines[j]:
                lines.insert(j+1, "\n#ifdef CONFIG_KSU\n\tksu_handle_sys_read(fd, &buf, &count);\n#endif\n")
                break
        break

with open("kernel_source/fs/read_write.c", "w", newline='\n') as f:
    f.writelines(lines)

# Generate patches
run_cmd("git diff fs/exec.c > ../patches/execve_hook.patch", "kernel_source")
run_cmd("git diff fs/read_write.c > ../patches/read_hook.patch", "kernel_source")

# Revert
run_cmd("git checkout fs/exec.c", "kernel_source")
run_cmd("git checkout fs/read_write.c", "kernel_source")

print("Patches regenerated successfully.")
