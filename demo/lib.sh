# shellcheck shell=bash
# Shared by the fake commands in demo/bin.

# nap <seconds>: sleep, divided by DEMO_SPEED
nap() {
    sleep "$(awk -v s="$1" -v k="${DEMO_SPEED:-1}" 'BEGIN { print s / k }')"
}

running_release() {
    cat "${DEMO_DIR}/session/running"
}

running_custom() {
    [[ "$(running_release)" == *oai-sctp* ]]
}
