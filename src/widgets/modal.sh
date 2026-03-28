#!/usr/bin/env bash
# shellframe/src/widgets/modal.sh — Modal/dialog overlay (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/panel.sh, src/widgets/input-field.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A centered overlay container for confirmations, prompts, and informational
# alerts.  Renders a bordered panel with an optional title, a message body,
# an optional single-line input field, and a row of labelled buttons.
#
# Focus is trapped inside the modal: only button cycling (Left/Right/Tab) and
# confirm/dismiss (Enter/Esc) are handled.  When SHELLFRAME_MODAL_INPUT=1,
# text-editing keys are forwarded to the embedded field; Tab then cycles
# buttons.
#
# ── Layout ─────────────────────────────────────────────────────────────────
#
#   ┌── Title ──────────────────────┐
#   │                               │  ← inner row 0: top padding
#   │  Message text (word-wrapped)  │  ← inner rows 1..n_msg
#   │                               │  ← gap row
#   │  [input field]                │  (if SHELLFRAME_MODAL_INPUT=1)
#   │                               │  ← gap row  (if input)
#   │     [ OK ]  [ Cancel ]        │  ← last inner row: button row
#   └───────────────────────────────┘
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MODAL_TITLE       — panel border title (empty → none)
#   SHELLFRAME_MODAL_MESSAGE     — body text; "\n" is treated as a line break
#   SHELLFRAME_MODAL_BUTTONS[@]  — button labels (default: ("OK" "Cancel"))
#   SHELLFRAME_MODAL_ACTIVE_BTN  — index of highlighted button (0-based)
#   SHELLFRAME_MODAL_STYLE       — border style: single (default) | double | rounded | none
#   SHELLFRAME_MODAL_FOCUSED     — 0 (default) | 1
#   SHELLFRAME_MODAL_FOCUSABLE   — 1 (default) | 0
#   SHELLFRAME_MODAL_WIDTH       — fixed modal width  (0 = content-driven)
#   SHELLFRAME_MODAL_HEIGHT      — fixed modal height (0 = content-driven)
#   SHELLFRAME_MODAL_INPUT       — 0 (default) | 1 (show embedded input field)
#   SHELLFRAME_MODAL_INPUT_CTX   — cursor context for the input field (default: "modal_input")
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MODAL_RESULT  — set when on_key returns 2:
#                              active button index (0-based) on Enter,
#                              -1 on Escape or q/Q dismiss.
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_modal_init [input_ctx]
#     Initialise the embedded input field's cursor context.  Call before use
#     if SHELLFRAME_MODAL_INPUT=1.
#
#   shellframe_modal_render top left width height
#     Compute modal dimensions, center in the given region, draw the panel,
#     message, optional input field, and button row.  Output to /dev/tty.
#
#   shellframe_modal_on_key key
#     Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Enter or Esc: SHELLFRAME_MODAL_RESULT is set; app shell fires event
#
#   shellframe_modal_on_focus focused  — set SHELLFRAME_MODAL_FOCUSED
#
#   shellframe_modal_size              — print "20 7 0 0"

SHELLFRAME_MODAL_TITLE=""
SHELLFRAME_MODAL_MESSAGE=""
SHELLFRAME_MODAL_BUTTONS=("OK" "Cancel")
SHELLFRAME_MODAL_ACTIVE_BTN=0
SHELLFRAME_MODAL_STYLE="single"
SHELLFRAME_MODAL_FOCUSED=0
SHELLFRAME_MODAL_FOCUSABLE=1
SHELLFRAME_MODAL_WIDTH=0
SHELLFRAME_MODAL_HEIGHT=0
SHELLFRAME_MODAL_INPUT=0
SHELLFRAME_MODAL_INPUT_CTX="modal_input"
SHELLFRAME_MODAL_RESULT=-1

# ── shellframe_modal_init ─────────────────────────────────────────────────────

shellframe_modal_init() {
    local _ctx="${1:-${SHELLFRAME_MODAL_INPUT_CTX:-modal_input}}"
    shellframe_field_init "$_ctx"
}

# ── Internal: render button row ───────────────────────────────────────────────

