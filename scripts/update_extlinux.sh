#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
    printf 'Usage: %s <extlinux.conf> <kernel-release> <activate:0|1>\n' "$0" >&2
    exit 2
fi

CONFIG_PATH="$1"
KERNEL_RELEASE="$2"
ACTIVATE="$3"
LABEL="oai-sctp"
IMAGE_PATH="/boot/Image-${KERNEL_RELEASE}"
INITRD_PATH="/boot/initrd.img-${KERNEL_RELEASE}"

[[ -f "${CONFIG_PATH}" ]] || {
    printf 'ERROR: %s does not exist\n' "${CONFIG_PATH}" >&2
    exit 1
}
[[ "${ACTIVATE}" == "0" || "${ACTIVATE}" == "1" ]] || {
    printf 'ERROR: activate must be 0 or 1\n' >&2
    exit 2
}

ROOT_LINE="$(
    awk '
        /^[[:space:]]*LABEL[[:space:]]+primary[[:space:]]*$/ { in_primary=1; next }
        in_primary && /^[[:space:]]*LABEL[[:space:]]+/ { in_primary=0 }
        in_primary && /^[[:space:]]*APPEND[[:space:]]+/ {
            sub(/^[[:space:]]*/, "")
            print
            exit
        }
    ' "${CONFIG_PATH}"
)"
if [[ -z "${ROOT_LINE}" ]]; then
    ROOT_LINE="$(awk '/^[[:space:]]*APPEND[[:space:]]+/ {sub(/^[[:space:]]*/, ""); print; exit}' "${CONFIG_PATH}")"
fi
[[ -n "${ROOT_LINE}" ]] || {
    printf 'ERROR: no APPEND line found in %s\n' "${CONFIG_PATH}" >&2
    exit 1
}

TMP_PATH="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
trap 'rm -f "${TMP_PATH}"' EXIT

awk '
    function emit(line) {
        if (line ~ /^[[:space:]]*$/) {
            blanks++
            return
        }
        while (blanks > 0) {
            print ""
            blanks--
        }
        print line
    }
    /^[[:space:]]*LABEL[[:space:]]+oai-sctp[[:space:]]*$/ { skip=1; next }
    skip && /^[[:space:]]*LABEL[[:space:]]+/ { skip=0 }
    !skip { emit($0) }
' "${CONFIG_PATH}" >"${TMP_PATH}"

{
    printf '\nLABEL %s\n' "${LABEL}"
    printf '      MENU LABEL custom SCTP kernel %s\n' "${KERNEL_RELEASE}"
    printf '      LINUX %s\n' "${IMAGE_PATH}"
    printf '      INITRD %s\n' "${INITRD_PATH}"
    printf '      %s\n' "${ROOT_LINE}"
} >>"${TMP_PATH}"

if [[ "${ACTIVATE}" == "1" ]]; then
    ACTIVE_PATH="$(mktemp "${CONFIG_PATH}.active.XXXXXX")"
    trap 'rm -f "${TMP_PATH}" "${ACTIVE_PATH}"' EXIT
    awk '
        BEGIN { replaced=0 }
        /^[[:space:]]*DEFAULT[[:space:]]+/ && !replaced {
            print "DEFAULT oai-sctp"
            replaced=1
            next
        }
        { print }
        END {
            if (!replaced) print "DEFAULT oai-sctp"
        }
    ' "${TMP_PATH}" >"${ACTIVE_PATH}"
    cp "${ACTIVE_PATH}" "${TMP_PATH}"
fi

cat "${TMP_PATH}" >"${CONFIG_PATH}"
printf 'Updated %s with LABEL %s\n' "${CONFIG_PATH}" "${LABEL}"
