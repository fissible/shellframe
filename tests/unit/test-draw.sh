#!/usr/bin/env bash
# tests/unit/test-draw.sh — Unit tests for clui/src/draw.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUI_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$CLUI_DIR/src/draw.sh"
source "$TESTS_DIR/assert.sh"

# ── clui_pad_left ─────────────────────────────────────────────────────────────

clui_test_begin "clui_pad_left: basic left-align with padding"
result="$(clui_pad_left "hello" "hello" 10)"
assert_eq "hello     " "$result"

clui_test_begin "clui_pad_left: exact width — no padding"
result="$(clui_pad_left "hello" "hello" 5)"
assert_eq "hello" "$result"

clui_test_begin "clui_pad_left: wider than width — no truncation"
result="$(clui_pad_left "toolong" "toolong" 4)"
assert_eq "toolong" "$result"

clui_test_begin "clui_pad_left: zero width string"
result="$(clui_pad_left "" "" 5)"
assert_eq "     " "$result"

clui_test_begin "clui_pad_left: ANSI rendered; raw used for width"
# rendered has ANSI bold+reset (invisible), raw is plain text
raw="~/bin/gflow"
rendered="${CLUI_BOLD}~/bin/gflow${CLUI_RESET}"
result="$(clui_pad_left "$raw" "$rendered" 15)"
# Visible width of raw is 11; padding = 4 spaces; result is rendered + 4 spaces
expected="${CLUI_BOLD}~/bin/gflow${CLUI_RESET}    "
assert_eq "$expected" "$result" "ANSI padding width"

clui_test_begin "clui_pad_left: width equals raw length with ANSI in rendered"
raw="hi"
rendered="${CLUI_GREEN}hi${CLUI_RESET}"
result="$(clui_pad_left "$raw" "$rendered" 2)"
assert_eq "${CLUI_GREEN}hi${CLUI_RESET}" "$result" "exact width, ANSI rendered"

clui_test_summary
