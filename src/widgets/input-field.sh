#!/usr/bin/env bash
# shellframe/src/widgets/input-field.sh — Single-line text input (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/cursor.sh, src/input.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A single-line editable text field.  Supports cursor movement, insert/delete,
# kill operations, and password masking.  Text state is managed via cursor.sh;
# set SHELLFRAME_FIELD_CTX to the cursor context name.
#
# Call shellframe_field_init before first use to initialise the cursor context.
# Multiple fields can coexist by using different SHELLFRAME_FIELD_CTX values.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_FIELD_CTX          — cursor context name (default: "field")
#   SHELLFRAME_FIELD_PLACEHOLDER  — dim hint shown when empty and unfocused
#   SHELLFRAME_FIELD_MASK         — 0 (default) | 1 (replace chars with ●)
#   SHELLFRAME_FIELD_FOCUSED      — 0 (default) | 1
#   SHELLFRAME_FIELD_FOCUSABLE    — 1 (default) | 0
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_field_init [ctx]
#     Initialise the cursor context for this field (empty text, pos=0).
#
#   shellframe_field_render top left width height
#     Draw the field content in the first row of the region.
#     Output goes to /dev/tty.
#
#   shellframe_field_on_key key
#     Handle a keypress.  Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Enter pressed (field confirmed; read value via shellframe_cur_text)
#
#   shellframe_field_on_focus focused  — set SHELLFRAME_FIELD_FOCUSED
#
#   shellframe_field_size              — print "1 1 0 1"

SHELLFRAME_FIELD_CTX="field"
SHELLFRAME_FIELD_PLACEHOLDER=""
SHELLFRAME_FIELD_MASK=0
SHELLFRAME_FIELD_FOCUSED=0
SHELLFRAME_FIELD_FOCUSABLE=1

# ── shellframe_field_init ────────────────────────────────────────────────────

shellframe_field_init() {
    local _ctx="${1:-${SHELLFRAME_FIELD_CTX:-field}}"
    shellframe_cur_init "$_ctx"
}

# ── Internal: printability check ─────────────────────────────────────────────

