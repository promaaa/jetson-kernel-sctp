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

cp "${FIXTURE}" "${CONFIG}"
chmod 0644 "${CONFIG}"

"${UPDATE}" "${CONFIG}" "${RELEASE}" 0
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

cp "${CONFIG}" "${TMP_DIR}/first.conf"
"${UPDATE}" "${CONFIG}" "${RELEASE}" 0
cmp "${TMP_DIR}/first.conf" "${CONFIG}"

"${UPDATE}" "${CONFIG}" "${RELEASE}" 1
grep -qx 'DEFAULT oai-sctp' "${CONFIG}"
[[ "$(grep -c '^LABEL oai-sctp$' "${CONFIG}")" == "1" ]]
grep -qx 'LABEL primary' "${CONFIG}"
grep -qx 'LABEL recovery' "${CONFIG}"

# Without the stock entry there is no rollback path, so the file stays as is.
grep -v 'LABEL primary' "${FIXTURE}" >"${TMP_DIR}/no-primary.conf"
cp "${TMP_DIR}/no-primary.conf" "${TMP_DIR}/no-primary.orig"
if "${UPDATE}" "${TMP_DIR}/no-primary.conf" "${RELEASE}" 1 2>/dev/null; then
    printf 'FAIL: update accepted a configuration without LABEL primary\n' >&2
    exit 1
fi
cmp "${TMP_DIR}/no-primary.orig" "${TMP_DIR}/no-primary.conf"

printf '%s\n' "PASS: extlinux update copies the stock options, is idempotent and keeps rollback entries"
