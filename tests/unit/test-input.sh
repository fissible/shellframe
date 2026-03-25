#!/usr/bin/env bash
# tests/unit/test-input.sh — Unit tests for src/input.sh
#
# Covers:
#   - SHELLFRAME_KEY_F1–F12 constant values
#   - SHELLFRAME_KEY_SHIFT/ALT/CTRL + arrow constant values
#   - shellframe_read_key CSI drain: unrecognized sequences do not leak
#   - shellframe_read_key recognizes F1–F12 and modifier+arrow sequences

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/input.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── F1–F12 constant values ─────────────────────────────────────────────────

ptyunit_test_begin "input: SHELLFRAME_KEY_F1 is ESC O P"
assert_eq $'\x1bOP' "$SHELLFRAME_KEY_F1"

ptyunit_test_begin "input: SHELLFRAME_KEY_F2 is ESC O Q"
assert_eq $'\x1bOQ' "$SHELLFRAME_KEY_F2"

ptyunit_test_begin "input: SHELLFRAME_KEY_F3 is ESC O R"
assert_eq $'\x1bOR' "$SHELLFRAME_KEY_F3"

ptyunit_test_begin "input: SHELLFRAME_KEY_F4 is ESC O S"
assert_eq $'\x1bOS' "$SHELLFRAME_KEY_F4"

ptyunit_test_begin "input: SHELLFRAME_KEY_F5 is ESC [ 1 5 ~"
assert_eq $'\x1b[15~' "$SHELLFRAME_KEY_F5"

ptyunit_test_begin "input: SHELLFRAME_KEY_F6 is ESC [ 1 7 ~"
assert_eq $'\x1b[17~' "$SHELLFRAME_KEY_F6"

ptyunit_test_begin "input: SHELLFRAME_KEY_F7 is ESC [ 1 8 ~"
assert_eq $'\x1b[18~' "$SHELLFRAME_KEY_F7"

ptyunit_test_begin "input: SHELLFRAME_KEY_F8 is ESC [ 1 9 ~"
assert_eq $'\x1b[19~' "$SHELLFRAME_KEY_F8"

ptyunit_test_begin "input: SHELLFRAME_KEY_F9 is ESC [ 2 0 ~"
assert_eq $'\x1b[20~' "$SHELLFRAME_KEY_F9"

ptyunit_test_begin "input: SHELLFRAME_KEY_F10 is ESC [ 2 1 ~"
assert_eq $'\x1b[21~' "$SHELLFRAME_KEY_F10"

ptyunit_test_begin "input: SHELLFRAME_KEY_F11 is ESC [ 2 3 ~"
assert_eq $'\x1b[23~' "$SHELLFRAME_KEY_F11"

ptyunit_test_begin "input: SHELLFRAME_KEY_F12 is ESC [ 2 4 ~"
assert_eq $'\x1b[24~' "$SHELLFRAME_KEY_F12"

# ── Modifier+arrow constant values ─────────────────────────────────────────

ptyunit_test_begin "input: SHELLFRAME_KEY_SHIFT_UP is ESC [ 1 ; 2 A"
assert_eq $'\x1b[1;2A' "$SHELLFRAME_KEY_SHIFT_UP"

ptyunit_test_begin "input: SHELLFRAME_KEY_SHIFT_DOWN is ESC [ 1 ; 2 B"
assert_eq $'\x1b[1;2B' "$SHELLFRAME_KEY_SHIFT_DOWN"

ptyunit_test_begin "input: SHELLFRAME_KEY_SHIFT_RIGHT is ESC [ 1 ; 2 C"
assert_eq $'\x1b[1;2C' "$SHELLFRAME_KEY_SHIFT_RIGHT"

ptyunit_test_begin "input: SHELLFRAME_KEY_SHIFT_LEFT is ESC [ 1 ; 2 D"
assert_eq $'\x1b[1;2D' "$SHELLFRAME_KEY_SHIFT_LEFT"

