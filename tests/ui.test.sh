#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${TEST_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

for script in build_kernel install_kernel verify_kernel; do
    "${ROOT_DIR}/scripts/${script}.sh" --help | grep -q '^Usage: '
    if "${ROOT_DIR}/scripts/${script}.sh" --bad-option 2>"${TMP_DIR}/error.txt"; then
        printf 'FAIL: %s accepted an unknown option\n' "${script}" >&2
        exit 1
    fi
    grep -q 'error: unknown option: --bad-option' "${TMP_DIR}/error.txt"
done

# Two steps through the shared output code: one passes, one fails.
status=0
(
    SCRIPT_DIR="${ROOT_DIR}/scripts"
    # shellcheck source=../scripts/common.sh
    source "${ROOT_DIR}/scripts/common.sh"
    LOG_FILE="${TMP_DIR}/steps.log"
    STEP_TOTAL=2
    step "First step"
    run printf 'first output\n'
    end_step "first note"
    step "Second step"
    run sh -c 'echo second output; exit 3'
    end_step
) >"${TMP_DIR}/steps.txt" 2>&1 || status=$?

[[ "${status}" == "1" ]]
grep -q '\[1/2\] First step .* first note$' "${TMP_DIR}/steps.txt"
grep -q '\[2/2\] Second step' "${TMP_DIR}/steps.txt"
grep -q '^error: command failed with exit status 3$' "${TMP_DIR}/steps.txt"
grep -q "sh -c echo second output; exit 3" "${TMP_DIR}/steps.txt"
grep -q 'Full log: ' "${TMP_DIR}/steps.txt"
grep -qx 'first output' "${TMP_DIR}/steps.log"
grep -qx 'second output' "${TMP_DIR}/steps.log"

# The main command picks the next step from the state of the board.
TOOL="${ROOT_DIR}/jetson-sctp"
"${TOOL}" help | grep -q '^Commands:'
if "${TOOL}" bogus 2>"${TMP_DIR}/error.txt"; then
    printf 'FAIL: jetson-sctp accepted an unknown command\n' >&2
    exit 1
fi
grep -q 'error: unknown command: bogus' "${TMP_DIR}/error.txt"

export JETSON_KERNEL_WORKSPACE="${TMP_DIR}/workspace"
export JETSON_EXTLINUX_CONF="${TMP_DIR}/extlinux.conf"
cp "${TEST_DIR}/fixtures/extlinux.conf" "${JETSON_EXTLINUX_CONF}"
"${TOOL}" </dev/null >"${TMP_DIR}/status.txt"
grep -q 'Run: .*jetson-sctp build$' "${TMP_DIR}/status.txt"

# shellcheck source=../sources.env
source "${ROOT_DIR}/sources.env"
BUILD_DIR="${JETSON_KERNEL_WORKSPACE}/sources/${L4T_VERSION}-${SOURCE_SHA256:0:12}"
mkdir -p "${BUILD_DIR}/Linux_for_Tegra/source/kernel/kernel-jammy-src/arch/arm64/boot"
touch "${BUILD_DIR}/Linux_for_Tegra/source/kernel/kernel-jammy-src/arch/arm64/boot/Image"
printf 'kernel_release=5.15.148-oai-sctp\n' >"${BUILD_DIR}/build-inputs.txt"
"${TOOL}" status >"${TMP_DIR}/status.txt"
grep -q 'Built .*5.15.148-oai-sctp' "${TMP_DIR}/status.txt"
grep -q 'Run: .*jetson-sctp install$' "${TMP_DIR}/status.txt"

# An entry without its files in /boot is a problem, and install fixes it.
"${ROOT_DIR}/scripts/update_extlinux.sh" add "${JETSON_EXTLINUX_CONF}" 5.15.148-test-oai-sctp 0 >/dev/null
"${TOOL}" status >"${TMP_DIR}/status.txt"
grep -q 'Installed .*/boot/Image-5.15.148-test-oai-sctp .* missing' "${TMP_DIR}/status.txt"
grep -q 'Run: .*jetson-sctp install$' "${TMP_DIR}/status.txt"

printf '%s\n' "PASS: scripts show help, reject unknown options, report failed steps and pick the next step"
