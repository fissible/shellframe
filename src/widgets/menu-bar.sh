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
    local _parsed_vn="${_rest%%:*}"
    local _parsed_lbl="${_rest#*:}"
    # VARNAME must match [A-Z0-9_]+
    [[ "$_parsed_vn" =~ ^[A-Z0-9_]+$ ]] || return 1
    printf -v "$_out_vn"  '%s' "$_parsed_vn"
    printf -v "$_out_lbl" '%s' "$_parsed_lbl"
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
    # Submenu state: variable name and label of the currently open submenu item
    printf -v "_SHELLFRAME_MB_${_ctx}_SM_VN"  '%s' ""
    printf -v "_SHELLFRAME_MB_${_ctx}_SM_LBL" '%s' ""
    # Selection contexts for dropdown and submenu cursors
    shellframe_sel_init "mb_${_ctx}_dd" 0
    shellframe_sel_init "mb_${_ctx}_sm" 0
}
# ── Internal: blank a rectangular region ──────────────────────────────────────

_shellframe_mb_blank_region() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    (( _width <= 0 || _height <= 0 )) && return 0
    local _r _blank
    printf -v _blank '%*s' "$_width" ''
    for (( _r=0; _r<_height; _r++ )); do
        printf '\033[%d;%dH%s' "$(( _top + _r ))" "$_left" "$_blank" >&3
    done
}

# ── Internal: compute dropdown dimensions ─────────────────────────────────────