ptyunit_test_begin "input: SHELLFRAME_KEY_ALT_UP is ESC [ 1 ; 3 A"
assert_eq $'\x1b[1;3A' "$SHELLFRAME_KEY_ALT_UP"

ptyunit_test_begin "input: SHELLFRAME_KEY_ALT_DOWN is ESC [ 1 ; 3 B"
assert_eq $'\x1b[1;3B' "$SHELLFRAME_KEY_ALT_DOWN"

ptyunit_test_begin "input: SHELLFRAME_KEY_ALT_RIGHT is ESC [ 1 ; 3 C"
assert_eq $'\x1b[1;3C' "$SHELLFRAME_KEY_ALT_RIGHT"

ptyunit_test_begin "input: SHELLFRAME_KEY_ALT_LEFT is ESC [ 1 ; 3 D"
assert_eq $'\x1b[1;3D' "$SHELLFRAME_KEY_ALT_LEFT"

ptyunit_test_begin "input: SHELLFRAME_KEY_CTRL_UP is ESC [ 1 ; 5 A"
assert_eq $'\x1b[1;5A' "$SHELLFRAME_KEY_CTRL_UP"

ptyunit_test_begin "input: SHELLFRAME_KEY_CTRL_DOWN is ESC [ 1 ; 5 B"
assert_eq $'\x1b[1;5B' "$SHELLFRAME_KEY_CTRL_DOWN"

ptyunit_test_begin "input: SHELLFRAME_KEY_CTRL_RIGHT is ESC [ 1 ; 5 C"
assert_eq $'\x1b[1;5C' "$SHELLFRAME_KEY_CTRL_RIGHT"

ptyunit_test_begin "input: SHELLFRAME_KEY_CTRL_LEFT is ESC [ 1 ; 5 D"
assert_eq $'\x1b[1;5D' "$SHELLFRAME_KEY_CTRL_LEFT"

# ── F1–F4 not confused with each other ───────────────────────────────────────

ptyunit_test_begin "input: F1–F4 constants are all distinct"
assert_not_eq "$SHELLFRAME_KEY_F1" "$SHELLFRAME_KEY_F2" "F1 != F2"
assert_not_eq "$SHELLFRAME_KEY_F2" "$SHELLFRAME_KEY_F3" "F2 != F3"
assert_not_eq "$SHELLFRAME_KEY_F3" "$SHELLFRAME_KEY_F4" "F3 != F4"

# ── shellframe_read_key: drain behavior ───────────────────────────────────────
#
# Strategy: spawn a bash subprocess with stdin redirected from a printf pipe.
# The pipe contains an unrecognized CSI sequence followed by the letter 'q'.
# We call shellframe_read_key twice and verify:
#   1. The first call returns the full unrecognized sequence (fully drained).
#   2. The second call returns 'q' cleanly (buffer not corrupted).
#
# This validates the real drain code path against actual bash `read` behavior,
# not theoretical reasoning.

