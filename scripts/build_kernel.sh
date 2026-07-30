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
ARCHIVE_PATH="${WORKSPACE_DIR}/downloads/public_sources-${L4T_VERSION}.tbz2"
SWAP_FILE="${JETSON_KERNEL_SWAP_FILE:-/swapfile_build}"
SWAP_SIZE_GB="${JETSON_KERNEL_SWAP_SIZE_GB:-4}"
BUILD_JOBS="${JETSON_KERNEL_BUILD_JOBS:-4}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

printf '%s\n' "=== Jetson Orin Nano SCTP Kernel Builder ==="
printf 'Target BSP release : %s\n' "${L4T_VERSION}"
printf 'Target JetPack     : %s\n' "${JETPACK_VERSION}"
printf 'Source SHA-256     : %s\n' "${SOURCE_SHA256}"
printf 'Build directory    : %s\n' "${SOURCE_ROOT}"
printf 'Parallel jobs      : %s\n' "${BUILD_JOBS}"

[[ "$(uname -m)" == "aarch64" ]] ||
    fail "this native build must run on the Jetson (aarch64)"
[[ "${BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]] || fail "JETSON_KERNEL_BUILD_JOBS must be a positive integer"
[[ "${SWAP_SIZE_GB}" =~ ^[1-9][0-9]*$ ]] || fail "JETSON_KERNEL_SWAP_SIZE_GB must be a positive integer"

if [[ -r /etc/nv_tegra_release ]]; then
    tr -d '\r' </etc/nv_tegra_release | head -1
fi

printf '%s\n' "--- Installing build dependencies ---"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bc \
    bison \
    build-essential \
    checkpolicy \
    flex \
    initramfs-tools \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    lksctp-tools \
    rsync \
    wget

TOTAL_RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
printf 'Detected RAM: %s GB\n' "${TOTAL_RAM_GB}"
if (( TOTAL_RAM_GB < 12 )); then
    if swapon --show=NAME --noheadings | awk '{$1=$1};1' | grep -Fxq "${SWAP_FILE}"; then
        printf 'Build swap is already active: %s\n' "${SWAP_FILE}"
    else
        printf 'Creating dedicated %s GB build swap at %s\n' "${SWAP_SIZE_GB}" "${SWAP_FILE}"
        if [[ ! -f "${SWAP_FILE}" ]]; then
            if ! sudo fallocate -l "${SWAP_SIZE_GB}G" "${SWAP_FILE}"; then
                sudo dd if=/dev/zero of="${SWAP_FILE}" bs=1M \
                    count="$((SWAP_SIZE_GB * 1024))" status=progress
            fi
        fi
        sudo chmod 600 "${SWAP_FILE}"
        sudo mkswap "${SWAP_FILE}"
        sudo swapon "${SWAP_FILE}"
        printf 'Build swap enabled. Existing swap devices were left unchanged.\n'
    fi
fi

mkdir -p "$(dirname -- "${ARCHIVE_PATH}")"
if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    printf '%s\n' "--- Downloading pinned NVIDIA public sources ---"
    wget --https-only --output-document="${ARCHIVE_PATH}" "${SOURCE_URL}"
fi

ACTUAL_SHA256="$(sha256_file "${ARCHIVE_PATH}")"
[[ "${ACTUAL_SHA256}" == "${SOURCE_SHA256}" ]] ||
    fail "source checksum mismatch: expected ${SOURCE_SHA256}, got ${ACTUAL_SHA256}"

ACTUAL_SIZE="$(stat --format='%s' "${ARCHIVE_PATH}")"
[[ "${ACTUAL_SIZE}" == "${SOURCE_SIZE_BYTES}" ]] ||
    fail "source size mismatch: expected ${SOURCE_SIZE_BYTES}, got ${ACTUAL_SIZE}"

if [[ ! -f "${SOURCE_ROOT}/.source-ready" ]]; then
    [[ ! -e "${SOURCE_ROOT}" ]] ||
        fail "incomplete source directory exists at ${SOURCE_ROOT}; inspect and remove it before retrying"
    mkdir -p "${SOURCE_ROOT}"
    printf '%s\n' "--- Extracting pinned source bundle ---"
    tar -xjf "${ARCHIVE_PATH}" -C "${SOURCE_ROOT}"
    (
        cd "${SOURCE_DIR}"
        tar -xjf kernel_src.tbz2
        tar -xjf kernel_oot_modules_src.tbz2
        tar -xjf nvidia_kernel_display_driver_source.tbz2
    )
    printf '%s\n' "${SOURCE_SHA256}" >"${SOURCE_ROOT}/.source-ready"
fi

[[ -d "${KERNEL_DIR}" ]] || fail "kernel source not found at ${KERNEL_DIR}"
[[ -f "${SOURCE_DIR}/Makefile" ]] || fail "NVIDIA OOT module Makefile was not extracted"

printf '%s\n' "--- Configuring the kernel ---"
make -C "${KERNEL_DIR}" mrproper
make -C "${KERNEL_DIR}" defconfig
"${KERNEL_DIR}/scripts/config" --file "${KERNEL_DIR}/.config" --set-val CONFIG_IP_SCTP m
"${KERNEL_DIR}/scripts/config" --file "${KERNEL_DIR}/.config" --set-str CONFIG_LOCALVERSION "${KERNEL_LOCALVERSION}"
make -C "${KERNEL_DIR}" olddefconfig
grep -qx 'CONFIG_IP_SCTP=m' "${KERNEL_DIR}/.config"
grep -qx "CONFIG_LOCALVERSION=\"${KERNEL_LOCALVERSION}\"" "${KERNEL_DIR}/.config"

KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" kernelrelease)"
printf 'Derived kernel release: %s\n' "${KERNEL_RELEASE}"

printf '%s\n' "--- Building kernel Image and in-tree modules ---"
make -C "${KERNEL_DIR}" -j"${BUILD_JOBS}" Image modules

printf '%s\n' "--- Building NVIDIA out-of-tree modules ---"
export KERNEL_HEADERS="${KERNEL_DIR}"
make -C "${SOURCE_DIR}" -j"${BUILD_JOBS}" modules

{
    printf 'repository_commit=%s\n' "$(git -C "${REPO_DIR}" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'l4t_version=%s\n' "${L4T_VERSION}"
    printf 'jetpack_version=%s\n' "${JETPACK_VERSION}"
    printf 'source_url=%s\n' "${SOURCE_URL}"
    printf 'source_sha256=%s\n' "${SOURCE_SHA256}"
    printf 'kernel_release=%s\n' "${KERNEL_RELEASE}"
    printf 'compiler=%s\n' "$(gcc --version | head -1)"
    printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    dpkg-query -W -f='package=${binary:Package} version=${Version}\n' \
        bc bison build-essential checkpolicy flex libelf-dev libncurses-dev \
        libssl-dev rsync 2>/dev/null
} >"${SOURCE_ROOT}/build-inputs.txt"

printf '%s\n' "=== Build completed ==="
printf 'Kernel release: %s\n' "${KERNEL_RELEASE}"
printf 'Build inputs  : %s\n' "${SOURCE_ROOT}/build-inputs.txt"
printf '%s\n' "Next: ${SCRIPT_DIR}/install_kernel.sh"
