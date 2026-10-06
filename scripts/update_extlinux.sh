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

[[ -f "${CONFIG_PATH}" ]] || {
    printf 'ERROR: %s does not exist\n' "${CONFIG_PATH}" >&2
    exit 1
}
[[ "${ACTIVATE}" == "0" || "${ACTIVATE}" == "1" ]] || {
    printf 'ERROR: activate must be 0 or 1\n' >&2
    exit 2
}

# Copy every boot option of the stock entry (APPEND, FDT, OVERLAYS), so the
# custom entry differs from it only by its kernel image and initrd.
PRIMARY_OPTIONS="$(
    awk '
        $1 == "LABEL" { in_primary = ($2 == "primary"); next }
        in_primary && NF && $1 !~ /^#/ && $1 != "MENU" && $1 != "LINUX" && $1 != "INITRD" {
            sub(/^[[:space:]]*/, "      ")
            print
        }
    ' "${CONFIG_PATH}"
)"
# The stock entry is the rollback path, so refuse to continue without it.
grep -q '^ *APPEND ' <<<"${PRIMARY_OPTIONS}" || {
    printf 'ERROR: no LABEL primary entry with an APPEND line in %s\n' "${CONFIG_PATH}" >&2
    exit 1
}

TMP_PATH="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
trap 'rm -f "${TMP_PATH}"' EXIT

awk -v activate="${ACTIVATE}" -v label="${LABEL}" '
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
    $1 == "LABEL" { skip = ($2 == label) }
    skip { next }
    activate == 1 && $1 == "DEFAULT" && !defaulted {
        $0 = "DEFAULT " label
        defaulted = 1
    }
    { emit($0) }
    END {
        if (activate == 1 && !defaulted) print "DEFAULT " label
    }
' "${CONFIG_PATH}" >"${TMP_PATH}"

{
    printf '\nLABEL %s\n' "${LABEL}"
    printf '      MENU LABEL custom SCTP kernel %s\n' "${KERNEL_RELEASE}"
    printf '      LINUX /boot/Image-%s\n' "${KERNEL_RELEASE}"
    printf '      INITRD /boot/initrd.img-%s\n' "${KERNEL_RELEASE}"
    printf '%s\n' "${PRIMARY_OPTIONS}"
} >>"${TMP_PATH}"

# One rename replaces the file, so an interrupted run never leaves a
# truncated boot configuration.
chmod --reference="${CONFIG_PATH}" "${TMP_PATH}"
chown --reference="${CONFIG_PATH}" "${TMP_PATH}"
mv -f "${TMP_PATH}" "${CONFIG_PATH}"
printf 'Updated %s with LABEL %s\n' "${CONFIG_PATH}" "${LABEL}"
