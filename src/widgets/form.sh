#!/usr/bin/env bash
# shellframe/src/widgets/form.sh — Multi-field labeled form widget
#
# COMPATIBILITY: bash 3.2+
# REQUIRES: src/cursor.sh, src/widgets/input-field.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A scrollable N-field form. Each field is a shellframe_field instance.
# The caller draws the enclosing panel; shellframe_form_render fills the inner
# area with labeled field rows.
#
# ── Caller-set globals ────────────────────────────────────────────────────────
#
#   SHELLFRAME_FORM_FIELDS[@]  — field definitions: "label<TAB>ctx<TAB>type"
#                                type: text (default) | readonly | password
#
# ── Per-context state (keyed by form ctx) ────────────────────────────────────
#
#   _SHELLFRAME_FORM_${ctx}_FOCUS   — focused field index (0-based)
#   _SHELLFRAME_FORM_${ctx}_ERROR   — inline error string (empty = no error)
#   _SHELLFRAME_FORM_${ctx}_SCROLL  — scroll offset (rows hidden above viewport)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_form_init ctx
#     Initialize all field cursor contexts; reset focus and scroll.
#
#   shellframe_form_render ctx top left width height
#     Draw labeled fields. Each field: "  label:  [value]"
#     Scrolls to keep focused field visible. If _ERROR is set, renders
#     it on the last visible row in a warning color.
#
#   shellframe_form_on_key ctx key
#     Returns:
#       0  — key handled (redraw needed)
#       1  — key not handled
#       2  — Enter pressed (submit)
#
#   shellframe_form_values ctx out_array
#     Fill out_array with current text value for each field (by index).
#
#   shellframe_form_set_value ctx field_idx value
#     Pre-fill field field_idx with value.
#
#   shellframe_form_set_error ctx message
#     Set inline error message. Empty string clears error.

SHELLFRAME_FORM_FIELDS=()

# ── shellframe_form_init ──────────────────────────────────────────────────────

