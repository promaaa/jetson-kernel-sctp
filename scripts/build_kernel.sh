#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $0 [--verbose]

Build the SCTP kernel, its modules, and the NVIDIA OOT and display modules
natively on the Jetson, from the NVIDIA sources pinned in sources.env.

Options:
  -v, --verbose  Show all build output instead of one status line per step
  -h, --help     Show this help

Environment:
  JETSON_KERNEL_WORKSPACE     Build directory (default: ~/jetson-kernel-build)
  JETSON_KERNEL_BUILD_JOBS    Parallel build jobs (default: 4)
  JETSON_KERNEL_SWAP_FILE     Build swapfile (default: /swapfile_build)
  JETSON_KERNEL_SWAP_SIZE_GB  Build swapfile size in GB (default: 4)
EOF
}

for arg in "$@"; do
    case "${arg}" in
        -v | --verbose) VERBOSE=1 ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option: ${arg}" "Run $0 --help to see the options." ;;
    esac
done

ARCHIVE_PATH="${WORKSPACE_DIR}/downloads/public_sources-${L4T_VERSION}.tbz2"
SWAP_FILE="${JETSON_KERNEL_SWAP_FILE:-/swapfile_build}"
SWAP_SIZE_GB="${JETSON_KERNEL_SWAP_SIZE_GB:-4}"
BUILD_JOBS="${JETSON_KERNEL_BUILD_JOBS:-4}"
STEP_TOTAL=8

[[ "$(uname -m)" == "aarch64" ]] ||
    fail "this build must run on the Jetson (aarch64), not on $(uname -m)"
