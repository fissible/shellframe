#!/usr/bin/env bash
# examples/shell-list.sh — Minimal shellframe_shell app with a single list region.
#
# Used by tests/integration/test-mouse-routing.sh for IO validation of
# mouse click-to-select and scroll-wheel through a real PTY.
#
# Usage: ./shell-list.sh
# Prints the selected item label to stdout on Enter, or nothing if quit with q.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shellframe.sh"

# ── App state ─────────────────────────────────────────────────────────────────

_SL_ITEMS=("apple" "banana" "cherry" "date" "elderberry")
_SL_RESULT=""

SHELLFRAME_LIST_CTX="sl"
SHELLFRAME_LIST_ITEMS=("${_SL_ITEMS[@]}")
shellframe_list_init "sl" 10

# ── Screen definition ─────────────────────────────────────────────────────────

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
    shellframe_list_on_key "$1"
}

_sl_ROOT_list_on_mouse() {
    SHELLFRAME_LIST_CTX="sl"
    shellframe_list_on_mouse "$@"
}

_sl_ROOT_list_on_focus() {
    SHELLFRAME_LIST_FOCUSED="$1"
}

_sl_ROOT_list_action() {
    local _cursor
    shellframe_sel_cursor "sl" _cursor
    _SL_RESULT="${_SL_ITEMS[$_cursor]}"
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

_sl_ROOT_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    printf '\033[%d;%dH%-*s' "$_top" "$_left" "$_width" \
        " ↑/↓ move  click select  Enter confirm  q quit" >&3
}

_sl_ROOT_quit() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

# ── Run ───────────────────────────────────────────────────────────────────────

shellframe_shell "_sl" "ROOT"

[[ -n "$_SL_RESULT" ]] && printf 'Selected: %s\n' "$_SL_RESULT" || printf 'No selection.\n'
