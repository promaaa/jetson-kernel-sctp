#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/extlinux.conf"
TMP_DIR="$(mktemp -d /tmp/jetson-extlinux-test.XXXXXX)"
CONFIG="${TMP_DIR}/extlinux.conf"
trap 'rm -rf "${TMP_DIR}"' EXIT

cp "${FIXTURE}" "${CONFIG}"

"${REPO_DIR}/scripts/update_extlinux.sh" "${CONFIG}" "5.15.148-oai-sctp-tegra" 0
grep -qx 'DEFAULT primary' "${CONFIG}"
grep -qx 'LABEL oai-sctp' "${CONFIG}"
grep -qx '      LINUX /boot/Image-5.15.148-oai-sctp-tegra' "${CONFIG}"
grep -qx '      INITRD /boot/initrd.img-5.15.148-oai-sctp-tegra' "${CONFIG}"
[[ "$(grep -c '^LABEL oai-sctp$' "${CONFIG}")" == "1" ]]

cp "${CONFIG}" "${TMP_DIR}/first.conf"
"${REPO_DIR}/scripts/update_extlinux.sh" "${CONFIG}" "5.15.148-oai-sctp-tegra" 0
cmp "${TMP_DIR}/first.conf" "${CONFIG}"

"${REPO_DIR}/scripts/update_extlinux.sh" "${CONFIG}" "5.15.148-oai-sctp-tegra" 1
grep -qx 'DEFAULT oai-sctp' "${CONFIG}"
[[ "$(grep -c '^LABEL oai-sctp$' "${CONFIG}")" == "1" ]]
grep -qx 'LABEL primary' "${CONFIG}"
grep -qx 'LABEL recovery' "${CONFIG}"

printf '%s\n' "PASS: extlinux update is idempotent and preserves recovery entries"
