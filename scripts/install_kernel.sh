#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $0 [--activate] [--verbose]

Install the kernel built by build_kernel.sh beside the stock kernel and add the
oai-sctp entry to extlinux.conf. The default boot entry changes only with
--activate.

Options:
  --activate     Make oai-sctp the default boot entry
  -v, --verbose  Show all command output instead of one status line per step
  -h, --help     Show this help

Environment:
  JETSON_KERNEL_WORKSPACE  Build directory (default: ~/jetson-kernel-build)
  JETSON_EXTLINUX_CONF     Boot configuration (default: /boot/extlinux/extlinux.conf)
EOF
}

ACTIVATE=0
for arg in "$@"; do
    case "${arg}" in
        --activate) ACTIVATE=1 ;;
        -v | --verbose) VERBOSE=1 ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option: ${arg}" "Run $0 --help to see the options." ;;
    esac
done

STEP_TOTAL=6

[[ -f "${KERNEL_DIR}/arch/arm64/boot/Image" && -f "${SOURCE_ROOT}/build-inputs.txt" ]] ||
    fail "no finished build in $(pretty_path "${SOURCE_ROOT}")" \
        "Run ${TOOL} build first."

KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" kernelrelease)"
IMAGE_PATH="/boot/Image-${KERNEL_RELEASE}"
INITRD_PATH="/boot/initrd.img-${KERNEL_RELEASE}"
if (( ACTIVATE == 1 )); then
    BOOT_NOTE="oai-sctp, made the default"
else
    BOOT_NOTE="oai-sctp, default entry unchanged"
fi

start_log install

header "install"
field "Release" "${KERNEL_RELEASE}"
field "Boot" "${BOOT_NOTE}"
field "Config" "${EXTLINUX_CONF}"
field "Log" "$(pretty_path "${LOG_FILE}")"
printf '\n'

need_sudo "write to /boot and /lib/modules"
sudo test -f "${EXTLINUX_CONF}" ||
    fail "${EXTLINUX_CONF} does not exist" \
        "Set JETSON_EXTLINUX_CONF when the boot configuration is somewhere else."

backup_extlinux

step "Install kernel image"
run sudo install -m 0644 "${KERNEL_DIR}/arch/arm64/boot/Image" "${IMAGE_PATH}"
end_step "${IMAGE_PATH}"

step "Install in-tree modules"
run sudo make -C "${KERNEL_DIR}" modules_install INSTALL_MOD_PATH=/
end_step "/lib/modules/${KERNEL_RELEASE}"

step "Install NVIDIA OOT modules"
export KERNEL_HEADERS="${KERNEL_DIR}"
run sudo -E make -C "${SOURCE_DIR}" modules_install INSTALL_MOD_PATH=/
end_step

step "Build initramfs"
run sudo depmod -a "${KERNEL_RELEASE}"
run sudo mkinitramfs -o "${INITRD_PATH}" "${KERNEL_RELEASE}"
end_step "${INITRD_PATH}"

step "Add boot entry"
run sudo "${SCRIPT_DIR}/update_extlinux.sh" add "${EXTLINUX_CONF}" "${KERNEL_RELEASE}" "${ACTIVATE}"
end_step "${BOOT_NOTE}"

fmt_time TOTAL_TIME "${SECONDS}"
printf '\n%s in %s.\n' "${GREEN}${BOLD}Installed ${KERNEL_RELEASE}${RESET}" "${TOTAL_TIME}"
field "Backup" "${BACKUP_PATH}"
field "Log" "$(pretty_path "${LOG_FILE}")"

printf '\n%s\n' "${BOLD}Next steps${RESET}"
if (( ACTIVATE == 1 )); then
    printf '  1. %s\n' "sudo reboot"
    printf '  2. %s\n' "${TOOL} verify"
    printf '\n%s\n' "${DIM}To go back to the stock kernel: ${TOOL} rollback, then reboot.${RESET}"
else
    printf '  1. %s\n' "Review ${EXTLINUX_CONF}"
    printf '  2. %s\n' "${TOOL} activate"
    printf '  3. %s\n' "sudo reboot"
    printf '  4. %s\n' "${TOOL} verify"
fi
