# shellcheck shell=bash disable=SC2034 # the variables are used by the files that source this one
# Shared paths and terminal output for jetson-sctp and the scripts it runs.
# Each caller sets SCRIPT_DIR to this directory, then sources this file.

REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../sources.env
source "${REPO_DIR}/sources.env"

WORKSPACE_DIR="${JETSON_KERNEL_WORKSPACE:-${HOME}/jetson-kernel-build}"
SOURCE_ROOT="${WORKSPACE_DIR}/sources/${L4T_VERSION}-${SOURCE_SHA256:0:12}"
SOURCE_DIR="${SOURCE_ROOT}/Linux_for_Tegra/source"
KERNEL_DIR="${SOURCE_DIR}/kernel/kernel-jammy-src"
EXTLINUX_CONF="${JETSON_EXTLINUX_CONF:-/boot/extlinux/extlinux.conf}"
# The text that marks the custom kernel in "uname -r", without the leading dash
CUSTOM_MARKER="${KERNEL_LOCALVERSION#-}"

VERBOSE=0
LOG_FILE=""
STEP_NUM=0
STEP_TOTAL=0
STEP_LINE=""
STEP_START=0
FAIL_MESSAGE=""
FAIL_HINT=""
ERR_COMMAND=""
SHOW_LOG_TAIL=0
TERM_COLS=80

# A terminal gets colors and one live status line per step. Pipes, CI logs
# and --verbose get the full command output instead.
TTY=0
BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" RESET=""
if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
    TTY=1
    if [[ -z "${NO_COLOR:-}" ]]; then
        BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m'
        YELLOW=$'\e[33m' CYAN=$'\e[36m' RESET=$'\e[0m'
    fi
fi
OK_MARK="ok" FAIL_MARK="!!" RUN_MARK=">" BAR="|" DOT="-"
if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]]; then
    OK_MARK="✓" FAIL_MARK="✗" RUN_MARK="▸" BAR="│" DOT="·"
fi

live() {
    (( TTY == 1 && VERBOSE == 0 ))
}

