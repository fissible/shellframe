#!/usr/bin/env bash
# tests/unit/test-scrollbar.sh — Unit tests for src/widgets/scrollbar.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/widgets/scrollbar.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── Helper: extract visible chars from row fragment ──────────────────────────

_cell() {
    local _row="$1" _col="$2"
    # Row fragment contains positioned ANSI content; strip escapes to get
    # visible chars.  For single-cell widgets (scrollbar) this yields the
    # one character written to the row.
    printf '%s' "${_SF_ROW_CURR[$_row]:-}" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g'
}

# ── Content fits in viewport: nothing rendered ───────────────────────────────

ptyunit_test_begin "no render when content fits in viewport"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb1" 10 1 20 1    # 10 rows in 20-row viewport
shellframe_scrollbar_render "sb1" 80 1 20
assert_eq 1 $?

# ── Exactly equal: nothing rendered ──────────────────────────────────────────

ptyunit_test_begin "no render when content equals viewport"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb2" 20 1 20 1
shellframe_scrollbar_render "sb2" 80 1 20
assert_eq 1 $?

# ── Content overflows: renders track + thumb ─────────────────────────────────

ptyunit_test_begin "renders when content overflows viewport"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb3" 100 1 20 1    # 100 rows in 20-row viewport
shellframe_scrollbar_render "sb3" 80 1 20
assert_eq 0 $?

# ── Thumb at top when scroll_top=0 ───────────────────────────────────────────

ptyunit_test_begin "thumb starts at top when scroll is at 0"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb4" 100 1 20 1
# scroll_top is 0 (default from init)
shellframe_scrollbar_render "sb4" 80 1 20
# Row 1 should have thumb character
_c=$(_cell 1 80)
assert_eq "█" "$_c"

# ── Track character present below thumb ──────────────────────────────────────

ptyunit_test_begin "track character present below thumb"
# Continuing from sb4: thumb is ~4 rows (20*20/100=4), track below
_c=$(_cell 10 80)
assert_eq "░" "$_c"

# ── Thumb at bottom when scrolled to end ─────────────────────────────────────

ptyunit_test_begin "thumb at bottom when scrolled to end"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb5" 100 1 20 1
shellframe_scroll_move "sb5" end
shellframe_scrollbar_render "sb5" 80 1 20
# Last row should have thumb
_c=$(_cell 20 80)
assert_eq "█" "$_c"
# First row should be track
_c=$(_cell 1 80)
assert_eq "░" "$_c"

# ── Thumb size: minimum 1 row ────────────────────────────────────────────────

ptyunit_test_begin "thumb minimum 1 row for very large content"
shellframe_fb_frame_start 10 80
shellframe_scroll_init "sb6" 10000 1 10 1    # 10000 rows in 10-row viewport
shellframe_scrollbar_render "sb6" 80 1 10
# Thumb would be 10*10/10000 = 0, clamped to 1
# Count thumb chars
_thumbs=0
for (( _r=1; _r<=10; _r++ )); do
    _c=$(_cell "$_r" 80)
    [[ "$_c" == "█" ]] && (( _thumbs++ ))
done
assert_eq 1 "$_thumbs"

# ── Thumb at middle position ─────────────────────────────────────────────────

ptyunit_test_begin "thumb at middle when scrolled to middle"
shellframe_fb_frame_start 20 80
shellframe_scroll_init "sb7" 100 1 20 1
# Scroll to middle: top = 40 (roughly half of max_scroll=80)
shellframe_scroll_move "sb7" down 40
shellframe_scrollbar_render "sb7" 80 1 20
# Thumb is ~4 rows, track_space=16, thumb_top = 40*16/80 = 8
# So rows 9-12 should be thumb
_c=$(_cell 9 80)
assert_eq "█" "$_c"
_c=$(_cell 1 80)
assert_eq "░" "$_c"

# ── Custom characters ────────────────────────────────────────────────────────

ptyunit_test_begin "respects custom track and thumb characters"
shellframe_fb_frame_start 10 80
shellframe_scroll_init "sb8" 50 1 10 1
SHELLFRAME_SCROLLBAR_TRACK="|"
SHELLFRAME_SCROLLBAR_THUMB="#"
shellframe_scrollbar_render "sb8" 80 1 10
_c=$(_cell 1 80)
assert_eq "#" "$_c"
_c=$(_cell 10 80)
assert_eq "|" "$_c"
# Restore defaults
SHELLFRAME_SCROLLBAR_TRACK="░"
SHELLFRAME_SCROLLBAR_THUMB="█"

ptyunit_test_summary
