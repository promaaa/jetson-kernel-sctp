#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/extlinux.conf"
UPDATE="${REPO_DIR}/scripts/update_extlinux.sh"
RELEASE="5.15.148-oai-sctp"
TMP_DIR="$(mktemp -d)"
CONFIG="${TMP_DIR}/extlinux.conf"
trap 'rm -rf "${TMP_DIR}"' EXIT

# expect_failure <command...>: the command must fail and leave the file as is
expect_failure() {
    cp "${CONFIG}" "${TMP_DIR}/before.conf"
    if "$@" 2>/dev/null; then
        printf 'FAIL: this command succeeded: %s\n' "$*" >&2
        exit 1
    fi
    cmp "${TMP_DIR}/before.conf" "${CONFIG}"
}

cp "${FIXTURE}" "${CONFIG}"
chmod 0644 "${CONFIG}"

"${UPDATE}" add "${CONFIG}" "${RELEASE}" 0
grep -qx 'DEFAULT primary' "${CONFIG}"
[[ "$(grep -c '^LABEL oai-sctp$' "${CONFIG}")" == "1" ]]
[[ "$(stat --format='%a' "${CONFIG}")" == "644" ]]

# The custom entry boots the new kernel with the options of the stock entry.
sed -n '/^LABEL oai-sctp$/,$p' "${CONFIG}" >"${TMP_DIR}/entry.conf"
diff -u - "${TMP_DIR}/entry.conf" <<EOF
LABEL oai-sctp
      MENU LABEL custom SCTP kernel ${RELEASE}
      LINUX /boot/Image-${RELEASE}
      INITRD /boot/initrd.img-${RELEASE}
      FDT /boot/dtb/kernel_tegra234-p3768-0000+p3767-0005-nv.dtb
      APPEND \${cbootargs} root=PARTUUID=<root-partuuid> rw rootwait
EOF

cp "${CONFIG}" "${TMP_DIR}/added.conf"
"${UPDATE}" add "${CONFIG}" "${RELEASE}" 0
cmp "${TMP_DIR}/added.conf" "${CONFIG}"

"${UPDATE}" add "${CONFIG}" "${RELEASE}" 1
grep -qx 'DEFAULT oai-sctp' "${CONFIG}"
[[ "$(grep -c '^LABEL oai-sctp$' "${CONFIG}")" == "1" ]]
grep -qx 'LABEL primary' "${CONFIG}"
grep -qx 'LABEL recovery' "${CONFIG}"

# Rolling back and activating again only switch DEFAULT.
"${UPDATE}" default "${CONFIG}" primary
cmp "${TMP_DIR}/added.conf" "${CONFIG}"
"${UPDATE}" default "${CONFIG}" oai-sctp
grep -qx 'DEFAULT oai-sctp' "${CONFIG}"
expect_failure "${UPDATE}" default "${CONFIG}" missing-entry

# Removing the active entry gives back the stock file, with DEFAULT primary.
"${UPDATE}" remove "${CONFIG}"
cmp "${FIXTURE}" "${CONFIG}"
expect_failure "${UPDATE}" default "${CONFIG}" oai-sctp

# Without the stock entry there is no rollback path, so the file stays as is.
grep -v 'LABEL primary' "${FIXTURE}" >"${CONFIG}"
expect_failure "${UPDATE}" add "${CONFIG}" "${RELEASE}" 1

printf '%s\n' "PASS: extlinux add, default and remove keep the stock entries and are idempotent"
