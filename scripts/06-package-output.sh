#!/bin/bash
# ============================================================
# Step 6: Package Output (Image, boot.img, AnyKernel3)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Packaging Output"

KERNEL_IMG="${OUTPUT_PATH}/arch/${ARCH}/boot/${KERNEL_IMAGE}"

if [ ! -f "$KERNEL_IMG" ]; then
    error "Kernel image not found: ${KERNEL_IMG}"
    error "Run step 05 (Build Kernel) first."
    exit 1
fi

# Create final output directory
mkdir -p "$FINAL_OUTPUT_PATH"

# --- Copy kernel image ---
substep "Copying kernel image to output..."
cp "$KERNEL_IMG" "${FINAL_OUTPUT_PATH}/${KERNEL_IMAGE}"
success "Kernel image: ${FINAL_OUTPUT_PATH}/${KERNEL_IMAGE}"

# --- Repack boot.img (optional) ---
if [ -n "$BOOT_IMG" ] && [ -f "$BOOT_IMG" ]; then
    substep "Repacking boot.img with new kernel..."
    
    REPACK_DIR="${BUILDER_ROOT}/.repack_tmp"
    rm -rf "$REPACK_DIR"
    mkdir -p "$REPACK_DIR"
    
    # Download magiskboot if not present
    MAGISKBOOT="${BUILDER_ROOT}/tools/magiskboot"
    if [ ! -x "$MAGISKBOOT" ]; then
        substep "Downloading magiskboot..."
        mkdir -p "${BUILDER_ROOT}/tools"
        
        # Try to get magiskboot from magiskboot_build releases
        MAGISKBOOT_URL="https://github.com/nicholaschum/magiskboot_build/releases/latest/download/magiskboot-x86_64-linux"
        if curl -sL -o "$MAGISKBOOT" "$MAGISKBOOT_URL" && file "$MAGISKBOOT" | grep -q "ELF"; then
            chmod +x "$MAGISKBOOT"
            success "magiskboot downloaded."
        else
            warn "Could not download magiskboot automatically."
            warn "Please download magiskboot manually and place it at: ${MAGISKBOOT}"
            warn "Skipping boot.img repacking."
            BOOT_IMG=""
        fi
    fi
    
    if [ -n "$BOOT_IMG" ] && [ -x "$MAGISKBOOT" ]; then
        cd "$REPACK_DIR"
        
        # Unpack
        substep "Unpacking stock boot.img..."
        cp "$BOOT_IMG" boot.img
        "$MAGISKBOOT" unpack boot.img
        
        if [ -f kernel ]; then
            # Replace kernel
            substep "Replacing kernel with ReSukiSU-patched version..."
            cp "$KERNEL_IMG" kernel
            
            # Repack
            substep "Repacking boot.img..."
            "$MAGISKBOOT" repack boot.img new-boot.img
            
            if [ -f new-boot.img ]; then
                cp new-boot.img "${FINAL_OUTPUT_PATH}/ksu-boot.img"
                success "Repacked boot image: ${FINAL_OUTPUT_PATH}/ksu-boot.img"
            else
                error "Failed to repack boot.img"
            fi
        else
            error "Failed to unpack boot.img (no kernel found)"
        fi
        
        cd "$BUILDER_ROOT"
        rm -rf "$REPACK_DIR"
    fi
elif [ -n "$BOOT_IMG" ]; then
    warn "Boot image not found at: ${BOOT_IMG}"
    warn "Skipping boot.img repacking."
fi

# --- Package AnyKernel3 (optional) ---
if [ "$USE_ANYKERNEL3" = "true" ]; then
    AK3_PATH="${BUILDER_ROOT}/AnyKernel3"
    
    if [ ! -d "$AK3_PATH" ]; then
        warn "AnyKernel3 not found. Skipping zip packaging."
    else
        substep "Packaging AnyKernel3 zip..."
        
        AK3_WORK="${BUILDER_ROOT}/.ak3_tmp"
        rm -rf "$AK3_WORK"
        cp -r "$AK3_PATH" "$AK3_WORK"
        
        # Clean git files
        rm -rf "$AK3_WORK/.git"
        
        # Copy kernel image
        cp "$KERNEL_IMG" "${AK3_WORK}/${KERNEL_IMAGE}"
        
        # Write exact verified anykernel.sh for OnePlus 5/5T
        substep "Writing verified anykernel.sh for OnePlus 5/5T..."
        cat << 'EOF' > "${AK3_WORK}/anykernel.sh"
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=ReSukiSU Kernel
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=dumpling
device.name2=OnePlus5T
device.name3=cheeseburger
device.name4=OnePlus5
device.name5=
supported.versions=9 - 15
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

# init.rc
backup_file init.rc;
replace_string init.rc "cpuctl cpu,timer_slack" "mount cgroup none /dev/cpuctl cpu" "mount cgroup none /dev/cpuctl cpu,timer_slack";

# init.tuna.rc
backup_file init.tuna.rc;
insert_line init.tuna.rc "nodiratime barrier=0" after "mount_all /fstab.tuna" "\tmount ext4 /dev/block/platform/omap/omap_hsmmc.0/by-name/userdata /data remount nosuid nodev noatime nodiratime barrier=0";
append_file init.tuna.rc "bootscript" init.tuna;

# fstab.tuna
backup_file fstab.tuna;
patch_fstab fstab.tuna /system ext4 options "noatime,barrier=1" "noatime,nodiratime,barrier=0";
patch_fstab fstab.tuna /cache ext4 options "barrier=1" "barrier=0,nomblk_io_submit";
patch_fstab fstab.tuna /data ext4 options "data=ordered" "nomblk_io_submit,data=writeback";
append_file fstab.tuna "usbdisk" fstab;

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install
EOF
        
        # Create zip
        TIMESTAMP=$(date +%Y%m%d_%H%M)
        ZIP_NAME="ReSukiSU-OP5-${TIMESTAMP}.zip"
        
        cd "$AK3_WORK"
        zip -r9 "${FINAL_OUTPUT_PATH}/${ZIP_NAME}" . -x ".git/*" "*.md" "LICENSE"
        cd "$BUILDER_ROOT"
        
        rm -rf "$AK3_WORK"
        
        if [ -f "${FINAL_OUTPUT_PATH}/${ZIP_NAME}" ]; then
            ZIP_SIZE=$(du -h "${FINAL_OUTPUT_PATH}/${ZIP_NAME}" | cut -f1)
            success "AnyKernel3 zip: ${FINAL_OUTPUT_PATH}/${ZIP_NAME} (${ZIP_SIZE})"
        else
            error "Failed to create AnyKernel3 zip."
        fi
    fi
fi

# --- Final Summary ---
echo ""
separator
step "Build Complete! 🎉"
info "Output files in: ${FINAL_OUTPUT_PATH}/"
echo ""

for f in "${FINAL_OUTPUT_PATH}"/*; do
    if [ -f "$f" ]; then
        local_size=$(du -h "$f" | cut -f1)
        success "  $(basename "$f") (${local_size})"
    fi
done

echo ""
info "Next steps:"
substep "1. Transfer the output files to your device"
substep "2. Flash via TWRP (AnyKernel3 zip) or fastboot (boot.img)"
substep "3. Install ReSukiSU Manager from:"
substep "   https://nightly.link/ReSukiSU/ReSukiSU/workflows/build-manager/main/Manager-release.zip"
separator

mark_step_done "06-package-output"
