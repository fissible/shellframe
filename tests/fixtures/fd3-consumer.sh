#!/usr/bin/env bash
# tests/fixtures/fd3-consumer.sh — consumer owning fd 3 across a v1 widget (#48)
set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

_out_file="${SF48_OUT:?output file required}"
exec 3>"$_out_file"
printf 'before\n' >&3

answer=$(shellframe_confirm "Proceed?")
printf 'after rc=%s answer=%s\n' "$?" "$answer" >&3
