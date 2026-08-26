#!/usr/bin/env bash
# src/pager.sh — scrollback escape hatch: view content in $PAGER (#56)
#
# TUIs live on the alternate screen by design, which means nothing reaches
# the terminal's scrollback. These helpers let a widget hand its full plain-
# text content to ${PAGER:-less}: the alt screen is exited, the terminal is
# restored to cooked mode for the pager, and the CALLER re-enters raw mode
# and redraws afterwards.
#
#   shellframe_dump_lines <array_name> [header] <out_file>
#         Write sanitized (ANSI/C0-stripped) copies of the array elements to
#         out_file, optionally prefixed with a header line. Never touches
#         the terminal.
#
#   SHELLFRAME_DUMP=1  — non-interactive counterpart (#56): widgets check
#         this flag via shellframe_pager_requested and print their dump to
#         stdout instead of entering the TUI at all.
#
#   shellframe_pager_view <file> <saved_stty>
#         Exit the alternate screen, restore cooked mode, run
#         ${PAGER:-less} on <file> with stdio wired to /dev/tty (the $()
#         contract: pager output never lands in captured stdout), then
#         leave the terminal OFF — the caller re-enters raw/alt mode and
#         redraws.

# Non-interactive dump requested? (#56)
shellframe_pager_requested() {
    [[ "${SHELLFRAME_DUMP:-0}" == "1" ]]
}

# shellframe_dump_lines <array_name> [header] <out_file>
shellframe_dump_lines() {
    local _arr_name="$1" _header="${2:-}" _out="$3"
    local -a _lines=()
    eval "_lines=(\${$_arr_name[@]+\"\${$_arr_name[@]}\"})"

    {
        [[ -n "$_header" ]] && printf '%s\n' "$_header"
        local _line
        for _line in "${_lines[@]+"${_lines[@]}"}"; do
            printf '%s\n' "$_line"
        done
    } | LC_ALL=C sed 's/\x1b\[[0-?]*[ -\/]*[@-~]//g; s/\x1b[@-Z\\-_]//g' > "$_out"
}

# shellframe_pager_view <file> <saved_stty>
# Exits alt screen + restores cooked tty, pages the file, leaves the
# terminal unconfigured; caller must re-enter raw mode and redraw.
shellframe_pager_view() {
    local _file="$1" _saved_stty="$2"
    local _pager="${PAGER:-less}"

    # Leave the alternate screen and hand the tty back in a sane state.
    printf '\033[?25h\033[?2004l\033[?1006l\033[?1000l\033[?1049l' >/dev/tty 2>/dev/null
    stty "$_saved_stty" 2>/dev/null || stty sane 2>/dev/null

    if type "$_pager" >/dev/null 2>&1; then
        "$_pager" -- "$_file" >/dev/tty </dev/tty 2>/dev/tty
    else
        cat -- "$_file" >/dev/tty
    fi

    rm -f "$_file"
}
