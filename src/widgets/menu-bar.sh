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

shellframe_menubar_init() {
    local _ctx="${1:-${SHELLFRAME_MENUBAR_CTX:-menubar}}"
    # State machine
    printf -v "_SHELLFRAME_MB_${_ctx}_STATE"   '%s' "idle"
    printf -v "_SHELLFRAME_MB_${_ctx}_BAR_IDX" '%d' 0
    # Prev panel dimensions (0 = nothing to erase)
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_TOP"  '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_LEFT" '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_W"    '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_H"    '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_TOP"  '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_LEFT" '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_W"    '%d' 0
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_H"    '%d' 0
    # Selection contexts for dropdown and submenu cursors
    shellframe_sel_init "mb_${_ctx}_dd" 0
    shellframe_sel_init "mb_${_ctx}_sm" 0
}
shellframe_menubar_render() { true; }

# ── shellframe_menubar_on_focus ────────────────────────────────────────────────

shellframe_menubar_on_focus() {
    local _focused="${1:-0}"
    local _ctx="${SHELLFRAME_MENUBAR_CTX:-menubar}"
    SHELLFRAME_MENUBAR_FOCUSED="$_focused"
    if (( _focused )); then
        printf -v "_SHELLFRAME_MB_${_ctx}_STATE" '%s' "bar"
    else
        printf -v "_SHELLFRAME_MB_${_ctx}_STATE" '%s' "idle"
    fi
}

# ── Internal: first selectable index in a menu array ──────────────────────────

# _shellframe_mb_first_selectable items_var_name out_var
# Finds the first non-separator index.
# Stores result in out_var (0-based). Returns 1 if all items are separators.
_shellframe_mb_first_selectable() {
    local _arr_var="$1" _out="$2"
    local _n _i _item
    eval "_n=\${#${_arr_var}[@]}"
    for (( _i=0; _i<_n; _i++ )); do
        eval "_item=\"\${${_arr_var}[$_i]}\""
        _shellframe_mb_is_sep "$_item" || { printf -v "$_out" '%d' "$_i"; return 0; }
    done
    printf -v "$_out" '%d' 0
    return 1
}

# ── Internal: menu variable name for bar index ────────────────────────────────

# _shellframe_mb_menu_var idx out_var
# Converts SHELLFRAME_MENU_NAMES[idx] to its array variable name.
# e.g. "File" → "SHELLFRAME_MENU_FILE"
_shellframe_mb_menu_var() {
    local _idx="$1" _out="$2"
    local _label="${SHELLFRAME_MENU_NAMES[$_idx]}"
    # uppercase, spaces → underscores
    local _uname
    _uname=$(printf '%s' "$_label" | tr '[:lower:]' '[:upper:]' | tr ' ' '_')
    printf -v "$_out" '%s' "SHELLFRAME_MENU_${_uname}"
}

# ── shellframe_menubar_on_key ──────────────────────────────────────────────────

shellframe_menubar_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_MENUBAR_CTX:-menubar}"
    local _state_var="_SHELLFRAME_MB_${_ctx}_STATE"
    local _idx_var="_SHELLFRAME_MB_${_ctx}_BAR_IDX"
    local _state="${!_state_var}"
    local _n_menus="${#SHELLFRAME_MENU_NAMES[@]}"

    case "$_state" in
        idle)
            return 1
            ;;
        bar)
            case "$_key" in
                "$SHELLFRAME_KEY_RIGHT")
                    local _idx="${!_idx_var}"
                    _idx=$(( (_idx + 1) % _n_menus ))
                    printf -v "$_idx_var" '%d' "$_idx"
                    return 0
                    ;;
                "$SHELLFRAME_KEY_LEFT")
                    local _idx="${!_idx_var}"
                    _idx=$(( (_idx - 1 + _n_menus) % _n_menus ))
                    printf -v "$_idx_var" '%d' "$_idx"
                    return 0
                    ;;
                "$SHELLFRAME_KEY_ENTER"|"$SHELLFRAME_KEY_DOWN")
                    # Open dropdown: init sel context for current menu
                    local _mvar
                    _shellframe_mb_menu_var "${!_idx_var}" _mvar
                    local _n_items
                    eval "_n_items=\${#${_mvar}[@]}"
                    shellframe_sel_init "mb_${_ctx}_dd" "$_n_items"
                    local _first
                    _shellframe_mb_first_selectable "$_mvar" _first
                    # Move cursor to first selectable
                    local _i
                    for (( _i=0; _i<_first; _i++ )); do
                        shellframe_sel_move "mb_${_ctx}_dd" down
                    done
                    printf -v "$_state_var" '%s' "dropdown"
                    return 0
                    ;;
                "$SHELLFRAME_KEY_ESC")
                    SHELLFRAME_MENUBAR_RESULT=""
                    printf -v "$_state_var" '%s' "idle"
                    SHELLFRAME_MENUBAR_FOCUSED=0
                    return 2
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
    return 1
}

shellframe_menubar_size()   { printf '%d %d %d %d' 1 1 0 1; }
shellframe_menubar_open()   { return 1; }
