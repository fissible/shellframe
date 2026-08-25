#!/usr/bin/env bash
# tests/fixtures/confirm-eof.sh — v1 confirm widget with detached stdin (#44)
#
# shellframe_read_key's untimed first read hits EOF instantly; the widget
# loop must exit cancelled instead of spinning at 100% CPU.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/shellframe.sh"

exec 0</dev/null

shellframe_confirm "Proceed?"
printf 'confirm-rc:%d\n' "$?"