# Return 0 if _key is a single printable ASCII character (0x20–0x7E).
_shellframe_field_is_printable() {
    local _k="$1"
    [[ ${#_k} -ne 1 ]] && return 1
    case "$_k" in
        [[:print:]]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── shellframe_field_render ───────────────────────────────────────────────────

shellframe_field_render() {
    local _top="$1" _left="$2" _width="$3"
    # height param accepted; field always occupies exactly 1 row
    local _ctx="${SHELLFRAME_FIELD_CTX:-field}"
    local _focused="${SHELLFRAME_FIELD_FOCUSED:-0}"
    local _mask="${SHELLFRAME_FIELD_MASK:-0}"
    local _placeholder="${SHELLFRAME_FIELD_PLACEHOLDER:-}"

    local _text _pos
    shellframe_cur_text "$_ctx" _text
    shellframe_cur_pos  "$_ctx" _pos

    # Clear the row
    shellframe_fb_fill "$_top" "$_left" "$_width"

    # Empty + unfocused: show placeholder
    if [[ -z "$_text" && $(( _focused )) -eq 0 && -n "$_placeholder" ]]; then
        local _ph
        shellframe_str_clip_ellipsis "$_placeholder" "$_placeholder" "$_width" _ph
        shellframe_fb_print "$_top" "$_left" "$_ph" $'\033[2m'
        return 0
    fi

    # Apply mask (password mode)
    local _disp="$_text"
    if (( _mask )); then
        local _mi _mc="" _ml=${#_text}
        for (( _mi=0; _mi<_ml; _mi++ )); do _mc="${_mc}●"; done
        _disp="$_mc"
    fi

    # Horizontal scroll to keep cursor in viewport
    local _scroll=0
    if (( _pos >= _width )); then
        _scroll=$(( _pos - _width + 1 ))
    fi

    # Visible slice of text
    local _vis="${_disp:$_scroll:$_width}"
    local _vlen=${#_vis}
    local _cur_vis=$(( _pos - _scroll ))

    if (( _focused )); then
        local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"

        # Text before cursor
        shellframe_fb_print "$_top" "$_left" "${_vis:0:$_cur_vis}"

        # Cursor: highlight char at cursor pos, or a space if at end of text
        if (( _cur_vis < _vlen )); then
            shellframe_fb_put "$_top" "$(( _left + _cur_vis ))" "${_rev}${_vis:$_cur_vis:1}"
            shellframe_fb_print "$_top" "$(( _left + _cur_vis + 1 ))" "${_vis:$(( _cur_vis + 1 ))}"
        else
            shellframe_fb_put "$_top" "$(( _left + _cur_vis ))" "${_rev} "
        fi

        # Pad remaining columns
        local _drawn=$(( _vlen < _width ? _vlen : _width ))
        (( _cur_vis >= _vlen )) && (( _drawn++ )) || true
        shellframe_fb_fill "$_top" "$(( _left + _drawn ))" "$(( _width - _drawn ))"
    else
        shellframe_fb_print "$_top" "$_left" "$_vis"
        shellframe_fb_fill  "$_top" "$(( _left + _vlen ))" "$(( _width - _vlen ))"
    fi
}

# ── shellframe_field_on_key ───────────────────────────────────────────────────

shellframe_field_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_FIELD_CTX:-field}"

    # Use SHELLFRAME_KEY_* constants with raw-sequence fallbacks
    local _k_bs="${SHELLFRAME_KEY_BACKSPACE:-$'\x7f'}"
    local _k_del="${SHELLFRAME_KEY_DELETE:-$'\033[3~'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"
    local _k_ctrl_a="${SHELLFRAME_KEY_CTRL_A:-$'\x01'}"
    local _k_ctrl_e="${SHELLFRAME_KEY_CTRL_E:-$'\x05'}"
    local _k_ctrl_k="${SHELLFRAME_KEY_CTRL_K:-$'\x0b'}"
    local _k_ctrl_u="${SHELLFRAME_KEY_CTRL_U:-$'\x15'}"
    local _k_ctrl_w="${SHELLFRAME_KEY_CTRL_W:-$'\x17'}"

    if [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]]; then
        shellframe_shell_mark_dirty
        return 2    # Enter: field confirmed
    elif [[ "$_key" == "$_k_bs" ]]; then
        shellframe_cur_backspace "$_ctx"
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_del" ]]; then
        shellframe_cur_delete "$_ctx"
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_left" ]]; then
        shellframe_cur_move "$_ctx" left
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_right" ]]; then
        shellframe_cur_move "$_ctx" right
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_home" ]] || [[ "$_key" == "$_k_ctrl_a" ]]; then
        shellframe_cur_move "$_ctx" home
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_end" ]] || [[ "$_key" == "$_k_ctrl_e" ]]; then
        shellframe_cur_move "$_ctx" end
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_ctrl_k" ]]; then
        shellframe_cur_kill_to_end "$_ctx"
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_ctrl_u" ]]; then
        shellframe_cur_kill_to_start "$_ctx"
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_ctrl_w" ]]; then
        shellframe_cur_kill_word_left "$_ctx"
        shellframe_shell_mark_dirty; return 0
    elif _shellframe_field_is_printable "$_key"; then
        shellframe_cur_insert "$_ctx" "$_key"
        shellframe_shell_mark_dirty; return 0
    fi

    return 1
}

# ── shellframe_field_on_focus ─────────────────────────────────────────────────

shellframe_field_on_focus() {
    SHELLFRAME_FIELD_FOCUSED="${1:-0}"
}

# ── shellframe_field_size ─────────────────────────────────────────────────────

# min: 1×1 (at minimum shows the cursor); preferred: full-width (0) × 1 row
shellframe_field_size() {
    printf '%d %d %d %d' 1 1 0 1
}
