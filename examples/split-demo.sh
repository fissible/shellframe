#!/usr/bin/env bash
# split-demo.sh — Visual test for shellframe split panes
#
# Demonstrates 2-pane and 3-pane vertical splits with focusable regions.
# Tab/Shift-Tab to move focus. q to quit.
# Press 1/2/3 to switch between layouts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../shellframe.sh"

# ── Layout modes ────────────────────────────────────────────────────────────

_DEMO_LAYOUT=1   # 1=2-pane v, 2=3-pane v, 3=2-pane h

shellframe_split_init "split2v" "v" 2 "0:0"
shellframe_split_init "split3v" "v" 3 "20:0:20"
shellframe_split_init "split2h" "h" 2 "0:0"

# ── Fill a pane with a label and border indicator ───────────────────────────

_demo_fill_pane() {
    local _top="$1" _left="$2" _w="$3" _h="$4"
    local _label="$5" _focused="$6"

    local _color="${SHELLFRAME_GRAY:-}"
    local _bold="${SHELLFRAME_BOLD:-}"
    local _reset="${SHELLFRAME_RESET:-}"

    # Background shade for focused pane
    local _bg=""
    if (( _focused )); then
        _bg="${_bold}"
    fi

    # Fill area with dots, label in center
    local _mid_row=$(( _top + _h / 2 ))
    local _r
    for (( _r=0; _r < _h; _r++ )); do
        local _row=$(( _top + _r ))
        printf '\033[%d;%dH' "$_row" "$_left" >/dev/tty
        if (( _row == _mid_row )); then
            # Center the label
            local _pad=$(( (_w - ${#_label}) / 2 ))
            (( _pad < 0 )) && _pad=0
            local _c
            for (( _c=0; _c < _pad; _c++ )); do
                printf '%s·%s' "$_color" "$_reset" >/dev/tty
            done
            printf '%s%s%s' "$_bg" "$_label" "$_reset" >/dev/tty
            local _remaining=$(( _w - _pad - ${#_label} ))
            for (( _c=0; _c < _remaining; _c++ )); do
                printf '%s·%s' "$_color" "$_reset" >/dev/tty
            done
        else
            local _c
            for (( _c=0; _c < _w; _c++ )); do
                printf '%s·%s' "$_color" "$_reset" >/dev/tty
            done
        fi
    done
}

# ── Pane focus state ────────────────────────────────────────────────────────

_DEMO_PANE_A_FOCUSED=0
_DEMO_PANE_B_FOCUSED=0
_DEMO_PANE_C_FOCUSED=0

# ── Screen: ROOT ────────────────────────────────────────────────────────────

_demo_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    # Header (nofocus)
    shellframe_shell_region header 1 1 "$_cols" 1 nofocus

    # Footer (nofocus)
    shellframe_shell_region footer "$_rows" 1 "$_cols" 1 nofocus

    # Main area: split panes
    local _main_top=2 _main_left=1 _main_w="$_cols" _main_h=$(( _rows - 2 ))

    local _ctx
    case "$_DEMO_LAYOUT" in
        1) _ctx="split2v" ;;
        2) _ctx="split3v" ;;
        3) _ctx="split2h" ;;
    esac

    # Draw separators
    shellframe_split_render "$_ctx" "$_main_top" "$_main_left" "$_main_w" "$_main_h"

    # Register child regions
    if (( _DEMO_LAYOUT == 2 )); then
        shellframe_split_regions "$_ctx" "$_main_top" "$_main_left" "$_main_w" "$_main_h" \
            "pane_a" "focus" "pane_b" "focus" "pane_c" "focus"
    else
        shellframe_split_regions "$_ctx" "$_main_top" "$_main_left" "$_main_w" "$_main_h" \
            "pane_a" "focus" "pane_b" "focus"
    fi
}

_demo_ROOT_header_render() {
    local _top="$1" _left="$2" _w="$3"
    printf '\033[%d;%dH' "$_top" "$_left" >/dev/tty

    local _title
    case "$_DEMO_LAYOUT" in
        1) _title="Layout 1: 2-pane vertical (50/50)" ;;
        2) _title="Layout 2: 3-pane vertical (20/flex/20)" ;;
        3) _title="Layout 3: 2-pane horizontal (50/50)" ;;
    esac

    printf '%s%s%s' "${SHELLFRAME_REVERSE:-}" "$_title" "${SHELLFRAME_RESET:-}" >/dev/tty
    # Pad rest of header
    local _pad=$(( _w - ${#_title} ))
    local _i
    for (( _i=0; _i < _pad; _i++ )); do
        printf '%s %s' "${SHELLFRAME_REVERSE:-}" "${SHELLFRAME_RESET:-}" >/dev/tty
    done
}

_demo_ROOT_footer_render() {
    local _top="$1" _left="$2" _w="$3"
    printf '\033[%d;%dH' "$_top" "$_left" >/dev/tty
    local _msg="Tab: focus  1/2/3: layout  q: quit"
    printf '%s%s%s' "${SHELLFRAME_GRAY:-}" "$_msg" "${SHELLFRAME_RESET:-}" >/dev/tty
    local _pad=$(( _w - ${#_msg} ))
    local _i
    for (( _i=0; _i < _pad; _i++ )); do
        printf ' ' >/dev/tty
    done
}

# ── Pane render/key/focus callbacks ─────────────────────────────────────────

_demo_ROOT_pane_a_render() {
    local _label="Pane A"
    (( _DEMO_PANE_A_FOCUSED )) && _label="[ Pane A - FOCUSED ]"
    _demo_fill_pane "$1" "$2" "$3" "$4" "$_label" "$_DEMO_PANE_A_FOCUSED"
}
_demo_ROOT_pane_a_on_focus() { _DEMO_PANE_A_FOCUSED="$1"; }
_demo_ROOT_pane_a_on_key() {
    case "$1" in
        1) _DEMO_LAYOUT=1; return 0 ;;
        2) _DEMO_LAYOUT=2; return 0 ;;
        3) _DEMO_LAYOUT=3; return 0 ;;
    esac
    return 1
}

_demo_ROOT_pane_b_render() {
    local _label="Pane B"
    (( _DEMO_PANE_B_FOCUSED )) && _label="[ Pane B - FOCUSED ]"
    _demo_fill_pane "$1" "$2" "$3" "$4" "$_label" "$_DEMO_PANE_B_FOCUSED"
}
_demo_ROOT_pane_b_on_focus() { _DEMO_PANE_B_FOCUSED="$1"; }
_demo_ROOT_pane_b_on_key() {
    case "$1" in
        1) _DEMO_LAYOUT=1; return 0 ;;
        2) _DEMO_LAYOUT=2; return 0 ;;
        3) _DEMO_LAYOUT=3; return 0 ;;
    esac
    return 1
}

_demo_ROOT_pane_c_render() {
    local _label="Pane C"
    (( _DEMO_PANE_C_FOCUSED )) && _label="[ Pane C - FOCUSED ]"
    _demo_fill_pane "$1" "$2" "$3" "$4" "$_label" "$_DEMO_PANE_C_FOCUSED"
}
_demo_ROOT_pane_c_on_focus() { _DEMO_PANE_C_FOCUSED="$1"; }
_demo_ROOT_pane_c_on_key() {
    case "$1" in
        1) _DEMO_LAYOUT=1; return 0 ;;
        2) _DEMO_LAYOUT=2; return 0 ;;
        3) _DEMO_LAYOUT=3; return 0 ;;
    esac
    return 1
}

_demo_ROOT_quit() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

# ── Run ─────────────────────────────────────────────────────────────────────

shellframe_shell "_demo" "ROOT"
