#!/usr/bin/env bash
# tests/fixtures/shell-eof.sh — shellframe_shell with detached stdin (#44)
#
# fd 0 points at /dev/null while /dev/tty (fd 3) stays open: exactly the
# "tty detached, stdin closed" case where the input loop must quit instead
# of busy-spinning on instant-EOF reads.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/shellframe.sh"
printf 'sourced\n' >&8

exec 0</dev/null
printf 'fd0-detached\n' >&8

_sl_ITEMS=("apple")
SHELLFRAME_LIST_CTX="sl"
SHELLFRAME_LIST_ITEMS=("${_sl_ITEMS[@]}")
shellframe_list_init "sl" 10
printf 'list-init done\n' >&8

_sl_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region "list" 1 1 "$_cols" "$(( _rows - 1 ))"
}

printf 'before-shell\n' >&8
shellframe_shell "_sl" "ROOT"
_sf_rc=$?
printf 'shell-returned:%d\n' "$_sf_rc"
