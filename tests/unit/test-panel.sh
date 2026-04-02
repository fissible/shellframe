#!/usr/bin/env bash
# tests/unit/test-panel.sh — Unit tests for src/panel.sh
# (Rendering tests require PTY; these cover inner-bounds and focus state only.)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── shellframe_panel_inner: single border style ───────────────────────────────

_inner() {
    local t l w h
    SHELLFRAME_PANEL_STYLE="single"
    shellframe_panel_inner "$1" "$2" "$3" "$4" t l w h
    printf '%d %d %d %d' "$t" "$l" "$w" "$h"
}

ptyunit_test_begin "panel_inner: single — top offset by 1"
result=$(_inner 1 1 20 10)
it=$(printf '%s' "$result" | awk '{print $1}')
assert_eq "2" "$it" "inner top = outer top + 1"

ptyunit_test_begin "panel_inner: single — left offset by 1"
result=$(_inner 1 1 20 10)
il=$(printf '%s' "$result" | awk '{print $2}')
assert_eq "2" "$il" "inner left = outer left + 1"

ptyunit_test_begin "panel_inner: single — width reduced by 2"
result=$(_inner 1 1 20 10)
iw=$(printf '%s' "$result" | awk '{print $3}')
assert_eq "18" "$iw" "inner width = outer width - 2"

ptyunit_test_begin "panel_inner: single — height reduced by 2"
result=$(_inner 1 1 20 10)
ih=$(printf '%s' "$result" | awk '{print $4}')
assert_eq "8" "$ih" "inner height = outer height - 2"

# ── shellframe_panel_inner: none border style ─────────────────────────────────

ptyunit_test_begin "panel_inner: none — inner equals outer"
SHELLFRAME_PANEL_STYLE="none"
_it="" _il="" _iw="" _ih=""
shellframe_panel_inner 3 5 20 10 _it _il _iw _ih
assert_eq "3"  "$_it" "none: top unchanged"
assert_eq "5"  "$_il" "none: left unchanged"
assert_eq "20" "$_iw" "none: width unchanged"
assert_eq "10" "$_ih" "none: height unchanged"

# ── shellframe_panel_inner: non-origin region ─────────────────────────────────

ptyunit_test_begin "panel_inner: non-origin region with single border"
SHELLFRAME_PANEL_STYLE="single"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 5 10 30 15 _ot _ol _ow _oh
assert_eq "6"  "$_ot" "top = 5+1"
assert_eq "11" "$_ol" "left = 10+1"
assert_eq "28" "$_ow" "width = 30-2"
assert_eq "13" "$_oh" "height = 15-2"

# ── shellframe_panel_on_focus ─────────────────────────────────────────────────

ptyunit_test_begin "panel_on_focus: sets FOCUSED=1"
SHELLFRAME_PANEL_FOCUSED=0
shellframe_panel_on_focus 1
assert_eq "1" "$SHELLFRAME_PANEL_FOCUSED" "focused set to 1"

ptyunit_test_begin "panel_on_focus: sets FOCUSED=0"
SHELLFRAME_PANEL_FOCUSED=1
shellframe_panel_on_focus 0
assert_eq "0" "$SHELLFRAME_PANEL_FOCUSED" "focused set to 0"

# ── shellframe_panel_on_key ───────────────────────────────────────────────────

ptyunit_test_begin "panel_on_key: always returns 1 (not handled)"
shellframe_panel_on_key "x"
assert_eq "1" "$?" "on_key returns 1"

# ── shellframe_panel_size ─────────────────────────────────────────────────────

ptyunit_test_begin "panel_size: min 2x2, preferred unconstrained"
assert_output "2 2 0 0" shellframe_panel_size

# ── shellframe_panel_inner: windowed mode ─────────────────────────────────────

ptyunit_test_begin "panel_inner: windowed+single — top offset by 2"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_MODE="windowed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "3" "$_ot" "windowed+single: inner top = outer top + border(1) + title_row(1)"

ptyunit_test_begin "panel_inner: windowed+single — height reduced by 3"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_MODE="windowed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "7" "$_oh" "windowed+single: inner height = outer height - border*2(2) - title_row(1)"

ptyunit_test_begin "panel_inner: windowed+single — left and width unchanged vs framed"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_MODE="windowed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "2"  "$_ol" "windowed: left still offset by border"
assert_eq "18" "$_ow" "windowed: width still reduced by border*2"

