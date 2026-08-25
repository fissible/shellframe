#!/usr/bin/env bash
# examples/spinner-demo.sh — spinner wrapping a slow command (#52)
set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"
SHELLFRAME_SPINNER_INTERVAL=0.1
shellframe_spinner "working" -- bash -c 'sleep "${SPINNER_EXIT_DELAY:-0.3}"; exit ${SPINNER_EXIT:-0}'
