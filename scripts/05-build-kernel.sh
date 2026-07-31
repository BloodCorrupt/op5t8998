#!/bin/bash
# ============================================================
# Step 5: Build the Kernel
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Building Kernel"
timer_start

if [ ! -d "$KERNEL_PATH" ] || [ ! -f "$KERNEL_PATH/Makefile" ]; then
    error "Kernel source not found at ${KERNEL_PATH}"
    exit 1
fi

if [ ! -f "${OUTPUT_PATH}/.config" ]; then
    error "Kernel not configured. Run step 04 (Configure Kernel) first."
    exit 1
fi

cd "$KERNEL_PATH"

# --- Setup toolchain paths ---
substep "Setting up toolchain environment..."

case "$TOOLCHAIN_TYPE" in
    proton-clang)
        CLANG_PATH="${TOOLCHAIN_PATH}/proton-clang"
        # Use full path to clang executable for kernel targets
        CC="${CLANG_PATH}/bin/clang"
        CLANG_TRIPLE="aarch64-linux-gnu-"
        # Append to PATH (not prepend) so host tools keep system gcc/ld first
        export PATH="$PATH:${CLANG_PATH}/bin"
        ;;
    system-clang)
        CC="clang"
        CLANG_TRIPLE="aarch64-linux-gnu-"
        ;;
esac

GCC_AARCH64_PATH="${TOOLCHAIN_PATH}/gcc-aarch64"
GCC_ARM32_PATH="${TOOLCHAIN_PATH}/gcc-arm32"
export PATH="$PATH:${GCC_AARCH64_PATH}/bin:${GCC_ARM32_PATH}/bin"

CROSS_COMPILE="aarch64-linux-android-"
CROSS_COMPILE_ARM32="arm-linux-androideabi-"

# Setup ccache
if [ "$USE_CCACHE" = "true" ] && command -v ccache &>/dev/null; then
    CC="ccache ${CC}"
    info "Using ccache for faster rebuilds."
fi

# Print build info
info "Build configuration:"
substep "CC:               ${CC}"
substep "CROSS_COMPILE:    ${CROSS_COMPILE}"
substep "CROSS_COMPILE_ARM32: ${CROSS_COMPILE_ARM32}"
substep "ARCH:             ${ARCH}"
substep "Threads:          ${THREADS}"
substep "Output:           ${OUTPUT_PATH}"
separator

# --- Build ---
substep "Starting kernel compilation..."
echo ""

make_args=(
    O="$OUTPUT_PATH"
    ARCH="$ARCH"
    SUBARCH="$SUBARCH"
    CC="$CC"
    HOSTCC=gcc
    HOSTCXX=g++
    HOSTLD=/usr/bin/ld
    HOSTLDFLAGS="-B/usr/bin"
    CROSS_COMPILE="$CROSS_COMPILE"
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"
    CROSS_COMPILE_COMPAT="$CROSS_COMPILE_ARM32"
    CLANG_TRIPLE="$CLANG_TRIPLE"
    -j"$THREADS"
)

# Run the build
make "${make_args[@]}" 2>&1 | tee "${BUILDER_ROOT}/build.log"
BUILD_EXIT=${PIPESTATUS[0]}

echo ""

if [ $BUILD_EXIT -ne 0 ]; then
    error "Kernel build FAILED with exit code ${BUILD_EXIT}"
    error "Check build.log for details: ${BUILDER_ROOT}/build.log"
    echo ""
    
    # Check for common errors
    if grep -q "CONFIG_KSU_MANUAL_HOOK" "${BUILDER_ROOT}/build.log" 2>/dev/null; then
        warn "Hint: There may be missing manual hooks. Check manual-integrate.md"
    fi
    if grep -q "implicit declaration" "${BUILDER_ROOT}/build.log" 2>/dev/null; then
        warn "Hint: There may be missing extern declarations in hook patches."
    fi
    
    exit 1
fi

# --- Verify output ---
KERNEL_IMG="${OUTPUT_PATH}/arch/${ARCH}/boot/${KERNEL_IMAGE}"

if [ -f "$KERNEL_IMG" ]; then
    IMG_SIZE=$(du -h "$KERNEL_IMG" | cut -f1)
    success "Kernel built successfully!"
    success "Image: ${KERNEL_IMG} (${IMG_SIZE})"
else
    error "Kernel image not found at expected path: ${KERNEL_IMG}"
    error "Build may have partially succeeded. Check build.log."
    exit 1
fi

timer_end
mark_step_done "05-build-kernel"
