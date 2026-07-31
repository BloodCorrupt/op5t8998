#!/bin/bash
# ============================================================
# Step 1: Clone Kernel Source, ReSukiSU, SuSFS, and Toolchains
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_config

step "Cloning Sources & Toolchains"
timer_start

# --- Clone Kernel Source ---
if [ -d "$KERNEL_PATH" ] && [ -f "$KERNEL_PATH/Makefile" ]; then
    warn "Kernel source already exists at ${KERNEL_PATH}"
    substep "Cleaning and resetting kernel tree to ensure pristine state..."
    cd "$KERNEL_PATH"
    git fetch origin "$KERNEL_BRANCH" > /dev/null 2>&1
    git checkout -B "$KERNEL_BRANCH" "origin/$KERNEL_BRANCH" > /dev/null 2>&1
    git reset --hard "origin/$KERNEL_BRANCH" > /dev/null
    git clean -fd > /dev/null
    cd - > /dev/null
else
    substep "Cloning kernel source (shallow)..."
    info "Repo: ${KERNEL_REPO}"
    info "Branch: ${KERNEL_BRANCH}"
    git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_PATH"
    success "Kernel source cloned."
fi

# Verify kernel version
if [ -f "$KERNEL_PATH/Makefile" ]; then
    KVER=$(head -5 "$KERNEL_PATH/Makefile" | grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL' | awk '{print $3}' | tr '\n' '.' | sed 's/\.$//')
    info "Kernel version: ${KVER}"
fi

# --- Clone ReSukiSU ---
RESUKISU_PATH="${BUILDER_ROOT}/ReSukiSU"
if [ -d "$RESUKISU_PATH" ] && [ -d "$RESUKISU_PATH/kernel" ]; then
    warn "ReSukiSU already exists at ${RESUKISU_PATH}"
    substep "Pulling latest ReSukiSU updates..."
    cd "$RESUKISU_PATH"
    git pull || warn "Failed to pull ReSukiSU updates"
    cd - > /dev/null
else
    substep "Cloning ReSukiSU..."
    if [ -n "$RESUKISU_TAG" ]; then
        info "Tag: ${RESUKISU_TAG}"
        git clone --depth=1 -b "$RESUKISU_TAG" "$RESUKISU_REPO" "$RESUKISU_PATH"
    else
        info "Branch: ${RESUKISU_BRANCH}"
        git clone --depth=1 -b "$RESUKISU_BRANCH" "$RESUKISU_REPO" "$RESUKISU_PATH"
    fi
    success "ReSukiSU cloned."
fi

# --- Clone SuSFS (optional) ---
if [ "${SUSFS_ENABLED}" = "true" ]; then
    SUSFS_PATH="${BUILDER_ROOT}/susfs4ksu"
    if [ -d "$SUSFS_PATH" ] && [ -d "$SUSFS_PATH/kernel_patches" ]; then
        warn "SuSFS already exists at ${SUSFS_PATH}"
        substep "Pulling latest SuSFS updates..."
        cd "$SUSFS_PATH"
        git pull || warn "Failed to pull SuSFS updates"
        cd - > /dev/null
    else
        substep "Cloning SuSFS (${SUSFS_BRANCH})..."
        info "Repo: ${SUSFS_REPO}"
        info "Branch: ${SUSFS_BRANCH}"
        git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_PATH"
        success "SuSFS cloned."
    fi
else
    info "SuSFS is disabled. Skipping SuSFS clone."
fi

# --- Download Toolchain ---
mkdir -p "$TOOLCHAIN_PATH"

case "$TOOLCHAIN_TYPE" in
    proton-clang)
        CLANG_PATH="${TOOLCHAIN_PATH}/proton-clang"
        if [ -d "$CLANG_PATH" ] && [ -x "$CLANG_PATH/bin/clang" ]; then
            warn "Proton Clang already exists. Skipping download."
        else
            substep "Cloning Proton Clang toolchain (this may take a while)..."
            git clone --depth=1 -b "$PROTON_CLANG_BRANCH" "$PROTON_CLANG_REPO" "$CLANG_PATH"
            success "Proton Clang downloaded."
        fi
        info "Clang version: $($CLANG_PATH/bin/clang --version | head -1)"
        ;;
    system-clang)
        info "Using system clang. Make sure clang is installed."
        check_cmd clang || { error "clang not found. Install with: sudo apt install clang"; exit 1; }
        info "Clang version: $(clang --version | head -1)"
        ;;
    *)
        error "Unknown toolchain type: $TOOLCHAIN_TYPE"
        exit 1
        ;;
esac

# --- Download GCC Cross-compilers ---
GCC_AARCH64_PATH="${TOOLCHAIN_PATH}/gcc-aarch64"
if [ -d "$GCC_AARCH64_PATH" ] && [ -x "$GCC_AARCH64_PATH/bin/aarch64-linux-android-gcc" ]; then
    warn "GCC aarch64 already exists. Skipping download."
else
    substep "Cloning GCC aarch64 cross-compiler..."
    git clone --depth=1 -b "$GCC_AARCH64_BRANCH" "$GCC_AARCH64_REPO" "$GCC_AARCH64_PATH"
    success "GCC aarch64 downloaded."
fi

GCC_ARM32_PATH="${TOOLCHAIN_PATH}/gcc-arm32"
if [ -d "$GCC_ARM32_PATH" ] && [ -x "$GCC_ARM32_PATH/bin/arm-linux-androideabi-gcc" ]; then
    warn "GCC arm32 already exists. Skipping download."
else
    substep "Cloning GCC arm32 cross-compiler..."
    git clone --depth=1 -b "$GCC_ARM32_BRANCH" "$GCC_ARM32_REPO" "$GCC_ARM32_PATH"
    success "GCC arm32 downloaded."
fi

# --- Download AnyKernel3 (optional) ---
if [ "$USE_ANYKERNEL3" = "true" ]; then
    AK3_PATH="${BUILDER_ROOT}/AnyKernel3"
    if [ -d "$AK3_PATH" ]; then
        warn "AnyKernel3 already exists. Skipping download."
    else
        substep "Cloning AnyKernel3..."
        git clone --depth=1 -b "$ANYKERNEL3_BRANCH" "$ANYKERNEL3_REPO" "$AK3_PATH"
        success "AnyKernel3 downloaded."
    fi
fi

timer_end
success "All sources and toolchains are ready!"
mark_step_done "01-clone-sources"
