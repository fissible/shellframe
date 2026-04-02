#!/usr/bin/env bash
# shellframe/src/sheet.sh — Sheet navigation primitive
#
# A sheet is a partial overlay that sits above the current shellframe_shell
# screen. It shows one frozen dimmed row of the underlying screen at the top
# (the "back strip") and renders its own content from row 2 downward.
#
# Public API:
#   shellframe_sheet_push prefix screen  — open a sheet
#   shellframe_sheet_pop                 — schedule sheet dismissal
#   shellframe_sheet_active              — 0=true if a sheet is open
#   shellframe_sheet_draw rows cols      — called by shell.sh draw delegation
#   shellframe_sheet_on_key key          — called by shell.sh key delegation
#
# Consumer hooks (identical convention to shellframe_shell):
#   PREFIX_SCREEN_render()               — layout; set SHELLFRAME_SHEET_HEIGHT
#   PREFIX_SCREEN_REGION_render t l w h  — region render
#   PREFIX_SCREEN_REGION_on_key key      — region key handler (rc: 0=handled, 1=unhandled, 2=action)
#   PREFIX_SCREEN_REGION_on_focus active — focus change notification
#   PREFIX_SCREEN_REGION_action()        — called when on_key returns 2
#   PREFIX_SCREEN_quit()                 — called on Esc or Up-from-topmost
#
# Row coordinates in consumer hooks are sheet-relative: row 1 = first content
# row (screen row 2, immediately below the back strip). Use $SHELLFRAME_SHEET_WIDTH.
#
# KNOWN LIMITATION: back-strip dimming uses \033[2m...\033[22m. Rows containing
# \033[0m mid-string will have dim cancelled at that point — best-effort for v1.

# ── State globals ─────────────────────────────────────────────────────────────

_SHELLFRAME_SHEET_ACTIVE=0          # 0|1 — whether a sheet is currently open
_SHELLFRAME_SHEET_PREFIX=""         # consumer prefix (e.g. "_myapp")
_SHELLFRAME_SHEET_SCREEN=""         # current screen within the sheet
_SHELLFRAME_SHEET_NEXT=""           # next screen name; "__POP__" to dismiss
_SHELLFRAME_SHEET_FROZEN_ROWS=()    # full-screen framebuffer snapshot at push time
SHELLFRAME_SHEET_HEIGHT=0           # consumer sets in render hook; 0 = fill to bottom
SHELLFRAME_SHEET_WIDTH=0            # set before render hook; read-only for consumers
# Sheet-local focus / region registry (swapped in/out each frame)
_SHELLFRAME_SHEET_REGIONS=()
_SHELLFRAME_SHEET_FOCUS_RING=()
_SHELLFRAME_SHEET_FOCUS_IDX=0
_SHELLFRAME_SHEET_FOCUS_REQUEST=""

# ── shellframe_sheet_push ─────────────────────────────────────────────────────

shellframe_sheet_push() {
    local _prefix="$1" _screen="$2"

    if (( _SHELLFRAME_SHEET_ACTIVE )); then
        printf 'shellframe_sheet_push: sheet already active (stacking not supported in v1)\n' >&2
        return 1
    fi

    _SHELLFRAME_SHEET_ACTIVE=1
    _SHELLFRAME_SHEET_PREFIX="$_prefix"
    _SHELLFRAME_SHEET_SCREEN="$_screen"
    _SHELLFRAME_SHEET_NEXT=""

    # Snapshot current framebuffer for back strip and below-sheet frozen content
    local _rows="${_SHELLFRAME_SHELL_ROWS:-24}"
    _SHELLFRAME_SHEET_FROZEN_ROWS=()
    local _r
    for (( _r=1; _r<=_rows; _r++ )); do
        _SHELLFRAME_SHEET_FROZEN_ROWS[$_r]="${_SF_ROW_CURR[$_r]:-}"
    done

    # Reset sheet-local focus state (first frame starts at idx 0)
    _SHELLFRAME_SHEET_REGIONS=()
    _SHELLFRAME_SHEET_FOCUS_RING=()
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHEET_FOCUS_REQUEST=""

    shellframe_shell_mark_dirty
}

# ── shellframe_sheet_pop ──────────────────────────────────────────────────────

shellframe_sheet_pop() {
    _SHELLFRAME_SHEET_NEXT="__POP__"
}

# ── shellframe_sheet_active ───────────────────────────────────────────────────

shellframe_sheet_active() {
    (( _SHELLFRAME_SHEET_ACTIVE ))
}
