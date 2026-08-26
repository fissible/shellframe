#!/usr/bin/env bash
# src/widgets/spinner.sh — Feedback widgets for long-running work (#52)
#
#   shellframe_spinner 'msg' -- cmd [args...]   run cmd; animate on tty;
#                                               returns cmd's exit status;
#                                               cmd's stdout/stderr pass through
#   shellframe_progress <cur> <total> [label]   idempotent same-line bar
#   shellframe_status 'text'                    idempotent single-line status
#
# TTY behavior: animation/bar updates write to fd 7..3-style persistent fd
# rules do NOT apply here — these widgets target standalone scripts that have
# NOT entered the alternate screen. They write to /dev/tty directly so output
# survives $() capture, and degrade to plain text lines (or nothing) when
# /dev/tty is unavailable.
#
# Globals:
#   SHELLFRAME_SPINNER_FRAMES   animation frames (default "|/-\\")
#   SHELLFRAME_SPINNER_INTERVAL animation step seconds (default 0.15)
#   SHELLFRAME_PROGRESS_WIDTH   bar width in columns (default 20)

SHELLFRAME_SPINNER_FRAMES="${SHELLFRAME_SPINNER_FRAMES:-|/-\\}"
SHELLFRAME_SPINNER_INTERVAL="${SHELLFRAME_SPINNER_INTERVAL:-0.15}"
SHELLFRAME_PROGRESS_WIDTH="${SHELLFRAME_PROGRESS_WIDTH:-20}"

# Internal: best-effort line to the terminal; success = tty reachable.
_sf_spin_line() {
    printf '%s' "$1" >/dev/tty 2>/dev/null
}

# ── shellframe_progress <current> <total> [label] ─────────────────────────────
# Render an inline progress bar on the current line. Safe to call repeatedly
# from a loop: each call repaints the same line via \r + clear-to-EOL.
shellframe_progress() {
    local _cur="$1" _total="$2" _label="${3:-}"
    [[ "$_cur" =~ ^[0-9]+$ && "$_total" =~ ^[0-9]+$ ]] || return 2
    ((_total <= 0)) && { _total=1; _cur=0; }
    ((_cur > _total)) && _cur=$_total

    local _w="${SHELLFRAME_PROGRESS_WIDTH}"
    local _filled=$(( (_cur * _w) / _total ))
    local _empty=$(( _w - _filled ))
    local _pct=$(( (_cur * 100) / _total ))

    local _bar=""
    local _i=0
    while (( _i < _filled )); do _bar+='█'; (( _i++ )); done
    _i=0
    while (( _i < _empty )); do _bar+='░'; (( _i++ )); done

    local _line="$_label [${_bar}] ${_pct}%"
    if [[ -t 2 ]]; then
        printf '\r\033[2K%s' "$_line" >&2
    else
        printf '%s\n' "$_line"      # non-tty degradation: plain lines (#52)
    fi
}

# ── shellframe_status 'text' ──────────────────────────────────────────────────
# Single-line status: repaints the current line with 'text'. Pair with
# shellframe_progress-style loops or call between long steps.
shellframe_status() {
    if [[ -t 2 ]]; then
        printf '\r\033[2K%s' "$1" >&2
    else
        printf '%s\n' "$1"
    fi
}

# ── shellframe_spinner 'msg' -- cmd [args...] ─────────────────────────────────
shellframe_spinner() {
    local _msg="$1"
    shift
    [[ "${1:-}" == "--" ]] && shift
    (($# == 0)) && return 2

    if [[ -t 2 ]]; then
        (
            trap 'exit 0' TERM INT
            local _i=0
            local _frames="$SHELLFRAME_SPINNER_FRAMES"
            local _n=${#_frames}
            while :; do
                printf '\r\033[2K%s %s' "$_msg" "${_frames:_i:1}" >&2 2>/dev/null || exit 0
                _i=$(( (_i + 1) % _n ))
                sleep "$SHELLFRAME_SPINNER_INTERVAL"
            done
        ) &
        local _anim=$!
    else
        # stderr, not stdout: the wrapper must not pollute $() capture of the
        # command's output in non-tty contexts (CI, cron, pipes) — review round 3.
        printf '%s...\n' "$_msg" >&2
    fi

    "$@"
    local _rc=$?

    if [[ -n "${_anim:-}" ]]; then
        kill "$_anim" 2>/dev/null
        wait "$_anim" 2>/dev/null
        printf '\r\033[2K' >&2 2>/dev/null
    fi
    return $_rc
}
