#!/usr/bin/env bash

set -euo pipefail

usage() {
    printf 'Usage: %s add <extlinux.conf> <kernel-release> <activate:0|1>\n' "$0" >&2
    printf '       %s default <extlinux.conf> <label>\n' "$0" >&2
    printf '       %s remove <extlinux.conf>\n' "$0" >&2
    exit 2
}

error() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

MODE="${1:-}"
CONFIG_PATH="${2:-}"
LABEL="oai-sctp"
DROP_ENTRY=1
NEW_DEFAULT=""
case "${MODE}:$#" in
    add:4)
        KERNEL_RELEASE="$3"
        [[ "$4" == "0" || "$4" == "1" ]] || usage
        [[ "$4" == "0" ]] || NEW_DEFAULT="${LABEL}"
        ;;
    default:3)
        DROP_ENTRY=0
        NEW_DEFAULT="$3"
        ;;
    remove:2) ;;
    *) usage ;;
esac
[[ -f "${CONFIG_PATH}" ]] || error "${CONFIG_PATH} does not exist"

has_label() {
    awk -v label="$1" '$1 == "LABEL" && $2 == label { found = 1 } END { exit !found }' "${CONFIG_PATH}"
}

if [[ "${MODE}" == "add" ]]; then
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
    grep -q '^ *APPEND ' <<<"${PRIMARY_OPTIONS}" ||
        error "no LABEL primary entry with an APPEND line in ${CONFIG_PATH}"
elif [[ "${MODE}" == "remove" ]]; then
    # Without its entry, a DEFAULT oai-sctp would point at nothing.
    if awk '$1 == "DEFAULT" { found = ($2 == "oai-sctp"); exit } END { exit !found }' "${CONFIG_PATH}"; then
        NEW_DEFAULT="primary"
    fi
fi
# A new DEFAULT must name an existing entry. The add mode writes its entry below.
if [[ -n "${NEW_DEFAULT}" && "${MODE}" != "add" ]]; then
    has_label "${NEW_DEFAULT}" || error "no LABEL ${NEW_DEFAULT} entry in ${CONFIG_PATH}"
fi

TMP_PATH="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
trap 'rm -f "${TMP_PATH}"' EXIT

awk -v drop="${DROP_ENTRY}" -v new_default="${NEW_DEFAULT}" -v label="${LABEL}" '
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
    $1 == "LABEL" { skip = (drop == 1 && $2 == label) }
    skip { next }
    $1 == "DEFAULT" && !defaulted {
        if (new_default != "") $0 = "DEFAULT " new_default
        defaulted = 1
    }
    { emit($0) }
    END {
        if (new_default != "" && !defaulted) print "DEFAULT " new_default
    }
' "${CONFIG_PATH}" >"${TMP_PATH}"

if [[ "${MODE}" == "add" ]]; then
    {
        printf '\nLABEL %s\n' "${LABEL}"
        printf '      MENU LABEL custom SCTP kernel %s\n' "${KERNEL_RELEASE}"
        printf '      LINUX /boot/Image-%s\n' "${KERNEL_RELEASE}"
        printf '      INITRD /boot/initrd.img-%s\n' "${KERNEL_RELEASE}"
        printf '%s\n' "${PRIMARY_OPTIONS}"
    } >>"${TMP_PATH}"
fi

# One rename replaces the file, so an interrupted run never leaves a
# truncated boot configuration.
chmod --reference="${CONFIG_PATH}" "${TMP_PATH}"
chown --reference="${CONFIG_PATH}" "${TMP_PATH}"
mv -f "${TMP_PATH}" "${CONFIG_PATH}"

case "${MODE}" in
    add) printf 'Updated %s with LABEL %s\n' "${CONFIG_PATH}" "${LABEL}" ;;
    default) printf 'Set DEFAULT %s in %s\n' "${NEW_DEFAULT}" "${CONFIG_PATH}" ;;
    remove) printf 'Removed LABEL %s from %s\n' "${LABEL}" "${CONFIG_PATH}" ;;
esac