# Helper: run two successive shellframe_read_key calls with stdin from a pipe.
# Prints "KEY1|KEY2" with each result hex-encoded for safe comparison.
_two_reads_hex() {
    local _input="$1"
    # Run in a subprocess with stdin redirected from the printf output.
    # Use printf -v to hex-encode each result so special bytes survive stdout.
    bash -c '
        source "'"$SHELLFRAME_DIR"'/src/input.sh"
        k1="" k2=""
        shellframe_read_key k1
        shellframe_read_key k2
        # Hex-encode k1 and k2 for safe transport through stdout
        hex1="" hex2="" i code
        for (( i=0; i<${#k1}; i++ )); do
            printf -v code "%d" "'"'"'${k1:$i:1}"
            printf -v hex1 "%s%02x" "$hex1" "$code"
        done
        for (( i=0; i<${#k2}; i++ )); do
            printf -v code "%d" "'"'"'${k2:$i:1}"
            printf -v hex2 "%s%02x" "$hex2" "$code"
        done
        printf "%s|%s\n" "$hex1" "$hex2"
    ' < <(printf '%s' "$_input")
}

ptyunit_test_begin "read_key: CSI drain — unrecognized ESC[999~ followed by 'q'"
# ESC [ 9 9 9 ~ is not a recognized constant; it must be fully consumed.
# The 'q' following it must come back clean as the second read.
_result=$(_two_reads_hex $'\x1b[999~q')
_key1="${_result%%|*}"
_key2="${_result##*|}"
# key1 should be the hex of ESC [ 9 9 9 ~  = 1b 5b 39 39 39 7e
assert_eq "1b5b3939397e" "$_key1" "first read consumed full unrecognized CSI sequence"
# key2 should be hex of 'q' = 71
assert_eq "71" "$_key2" "second read returned clean 'q' after drain"

ptyunit_test_begin "read_key: CSI drain — unrecognized ESC[?25l (DEC private mode) followed by 'a'"
# ESC [ ? 2 5 l is a DEC private sequence — not a recognized constant.
# It uses the same CSI structure and must be fully consumed.
_result=$(_two_reads_hex $'\x1b[?25la')
_key1="${_result%%|*}"
_key2="${_result##*|}"
# hex of ESC [ ? 2 5 l = 1b 5b 3f 32 35 6c
assert_eq "1b5b3f32356c" "$_key1" "first read consumed full DEC private mode sequence"
# hex of 'a' = 61
assert_eq "61" "$_key2" "second read returned clean 'a' after drain"

ptyunit_test_begin "read_key: CSI drain — unrecognized ESC[1;9A (future modifier code) followed by Enter"
# ESC [ 1 ; 9 A uses modifier code 9 (not currently assigned).
# Must be fully consumed, not leak ';', '9' as next reads.
_result=$(_two_reads_hex $'\x1b[1;9A'$'\n')
_key1="${_result%%|*}"
_key2="${_result##*|}"
# hex of ESC [ 1 ; 9 A = 1b 5b 31 3b 39 41
assert_eq "1b5b313b3941" "$_key1" "first read consumed future modifier+arrow sequence"
# hex of newline = 0a
assert_eq "0a" "$_key2" "second read returned clean Enter (newline) after drain"

# ── shellframe_read_key: recognized new sequences ────────────────────────────

# Helper: run one shellframe_read_key call and return hex of result.
_one_read_hex() {
    local _input="$1"
    bash -c '
        source "'"$SHELLFRAME_DIR"'/src/input.sh"
        k1=""
        shellframe_read_key k1
        hex1="" i code
        for (( i=0; i<${#k1}; i++ )); do
            printf -v code "%d" "'"'"'${k1:$i:1}"
            printf -v hex1 "%s%02x" "$hex1" "$code"
        done
        printf "%s\n" "$hex1"
    ' < <(printf '%s' "$_input")
}

ptyunit_test_begin "read_key: F1 (ESC O P) is read as full 3-byte sequence"
_got=$(_one_read_hex $'\x1bOP')
# ESC O P = 1b 4f 50
assert_eq "1b4f50" "$_got" "F1 sequence returned in full"

ptyunit_test_begin "read_key: F5 (ESC [ 1 5 ~) is read as full 5-byte sequence"
_got=$(_one_read_hex $'\x1b[15~')
# ESC [ 1 5 ~ = 1b 5b 31 35 7e
assert_eq "1b5b31357e" "$_got" "F5 sequence returned in full"

ptyunit_test_begin "read_key: Shift+Up (ESC [ 1 ; 2 A) is read as full 6-byte sequence"
_got=$(_one_read_hex $'\x1b[1;2A')
# ESC [ 1 ; 2 A = 1b 5b 31 3b 32 41
assert_eq "1b5b313b3241" "$_got" "Shift+Up sequence returned in full"

ptyunit_test_begin "read_key: Ctrl+Right (ESC [ 1 ; 5 C) is read as full 6-byte sequence"
_got=$(_one_read_hex $'\x1b[1;5C')
# ESC [ 1 ; 5 C = 1b 5b 31 3b 35 43
assert_eq "1b5b313b3543" "$_got" "Ctrl+Right sequence returned in full"

# ── SHELLFRAME_KEY_MOUSE constant ────────────────────────────────────────────

ptyunit_test_begin "input: SHELLFRAME_KEY_MOUSE constant is defined and non-empty"
assert_not_eq "" "$SHELLFRAME_KEY_MOUSE" "SHELLFRAME_KEY_MOUSE is non-empty"

# ── shellframe_read_key: SGR mouse sequence parsing ───────────────────────────
#
# Strategy: identical to the CSI drain tests — spawn a bash subprocess with
# stdin from a pipe carrying a real SGR mouse sequence.  shellframe_read_key
# runs, sets SHELLFRAME_MOUSE_*, and prints "KEY|BUTTON|COL|ROW|ACTION" for
# assertion.  This validates the real read + parse path against actual bash
# `read` behavior (IO validation per CLAUDE.md §5).
#
# SGR format: ESC [ < Pb ; Px ; Py M (press) / m (release)

_mouse_read_vars() {
    local _input="$1"
    bash -c '
        source "'"$SHELLFRAME_DIR"'/src/input.sh"
        SHELLFRAME_MOUSE_BUTTON=""
        SHELLFRAME_MOUSE_COL=""
        SHELLFRAME_MOUSE_ROW=""
        SHELLFRAME_MOUSE_ACTION=""
        shellframe_read_key _key
        printf "%s|%s|%s|%s|%s\n" \
            "$_key" \
            "${SHELLFRAME_MOUSE_BUTTON}" \
            "${SHELLFRAME_MOUSE_COL}" \
            "${SHELLFRAME_MOUSE_ROW}" \
            "${SHELLFRAME_MOUSE_ACTION}"
    ' < <(printf '%s' "$_input")
}

# Parse "KEY|BUTTON|COL|ROW|ACTION" into _mo_key, _mo_btn, _mo_col, _mo_row, _mo_act
_parse_mouse_out() {
    local _r="$1"
    _mo_key="${_r%%|*}"; _r="${_r#*|}"
    _mo_btn="${_r%%|*}"; _r="${_r#*|}"
    _mo_col="${_r%%|*}"; _r="${_r#*|}"
    _mo_row="${_r%%|*}"
    _mo_act="${_r#*|}"
}

ptyunit_test_begin "read_key: SGR left-click press — key SHELLFRAME_KEY_MOUSE, all vars set"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<0;10;5M')"
assert_eq "$SHELLFRAME_KEY_MOUSE" "$_mo_key" "key is SHELLFRAME_KEY_MOUSE"
assert_eq "0"     "$_mo_btn" "button 0 (left)"
assert_eq "10"    "$_mo_col" "col 10"
assert_eq "5"     "$_mo_row" "row 5"
assert_eq "press" "$_mo_act" "action press"

ptyunit_test_begin "read_key: SGR left-click release — action is release"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<0;10;5m')"
assert_eq "release" "$_mo_act" "lowercase m → release"

ptyunit_test_begin "read_key: SGR right-click press — button 2"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<2;15;3M')"
assert_eq "2" "$_mo_btn" "right click = button 2"

ptyunit_test_begin "read_key: SGR scroll-up — button 64"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<64;10;5M')"
assert_eq "64" "$_mo_btn" "scroll-up = button 64"

ptyunit_test_begin "read_key: SGR scroll-down — button 65"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<65;10;5M')"
assert_eq "65" "$_mo_btn" "scroll-down = button 65"

ptyunit_test_begin "read_key: SGR mouse multi-digit coordinates"
_parse_mouse_out "$(_mouse_read_vars $'\x1b[<0;120;45M')"
assert_eq "120" "$_mo_col" "col 120"
assert_eq "45"  "$_mo_row" "row 45"

ptyunit_test_begin "read_key: SGR mouse does not leak bytes to subsequent read"
_result=$(_two_reads_hex $'\x1b[<0;10;5M''q')
assert_eq "71" "${_result##*|}" "second read is 'q' (0x71) after mouse sequence"

ptyunit_test_summary
