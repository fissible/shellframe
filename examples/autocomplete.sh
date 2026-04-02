#!/usr/bin/env bash
# examples/autocomplete.sh — Demo for shellframe autocomplete overlay
#
# Shows a single input field with Tab-triggered autocomplete against a
# list of table names.  Press Tab to trigger completion, Enter to confirm,
# Esc to quit.  Prints "Selected: <value>" on confirm.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

# ── Autocomplete provider ─────────────────────────────────────────────────────

_demo_provider() {
    local _prefix="$1"
    local _out="$2"
    local _items=("users" "user_roles" "products" "profiles" "orders" "order_items")
    local _matches=()
    local _item
    for _item in "${_items[@]}"; do
        case "$_item" in
            "${_prefix}"*) _matches+=("$_item") ;;
        esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

# ── App state ─────────────────────────────────────────────────────────────────

_DEMO_RESULT=""
_DEMO_FIELD_CTX="ac_field"

SHELLFRAME_FIELD_CTX="$_DEMO_FIELD_CTX"
SHELLFRAME_FIELD_PLACEHOLDER="Type a table name and press Tab..."
shellframe_field_init "$_DEMO_FIELD_CTX"

SHELLFRAME_AC_PROVIDER="_demo_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_attach "$_DEMO_FIELD_CTX" "field"

# ── Screen: ROOT ──────────────────────────────────────────────────────────────

_demo_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region "header" 1 1 "$_cols" 1 nofocus
    shellframe_shell_region "label"  3 1 "$_cols" 1 nofocus
    shellframe_shell_region "input"  4 3 "$(( _cols - 4 ))" 1
    shellframe_shell_region "footer" "$_rows" 1 "$_cols" 1 nofocus
}

_demo_ROOT_header_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " $'\033[44;97m'
    shellframe_fb_print "$_top" "$_left" " Autocomplete Demo" $'\033[44;97m'
}

_demo_ROOT_label_render() {
    local _top="$1" _left="$2"
    shellframe_fb_print "$_top" "$_left" "Table name:"
}

_demo_ROOT_input_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    SHELLFRAME_FIELD_CTX="$_DEMO_FIELD_CTX"
    shellframe_field_render "$_top" "$_left" "$_width" "$_height"

    # Render autocomplete popup anchored at the field's cursor column
    local _pos=0
    shellframe_cur_pos "$_DEMO_FIELD_CTX" _pos
    local _cursor_col=$(( _left + _pos ))
    shellframe_ac_render "$_top" "$_left" "$_width" "$_height" "$_top" "$_cursor_col"
}

_demo_ROOT_input_on_key() {
    local _key="$1"
    local _ac_rc _field_rc

    # Autocomplete gets first look; if it handles the key, redraw and return
    _ac_rc=1
    shellframe_ac_on_key "$_key" && _ac_rc=0 || _ac_rc=$?
    if (( _ac_rc == 0 )); then
        shellframe_shell_mark_dirty
        return 0
    fi

    # Esc — pass through so the shell's global handler can quit
    if [[ "$_key" == $'\033' ]]; then
        return 1
    fi

    # Delegate to field
    SHELLFRAME_FIELD_CTX="$_DEMO_FIELD_CTX"
    _field_rc=1
    shellframe_field_on_key "$_key" && _field_rc=0 || _field_rc=$?

    # After field processes a key, let autocomplete re-evaluate (auto trigger)
    shellframe_ac_on_key_after

    if (( _field_rc == 2 )); then
        # Enter confirmed — capture result and signal done (action handles quit)
        shellframe_cur_text "$_DEMO_FIELD_CTX" _DEMO_RESULT
        return 2
    fi

    return "$_field_rc"
}

_demo_ROOT_input_action() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

_demo_ROOT_input_on_focus() {
    SHELLFRAME_FIELD_FOCUSED="${1:-0}"
}

_demo_ROOT_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "${SHELLFRAME_GRAY:-}"
    shellframe_fb_print "$_top" "$_left" " Tab complete  ↑/↓ navigate  Enter confirm  Esc quit" "${SHELLFRAME_GRAY:-}"
}

_demo_ROOT_quit() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

# ── Run ───────────────────────────────────────────────────────────────────────

shellframe_shell "_demo" "ROOT"

if [[ -n "$_DEMO_RESULT" ]]; then
    printf 'Selected: %s\n' "$_DEMO_RESULT"
fi
