#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $0 [--verbose]

Check the running kernel after a reboot: architecture, kernel release, the
sctp module, SCTP socket support and the NVIDIA driver stack.

Options:
  -v, --verbose  Also show the full modinfo and nvidia-smi output
  -h, --help     Show this help

Environment:
  JETSON_KERNEL_EXPECTED_MARKER  Text expected in uname -r (default: oai-sctp)
EOF
}

for arg in "$@"; do
    case "${arg}" in
        -v | --verbose) VERBOSE=1 ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option: ${arg}" "Run $0 --help to see the options." ;;
    esac
done

EXPECTED_MARKER="${JETSON_KERNEL_EXPECTED_MARKER:-oai-sctp}"
ARCH="$(uname -m)"
KERNEL_RELEASE="$(uname -r)"
CHECKS=0
FAILED=0

# passed <name> <detail> [output]
passed() {
    local line
    CHECKS=$((CHECKS + 1))
    printf '  %s %-15s %s\n' "${GREEN}${OK_MARK}${RESET}" "$1" "$2"
    if (( VERBOSE == 1 )) && [[ -n "${3:-}" ]]; then
        while IFS= read -r line; do
            printf '      %s\n' "${DIM}${line}${RESET}"
        done <<<"$3"
    fi
}

# failed <name> <detail> <hint>
failed() {
    CHECKS=$((CHECKS + 1))
    FAILED=$((FAILED + 1))
    printf '  %s %-15s %s\n' "${RED}${FAIL_MARK}${RESET}" "$1" "$2"
    printf '    %-15s %s\n' "" "${DIM}$3${RESET}"
}

header "verify"
need_sudo "load the sctp module"

if [[ "${ARCH}" == "aarch64" ]]; then
    passed "Architecture" "${ARCH}"
else
    failed "Architecture" "${ARCH}" "Run this script on the Jetson."
fi

if [[ "${KERNEL_RELEASE}" == *"${EXPECTED_MARKER}"* ]]; then
    passed "Kernel" "${KERNEL_RELEASE}"
else
    failed "Kernel" "${KERNEL_RELEASE}, expected a release with ${EXPECTED_MARKER}" \
        "Boot the oai-sctp entry: ${TOOL} activate, then reboot."
fi

if OUTPUT="$(sudo modprobe sctp 2>&1)"; then
    passed "SCTP module" "$(modinfo -n sctp)" "$(modinfo sctp)"
else
    failed "SCTP module" "${OUTPUT:-modprobe sctp failed}" \
        "This kernel has no sctp module. Boot the oai-sctp entry."
fi

if command -v checksctp >/dev/null 2>&1; then
    if OUTPUT="$(checksctp 2>&1)"; then
        passed "SCTP sockets" "${OUTPUT}"
    else
        failed "SCTP sockets" "${OUTPUT}" "The kernel refuses SCTP sockets. Check that the sctp module is loaded."
    fi
elif ss -A sctp -a >/dev/null 2>&1; then
    passed "SCTP sockets" "socket query works (install lksctp-tools for checksctp)"
else
    failed "SCTP sockets" "ss -A sctp failed" "Install lksctp-tools, then run checksctp."
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
    failed "NVIDIA driver" "nvidia-smi not found" "Install the NVIDIA JetPack userspace packages."
elif OUTPUT="$(nvidia-smi 2>&1)"; then
    passed "NVIDIA driver" "$(grep -o 'Driver Version: [^ ]*' <<<"${OUTPUT}" || printf 'nvidia-smi works')" "${OUTPUT}"
else
    failed "NVIDIA driver" "nvidia-smi failed" \
        "The NVIDIA OOT modules may not match this kernel. Check 'sudo dmesg' for module errors."
fi

printf '\n'
(( FAILED == 0 )) || fail "${FAILED} of ${CHECKS} checks failed"
printf '%s SCTP and the NVIDIA driver work on %s.\n' "${GREEN}${BOLD}All ${CHECKS} checks passed.${RESET}" "${KERNEL_RELEASE}"
