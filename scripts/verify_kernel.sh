#!/usr/bin/env bash

set -euo pipefail

EXPECTED_MARKER="${JETSON_KERNEL_EXPECTED_MARKER:-oai-sctp}"
KERNEL_RELEASE="$(uname -r)"

printf '%s\n' "=== Jetson SCTP Kernel Verification ==="
printf 'kernel_release=%s\n' "${KERNEL_RELEASE}"
printf 'architecture=%s\n' "$(uname -m)"

[[ "$(uname -m)" == "aarch64" ]] || {
    printf 'ERROR: expected aarch64\n' >&2
    exit 1
}
[[ "${KERNEL_RELEASE}" == *"${EXPECTED_MARKER}"* ]] || {
    printf 'ERROR: running kernel does not contain marker %s\n' "${EXPECTED_MARKER}" >&2
    exit 1
}

sudo modprobe sctp
modinfo sctp | sed -n '1,12p'

if command -v checksctp >/dev/null 2>&1; then
    checksctp
else
    ss -A sctp -a >/dev/null
    printf '%s\n' "checksctp is unavailable; SCTP socket-family query succeeded"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
else
    printf 'ERROR: nvidia-smi is unavailable\n' >&2
    exit 1
fi

printf '%s\n' "PASS: custom kernel, SCTP module, and NVIDIA userspace are available"