# _shellframe_mb_dd_dims ctx out_w out_h
# Computes width and height of the dropdown panel for the current bar index.
_shellframe_mb_dd_dims() {
    local _ctx="$1" _out_w="$2" _out_h="$3"
    local _idx_var="_SHELLFRAME_MB_${_ctx}_BAR_IDX"
    local _mvar
    _shellframe_mb_menu_var "${!_idx_var}" _mvar
    local _n
    eval "_n=\${#${_mvar}[@]}"
    local _max_len=0 _i _item _lbl _vn
    for (( _i=0; _i<_n; _i++ )); do
        eval "_item=\"\${${_mvar}[$_i]}\""
        if _shellframe_mb_is_sep "$_item"; then
            _lbl="───────────"
        elif _shellframe_mb_parse_sigil "$_item" _vn _lbl 2>/dev/null; then
            _lbl="${_lbl} ▶"
        else
            _lbl="$_item"
        fi
        (( ${#_lbl} > _max_len )) && _max_len=${#_lbl}
    done
    printf -v "$_out_w" '%d' "$(( _max_len + 4 ))"   # 2 border + 2 padding
    printf -v "$_out_h" '%d' "$(( _n + 2 ))"          # items + top/bottom border
}

# ── shellframe_menubar_render ──────────────────────────────────────────────────

shellframe_menubar_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_MENUBAR_CTX:-menubar}"
    local _state_var="_SHELLFRAME_MB_${_ctx}_STATE"
    local _idx_var="_SHELLFRAME_MB_${_ctx}_BAR_IDX"
    local _state="${!_state_var}"
    local _bar_idx="${!_idx_var}"

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"
    local _act="${SHELLFRAME_MENUBAR_ACTIVE_COLOR:-${SHELLFRAME_BOLD:-$'\033[1m'}}"

    # ── Erase previous overlay panels ─────────────────────────────────────────
    local _prev_dd_w_var="_SHELLFRAME_MB_${_ctx}_PREV_DD_W"
    local _prev_dd_h_var="_SHELLFRAME_MB_${_ctx}_PREV_DD_H"
    local _prev_dd_top_var="_SHELLFRAME_MB_${_ctx}_PREV_DD_TOP"
    local _prev_dd_left_var="_SHELLFRAME_MB_${_ctx}_PREV_DD_LEFT"
    if (( ${!_prev_dd_w_var} > 0 )); then
        _shellframe_mb_blank_region \
            "${!_prev_dd_top_var}" "${!_prev_dd_left_var}" \
            "${!_prev_dd_w_var}"   "${!_prev_dd_h_var}"
        printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_W" '%d' 0
        printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_H" '%d' 0
    fi
    local _prev_sm_w_var="_SHELLFRAME_MB_${_ctx}_PREV_SM_W"
    local _prev_sm_h_var="_SHELLFRAME_MB_${_ctx}_PREV_SM_H"
    local _prev_sm_top_var="_SHELLFRAME_MB_${_ctx}_PREV_SM_TOP"
    local _prev_sm_left_var="_SHELLFRAME_MB_${_ctx}_PREV_SM_LEFT"
    if (( ${!_prev_sm_w_var} > 0 )); then
        _shellframe_mb_blank_region \
            "${!_prev_sm_top_var}" "${!_prev_sm_left_var}" \
            "${!_prev_sm_w_var}"   "${!_prev_sm_h_var}"
        printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_W" '%d' 0
        printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_H" '%d' 0
    fi

    # ── Bar row ────────────────────────────────────────────────────────────────
    printf '\033[%d;%dH' "$_top" "$_left" >&3
    local _col=0 _i _n_menus="${#SHELLFRAME_MENU_NAMES[@]}"
    for (( _i=0; _i<_n_menus; _i++ )); do
        local _lbl=" ${SHELLFRAME_MENU_NAMES[$_i]} "
        local _llen=${#_lbl}
        (( _col + _llen > _width )) && break
        if [[ "$_state" != "idle" && "$_i" == "$_bar_idx" ]]; then
            printf '%s%s%s' "$_rev" "$_lbl" "$_rst" >&3
        else
            printf '%s' "$_lbl" >&3
        fi
        (( _col += _llen ))
    done
    # Fill remainder
    local _fill=$(( _width - _col ))
    (( _fill > 0 )) && printf '%*s' "$_fill" '' >&3

    # ── Dropdown panel ─────────────────────────────────────────────────────────
    [[ "$_state" == "idle" || "$_state" == "bar" ]] && return 0

    # Compute label_col: sum of label widths up to bar_idx
    local _label_col=$(( _left ))
    for (( _i=0; _i<_bar_idx; _i++ )); do
        (( _label_col += ${#SHELLFRAME_MENU_NAMES[$_i]} + 2 ))
    done
    local _dd_top=$(( _top + 1 ))
    local _dd_w _dd_h
    _shellframe_mb_dd_dims "$_ctx" _dd_w _dd_h

    # Save for teardown
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_TOP"  '%d' "$_dd_top"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_LEFT" '%d' "$_label_col"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_W"    '%d' "$_dd_w"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_DD_H"    '%d' "$_dd_h"

    # Draw double-border panel
    local _inner_w=$(( _dd_w - 2 )) _inner_left=$(( _label_col + 1 ))
    # Top border
    printf '\033[%d;%dH%s╔' "$_dd_top" "$_label_col" "$_act" >&3
    local _k; for (( _k=0; _k<_inner_w; _k++ )); do printf '═' >&3; done
    printf '╗%s' "$_rst" >&3

    # Item rows
    local _mvar; _shellframe_mb_menu_var "$_bar_idx" _mvar
    local _n_items; eval "_n_items=\${#${_mvar}[@]}"
    local _dd_cursor; shellframe_sel_cursor "mb_${_ctx}_dd" _dd_cursor
    for (( _i=0; _i<_n_items; _i++ )); do
        local _row=$(( _dd_top + 1 + _i ))
        local _raw_item; eval "_raw_item=\"\${${_mvar}[$_i]}\""
        local _display _vn _lbl
        if _shellframe_mb_is_sep "$_raw_item"; then
            # Separator row
            printf '\033[%d;%dH%s║%s' "$_row" "$_label_col" "$_act" "$_rst" >&3
            local _j; for (( _j=0; _j<_inner_w; _j++ )); do printf '═' >&3; done
            printf '%s║%s' "$_act" "$_rst" >&3
            continue
        elif _shellframe_mb_parse_sigil "$_raw_item" _vn _lbl 2>/dev/null; then
            _display="${_lbl} ▶"
        else
            _display="$_raw_item"
        fi
        # Pad/clip display to inner_w - 2 (1 space padding each side)
        local _cell_w=$(( _inner_w - 2 ))
        local _padded
        printf -v _padded '%-*s' "$_cell_w" "$_display"
        _padded="${_padded:0:$_cell_w}"

        printf '\033[%d;%dH%s║%s' "$_row" "$_label_col" "$_act" "$_rst" >&3
        if [[ "$_state" == "submenu" && "$_i" == "$_dd_cursor" ]]; then
            # ▶ item — dimmed when submenu is open
            printf ' %s%s%s ' "${SHELLFRAME_RESET:-$'\033[0m'}" "$_padded" "${SHELLFRAME_RESET:-$'\033[0m'}" >&3
        elif [[ "$_state" != "submenu" && "$_i" == "$_dd_cursor" ]]; then
            # Normal cursor highlight
            printf ' %s%s%s ' "$_rev" "$_padded" "$_rst" >&3
        else
            printf ' %s ' "$_padded" >&3
        fi
        printf '%s║%s' "$_act" "$_rst" >&3
    done

    # Bottom border
    local _bot=$(( _dd_top + _dd_h - 1 ))
    printf '\033[%d;%dH%s╚' "$_bot" "$_label_col" "$_act" >&3
    for (( _k=0; _k<_inner_w; _k++ )); do printf '═' >&3; done
    printf '╝%s' "$_rst" >&3

    # ── Submenu panel ──────────────────────────────────────────────────────────
    [[ "$_state" != "submenu" ]] && return 0

    local _raw_dd_item _sm_vn _sm_lbl
    eval "_raw_dd_item=\"\${${_mvar}[$_dd_cursor]}\""
    _shellframe_mb_parse_sigil "$_raw_dd_item" _sm_vn _sm_lbl 2>/dev/null || return 0
    local _sm_var="SHELLFRAME_MENU_${_sm_vn}"
    local _n_sm; eval "_n_sm=\${#${_sm_var}[@]}"

    # Submenu panel top = dropdown_top + 1 + cursor_item_index
    local _sm_top=$(( _dd_top + 1 + _dd_cursor ))
    local _sm_left=$(( _label_col + _dd_w ))

    # Compute submenu width
    local _sm_max=0
    for (( _i=0; _i<_n_sm; _i++ )); do
        local _si; eval "_si=\"\${${_sm_var}[$_i]}\""
        (( ${#_si} > _sm_max )) && _sm_max=${#_si}
    done
    local _sm_w=$(( _sm_max + 4 ))
    local _sm_h=$(( _n_sm + 2 ))
    local _sm_inner_w=$(( _sm_w - 2 ))

    # Save for teardown
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_TOP"  '%d' "$_sm_top"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_LEFT" '%d' "$_sm_left"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_W"    '%d' "$_sm_w"
    printf -v "_SHELLFRAME_MB_${_ctx}_PREV_SM_H"    '%d' "$_sm_h"

    # Top border
    printf '\033[%d;%dH%s╔' "$_sm_top" "$_sm_left" "$_act" >&3
    for (( _k=0; _k<_sm_inner_w; _k++ )); do printf '═' >&3; done
    printf '╗%s' "$_rst" >&3

    local _sm_cursor; shellframe_sel_cursor "mb_${_ctx}_sm" _sm_cursor
    for (( _i=0; _i<_n_sm; _i++ )); do
        local _row=$(( _sm_top + 1 + _i ))
        local _si; eval "_si=\"\${${_sm_var}[$_i]}\""
        local _cell_w=$(( _sm_inner_w - 2 ))
        local _padded; printf -v _padded '%-*s' "$_cell_w" "$_si"; _padded="${_padded:0:$_cell_w}"
        printf '\033[%d;%dH%s║%s' "$_row" "$_sm_left" "$_act" "$_rst" >&3
        if [[ "$_i" == "$_sm_cursor" ]]; then
            printf ' %s%s%s ' "$_rev" "$_padded" "$_rst" >&3
        else
            printf ' %s ' "$_padded" >&3
        fi
        printf '%s║%s' "$_act" "$_rst" >&3
    done

    local _sm_bot=$(( _sm_top + _sm_h - 1 ))
    printf '\033[%d;%dH%s╚' "$_sm_bot" "$_sm_left" "$_act" >&3
    for (( _k=0; _k<_sm_inner_w; _k++ )); do printf '═' >&3; done
    printf '╝%s' "$_rst" >&3
}

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
    # Validate against [A-Z0-9_]+ before use in eval
    [[ "$_uname" =~ ^[A-Z0-9_]+$ ]] || { printf -v "$_out" '%s' ""; return 1; }
    printf -v "$_out" '%s' "SHELLFRAME_MENU_${_uname}"
}

# ── Internal: open dropdown for a given bar index ──────────────────────────────

# _shellframe_mb_open_dropdown ctx bar_idx
# Re-initialises the dropdown selection context for the menu at bar_idx.
# Moves cursor to the first selectable item.
_shellframe_mb_open_dropdown() {
    local _ctx="$1" _idx="$2"
    local _mvar
    _shellframe_mb_menu_var "$_idx" _mvar
    local _n_items
    eval "_n_items=\${#${_mvar}[@]}"
    shellframe_sel_init "mb_${_ctx}_dd" "$_n_items"
    local _first=0
    _shellframe_mb_first_selectable "$_mvar" _first || true
    local _i
    for (( _i=0; _i<_first; _i++ )); do
        shellframe_sel_move "mb_${_ctx}_dd" down
    done
}

# ── Internal: skip separators (move cursor past --- items) ────────────────────

# _shellframe_mb_skip_seps ctx sel_ctx arr_var direction
# Moves the cursor in direction until it lands on a non-separator item.
_shellframe_mb_skip_seps() {
    local _ctx="$1" _sel_ctx="$2" _arr_var="$3" _dir="$4"
    local _n
    eval "_n=\${#${_arr_var}[@]}"
    local _max=$(( _n + 1 )) _i=0 _cursor _item
    while (( _i++ < _max )); do
        shellframe_sel_cursor "$_sel_ctx" _cursor
        eval "_item=\"\${${_arr_var}[$_cursor]}\""
        _shellframe_mb_is_sep "$_item" || break
        shellframe_sel_move "$_sel_ctx" "$_dir"
    done
}

# ── shellframe_menubar_on_key ──────────────────────────────────────────────────

shellframe_menubar_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_MENUBAR_CTX:-menubar}"
    local _state_var="_SHELLFRAME_MB_${_ctx}_STATE"
    local _idx_var="_SHELLFRAME_MB_${_ctx}_BAR_IDX"
    local _state="${!_state_var}"
    local _n_menus="${#SHELLFRAME_MENU_NAMES[@]}"
    (( _n_menus == 0 )) && return 1

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
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_LEFT")
                    local _idx="${!_idx_var}"
                    _idx=$(( (_idx - 1 + _n_menus) % _n_menus ))
                    printf -v "$_idx_var" '%d' "$_idx"
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_ENTER"|"$SHELLFRAME_KEY_DOWN")
                    _shellframe_mb_open_dropdown "$_ctx" "${!_idx_var}"
                    printf -v "$_state_var" '%s' "dropdown"
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_UP"|"$SHELLFRAME_KEY_ESC")
                    SHELLFRAME_MENUBAR_RESULT=""
                    printf -v "$_state_var" '%s' "idle"
                    SHELLFRAME_MENUBAR_FOCUSED=0
                    shellframe_shell_mark_dirty; return 2
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        dropdown)
            local _idx="${!_idx_var}"
            local _mvar
            _shellframe_mb_menu_var "$_idx" _mvar
            case "$_key" in
                "$SHELLFRAME_KEY_DOWN")
                    shellframe_sel_move "mb_${_ctx}_dd" down
                    _shellframe_mb_skip_seps "$_ctx" "mb_${_ctx}_dd" "$_mvar" down
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_UP")
                    local _cursor
                    shellframe_sel_cursor "mb_${_ctx}_dd" _cursor
                    local _first=0
                    _shellframe_mb_first_selectable "$_mvar" _first || true
                    if (( _cursor <= _first )); then
                        # Already at first selectable — close dropdown to bar
                        printf -v "$_state_var" '%s' "bar"
                        shellframe_shell_mark_dirty; return 0
                    fi
                    shellframe_sel_move "mb_${_ctx}_dd" up
                    _shellframe_mb_skip_seps "$_ctx" "mb_${_ctx}_dd" "$_mvar" up
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_RIGHT"|"$SHELLFRAME_KEY_LEFT")
                    # Check if cursor is on a sigil item AND key is Right
                    local _cursor _raw_item _vn="" _lbl=""
                    shellframe_sel_cursor "mb_${_ctx}_dd" _cursor
                    eval "_raw_item=\"\${${_mvar}[$_cursor]}\""
                    if [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" ]] && \
                       _shellframe_mb_parse_sigil "$_raw_item" _vn _lbl 2>/dev/null; then
                        # Open submenu
                        local _sm_var="SHELLFRAME_MENU_${_vn}"
                        local _n_sm=0
                        eval "_n_sm=\${#${_sm_var}[@]}"
                        shellframe_sel_init "mb_${_ctx}_sm" "$_n_sm"
                        printf -v "_SHELLFRAME_MB_${_ctx}_SM_VN"  '%s' "$_vn"
                        printf -v "_SHELLFRAME_MB_${_ctx}_SM_LBL" '%s' "$_lbl"
                        printf -v "$_state_var" '%s' "submenu"
                        shellframe_shell_mark_dirty; return 0
                    fi
                    # Move to adjacent top-level menu
                    if [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" ]]; then
                        _idx=$(( (_idx + 1) % _n_menus ))
                    else
                        _idx=$(( (_idx - 1 + _n_menus) % _n_menus ))
                    fi
                    printf -v "$_idx_var" '%d' "$_idx"
                    _shellframe_mb_open_dropdown "$_ctx" "$_idx"
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_ENTER")
                    local _cursor _raw_item _vn="" _lbl=""
                    shellframe_sel_cursor "mb_${_ctx}_dd" _cursor
                    eval "_raw_item=\"\${${_mvar}[$_cursor]}\""
                    if _shellframe_mb_parse_sigil "$_raw_item" _vn _lbl 2>/dev/null; then
                        # Open submenu
                        local _sm_var="SHELLFRAME_MENU_${_vn}"
                        local _n_sm=0
                        eval "_n_sm=\${#${_sm_var}[@]}"
                        shellframe_sel_init "mb_${_ctx}_sm" "$_n_sm"
                        printf -v "_SHELLFRAME_MB_${_ctx}_SM_VN"  '%s' "$_vn"
                        printf -v "_SHELLFRAME_MB_${_ctx}_SM_LBL" '%s' "$_lbl"
                        printf -v "$_state_var" '%s' "submenu"
                        shellframe_shell_mark_dirty; return 0
                    fi
                    # Leaf selection
                    local _menu_label="${SHELLFRAME_MENU_NAMES[$_idx]}"
                    SHELLFRAME_MENUBAR_RESULT="${_menu_label}|${_raw_item}"
                    printf -v "$_state_var" '%s' "idle"
                    SHELLFRAME_MENUBAR_FOCUSED=0
                    shellframe_shell_mark_dirty; return 2
                    ;;
                "$SHELLFRAME_KEY_ESC")
                    printf -v "$_state_var" '%s' "bar"
                    shellframe_shell_mark_dirty; return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        submenu)
            local _idx="${!_idx_var}"
            local _vn_var="_SHELLFRAME_MB_${_ctx}_SM_VN"
            local _lbl_var="_SHELLFRAME_MB_${_ctx}_SM_LBL"
            local _vn="${!_vn_var}"
            local _lbl="${!_lbl_var}"
            local _sm_var="SHELLFRAME_MENU_${_vn}"

            case "$_key" in
                "$SHELLFRAME_KEY_DOWN")
                    shellframe_sel_move "mb_${_ctx}_sm" down
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_UP")
                    shellframe_sel_move "mb_${_ctx}_sm" up
                    shellframe_shell_mark_dirty; return 0
                    ;;
                "$SHELLFRAME_KEY_ENTER")
                    local _sm_cursor _sm_item
                    shellframe_sel_cursor "mb_${_ctx}_sm" _sm_cursor
                    eval "_sm_item=\"\${${_sm_var}[$_sm_cursor]}\""
                    local _menu_label="${SHELLFRAME_MENU_NAMES[$_idx]}"
                    SHELLFRAME_MENUBAR_RESULT="${_menu_label}|${_lbl}|${_sm_item}"
                    printf -v "$_state_var" '%s' "idle"
                    SHELLFRAME_MENUBAR_FOCUSED=0
                    shellframe_shell_mark_dirty; return 2
                    ;;
                "$SHELLFRAME_KEY_LEFT"|"$SHELLFRAME_KEY_ESC")
                    printf -v "$_state_var" '%s' "dropdown"
                    shellframe_shell_mark_dirty; return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
    return 1
}

shellframe_menubar_size() { printf '%d %d %d %d' 1 1 0 1; }

shellframe_menubar_open() {
    local _name="$1"
    local _ctx="${SHELLFRAME_MENUBAR_CTX:-menubar}"
    local _n="${#SHELLFRAME_MENU_NAMES[@]}" _i
    for (( _i=0; _i<_n; _i++ )); do
        if [[ "${SHELLFRAME_MENU_NAMES[$_i]}" == "$_name" ]]; then
            shellframe_menubar_on_focus 1
            local _idx_var="_SHELLFRAME_MB_${_ctx}_BAR_IDX"
            local _state_var="_SHELLFRAME_MB_${_ctx}_STATE"
            printf -v "$_idx_var" '%d' "$_i"
            _shellframe_mb_open_dropdown "$_ctx" "$_i"
            printf -v "$_state_var" '%s' "dropdown"
            return 0
        fi
    done
    return 1
}
