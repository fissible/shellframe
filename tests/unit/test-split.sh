#!/usr/bin/env bash
# tests/unit/test-split.sh — Unit tests for src/split.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/split.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── shellframe_split_init ────────────────────────────────────────────────────

ptyunit_test_begin "split_init: stores direction"
shellframe_split_init "s1" "v" 2 "0:0"
assert_eq "v" "$_SHELLFRAME_SPLIT_s1_DIR"

ptyunit_test_begin "split_init: stores count"
shellframe_split_init "s2" "h" 3 "10:0:10"
assert_eq "3" "$_SHELLFRAME_SPLIT_s2_COUNT"

ptyunit_test_begin "split_init: stores sizes"
shellframe_split_init "s3" "v" 2 "30:0"
assert_eq "30:0" "$_SHELLFRAME_SPLIT_s3_SIZES"

ptyunit_test_begin "split_init: default border is single"
shellframe_split_init "s4" "v" 2 "0:0"
assert_eq "single" "$_SHELLFRAME_SPLIT_s4_BORDER"

# ── shellframe_split_bounds: 2-pane vertical ─────────────────────────────────

ptyunit_test_begin "split_bounds: 2v flex+flex, child 0 gets half minus separator"
shellframe_split_init "b1" "v" 2 "0:0"
shellframe_split_bounds "b1" 0  1 1 80 24  t l w h
assert_eq "1" "$t" "top"
assert_eq "1" "$l" "left"
assert_eq "39" "$w" "width (39+1+40=80)"
assert_eq "24" "$h" "height"

ptyunit_test_begin "split_bounds: 2v flex+flex, child 1 gets remainder"
shellframe_split_bounds "b1" 1  1 1 80 24  t l w h
assert_eq "1" "$t" "top"
assert_eq "41" "$l" "left (39+1 separator+1)"
assert_eq "40" "$w" "width"
assert_eq "24" "$h" "height"

ptyunit_test_begin "split_bounds: 2v widths sum to container"
shellframe_split_bounds "b1" 0  1 1 80 24  t l w0 h
shellframe_split_bounds "b1" 1  1 1 80 24  t l w1 h
assert_eq "80" "$(( w0 + 1 + w1 ))" "w0 + sep + w1 = 80"

# ── shellframe_split_bounds: 2-pane vertical, fixed + flex ───────────────────

ptyunit_test_begin "split_bounds: 2v fixed 20 + flex, child 0 is 20 wide"
shellframe_split_init "b2" "v" 2 "20:0"
shellframe_split_bounds "b2" 0  1 1 80 24  t l w h
assert_eq "20" "$w"

ptyunit_test_begin "split_bounds: 2v fixed 20 + flex, child 1 is 59 wide"
shellframe_split_bounds "b2" 1  1 1 80 24  t l w h
assert_eq "59" "$w" "80 - 20 - 1 sep = 59"

# ── shellframe_split_bounds: 3-pane vertical ─────────────────────────────────

ptyunit_test_begin "split_bounds: 3v 20+flex+20, widths sum correctly"
shellframe_split_init "b3" "v" 3 "20:0:20"
shellframe_split_bounds "b3" 0  1 1 80 24  t l w0 h
shellframe_split_bounds "b3" 1  1 1 80 24  t l w1 h
shellframe_split_bounds "b3" 2  1 1 80 24  t l w2 h
assert_eq "20" "$w0" "child 0"
assert_eq "38" "$w1" "flex child (80-20-20-2seps)"
assert_eq "20" "$w2" "child 2"
assert_eq "80" "$(( w0 + 1 + w1 + 1 + w2 ))" "total"

# ── shellframe_split_bounds: 2-pane horizontal ──────────────────────────────

ptyunit_test_begin "split_bounds: 2h flex+flex, heights sum to container"
shellframe_split_init "b4" "h" 2 "0:0"
shellframe_split_bounds "b4" 0  1 1 80 24  t l w h0
shellframe_split_bounds "b4" 1  1 1 80 24  t l w h1
assert_eq "24" "$(( h0 + 1 + h1 ))" "h0 + sep + h1 = 24"

ptyunit_test_begin "split_bounds: 2h both children get full width"
shellframe_split_bounds "b4" 0  1 1 80 24  t l w h
assert_eq "80" "$w" "child 0 width"
shellframe_split_bounds "b4" 1  1 1 80 24  t l w h
assert_eq "80" "$w" "child 1 width"

# ── shellframe_split_bounds: minimum size clamping ───────────────────────────

