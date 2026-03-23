#!/usr/bin/env bash
# shellframe/src/widgets/menu-bar.sh — Horizontal menu bar widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/panel.sh, src/draw.sh, src/input.sh
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a one-row menu bar with dropdown panels and one level of submenu
# nesting. State machine: idle → bar → dropdown → submenu.
#
# ── Data model ────────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENU_NAMES=("File" "Edit" "View")
#   SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
#   SHELLFRAME_MENU_RECENT=("demo.db" "work.db")   # submenu via @VARNAME sigil
#
#   Item types:
#     plain string       — selectable leaf item
#     "---"              — separator (drawn as rule, never reachable by cursor)
#     "@VARNAME:Label"   — submenu item; Right/Enter opens SHELLFRAME_MENU_VARNAME
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENU_NAMES[@]         — top-level label order (caller sets)
#   SHELLFRAME_MENUBAR_CTX           — context name (default: "menubar")
#   SHELLFRAME_MENUBAR_FOCUSED       — 0 | 1
#   SHELLFRAME_MENUBAR_FOCUSABLE     — 1 (default) | 0
#   SHELLFRAME_MENUBAR_ACTIVE_COLOR  — ANSI escape for double-border color
#                                      (default: SHELLFRAME_BOLD)
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENUBAR_RESULT  — set on return 2:
#                                "Menu|Item" or "Menu|Item|Sub" on selection
#                                "" (empty) on Esc dismiss
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_menubar_init [ctx]
#     Initialise selection contexts. Call once after SHELLFRAME_MENU_NAMES is set.
#
#   shellframe_menubar_render top left width height
#     Draw bar row + open overlay panels. Output to fd 3.
#
#   shellframe_menubar_on_key key
#     Drive state machine. Returns 0 (handled), 1 (unrecognised), 2 (done).
#
#   shellframe_menubar_on_focus focused
#     1 → BAR state. 0 → IDLE (collapses open panels on next render).
#
#   shellframe_menubar_size
#     Print "1 1 0 1". Bar is always 1 row; overlays are absolute-positioned.
#
#   shellframe_menubar_open name
#     Focus bar and open named menu (hotkey seam). Returns 1 if name not found.

SHELLFRAME_MENU_NAMES=()
SHELLFRAME_MENUBAR_CTX="menubar"
SHELLFRAME_MENUBAR_FOCUSED=0
SHELLFRAME_MENUBAR_FOCUSABLE=1
SHELLFRAME_MENUBAR_ACTIVE_COLOR=""
SHELLFRAME_MENUBAR_RESULT=""

# ── Internal: separator detection ─────────────────────────────────────────────

# Return 0 if item is "---", 1 otherwise.
_shellframe_mb_is_sep() {
    [[ "$1" == "---" ]]
}

# ── Internal: sigil parsing ────────────────────────────────────────────────────

# Parse "@VARNAME:Display Label" into out variables.
# Returns 0 on success, 1 if item is not a sigil or VARNAME is invalid.
#
# Usage: _shellframe_mb_parse_sigil "$item" out_varname out_label
_shellframe_mb_parse_sigil() {
    local _item="$1" _out_vn="$2" _out_lbl="$3"
    # Must start with @
    [[ "${_item:0:1}" == "@" ]] || return 1
    local _rest="${_item:1}"
    # Must contain a colon
    [[ "$_rest" == *:* ]] || return 1
    local _vn="${_rest%%:*}"
    local _lbl="${_rest#*:}"
    # VARNAME must match [A-Z0-9_]+
    [[ "$_vn" =~ ^[A-Z0-9_]+$ ]] || return 1
    printf -v "$_out_vn"  '%s' "$_vn"
    printf -v "$_out_lbl" '%s' "$_lbl"
    return 0
}

shellframe_menubar_init()   { true; }
shellframe_menubar_render() { true; }
shellframe_menubar_on_key() { return 1; }
shellframe_menubar_on_focus() { SHELLFRAME_MENUBAR_FOCUSED="${1:-0}"; }
shellframe_menubar_size()   { printf '%d %d %d %d' 1 1 0 1; }
shellframe_menubar_open()   { return 1; }
