#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../sources.env disable=SC1091
source "${REPO_DIR}/sources.env"

WORKSPACE_DIR="${JETSON_KERNEL_WORKSPACE:-${HOME}/jetson-kernel-build}"
SOURCE_KEY="${L4T_VERSION}-${SOURCE_SHA256:0:12}"
SOURCE_ROOT="${WORKSPACE_DIR}/sources/${SOURCE_KEY}"
SOURCE_DIR="${SOURCE_ROOT}/Linux_for_Tegra/source"
KERNEL_DIR="${SOURCE_DIR}/kernel/kernel-jammy-src"
EXTLINUX_CONF="${JETSON_EXTLINUX_CONF:-/boot/extlinux/extlinux.conf}"
ACTIVATE_CUSTOM_KERNEL=0

if [[ "${1:-}" == "--activate" ]]; then
    ACTIVATE_CUSTOM_KERNEL=1
    shift
fi
if (( $# != 0 )); then
    printf 'Usage: %s [--activate]\n' "$0" >&2
    exit 2
fi

[[ -d "${KERNEL_DIR}" ]] || {
    printf 'ERROR: built sources not found at %s\n' "${KERNEL_DIR}" >&2
    exit 1
}
[[ -f "${KERNEL_DIR}/arch/arm64/boot/Image" ]] || {
    printf 'ERROR: kernel Image is missing; run build_kernel.sh first\n' >&2
    exit 1
}
[[ -f "${SOURCE_ROOT}/build-inputs.txt" ]] || {
    printf 'ERROR: build input record is missing; run build_kernel.sh first\n' >&2
    exit 1
}

KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" kernelrelease)"
IMAGE_PATH="/boot/Image-${KERNEL_RELEASE}"
INITRD_PATH="/boot/initrd.img-${KERNEL_RELEASE}"
BACKUP_PATH="${EXTLINUX_CONF}.bak.$(date -u +%Y%m%dT%H%M%SZ)"

printf '%s\n' "=== Jetson SCTP Kernel Installer ==="
printf 'Kernel release : %s\n' "${KERNEL_RELEASE}"
printf 'Kernel image   : %s\n' "${IMAGE_PATH}"
printf 'Initrd         : %s\n' "${INITRD_PATH}"
printf 'Activate       : %s\n' "${ACTIVATE_CUSTOM_KERNEL}"

sudo test -f "${EXTLINUX_CONF}"
sudo cp -p "${EXTLINUX_CONF}" "${BACKUP_PATH}"
printf 'Boot configuration backup: %s\n' "${BACKUP_PATH}"

sudo install -m 0644 "${KERNEL_DIR}/arch/arm64/boot/Image" "${IMAGE_PATH}"

printf '%s\n' "--- Installing in-tree modules ---"
sudo make -C "${KERNEL_DIR}" modules_install INSTALL_MOD_PATH=/

printf '%s\n' "--- Installing NVIDIA out-of-tree modules ---"
export KERNEL_HEADERS="${KERNEL_DIR}"
sudo -E make -C "${SOURCE_DIR}" modules_install INSTALL_MOD_PATH=/

sudo depmod -a "${KERNEL_RELEASE}"
sudo mkinitramfs -o "${INITRD_PATH}" "${KERNEL_RELEASE}"

sudo "${SCRIPT_DIR}/update_extlinux.sh" \
    "${EXTLINUX_CONF}" \
    "${KERNEL_RELEASE}" \
    "${ACTIVATE_CUSTOM_KERNEL}"

printf '%s\n' "=== Installation completed ==="
if (( ACTIVATE_CUSTOM_KERNEL == 1 )); then
    printf '%s\n' "The custom entry is now the default. Reboot when ready."
else
    printf '%s\n' "The existing default boot entry was preserved."
    printf 'Review %s, then rerun with --activate to select the custom kernel.\n' "${EXTLINUX_CONF}"
fi
printf 'After boot: %s\n' "${SCRIPT_DIR}/verify_kernel.sh"