ptyunit_test_begin "split_bounds: tiny container clamps children to minimum 1"
shellframe_split_init "b5" "v" 2 "0:0"
shellframe_split_bounds "b5" 0  1 1 3 1  t l w h
assert_eq "1" "$w" "minimum width is 1"

# ── shellframe_split_set_border ──────────────────────────────────────────────

ptyunit_test_begin "split_set_border: changes border style"
shellframe_split_init "b6" "v" 2 "0:0"
shellframe_split_set_border "b6" "none"
assert_eq "none" "$_SHELLFRAME_SPLIT_b6_BORDER"

# ── shellframe_split_regions ──────────────────────────────────────────────────

# Stub shellframe_shell_region to capture calls
_SPLIT_REGION_CALLS=()
shellframe_shell_region() { _SPLIT_REGION_CALLS+=("$1:$2:$3:$4:$5"); }

ptyunit_test_begin "split_regions: 2v — calls shell_region for each child with correct bounds"
shellframe_split_init "r1" "v" 2 "0:0"
_SPLIT_REGION_CALLS=()
shellframe_split_regions "r1" 1 1 80 24 "left" "focus" "right" "focus"
assert_eq "2" "${#_SPLIT_REGION_CALLS[@]}" "two regions registered"
assert_eq "left" "${_SPLIT_REGION_CALLS[0]%%:*}" "first region named left"
assert_eq "right" "${_SPLIT_REGION_CALLS[1]%%:*}" "second region named right"

ptyunit_test_begin "split_regions: 2h — regions cover full width"
shellframe_split_init "r2" "h" 2 "0:0"
_SPLIT_REGION_CALLS=()
shellframe_split_regions "r2" 1 1 80 24 "top" "focus" "bottom" "focus"
assert_eq "2" "${#_SPLIT_REGION_CALLS[@]}" "two regions registered"
# Each entry is name:top:left:width:height — width should be 80 for both
_w0="${_SPLIT_REGION_CALLS[0]}"; _w0="${_w0##*:}"; _w0prev="${_SPLIT_REGION_CALLS[0]%:*}"; _w0="${_w0prev##*:}"
assert_eq "80" "$_w0" "top pane full width"

ptyunit_test_begin "split_regions: 3v — three regions registered"
shellframe_split_init "r3" "v" 3 "20:0:20"
_SPLIT_REGION_CALLS=()
shellframe_split_regions "r3" 1 1 80 24 "a" "focus" "b" "focus" "c" "focus"
assert_eq "3" "${#_SPLIT_REGION_CALLS[@]}" "three regions registered"

# ── shellframe_split_render ───────────────────────────────────────────────────

ptyunit_test_begin "split_render: none border is no-op — no framebuffer output"
shellframe_split_init "sr1" "v" 2 "0:0"
shellframe_split_set_border "sr1" "none"
_SF_ROW_PREV=(); shellframe_fb_frame_start 10 40
_out=$(mktemp)
exec 3>"$_out"
shellframe_split_render "sr1" 1 1 40 10
shellframe_screen_flush
exec 3>&-
exec 3>/dev/null
_size=$(wc -c < "$_out" | tr -d ' ')
assert_eq "0" "$_size" "none border produces no output"
rm -f "$_out"

ptyunit_test_begin "split_render: 2v single border — separator character in output"
shellframe_split_init "sr2" "v" 2 "0:0"
_SF_ROW_PREV=(); shellframe_fb_frame_start 5 20
_out=$(mktemp)
exec 3>"$_out"
shellframe_split_render "sr2" 1 1 20 5
shellframe_screen_flush
exec 3>&-
exec 3>/dev/null
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "│" "vertical separator character present"
rm -f "$_out"

ptyunit_test_begin "split_render: 2h single border — horizontal separator in output"
shellframe_split_init "sr3" "h" 2 "0:0"
_SF_ROW_PREV=(); shellframe_fb_frame_start 10 20
_out=$(mktemp)
exec 3>"$_out"
shellframe_split_render "sr3" 1 1 20 10
shellframe_screen_flush
exec 3>&-
exec 3>/dev/null
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "─" "horizontal separator character present"
rm -f "$_out"

# ── Error path ────────────────────────────────────────────────────────────────

ptyunit_test_begin "split_init: invalid ctx returns 1"
shellframe_split_init "" "v" 2 "0:0"; _rc=$?
assert_eq "1" "$_rc" "empty ctx returns 1"

# ── Summary ──────────────────────────────────────────────────────────────────

ptyunit_test_summary