# _shellframe_modal_render_buttons row left inner_width active
# Draws the button row centered within the inner width.
_shellframe_modal_render_buttons() {
    local _row="$1" _left="$2" _inner_w="$3" _active="$4"
    local _n_btns=${#SHELLFRAME_MODAL_BUTTONS[@]}
    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"

    # Clear the row
    shellframe_fb_fill "$_row" "$_left" "$_inner_w"

    (( _n_btns == 0 )) && return

    # Build "[ label ]" strings and measure total width
    local _btn_strs=()
    local _total_w=0
    local _b
    for _b in "${SHELLFRAME_MODAL_BUTTONS[@]+"${SHELLFRAME_MODAL_BUTTONS[@]}"}"; do
        local _bs="[ ${_b} ]"
        _btn_strs+=("$_bs")
        (( _total_w += ${#_bs} ))
    done
    # One space between each button
    (( _n_btns > 1 )) && (( _total_w += _n_btns - 1 ))

    # Center within inner_width
    local _pad=$(( (_inner_w - _total_w) / 2 ))
    (( _pad < 0 )) && _pad=0

    local _c=$(( _left + _pad ))
    local _i
    for (( _i=0; _i<_n_btns; _i++ )); do
        if (( _i > 0 )); then
            shellframe_fb_put "$_row" "$_c" " "; (( _c++ ))
        fi
        local _bs="${_btn_strs[$_i]}"
        if (( _i == _active )); then
            shellframe_fb_print "$_row" "$_c" "$_bs" "$_rev"
        else
            shellframe_fb_print "$_row" "$_c" "$_bs"
        fi
        (( _c += ${#_bs} ))
    done
}

# ── Internal: compute content-driven dimensions ───────────────────────────────

# _shellframe_modal_dims max_w max_h out_modal_w out_modal_h
# Computes the modal's width and height, clamped to max_w × max_h.
# Stores results via printf -v into out_modal_w and out_modal_h.
_shellframe_modal_dims() {
    local _max_w="$1" _max_h="$2"
    local _out_w="$3" _out_h="$4"

    # ── Message lines ──
    local _msg="${SHELLFRAME_MODAL_MESSAGE:-}"
    local _n_msg=0 _msg_max_w=0
    if [[ -n "$_msg" ]]; then
        local _line
        while IFS= read -r _line; do
            (( _n_msg++ ))
            local _ll=${#_line}
            (( _ll > _msg_max_w )) && _msg_max_w=$_ll
        done < <(printf '%s\n' "$_msg")
    fi
    (( _n_msg == 0 )) && _n_msg=1   # at least one row of message space

    # ── Button row width ──
    local _btn_row_w=0
    local _n_btns=${#SHELLFRAME_MODAL_BUTTONS[@]}
    local _b
    for _b in "${SHELLFRAME_MODAL_BUTTONS[@]+"${SHELLFRAME_MODAL_BUTTONS[@]}"}"; do
        (( _btn_row_w += ${#_b} + 4 ))   # "[ " + label + " ]"
    done
    (( _n_btns > 1 )) && (( _btn_row_w += _n_btns - 1 ))  # spaces between

    # ── Width ──
    # Need inner_w >= max(message lines + 2-char side margins, button row) + 4 (border margins)
    local _need_inner_w=$(( _msg_max_w + 4 ))
    local _btn_inner_w=$(( _btn_row_w + 4 ))
    (( _btn_inner_w > _need_inner_w )) && _need_inner_w=$_btn_inner_w
    local _need_w=$(( _need_inner_w + 2 ))   # + 2 for border columns
    (( _need_w < 20 )) && _need_w=20

    local _dim_w="${SHELLFRAME_MODAL_WIDTH:-0}"
    (( _dim_w == 0 )) && _dim_w=$_need_w
    (( _dim_w > _max_w )) && _dim_w=$_max_w

    # ── Height ──
    # inner rows: 1 (top pad) + n_msg + 1 (gap) + [input: 1+1] + 1 (buttons)
    local _inner_h=$(( 1 + _n_msg + 1 + 1 ))
    (( ${SHELLFRAME_MODAL_INPUT:-0} )) && (( _inner_h += 2 ))
    local _title_row=0
    [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1
    local _need_h=$(( _inner_h + 2 + _title_row ))   # + 2 for border rows, + 1 for windowed title bar
    (( _need_h < 7 )) && _need_h=7

    local _dim_h="${SHELLFRAME_MODAL_HEIGHT:-0}"
    (( _dim_h == 0 )) && _dim_h=$_need_h
    (( _dim_h > _max_h )) && _dim_h=$_max_h

    printf -v "$_out_w" '%d' "$_dim_w"
    printf -v "$_out_h" '%d' "$_dim_h"
}

# ── shellframe_modal_render ───────────────────────────────────────────────────

shellframe_modal_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _style="${SHELLFRAME_MODAL_STYLE:-single}"
    local _focused="${SHELLFRAME_MODAL_FOCUSED:-0}"
    local _active="${SHELLFRAME_MODAL_ACTIVE_BTN:-0}"
    local _has_input="${SHELLFRAME_MODAL_INPUT:-0}"

    # ── Compute and center modal dimensions ──
    local _modal_w _modal_h
    _shellframe_modal_dims "$_width" "$_height" _modal_w _modal_h

    local _modal_top=$(( _top  + (_height - _modal_h) / 2 ))
    local _modal_left=$(( _left + (_width  - _modal_w) / 2 ))

    # ── Draw panel border ──
    local _save_style="$SHELLFRAME_PANEL_STYLE"
    local _save_title="$SHELLFRAME_PANEL_TITLE"
    local _save_talign="$SHELLFRAME_PANEL_TITLE_ALIGN"
    local _save_pfocused="$SHELLFRAME_PANEL_FOCUSED"
    local _save_pmode="${SHELLFRAME_PANEL_MODE:-framed}"      # pass-through: caller controls windowed mode
    local _save_ptitlebg="${SHELLFRAME_PANEL_TITLE_BG:-}"     # pass-through: caller controls title bar style

    SHELLFRAME_PANEL_STYLE="$_style"
    SHELLFRAME_PANEL_TITLE="${SHELLFRAME_MODAL_TITLE:-}"
    SHELLFRAME_PANEL_TITLE_ALIGN="center"
    SHELLFRAME_PANEL_FOCUSED="$_focused"
    shellframe_panel_render "$_modal_top" "$_modal_left" "$_modal_w" "$_modal_h"

    SHELLFRAME_PANEL_STYLE="$_save_style"
    SHELLFRAME_PANEL_TITLE="$_save_title"
    SHELLFRAME_PANEL_TITLE_ALIGN="$_save_talign"
    SHELLFRAME_PANEL_FOCUSED="$_save_pfocused"
    SHELLFRAME_PANEL_MODE="$_save_pmode"
    SHELLFRAME_PANEL_TITLE_BG="$_save_ptitlebg"

    # ── Compute inner content region ──
    local _border=0
    [[ "$_style" != "none" ]] && _border=1
    local _title_row=0
    [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1
    local _inner_top=$(( _modal_top  + _border + _title_row ))
    local _inner_left=$(( _modal_left + _border ))
    local _inner_w=$(( _modal_w - _border * 2 ))
    local _inner_h=$(( _modal_h - _border * 2 - _title_row ))

    # Clear inner area
    local _ir
    for (( _ir=0; _ir<_inner_h; _ir++ )); do
        shellframe_fb_fill "$(( _inner_top + _ir ))" "$_inner_left" "$_inner_w"
    done

    # ── Render message body (rows 1..n, with 2-char side margins) ──
    local _msg="${SHELLFRAME_MODAL_MESSAGE:-}"
    local _msg_col=$(( _inner_left + 2 ))
    local _msg_avail=$(( _inner_w - 4 ))
    (( _msg_avail < 1 )) && _msg_avail=1

    local _msg_row=$(( _inner_top + 1 ))   # row 0 = top padding
    if [[ -n "$_msg" ]]; then
        local _line
        while IFS= read -r _line; do
            if (( _msg_row < _inner_top + _inner_h - 1 )); then
                local _clipped
                shellframe_str_clip_ellipsis "$_line" "$_line" "$_msg_avail" _clipped
                shellframe_fb_print "$_msg_row" "$_msg_col" "$_clipped"
            fi
            (( _msg_row++ ))
        done < <(printf '%s\n' "$_msg")
    fi

    # ── Render input field (if enabled) ──
    if (( _has_input )); then
        local _field_row=$(( _msg_row + 1 ))   # one gap row after message
        local _field_col=$(( _inner_left + 2 ))
        local _field_w=$(( _inner_w - 4 ))
        (( _field_w < 1 )) && _field_w=1

        if (( _field_row < _inner_top + _inner_h - 1 )); then
            local _save_fctx="$SHELLFRAME_FIELD_CTX"
            local _save_ffoc="$SHELLFRAME_FIELD_FOCUSED"
            SHELLFRAME_FIELD_CTX="${SHELLFRAME_MODAL_INPUT_CTX:-modal_input}"
            SHELLFRAME_FIELD_FOCUSED="$_focused"
            shellframe_field_render "$_field_row" "$_field_col" "$_field_w" 1
            SHELLFRAME_FIELD_CTX="$_save_fctx"
            SHELLFRAME_FIELD_FOCUSED="$_save_ffoc"
        fi
    fi

    # ── Render button row (last inner row) ──
    local _btn_row=$(( _inner_top + _inner_h - 1 ))
    if (( _btn_row >= _inner_top )); then
        _shellframe_modal_render_buttons "$_btn_row" "$_inner_left" "$_inner_w" "$_active"
    fi
}

# ── shellframe_modal_on_key ───────────────────────────────────────────────────

shellframe_modal_on_key() {
    local _key="$1"
    local _n_btns=${#SHELLFRAME_MODAL_BUTTONS[@]}
    (( _n_btns == 0 )) && _n_btns=1

    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_tab="${SHELLFRAME_KEY_TAB:-$'\t'}"

    # ── Input field forwarding ──
    # In input mode, forward all keys to the field first (except Enter/Esc/Tab which the
    # modal always owns).  Left/Right move the text cursor; Tab cycles buttons.
    if (( ${SHELLFRAME_MODAL_INPUT:-0} )); then
        if [[ "$_key" != $'\r' && "$_key" != $'\n' && "$_key" != $'\033' && "$_key" != "$_k_tab" ]]; then
            local _save_fctx="$SHELLFRAME_FIELD_CTX"
            SHELLFRAME_FIELD_CTX="${SHELLFRAME_MODAL_INPUT_CTX:-modal_input}"
            shellframe_field_on_key "$_key"
            local _frc=$?
            SHELLFRAME_FIELD_CTX="$_save_fctx"
            (( _frc == 0 )) && return 0
        fi
    fi

    # ── Modal navigation ──
    if [[ "$_key" == $'\r' || "$_key" == $'\n' ]]; then
        SHELLFRAME_MODAL_RESULT="${SHELLFRAME_MODAL_ACTIVE_BTN:-0}"
        return 2
    elif [[ "$_key" == $'\033' ]]; then
        SHELLFRAME_MODAL_RESULT=-1
        return 2
    elif [[ "$_key" == "$_k_left" ]]; then
        local _cur="${SHELLFRAME_MODAL_ACTIVE_BTN:-0}"
        (( _cur > 0 )) && SHELLFRAME_MODAL_ACTIVE_BTN=$(( _cur - 1 )) || true
        return 0
    elif [[ "$_key" == "$_k_right" || "$_key" == "$_k_tab" ]]; then
        local _cur="${SHELLFRAME_MODAL_ACTIVE_BTN:-0}"
        (( _cur < _n_btns - 1 )) && SHELLFRAME_MODAL_ACTIVE_BTN=$(( _cur + 1 )) || true
        return 0
    fi

    return 1
}

# ── shellframe_modal_on_focus ─────────────────────────────────────────────────

shellframe_modal_on_focus() {
    SHELLFRAME_MODAL_FOCUSED="${1:-0}"
}

# ── shellframe_modal_size ─────────────────────────────────────────────────────

# min: 20×7 (comfortable minimum for a one-line message + two buttons).
# preferred: 0×0 (render centers itself in whatever region it receives).
shellframe_modal_size() {
    printf '%d %d %d %d' 20 7 0 0
}
