#!/usr/bin/env bash
# tests/unit/test-clip.sh — Unit tests for shellframe/src/clip.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/draw.sh"   # for SHELLFRAME_BOLD, SHELLFRAME_RESET, etc.
source "$SHELLFRAME_DIR/src/clip.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── shellframe_str_len ─────────────────────────────────────────────────────────

ptyunit_test_begin "str_len: empty string"
assert_output "0" shellframe_str_len ""

ptyunit_test_begin "str_len: ASCII string"
assert_output "5" shellframe_str_len "hello"

ptyunit_test_begin "str_len: longer string"
assert_output "11" shellframe_str_len "hello world"

# ── shellframe_str_clip — no-op (string fits) ──────────────────────────────────

ptyunit_test_begin "str_clip: exact fit — unchanged"
assert_output "hello" shellframe_str_clip "hello" "hello" 5

ptyunit_test_begin "str_clip: string shorter than width — unchanged"
assert_output "hi" shellframe_str_clip "hi" "hi" 10

ptyunit_test_begin "str_clip: empty string — unchanged"
assert_output "" shellframe_str_clip "" "" 5

ptyunit_test_begin "str_clip: width zero — prints nothing"
assert_output "" shellframe_str_clip "hello" "hello" 0

# ── shellframe_str_clip — truncation (plain text) ──────────────────────────────

ptyunit_test_begin "str_clip: plain text — hard clip"
assert_output "hello" shellframe_str_clip "hello world" "hello world" 5

ptyunit_test_begin "str_clip: plain text — clip to 1"
assert_output "h" shellframe_str_clip "hello" "hello" 1

ptyunit_test_begin "str_clip: plain text — clip to exact length"
assert_output "hello" shellframe_str_clip "hello world" "hello world" 5

# ── shellframe_str_clip — ANSI rendered strings ────────────────────────────────
#
# These tests use hard-coded SGR escape sequences rather than tput-derived
# SHELLFRAME_* constants. tput returns empty string when $TERM is unset
# (e.g. inside Docker), which would collapse rendered strings to plain text
# and make the ANSI code paths unreachable.

_BOLD=$'\033[1m'
_GREEN=$'\033[32m'
_RESET=$'\033[0m'

ptyunit_test_begin "str_clip: ANSI rendered — fits, unchanged"
raw="hi"
rendered="${_BOLD}hi${_RESET}"
result=$(shellframe_str_clip "$raw" "$rendered" 5)
assert_eq "$rendered" "$result" "ANSI string fits — should be unchanged"

ptyunit_test_begin "str_clip: plain text — no reset appended when no ANSI present"
# Plain-text rendered: clipped output should be a clean substring, no extra bytes.
raw="hello world"
rendered="hello world"
result=$(shellframe_str_clip "$raw" "$rendered" 5)
assert_eq "hello" "$result" "plain text clip — no reset appended"

ptyunit_test_begin "str_clip: ANSI rendered — clip appends reset to prevent color bleed"
# ANSI-colored rendered: truncating mid-ANSI region must append reset.
raw="hello world"
rendered="${_GREEN}hello world${_RESET}"
result=$(shellframe_str_clip "$raw" "$rendered" 5)
# Visible content should be "hello" (ANSI sequences stripped)
result_vis="${result//$_GREEN/}"
result_vis="${result_vis//$_RESET/}"
assert_eq "hello" "$result_vis" "ANSI clip — visible content is 5 chars"
# Reset must be present to prevent color bleed
assert_contains "$result" $'\033[0m' "ANSI clip — reset appended"

ptyunit_test_begin "str_clip: ANSI rendered — ANSI before clip point preserved"
# rendered: BOLD prefix + text; raw: just text
# Clip at 3 chars: ESC sequence + first 3 chars of text + reset
raw="abcde"
rendered="${_BOLD}abcde${_RESET}"
result=$(shellframe_str_clip "$raw" "$rendered" 3)
# Key: result must contain "abc" and not contain "de"
assert_contains "$result" "abc" "clip preserves leading ANSI and shows first 3 chars"
result_no_ansi="${result//$_BOLD/}"
result_no_ansi="${result_no_ansi//$_RESET/}"
assert_eq "abc" "$result_no_ansi" "clip visible content is exactly 3 chars"

# ── shellframe_str_clip_ellipsis — no-op (string fits) ────────────────────────

ptyunit_test_begin "str_clip_ellipsis: exact fit — unchanged (no ellipsis)"
assert_output "hello" shellframe_str_clip_ellipsis "hello" "hello" 5

ptyunit_test_begin "str_clip_ellipsis: string shorter than width — unchanged"
assert_output "hi" shellframe_str_clip_ellipsis "hi" "hi" 10

ptyunit_test_begin "str_clip_ellipsis: width zero — prints nothing"
assert_output "" shellframe_str_clip_ellipsis "hello" "hello" 0

ptyunit_test_begin "str_clip_ellipsis: width one — prints only ellipsis"
assert_output "…" shellframe_str_clip_ellipsis "hello" "hello" 1

# ── shellframe_str_clip_ellipsis — truncation ─────────────────────────────────

ptyunit_test_begin "str_clip_ellipsis: plain text — clip with ellipsis"
result=$(shellframe_str_clip_ellipsis "hello world" "hello world" 6)
# "hello " (5 chars) + "…" — but clip walk emits "hello" then reset then "…"
# Strip the injected reset to check visible content
result_vis="${result//$'\033[0m'/}"
assert_eq "hello…" "$result_vis" "ellipsis clip visible content"

ptyunit_test_begin "str_clip_ellipsis: width 2 — one char + ellipsis"
result=$(shellframe_str_clip_ellipsis "hello" "hello" 2)
result_vis="${result//$'\033[0m'/}"
assert_eq "h…" "$result_vis" "width 2 gives one char + ellipsis"

# ── shellframe_str_pad ─────────────────────────────────────────────────────────

ptyunit_test_begin "str_pad: exact width — no padding"
assert_output "hello" shellframe_str_pad "hello" "hello" 5

ptyunit_test_begin "str_pad: shorter — pads with spaces"
result=$(shellframe_str_pad "hi" "hi" 5)
assert_eq "hi   " "$result" "padded to 5"

ptyunit_test_begin "str_pad: empty string — all spaces"
result=$(shellframe_str_pad "" "" 4)
assert_eq "    " "$result" "empty string padded to 4 spaces"

ptyunit_test_begin "str_pad: longer than width — no truncation"
result=$(shellframe_str_pad "toolong" "toolong" 4)
assert_eq "toolong" "$result" "wider string not truncated"

ptyunit_test_begin "str_pad: ANSI rendered — width from raw"
raw="hi"
rendered="${_GREEN}hi${_RESET}"
result=$(shellframe_str_pad "$raw" "$rendered" 5)
expected="${_GREEN}hi${_RESET}   "
assert_eq "$expected" "$result" "ANSI rendered padded by raw width"

ptyunit_test_summary