ptyunit_test_begin "panel_inner: windowed+none — top offset by 1 (title row only)"
SHELLFRAME_PANEL_STYLE="none"
SHELLFRAME_PANEL_MODE="windowed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "2" "$_ot" "windowed+none: inner top = outer top + title_row(1)"

ptyunit_test_begin "panel_inner: windowed+none — height reduced by 1"
SHELLFRAME_PANEL_STYLE="none"
SHELLFRAME_PANEL_MODE="windowed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "9" "$_oh" "windowed+none: inner height = outer height - title_row(1)"

ptyunit_test_begin "panel_inner: framed mode unaffected by MODE global"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_MODE="framed"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
assert_eq "2" "$_ot" "framed: top offset by border only"
assert_eq "8" "$_oh" "framed: height reduced by border*2 only"

# ── shellframe_panel_render: fd 3 output ─────────────────────────────────────

ptyunit_test_begin "panel_render: single border writes top-left corner"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_MODE="framed"
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 20
exec 3>"$_out"
shellframe_panel_render 1 1 20 5
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "┌"
rm -f "$_out"

ptyunit_test_begin "panel_render: double border writes double-line corner"
SHELLFRAME_PANEL_STYLE="double"
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_MODE="framed"
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 20
exec 3>"$_out"
shellframe_panel_render 1 1 20 5
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "╔"
rm -f "$_out"

ptyunit_test_begin "panel_render: rounded border writes rounded corner"
SHELLFRAME_PANEL_STYLE="rounded"
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_MODE="framed"
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 20
exec 3>"$_out"
shellframe_panel_render 1 1 20 5
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "╭"
rm -f "$_out"

ptyunit_test_begin "panel_render: none border writes spaces only (no box chars)"
SHELLFRAME_PANEL_STYLE="none"
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_MODE="framed"
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 20
exec 3>"$_out"
shellframe_panel_render 1 1 20 5
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_not_contains "$_content" "┌"
assert_not_contains "$_content" "╔"
rm -f "$_out"

ptyunit_test_begin "panel_render: framed title is embedded in top border"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_TITLE="MyTitle"
SHELLFRAME_PANEL_TITLE_ALIGN="left"
SHELLFRAME_PANEL_MODE="framed"
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 30
exec 3>"$_out"
shellframe_panel_render 1 1 30 5
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "MyTitle"
rm -f "$_out"

ptyunit_test_begin "panel_render: windowed mode renders title in title bar row"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_TITLE="WinTitle"
SHELLFRAME_PANEL_MODE="windowed"
SHELLFRAME_PANEL_TITLE_BG=""
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 6 30
exec 3>"$_out"
shellframe_panel_render 1 1 30 6
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "WinTitle"
rm -f "$_out"

# ── _shellframe_panel_chars: all styles ───────────────────────────────────────

ptyunit_test_begin "panel_chars: double style sets double-line glyphs"
_shellframe_panel_chars "double"
assert_eq "╔" "$_tl" "double top-left"
assert_eq "═" "$_hr" "double horiz-rule"
assert_eq "╚" "$_bl" "double bot-left"

ptyunit_test_begin "panel_chars: rounded style sets rounded glyphs"
_shellframe_panel_chars "rounded"
assert_eq "╭" "$_tl" "rounded top-left"
assert_eq "╰" "$_bl" "rounded bot-left"

ptyunit_test_begin "panel_chars: none style sets spaces"
_shellframe_panel_chars "none"
assert_eq " " "$_tl" "none: space corner"
assert_eq " " "$_hr" "none: space fill"

ptyunit_test_begin "panel_chars: single (default) style sets single-line glyphs"
_shellframe_panel_chars "single"
assert_eq "┌" "$_tl" "single top-left"
assert_eq "─" "$_hr" "single horiz-rule"

ptyunit_test_begin "panel_chars: unknown style falls through to single"
_shellframe_panel_chars "bogus"
assert_eq "┌" "$_tl" "unknown → single top-left"

# ── shellframe_panel_on_focus: default arg ────────────────────────────────────

ptyunit_test_begin "panel_on_focus: no arg defaults to 0"
SHELLFRAME_PANEL_FOCUSED=1
shellframe_panel_on_focus
assert_eq "0" "$SHELLFRAME_PANEL_FOCUSED" "default arg sets 0"

ptyunit_test_summary