# pretty_path <path>: shorten the home directory to ~
pretty_path() {
    local path=$1
    [[ "${path}" != "${HOME}"/* ]] || path="~${path#"${HOME}"}"
    printf '%s' "${path}"
}

# fmt_time <variable> <seconds>: m:ss, or h:mm:ss from one hour
fmt_time() {
    local seconds=$2
    if (( seconds >= 3600 )); then
        printf -v "$1" '%d:%02d:%02d' $((seconds / 3600)) $((seconds % 3600 / 60)) $((seconds % 60))
    else
        printf -v "$1" '%d:%02d' $((seconds / 60)) $((seconds % 60))
    fi
}

# How to type the main command from the current directory, for hints
if [[ "${PWD}" == "${REPO_DIR}" ]]; then
    TOOL="./jetson-sctp"
else
    TOOL="$(pretty_path "${REPO_DIR}/jetson-sctp")"
fi

header() {
    printf '%s %s %s\n' "${BOLD}Jetson Orin Nano SCTP kernel${RESET}" "${DIM}${DOT}${RESET}" "${BOLD}$1${RESET}"
}

field() {
    printf '  %s%-10s%s %s\n' "${DIM}" "$1" "${RESET}" "$2"
}

warn() {
    printf '%s %s\n' "${YELLOW}${BOLD}warning:${RESET}" "$1" >&2
}

# fail <message> [hint]: stop with a message. The hint may span several lines.
fail() {
    FAIL_MESSAGE=$1
    FAIL_HINT=${2:-}
    exit 1
}

# confirm <question> <y|n>: ask a yes/no question. The second argument is
# the answer for Enter, and also the answer when there is no terminal.
confirm() {
    local answer choices="[Y/n]"
    [[ "$2" == "y" ]] || choices="[y/N]"
    if [[ -t 0 ]]; then
        read -r -p "$1 ${choices} " answer || answer=""
    fi
    answer="${answer:-$2}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# start_log <name>: write all command output to a new file in the workspace
start_log() {
    mkdir -p "${WORKSPACE_DIR}/logs"
    LOG_FILE="${WORKSPACE_DIR}/logs/$1-$(date -u +%Y%m%dT%H%M%SZ).log"
}

# backup_extlinux: numbered step that copies extlinux.conf to a timestamped file
backup_extlinux() {
    BACKUP_PATH="${EXTLINUX_CONF}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    step "Back up extlinux.conf"
    run sudo cp -p "${EXTLINUX_CONF}" "${BACKUP_PATH}"
    end_step "${BACKUP_PATH}"
}

need_sudo() {
    sudo -n true 2>/dev/null && return 0
    printf '%s\n' "${DIM}sudo is needed to $1.${RESET}"
    sudo -v || fail "sudo authentication failed"
}

# draw <mark> <color> <detail>: rewrite the terminal line of the running step
draw() {
    local elapsed main room detail=${3//[[:cntrl:]]/ }
    detail=${detail#"${detail%%[![:space:]]*}"}
    fmt_time elapsed $((SECONDS - STEP_START))
    printf -v main '%-42s %7s' "${STEP_LINE}" "${elapsed}"
    room=$((TERM_COLS - ${#main} - 5))
    if (( room < 1 )); then
        main=${main:0:TERM_COLS - 3}
        room=0
    fi
    printf '\r\e[K%s %s  %s' "$2$1${RESET}" "${main}" "${DIM}${detail:0:room}${RESET}"
}

# step <title>: start the next numbered step
step() {
    end_step
    STEP_NUM=$((STEP_NUM + 1))
    printf -v STEP_LINE '[%d/%d] %s' "${STEP_NUM}" "${STEP_TOTAL}" "$1"
    STEP_START=${SECONDS}
    [[ -z "${LOG_FILE}" ]] || printf '\n==> %s\n' "${STEP_LINE}" >>"${LOG_FILE}"
    if live; then
        TERM_COLS="$(tput cols 2>/dev/null || printf 80)"
        draw "${RUN_MARK}" "${CYAN}" ""
    else
        printf '%s %s\n' "${CYAN}${RUN_MARK}${RESET}" "${BOLD}${STEP_LINE}${RESET}"
    fi
}

# end_step [note]: mark the running step as done
end_step() {
    local elapsed
    [[ -n "${STEP_LINE}" ]] || return 0
    fmt_time elapsed $((SECONDS - STEP_START))
    if live; then
        printf '\r\e[K'
    fi
    printf '%s %-42s %7s  %s\n' "${GREEN}${OK_MARK}${RESET}" "${STEP_LINE}" "${elapsed}" "${DIM}${1:-}${RESET}"
    STEP_LINE=""
}

# follow: show the newest output line beside the step, with a running clock
follow() {
    local line="" next
    while :; do
        if IFS= read -r -t 1 next; then
            line=${next}
        elif (( $? <= 128 )); then
            break
        fi
        draw "${RUN_MARK}" "${CYAN}" "${line}"
    done
}

# run <command...>: run a command, keep its full output in the log
run() {
    local status=0
    printf '$ %s\n' "$*" >>"${LOG_FILE}"
    if live; then
        "$@" </dev/null 2>&1 | tee -a "${LOG_FILE}" | follow || status=$?
    else
        "$@" </dev/null 2>&1 | tee -a "${LOG_FILE}" || status=$?
    fi
    if (( status != 0 )); then
        SHOW_LOG_TAIL=1
        fail "command failed with exit status ${status}" "$*"
    fi
}

on_exit() {
    local status=$? elapsed line
    (( status != 0 )) || return 0
    if [[ -n "${STEP_LINE}" ]]; then
        fmt_time elapsed $((SECONDS - STEP_START))
        if live; then
            printf '\r\e[K'
        fi
        printf '%s %-42s %7s\n' "${RED}${FAIL_MARK}${RESET}" "${STEP_LINE}" "${elapsed}"
        if (( SHOW_LOG_TAIL == 1 )) && live; then
            while IFS= read -r line; do
                printf '  %s %s\n' "${DIM}${BAR}${RESET}" "${line}"
            done < <(tail -n 15 "${LOG_FILE}")
        fi
    fi
    [[ -n "${FAIL_MESSAGE}" ]] || FAIL_MESSAGE="command failed with exit status ${status}"
    [[ -n "${FAIL_HINT}" || -z "${ERR_COMMAND}" ]] || FAIL_HINT=${ERR_COMMAND}
    printf '%s %s\n' "${RED}${BOLD}error:${RESET}" "${FAIL_MESSAGE}" >&2
    if [[ -n "${FAIL_HINT}" ]]; then
        while IFS= read -r line; do
            printf '       %s\n' "${line}" >&2
        done <<<"${FAIL_HINT}"
    fi
    if [[ -n "${LOG_FILE}" && -f "${LOG_FILE}" ]]; then
        printf '       %s\n' "${DIM}Full log: $(pretty_path "${LOG_FILE}")${RESET}" >&2
    fi
}

set -o errtrace
trap '[[ -n "${ERR_COMMAND}" ]] || ERR_COMMAND=${BASH_COMMAND}' ERR
trap 'FAIL_MESSAGE="interrupted"; exit 130' INT TERM
trap on_exit EXIT