[[ "${BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]] ||
    fail "JETSON_KERNEL_BUILD_JOBS must be a positive integer, not '${BUILD_JOBS}'"
[[ "${SWAP_SIZE_GB}" =~ ^[1-9][0-9]*$ ]] ||
    fail "JETSON_KERNEL_SWAP_SIZE_GB must be a positive integer, not '${SWAP_SIZE_GB}'"

mkdir -p "$(dirname -- "${ARCHIVE_PATH}")"
start_log build

# /etc/nv_tegra_release starts with "# R36 (release), REVISION: 4.4, ...".
BOARD_RELEASE="$(sed -n 's/^# R\([0-9]*\) (release), REVISION: \([0-9.]*\),.*/R\1.\2/p' \
    /etc/nv_tegra_release 2>/dev/null || true)"

header "build"
field "Sources" "Jetson Linux ${L4T_VERSION} (JetPack ${JETPACK_VERSION})"
field "Board" "${BOARD_RELEASE:-unknown}"
field "Workspace" "$(pretty_path "${WORKSPACE_DIR}")"
field "Jobs" "${BUILD_JOBS}"
field "Log" "$(pretty_path "${LOG_FILE}")"
printf '\n'

if [[ -n "${BOARD_RELEASE}" && "${BOARD_RELEASE}" != "${L4T_VERSION}" ]]; then
    warn "this board runs ${BOARD_RELEASE}, but the pinned sources are ${L4T_VERSION}."
    warn "The NVIDIA modules may not match the NVIDIA userspace on this board."
    printf '\n'
fi

# A build in a plain SSH session dies with the connection.
if [[ -n "${SSH_CONNECTION:-}" && -z "${TMUX:-}" && -z "${STY:-}" ]]; then
    warn "this SSH session has no tmux or screen. The build stops if the connection drops."
    if [[ -t 0 ]] && ! confirm "Continue without tmux or screen?" n; then
        printf 'Start tmux or screen, then run the build again.\n'
        exit 0
    fi
    printf '\n'
fi

need_sudo "install build packages and prepare the build swapfile"

step "Install build dependencies"
run sudo apt-get update
run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
end_step

step "Prepare build swap"
TOTAL_RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
if (( TOTAL_RAM_GB >= 12 )); then
    end_step "not needed with ${TOTAL_RAM_GB} GB RAM"
elif swapon --show=NAME --noheadings | awk -v file="${SWAP_FILE}" '$1 == file { found = 1 } END { exit !found }'; then
    end_step "already active: ${SWAP_FILE}"
else
    if [[ ! -f "${SWAP_FILE}" ]]; then
        # The log belongs to the user, so the redirect must not use sudo.
        # shellcheck disable=SC2024
        if ! sudo fallocate -l "${SWAP_SIZE_GB}G" "${SWAP_FILE}" >>"${LOG_FILE}" 2>&1; then
            run sudo dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="$((SWAP_SIZE_GB * 1024))"
        fi
    fi
    run sudo chmod 600 "${SWAP_FILE}"
    run sudo mkswap "${SWAP_FILE}"
    run sudo swapon "${SWAP_FILE}"
    end_step "${SWAP_SIZE_GB} GB at ${SWAP_FILE}"
fi

step "Download NVIDIA sources"
if [[ -f "${ARCHIVE_PATH}" ]]; then
    end_step "already downloaded"
else
    # The archive gets its final name only when the download is complete.
    run wget --https-only --progress=dot:mega \
        --output-document="${ARCHIVE_PATH}.part" "${SOURCE_URL}"
    mv "${ARCHIVE_PATH}.part" "${ARCHIVE_PATH}"
    end_step "$(((SOURCE_SIZE_BYTES + 524288) / 1048576)) MB"
fi

step "Verify source archive"
REDOWNLOAD_HINT="Delete the archive and run the build again:
rm $(pretty_path "${ARCHIVE_PATH}")"
ACTUAL_SIZE="$(stat --format='%s' "${ARCHIVE_PATH}")"
[[ "${ACTUAL_SIZE}" == "${SOURCE_SIZE_BYTES}" ]] ||
    fail "the source archive has ${ACTUAL_SIZE} bytes, expected ${SOURCE_SIZE_BYTES}" "${REDOWNLOAD_HINT}"
ACTUAL_SHA256="$(sha256sum "${ARCHIVE_PATH}" | awk '{print $1}')"
[[ "${ACTUAL_SHA256}" == "${SOURCE_SHA256}" ]] ||
    fail "the source archive SHA-256 is ${ACTUAL_SHA256}, expected ${SOURCE_SHA256}" \
        "${REDOWNLOAD_HINT}
If it fails again, NVIDIA changed the file. Review the pin in sources.env."
end_step "SHA-256 ${SOURCE_SHA256:0:12}, ${ACTUAL_SIZE} bytes"

step "Extract sources"
if [[ -f "${SOURCE_ROOT}/.source-ready" ]]; then
    EXTRACT_NOTE="already extracted"
else
    [[ ! -e "${SOURCE_ROOT}" ]] ||
        fail "an earlier extraction did not finish" \
            "Remove it and run the build again:
rm -rf $(pretty_path "${SOURCE_ROOT}")"
    mkdir -p "${SOURCE_ROOT}"
    run tar -xjf "${ARCHIVE_PATH}" -C "${SOURCE_ROOT}"
    for part in kernel_src kernel_oot_modules_src nvidia_kernel_display_driver_source; do
        run tar -xjf "${SOURCE_DIR}/${part}.tbz2" -C "${SOURCE_DIR}"
    done
    printf '%s\n' "${SOURCE_SHA256}" >"${SOURCE_ROOT}/.source-ready"
    EXTRACT_NOTE="$(pretty_path "${SOURCE_ROOT}")"
fi
[[ -d "${KERNEL_DIR}" ]] || fail "kernel source not found at ${KERNEL_DIR}"
[[ -f "${SOURCE_DIR}/Makefile" ]] || fail "NVIDIA OOT module Makefile not found in ${SOURCE_DIR}"
end_step "${EXTRACT_NOTE}"

step "Configure kernel"
run make -C "${KERNEL_DIR}" mrproper
run make -C "${KERNEL_DIR}" defconfig
run "${KERNEL_DIR}/scripts/config" --file "${KERNEL_DIR}/.config" --set-val CONFIG_IP_SCTP m
run "${KERNEL_DIR}/scripts/config" --file "${KERNEL_DIR}/.config" --set-str CONFIG_LOCALVERSION "${KERNEL_LOCALVERSION}"
run make -C "${KERNEL_DIR}" olddefconfig
grep -qx 'CONFIG_IP_SCTP=m' "${KERNEL_DIR}/.config" ||
    fail "CONFIG_IP_SCTP=m is missing after olddefconfig" "Check ${KERNEL_DIR}/.config"
grep -qx "CONFIG_LOCALVERSION=\"${KERNEL_LOCALVERSION}\"" "${KERNEL_DIR}/.config" ||
    fail "CONFIG_LOCALVERSION is not \"${KERNEL_LOCALVERSION}\" after olddefconfig" "Check ${KERNEL_DIR}/.config"
KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" kernelrelease)"
end_step "CONFIG_IP_SCTP=m, release ${KERNEL_RELEASE}"

step "Build kernel Image and modules"
run make -C "${KERNEL_DIR}" -j"${BUILD_JOBS}" Image modules
end_step

step "Build NVIDIA OOT and display modules"
export KERNEL_HEADERS="${KERNEL_DIR}"
run make -C "${SOURCE_DIR}" -j"${BUILD_JOBS}" modules
end_step

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
        libssl-dev rsync 2>/dev/null || true
} >"${SOURCE_ROOT}/build-inputs.txt"

fmt_time TOTAL_TIME "${SECONDS}"
printf '\n%s in %s.\n' "${GREEN}${BOLD}Built ${KERNEL_RELEASE}${RESET}" "${TOTAL_TIME}"
field "Record" "$(pretty_path "${SOURCE_ROOT}/build-inputs.txt")"
field "Log" "$(pretty_path "${LOG_FILE}")"
printf '\nNext: %s\n' "${BOLD}${TOOL} install${RESET}"
