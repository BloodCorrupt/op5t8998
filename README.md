# OnePlus 5/5T ReSukiSU Kernel Builder

Automated kernel builder that integrates [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) (a KernelSU fork) into the LineageOS kernel for OnePlus 5 (cheeseburger) / 5T (dumpling).

## Device Info

| Property | Value |
|---|---|
| Kernel | 4.4.302 (Non-GKI) |
| SoC | Qualcomm MSM8998 (Snapdragon 835) |
| Source | [LineageOS/android_kernel_oneplus_msm8998](https://github.com/LineageOS/android_kernel_oneplus_msm8998) |
| Defconfig | `lineage_oneplus5_defconfig` |

## Prerequisites

- **Ubuntu 26.04** (or any modern Debian-based distro)
- ~30 GB free disk space
- Internet connection (for cloning repos)
- A stock `boot.img` from your device (optional, for boot image repacking)

## Quick Start

```bash
# 1. Clone this builder to your Ubuntu machine
git clone <this-repo> oplus5tksu-builder
cd oplus5tksu-builder

# 2. Make the build script executable
chmod +x build.sh scripts/*.sh

# 3. Run the builder
./build.sh
```

Select **option 1** (Full Build) and the script will:
1. Install all build dependencies
2. Clone kernel source, ReSukiSU, and toolchains
3. Integrate ReSukiSU into the kernel tree
4. Apply all manual hook patches
5. Configure the kernel with KSU flags
6. Compile the kernel
7. Package the output (Image.gz-dtb + AnyKernel3 zip)

## CLI Usage

You can also run individual steps from the command line:

```bash
./build.sh --full        # Run all steps
./build.sh --deps        # Install dependencies only
./build.sh --clone       # Clone sources only
./build.sh --integrate   # Integrate ReSukiSU only
./build.sh --patch       # Apply patches only
./build.sh --config      # Configure kernel only
./build.sh --build       # Build kernel only
./build.sh --package     # Package output only
./build.sh --clean       # Clean build state
```

## Configuration

Edit `config/builder.conf` to customize:
- Kernel source repo & branch
- ReSukiSU repo & tag
- Toolchain type
- Defconfig name (OnePlus 5 vs 5T)
- Thread count
- Boot image path
- AnyKernel3 packaging

## Output

After a successful build, you'll find these files in `output/`:

| File | Description |
|---|---|
| `Image.gz-dtb` | Raw kernel image |
| `ReSukiSU-OP5-*.zip` | AnyKernel3 flashable zip (for TWRP) |
| `ksu-boot.img` | Repacked boot image (if stock boot.img provided) |

## Flashing

### Method 1: AnyKernel3 (Recommended)
1. Copy the `ReSukiSU-OP5-*.zip` to your device
2. Reboot to TWRP recovery
3. Flash the zip
4. Reboot

### Method 2: Fastboot
```bash
fastboot flash boot ksu-boot.img
fastboot reboot
```

### Post-Flash
1. Install the [ReSukiSU Manager](https://nightly.link/ReSukiSU/ReSukiSU/workflows/build-manager/main/Manager-release.zip)
2. Open the manager — it should detect root access

## Patches Applied

The builder applies these manual hooks for the 4.4 non-GKI kernel:

| Hook | File | Purpose |
|---|---|---|
| stat | `fs/stat.c` | Hide su binary from stat calls |
| execve | `fs/exec.c` | Intercept process execution |
| faccessat | `fs/open.c` | Hide su from access checks |
| reboot | `kernel/reboot.c` | Safe reboot handling |
| input | `drivers/input/input.c` | Volume key root trigger |
| read | `fs/read_write.c` | Init.rc modification |
| setuid | `kernel/sys.c` | UID elevation handling |

## Troubleshooting

### Build fails with "CONFIG_KSU_MANUAL_HOOK" errors
→ One or more manual hooks are missing. Check `build.log` for which hook failed and apply it manually from `manual-integrate.md`.

### Patch fails to apply
→ The kernel source may have drifted from the expected format. Apply the patch manually using `manual-integrate.md` as reference.

### Bootloop after flashing
→ Usually means a hook was incorrectly placed. Double-check the hook locations against the actual kernel source files.

### "Image.gz-dtb not found" after build
→ Check `build.log` for compilation errors. Common causes: missing toolchain, wrong defconfig.

## License

The kernel source is GPL-2.0. ReSukiSU is GPL-3.0.
