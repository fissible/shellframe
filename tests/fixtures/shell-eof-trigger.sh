#!/usr/bin/env bash
# tests/fixtures/shell-eof-trigger.sh — deterministic stdin-detach lifecycle (#63)
#
# Replaces the fifo/sleep design whose wall-clock EOF raced CI runners
# (~2/7 rc-124 flakes on macOS 3.2). Here the TEST causes EOF: the 'E'
# keystroke detaches stdin (exec 0</dev/null), so the very next runtime
# read observes a genuine EOF — key ordering, not elapsed time, decides.
#
# Prints "detached-shell-returned:<rc>" after the runtime exits; the
# runtime must report 1 (its stdin-loss contract, #44).
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/shellframe.sh"

_sl_ITEMS=("apple")
SHELLFRAME_LIST_CTX="sl"
SHELLFRAME_LIST_ITEMS=("${_sl_ITEMS[@]}")
shellframe_list_init "sl" 10

_sl_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region "list" 1 1 "$_cols" "$(( _rows - 1 ))"
    shellframe_shell_region "footer" "$_rows" 1 "$_cols" 1 nofocus
}

_sl_ROOT_list_render() {
    SHELLFRAME_LIST_CTX="sl"
    shellframe_list_render "$@"
}

_sl_ROOT_list_on_key() {
    SHELLFRAME_LIST_CTX="sl"
    if [[ "$1" == "E" ]]; then
        exec 0</dev/null          # detach: EOF is now deterministic
        return 0
    fi
    shellframe_list_on_key "$1"
}

shellframe_shell "_sl" "ROOT"
_sf_rc=$?
printf 'detached-shell-returned:%d\n' "$_sf_rc"
