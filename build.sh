#!/bin/bash
# ============================================================
#   OnePlus 5/5T ReSukiSU Kernel Builder
#   ─────────────────────────────────────
#   Automated kernel builder with ReSukiSU (KernelSU) integration
#   for OnePlus 5 (cheeseburger) / 5T (dumpling)
#
#   Kernel: 4.4.302 (Non-GKI, manual hooks)
#   Source: LineageOS/android_kernel_oneplus_msm8998
# ============================================================
set -e

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Source utilities
source "${SCRIPTS_DIR}/utils.sh"
load_config

# ── Banner ──
show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║   ⚡ OnePlus 5/5T ReSukiSU Kernel Builder ⚡    ║"
    echo "║                                                  ║"
    echo "║   Kernel:  4.4.302 (Non-GKI)                     ║"
    echo "║   Device:  OnePlus 5 / 5T                        ║"
    echo "║   Root:    ReSukiSU (KernelSU fork)              ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Status ──
show_status() {
    echo -e "${WHITE}── Build State ──────────────────────────────────${NC}"
    
    local steps=(
        "00-install-deps:Install Dependencies"
        "01-clone-sources:Clone Sources"
        "02-integrate-resukisu:Integrate ReSukiSU"
        "03-patch-kernel:Apply Patches"
        "04-configure-kernel:Configure Kernel"
        "05-build-kernel:Build Kernel"
        "06-package-output:Package Output"
    )
    
    for entry in "${steps[@]}"; do
        local step_id="${entry%%:*}"
        local step_name="${entry#*:}"
        if check_step_done "$step_id"; then
            echo -e "  ${GREEN}[✓]${NC} ${step_name}"
        else
            echo -e "  ${RED}[ ]${NC} ${step_name}"
        fi
    done
    
    echo -e "${WHITE}─────────────────────────────────────────────────${NC}"
    echo ""
}

# ── Menu ──
show_menu() {
    echo -e "${YELLOW}Select an option:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC}  Full Build (all steps)            ${CYAN}← recommended${NC}"
    echo -e "  ${WHITE}2)${NC}  Install Dependencies Only"
    echo -e "  ${WHITE}3)${NC}  Clone Sources Only"
    echo -e "  ${WHITE}4)${NC}  Integrate ReSukiSU Only"
    echo -e "  ${WHITE}5)${NC}  Apply Patches Only"
    echo -e "  ${WHITE}6)${NC}  Configure Kernel Only"
    echo -e "  ${WHITE}7)${NC}  Build Kernel Only"
    echo -e "  ${WHITE}8)${NC}  Package Output Only"
    echo ""
    echo -e "  ${MAGENTA}9)${NC}  Clean Build (reset all state)"
    echo -e "  ${MAGENTA}m)${NC}  Configure Kernel (with menuconfig)"
    echo -e "  ${MAGENTA}c)${NC}  Edit Configuration"
    echo -e "  ${RED}0)${NC}  Exit"
    echo ""
}

# ── Run a step ──
run_step() {
    local script="$1"
    shift
    local script_path="${SCRIPTS_DIR}/${script}"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: ${script_path}"
        return 1
    fi
    
    chmod +x "$script_path"
    bash "$script_path" "$@"
}

# ── Full build ──
full_build() {
    step "Starting Full Build Pipeline"
    echo ""
    print_env_info
    
    local steps=(
        "00-install-deps.sh"
        "01-clone-sources.sh"
        "02-integrate-resukisu.sh"
        "03-patch-kernel.sh"
        "04-configure-kernel.sh"
        "05-build-kernel.sh"
        "06-package-output.sh"
    )
    
    local step_num=1
    local total=${#steps[@]}
    
    for s in "${steps[@]}"; do
        local step_id="${s%.sh}"
        
        if check_step_done "$step_id"; then
            warn "Step ${step_num}/${total}: ${s} (already done, skipping)"
            info "Delete .state/${step_id}.done to re-run, or choose 'Clean Build'"
        else
            info "Step ${step_num}/${total}: ${s}"
            run_step "$s"
        fi
        
        step_num=$((step_num + 1))
    done
}

# ── Clean ──
clean_build() {
    warn "This will reset all build state and remove output files."
    if confirm "Are you sure?"; then
        substep "Removing build state..."
        reset_all_steps
        
        substep "Removing output directory..."
        rm -rf "$OUTPUT_PATH" "$FINAL_OUTPUT_PATH"
        
        substep "Removing build log..."
        rm -f "${BUILDER_ROOT}/build.log"
        
        substep "Removing temporary directories..."
        rm -rf "${BUILDER_ROOT}/.repack_tmp" "${BUILDER_ROOT}/.ak3_tmp"
        
        success "Build state cleaned. Sources and toolchains preserved."
        info "To also remove sources/toolchains, delete them manually."
    fi
}

# ── Main ──
main() {
    show_banner
    
    while true; do
        show_status
        show_menu
        
        echo -ne "${YELLOW}Choice [1]: ${NC}"
        read -r choice
        choice="${choice:-1}"
        
        echo ""
        
        case "$choice" in
            1) full_build ;;
            2) run_step "00-install-deps.sh" ;;
            3) run_step "01-clone-sources.sh" ;;
            4) run_step "02-integrate-resukisu.sh" ;;
            5) run_step "03-patch-kernel.sh" ;;
            6) run_step "04-configure-kernel.sh" ;;
            7) run_step "05-build-kernel.sh" ;;
            8) run_step "06-package-output.sh" ;;
            9) clean_build ;;
            m|M) run_step "04-configure-kernel.sh" --menuconfig ;;
            c|C) "${EDITOR:-nano}" "${BUILDER_ROOT}/config/builder.conf" ;;
            0|q|Q) 
                info "Goodbye! 👋"
                exit 0
                ;;
            *)
                error "Invalid choice: ${choice}"
                ;;
        esac
        
        echo ""
        echo -ne "${WHITE}Press Enter to continue...${NC}"
        read -r
        clear 2>/dev/null || true
        show_banner
    done
}

# Allow running individual steps from command line
if [ $# -gt 0 ]; then
    case "$1" in
        --full)     full_build ;;
        --deps)     run_step "00-install-deps.sh" ;;
        --clone)    run_step "01-clone-sources.sh" ;;
        --integrate) run_step "02-integrate-resukisu.sh" ;;
        --patch)    run_step "03-patch-kernel.sh" ;;
        --config)   run_step "04-configure-kernel.sh" ;;
        --build)    run_step "05-build-kernel.sh" ;;
        --package)  run_step "06-package-output.sh" ;;
        --clean)    clean_build ;;
        --help|-h)
            show_banner
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  --full        Run full build pipeline"
            echo "  --deps        Install dependencies only"
            echo "  --clone       Clone sources only"
            echo "  --integrate   Integrate ReSukiSU only"
            echo "  --patch       Apply patches only"
            echo "  --config      Configure kernel only"
            echo "  --build       Build kernel only"
            echo "  --package     Package output only"
            echo "  --clean       Clean build state"
            echo "  --help        Show this help"
            echo ""
            echo "Run without arguments for interactive menu."
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
else
    main
fi
