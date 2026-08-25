#!/usr/bin/env bash
# tests/fixtures/shell-idle-eof.sh — idle-then-EOF lifecycle (#44)
#
# fd 0 is a fifo held open (no data) for HOLD seconds: the runtime must
# survive repeated timeout ticks (this is the bash 3.2 false-EOF regression
# window), then quit cleanly when the holder closes and reads hit EOF.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/shellframe.sh"

_fifo="${SHLVL:-0}_$$"   # unique per process without mktemp dependency
_fifo="${TMPDIR:-/tmp}/sf-idle-fifo.$$"
mkfifo "$_fifo"
( sleep 3 > "$_fifo" ) &
exec 0< "$_fifo"

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

shellframe_shell "_sl" "ROOT"
_sf_rc=$?
rm -f "$_fifo"
printf 'idle-shell-returned:%d\n' "$_sf_rc"