shellframe_form_init() {
    local _ctx="${1:-form}"
    printf -v "_SHELLFRAME_FORM_${_ctx}_FOCUS"  '%d' 0
    printf -v "_SHELLFRAME_FORM_${_ctx}_ERROR"  '%s' ""
    printf -v "_SHELLFRAME_FORM_${_ctx}_SCROLL" '%d' 0

    local _i _n=${#SHELLFRAME_FORM_FIELDS[@]}
    for (( _i=0; _i<_n; _i++ )); do
        local _def="${SHELLFRAME_FORM_FIELDS[$_i]}"
        local _fctx="${_def#*$'\t'}"
        _fctx="${_fctx%%$'\t'*}"
        shellframe_cur_init "$_fctx"
    done

    # Advance past any leading readonly fields to first editable field
    local _focus=0
    while (( _focus < _n )); do
        local _def="${SHELLFRAME_FORM_FIELDS[$_focus]}"
        local _type="${_def##*$'\t'}"
        [[ "$_type" != "readonly" ]] && break
        (( _focus++ ))
    done
    (( _focus >= _n )) && _focus=0
    printf -v "_SHELLFRAME_FORM_${_ctx}_FOCUS" '%d' "$_focus"
}

# ── shellframe_form_set_value ─────────────────────────────────────────────────

shellframe_form_set_value() {
    local _ctx="$1" _idx="$2" _val="$3"
    local _n=${#SHELLFRAME_FORM_FIELDS[@]}
    (( _idx < 0 || _idx >= _n )) && return 0
    local _def="${SHELLFRAME_FORM_FIELDS[$_idx]}"
    local _fctx="${_def#*$'\t'}"
    _fctx="${_fctx%%$'\t'*}"
    shellframe_cur_init "$_fctx" "$_val"
}

# ── shellframe_form_values ────────────────────────────────────────────────────

shellframe_form_values() {
    local _ctx="$1"
    local _out_var="$2"
    local _n=${#SHELLFRAME_FORM_FIELDS[@]}
    local _i
    eval "${_out_var}=()"
    for (( _i=0; _i<_n; _i++ )); do
        local _def="${SHELLFRAME_FORM_FIELDS[$_i]}"
        local _fctx="${_def#*$'\t'}"
        _fctx="${_fctx%%$'\t'*}"
        local _text=""
        shellframe_cur_text "$_fctx" _text
        eval "${_out_var}+=(\"${_text//\"/\\\"}\")"
    done
}

# ── shellframe_form_set_error ─────────────────────────────────────────────────

shellframe_form_set_error() {
    local _ctx="$1" _msg="$2"
    printf -v "_SHELLFRAME_FORM_${_ctx}_ERROR" '%s' "$_msg"
}

# ── _shellframe_form_next_focus ───────────────────────────────────────────────
# Advance focus by delta (+1 or -1), wrapping, skipping readonly fields.

_shellframe_form_next_focus() {
    local _ctx="$1" _delta="$2"
    local _focus_var="_SHELLFRAME_FORM_${_ctx}_FOCUS"
    local _cur="${!_focus_var}"
    local _n=${#SHELLFRAME_FORM_FIELDS[@]}
    (( _n == 0 )) && return 0

    local _new=$(( _cur + _delta ))
    (( _new < 0 ))   && _new=$(( _n - 1 ))
    (( _new >= _n )) && _new=0

    # Skip readonly fields in direction of travel
    local _tries=0
    while (( _tries < _n )); do
        local _def="${SHELLFRAME_FORM_FIELDS[$_new]}"
        local _type="${_def##*$'\t'}"
        [[ "$_type" != "readonly" ]] && break
        _new=$(( _new + _delta ))
        (( _new < 0 ))   && _new=$(( _n - 1 ))
        (( _new >= _n )) && _new=0
        (( _tries++ ))
    done

    printf -v "$_focus_var" '%d' "$_new"
}

# ── shellframe_form_on_key ────────────────────────────────────────────────────

shellframe_form_on_key() {
    local _ctx="$1" _key="$2"
    local _focus_var="_SHELLFRAME_FORM_${_ctx}_FOCUS"
    local _focus="${!_focus_var}"
    local _n=${#SHELLFRAME_FORM_FIELDS[@]}

    local _k_tab="${SHELLFRAME_KEY_TAB:-$'\t'}"
    local _k_stab="${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"

    case "$_key" in
        "$_k_tab"|"$_k_down")
            _shellframe_form_next_focus "$_ctx" 1
            return 0 ;;
        "$_k_stab"|"$_k_up")
            _shellframe_form_next_focus "$_ctx" -1
            return 0 ;;
        $'\r'|$'\n')
            return 2 ;;
        $'\033')
            return 1 ;;
    esac

    # Delegate to focused field
    (( _focus < 0 || _focus >= _n )) && return 1
    local _def="${SHELLFRAME_FORM_FIELDS[$_focus]}"
    local _fctx="${_def#*$'\t'}"
    _fctx="${_fctx%%$'\t'*}"
    local _type="${_def##*$'\t'}"
    [[ "$_type" == "readonly" ]] && return 1

    local _save_ctx="$SHELLFRAME_FIELD_CTX"
    local _save_mask="${SHELLFRAME_FIELD_MASK:-0}"
    SHELLFRAME_FIELD_CTX="$_fctx"
    SHELLFRAME_FIELD_MASK=0
    [[ "$_type" == "password" ]] && SHELLFRAME_FIELD_MASK=1
    shellframe_field_on_key "$_key"
    local _frc=$?
    SHELLFRAME_FIELD_CTX="$_save_ctx"
    SHELLFRAME_FIELD_MASK="$_save_mask"
    (( _frc == 2 )) && return 2   # Enter from field = submit
    return "$_frc"
}

# ── shellframe_form_render ────────────────────────────────────────────────────

shellframe_form_render() {
    local _ctx="$1" _top="$2" _left="$3" _width="$4" _height="$5"
    local _focus_var="_SHELLFRAME_FORM_${_ctx}_FOCUS"
    local _focus="${!_focus_var}"
    local _err_var="_SHELLFRAME_FORM_${_ctx}_ERROR"
    local _err="${!_err_var:-}"
    local _scroll_var="_SHELLFRAME_FORM_${_ctx}_SCROLL"
    local _scroll="${!_scroll_var:-0}"
    local _n=${#SHELLFRAME_FORM_FIELDS[@]}

    # Compute label column width: max label length, bounded [6, 20]
    local _lw=0 _i
    for (( _i=0; _i<_n; _i++ )); do
        local _def="${SHELLFRAME_FORM_FIELDS[$_i]}"
        local _lbl="${_def%%$'\t'*}"
        (( ${#_lbl} > _lw )) && _lw=${#_lbl}
    done
    (( _lw < 6  )) && _lw=6
    (( _lw > 20 )) && _lw=20
    # Layout: "  label:  field" — 2 + lw + 2 = lw+4 chars before field
    local _field_left=$(( _left + _lw + 4 ))
    local _field_w=$(( _width - _lw - 4 ))
    (( _field_w < 4 )) && _field_w=4

    # Reserve 1 row at bottom for error if set
    local _avail_h="$_height"
    [[ -n "$_err" ]] && (( _avail_h-- ))
    (( _avail_h < 1 )) && _avail_h=1

    # Scroll to keep focused field visible
    if (( _focus < _scroll )); then
        _scroll=$_focus
    elif (( _focus >= _scroll + _avail_h )); then
        _scroll=$(( _focus - _avail_h + 1 ))
    fi
    printf -v "$_scroll_var" '%d' "$_scroll"

    # Render visible fields
    for (( _i=0; _i<_avail_h; _i++ )); do
        local _fi=$(( _scroll + _i ))
        (( _fi >= _n )) && break
        local _row=$(( _top + _i ))

        local _def="${SHELLFRAME_FORM_FIELDS[$_fi]}"
        local _lbl="${_def%%$'\t'*}"
        local _fctx="${_def#*$'\t'}"
        _fctx="${_fctx%%$'\t'*}"
        local _type="${_def##*$'\t'}"
        local _is_focused=$(( _fi == _focus ))

        # Label: "  label: "
        local _lbl_padded
        printf -v _lbl_padded '%-*s' "$_lw" "$_lbl"
        local _lbl_style=""
        (( _is_focused )) && _lbl_style="${SHELLFRAME_BOLD:-$'\033[1m'}"
        shellframe_fb_print "$_row" "$(( _left + 2 ))" "${_lbl_padded}:" "$_lbl_style"
        shellframe_fb_fill  "$_row" "$(( _left + 2 + _lw + 1 ))" 2 " "

        # Field value
        local _save_ctx="$SHELLFRAME_FIELD_CTX"
        local _save_foc="${SHELLFRAME_FIELD_FOCUSED:-0}"
        local _save_mask="${SHELLFRAME_FIELD_MASK:-0}"
        SHELLFRAME_FIELD_CTX="$_fctx"
        SHELLFRAME_FIELD_FOCUSED="$_is_focused"
        SHELLFRAME_FIELD_MASK=0
        [[ "$_type" == "password" ]] && SHELLFRAME_FIELD_MASK=1
        if [[ "$_type" == "readonly" ]]; then
            local _rtext=""
            shellframe_cur_text "$_fctx" _rtext
            local _gray="${SHELLFRAME_GRAY:-$'\033[2m'}"
            shellframe_fb_print "$_row" "$_field_left" "$_rtext" "$_gray"
        else
            shellframe_field_render "$_row" "$_field_left" "$_field_w" 1
        fi
        SHELLFRAME_FIELD_CTX="$_save_ctx"
        SHELLFRAME_FIELD_FOCUSED="$_save_foc"
        SHELLFRAME_FIELD_MASK="$_save_mask"
    done

    # Error row at bottom (if set)
    if [[ -n "$_err" ]]; then
        local _err_row=$(( _top + _height - 1 ))
        local _red="${SHELLFRAME_RED:-$'\033[31m'}"
        local _clipped="$_err"
        if (( ${#_clipped} > _width - 2 )); then
            _clipped="${_clipped:0:$(( _width - 3 ))}…"
        fi
        shellframe_fb_fill  "$_err_row" "$_left" "$_width" " " "$_red"
        shellframe_fb_print "$_err_row" "$(( _left + 1 ))" "$_clipped" "$_red"
    fi
}
