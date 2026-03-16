#!/usr/bin/env bash
# shellframe/src/widgets/editor.sh — Multiline text editor (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/draw.sh, src/input.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A scrollable multiline text editor.  Lines are stored as individually named
# globals (_SHELLFRAME_ED_${ctx}_L0, _L1, …) so that multiple editor instances
# can coexist via different SHELLFRAME_EDITOR_CTX values.
#
# The cursor is a (row, col) pair.  Vertical scroll is tracked as VTOP — the
# first visible content row — and recomputed after every operation that changes
# the cursor row.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_EDITOR_LINES[@]  — initial line content (set before init)
#   SHELLFRAME_EDITOR_CTX       — context name (default: "editor")
#   SHELLFRAME_EDITOR_FOCUSED   — 0 (default) | 1
#   SHELLFRAME_EDITOR_FOCUSABLE — 1 (default) | 0
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_EDITOR_RESULT    — full text (newline-joined) set on Ctrl-D (rc=2)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_editor_init [ctx] [viewport_rows]
#     Initialise state from SHELLFRAME_EDITOR_LINES (or a single empty line).
#
#   shellframe_editor_render top left width height
#     Draw visible lines.  Output to /dev/tty.
#
#   shellframe_editor_on_key key
#     Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Ctrl-D pressed (submit; read SHELLFRAME_EDITOR_RESULT)
#
#   shellframe_editor_on_focus focused
#
#   shellframe_editor_size → "1 1 0 0"
#
#   shellframe_editor_get_text [ctx] [out_var]
#     Return current content as a single newline-joined string.
#
#   shellframe_editor_set_text [ctx] text
#     Replace content (splits on literal newlines; resets cursor to 0,0).
#
#   shellframe_editor_row [ctx]   → current cursor row
#   shellframe_editor_col [ctx]   → current cursor column
#   shellframe_editor_line_count [ctx]   → number of lines
#   shellframe_editor_line [ctx] idx    → text of line at idx
#   shellframe_editor_vtop [ctx]  → current vertical scroll offset
#
# ── Keyboard bindings ─────────────────────────────────────────────────────────
#
#   ↑ / ↓               — move cursor up / down (col clamped to new line length)
#   ← / →               — move left / right (wraps across line boundaries)
#   Home / Ctrl-A        — move to start of current line
#   End  / Ctrl-E        — move to end of current line
#   Page Up / Page Down  — move cursor by viewport height
#   Enter                — insert newline (split line at cursor)
#   Backspace            — delete char before cursor; at col 0 join with prev line
#   Delete               — delete char at cursor; at EOL join with next line
#   Ctrl-K               — kill to end of line; at EOL join with next line
#   Ctrl-U               — kill to start of line
#   Ctrl-W               — kill word left (whitespace + word)
#   Ctrl-D               — submit (rc=2, SHELLFRAME_EDITOR_RESULT set)

SHELLFRAME_EDITOR_CTX="editor"
SHELLFRAME_EDITOR_FOCUSED=0
SHELLFRAME_EDITOR_FOCUSABLE=1
SHELLFRAME_EDITOR_LINES=()
SHELLFRAME_EDITOR_RESULT=""

# ── Internal: line array accessors ───────────────────────────────────────────

_shellframe_ed_get_line() {
    local _ctx="$1" _i="$2" _out="${3:-}"
    local _var="_SHELLFRAME_ED_${_ctx}_L${_i}"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "${!_var:-}"
    else
        printf '%s' "${!_var:-}"
    fi
}

_shellframe_ed_set_line() {
    local _ctx="$1" _i="$2" _val="$3"
    printf -v "_SHELLFRAME_ED_${_ctx}_L${_i}" '%s' "$_val"
}

# Insert a line at position _idx, shifting subsequent lines up by one.
_shellframe_ed_insert_line_at() {
    local _ctx="$1" _idx="$2" _line="$3"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _count="${!_count_var:-1}"
    local _j
    for (( _j=_count; _j>_idx; _j-- )); do
        local _src_var="_SHELLFRAME_ED_${_ctx}_L$(( _j - 1 ))"
        printf -v "_SHELLFRAME_ED_${_ctx}_L${_j}" '%s' "${!_src_var:-}"
    done
    printf -v "_SHELLFRAME_ED_${_ctx}_L${_idx}" '%s' "$_line"
    printf -v "$_count_var" '%d' "$(( _count + 1 ))"
}

# Remove the line at position _idx, shifting subsequent lines down by one.
_shellframe_ed_delete_line_at() {
    local _ctx="$1" _idx="$2"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _count="${!_count_var:-1}"
    local _j
    for (( _j=_idx; _j<_count-1; _j++ )); do
        local _src_var="_SHELLFRAME_ED_${_ctx}_L$(( _j + 1 ))"
        printf -v "_SHELLFRAME_ED_${_ctx}_L${_j}" '%s' "${!_src_var:-}"
    done
    # Clear the now-unused last slot
    printf -v "_SHELLFRAME_ED_${_ctx}_L$(( _count - 1 ))" '%s' ""
    printf -v "$_count_var" '%d' "$(( _count - 1 ))"
}

# ── Internal: scroll ──────────────────────────────────────────────────────────

# Recompute VTOP so the cursor row is within the vertical viewport.
_shellframe_ed_ensure_visible() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _vtop_var="_SHELLFRAME_ED_${_ctx}_VTOP"
    local _vrows_var="_SHELLFRAME_ED_${_ctx}_VROWS"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _vtop="${!_vtop_var:-0}"
    local _vrows="${!_vrows_var:-10}"
    local _count="${!_count_var:-1}"

    if (( _row < _vtop )); then
        _vtop="$_row"
    elif (( _vrows > 0 && _row >= _vtop + _vrows )); then
        _vtop=$(( _row - _vrows + 1 ))
    fi

    local _max_vtop=$(( _count - _vrows ))
    (( _max_vtop < 0 )) && _max_vtop=0
    (( _vtop < 0 ))         && _vtop=0
    (( _vtop > _max_vtop )) && _vtop="$_max_vtop"

    printf -v "$_vtop_var" '%d' "$_vtop"
}

# ── Internal: printability ────────────────────────────────────────────────────

_shellframe_ed_is_printable() {
    local _k="$1"
    [[ ${#_k} -ne 1 ]] && return 1
    case "$_k" in
        [[:print:]]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Internal: editing operations ──────────────────────────────────────────────

_shellframe_ed_insert_char() {
    local _ctx="$1" _char="$2"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_col}${_char}${_line:$_col}"
    printf -v "$_col_var" '%d' "$(( _col + 1 ))"
}

_shellframe_ed_newline() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    # Current line keeps only the text before the cursor
    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_col}"
    # New line gets the text after the cursor
    _shellframe_ed_insert_line_at "$_ctx" "$(( _row + 1 ))" "${_line:$_col}"
    printf -v "$_row_var" '%d' "$(( _row + 1 ))"
    printf -v "$_col_var" '%d' 0
}

_shellframe_ed_backspace() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"

    if (( _col > 0 )); then
        local _line
        _shellframe_ed_get_line "$_ctx" "$_row" _line
        _shellframe_ed_set_line "$_ctx" "$_row" \
            "${_line:0:$(( _col - 1 ))}${_line:$_col}"
        printf -v "$_col_var" '%d' "$(( _col - 1 ))"
    elif (( _row > 0 )); then
        # Join current line onto the end of the previous line
        local _prev _cur
        _shellframe_ed_get_line "$_ctx" "$(( _row - 1 ))" _prev
        _shellframe_ed_get_line "$_ctx" "$_row" _cur
        local _new_col="${#_prev}"
        _shellframe_ed_set_line "$_ctx" "$(( _row - 1 ))" "${_prev}${_cur}"
        _shellframe_ed_delete_line_at "$_ctx" "$_row"
        printf -v "$_row_var" '%d' "$(( _row - 1 ))"
        printf -v "$_col_var" '%d' "$_new_col"
    fi
}

_shellframe_ed_delete_char() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    local _len="${#_line}"

    if (( _col < _len )); then
        _shellframe_ed_set_line "$_ctx" "$_row" \
            "${_line:0:$_col}${_line:$(( _col + 1 ))}"
    elif (( _row < _count - 1 )); then
        # At EOL: join next line onto current
        local _next
        _shellframe_ed_get_line "$_ctx" "$(( _row + 1 ))" _next
        _shellframe_ed_set_line "$_ctx" "$_row" "${_line}${_next}"
        _shellframe_ed_delete_line_at "$_ctx" "$(( _row + 1 ))"
    fi
}

_shellframe_ed_kill_to_eol() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    local _len="${#_line}"

    if (( _col < _len )); then
        _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_col}"
    elif (( _row < _count - 1 )); then
        local _next
        _shellframe_ed_get_line "$_ctx" "$(( _row + 1 ))" _next
        _shellframe_ed_set_line "$_ctx" "$_row" "${_line}${_next}"
        _shellframe_ed_delete_line_at "$_ctx" "$(( _row + 1 ))"
    fi
}

_shellframe_ed_kill_to_sol() {
    local _ctx="$1"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:$_col}"
    printf -v "$_col_var" '%d' 0
}

_shellframe_ed_kill_word_left() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"

    (( _col == 0 )) && return 0

    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line

    local _p="$_col"
    while (( _p > 0 )) && [[ "${_line:$(( _p - 1 )):1}" == ' ' ]]; do
        (( _p-- ))
    done
    while (( _p > 0 )) && [[ "${_line:$(( _p - 1 )):1}" != ' ' ]]; do
        (( _p-- ))
    done

    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_p}${_line:$_col}"
    printf -v "$_col_var" '%d' "$_p"
}

# ── Internal: cursor movement ─────────────────────────────────────────────────

_shellframe_ed_move_left() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"

    if (( _col > 0 )); then
        printf -v "$_col_var" '%d' "$(( _col - 1 ))"
    elif (( _row > 0 )); then
        local _prev
        _shellframe_ed_get_line "$_ctx" "$(( _row - 1 ))" _prev
        printf -v "$_row_var" '%d' "$(( _row - 1 ))"
        printf -v "$_col_var" '%d' "${#_prev}"
    fi
}

_shellframe_ed_move_right() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    local _len="${#_line}"

    if (( _col < _len )); then
        printf -v "$_col_var" '%d' "$(( _col + 1 ))"
    elif (( _row < _count - 1 )); then
        printf -v "$_row_var" '%d' "$(( _row + 1 ))"
        printf -v "$_col_var" '%d' 0
    fi
}

_shellframe_ed_move_up() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"

    (( _row == 0 )) && return 0

    local _new_row=$(( _row - 1 ))
    printf -v "$_row_var" '%d' "$_new_row"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_new_row" _line
    local _len="${#_line}"
    (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
}

_shellframe_ed_move_down() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"

    (( _row >= _count - 1 )) && return 0

    local _new_row=$(( _row + 1 ))
    printf -v "$_row_var" '%d' "$_new_row"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_new_row" _line
    local _len="${#_line}"
    (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
}

_shellframe_ed_page_up() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _vrows_var="_SHELLFRAME_ED_${_ctx}_VROWS"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _vrows="${!_vrows_var:-10}"

    local _new_row=$(( _row - _vrows ))
    (( _new_row < 0 )) && _new_row=0
    printf -v "$_row_var" '%d' "$_new_row"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_new_row" _line
    local _len="${#_line}"
    (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
}

_shellframe_ed_page_down() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _vrows_var="_SHELLFRAME_ED_${_ctx}_VROWS"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"
    local _vrows="${!_vrows_var:-10}"

    local _new_row=$(( _row + _vrows ))
    (( _new_row >= _count )) && _new_row=$(( _count - 1 ))
    printf -v "$_row_var" '%d' "$_new_row"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_new_row" _line
    local _len="${#_line}"
    (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
}

# ── shellframe_editor_get_text ────────────────────────────────────────────────

# Return current content as a single newline-joined string.
# Stores in out_var if given, otherwise prints to stdout.
shellframe_editor_get_text() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _out="${2:-}"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _count="${!_count_var:-1}"
    local _result="" _i
    for (( _i=0; _i<_count; _i++ )); do
        local _line
        _shellframe_ed_get_line "$_ctx" "$_i" _line
        if (( _i == 0 )); then
            _result="$_line"
        else
            _result="${_result}"$'\n'"${_line}"
        fi
    done
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "$_result"
    else
        printf '%s' "$_result"
    fi
}

# ── shellframe_editor_set_text ────────────────────────────────────────────────

# Replace content by splitting text on literal newlines.  Resets cursor to 0,0.
shellframe_editor_set_text() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _text="$2"
    local _i=0 _remaining="$_text"

    while [[ -n "$_remaining" ]] || (( _i == 0 )); do
        local _line="${_remaining%%$'\n'*}"
        printf -v "_SHELLFRAME_ED_${_ctx}_L${_i}" '%s' "$_line"
        (( _i++ )) || true
        if [[ "$_remaining" == *$'\n'* ]]; then
            _remaining="${_remaining#*$'\n'}"
        else
            _remaining=""
            break
        fi
    done

    printf -v "_SHELLFRAME_ED_${_ctx}_COUNT" '%d' "$_i"
    printf -v "_SHELLFRAME_ED_${_ctx}_ROW"   '%d' 0
    printf -v "_SHELLFRAME_ED_${_ctx}_COL"   '%d' 0
    _shellframe_ed_ensure_visible "$_ctx"
}

# ── shellframe_editor_init ────────────────────────────────────────────────────

shellframe_editor_init() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _vrows="${2:-10}"

    printf -v "_SHELLFRAME_ED_${_ctx}_VTOP"  '%d' 0
    printf -v "_SHELLFRAME_ED_${_ctx}_VROWS" '%d' "$_vrows"

    if [[ "${#SHELLFRAME_EDITOR_LINES[@]}" -gt 0 ]]; then
        local _i
        for (( _i=0; _i<${#SHELLFRAME_EDITOR_LINES[@]}; _i++ )); do
            printf -v "_SHELLFRAME_ED_${_ctx}_L${_i}" '%s' \
                "${SHELLFRAME_EDITOR_LINES[$_i]}"
        done
        printf -v "_SHELLFRAME_ED_${_ctx}_COUNT" '%d' "${#SHELLFRAME_EDITOR_LINES[@]}"
    else
        printf -v "_SHELLFRAME_ED_${_ctx}_L0"    '%s' ""
        printf -v "_SHELLFRAME_ED_${_ctx}_COUNT" '%d' 1
    fi

    printf -v "_SHELLFRAME_ED_${_ctx}_ROW" '%d' 0
    printf -v "_SHELLFRAME_ED_${_ctx}_COL" '%d' 0
}

# ── shellframe_editor_render ──────────────────────────────────────────────────

shellframe_editor_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_EDITOR_CTX:-editor}"
    local _focused="${SHELLFRAME_EDITOR_FOCUSED:-0}"

    # Keep viewport height in sync, then re-clamp scroll
    printf -v "_SHELLFRAME_ED_${_ctx}_VROWS" '%d' "$_height"
    _shellframe_ed_ensure_visible "$_ctx"

    local _vtop_var="_SHELLFRAME_ED_${_ctx}_VTOP"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"

    local _vtop="${!_vtop_var:-0}"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"

    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _screen_row=$(( _top + _r ))
        local _content_row=$(( _vtop + _r ))

        # Clear row
        printf '\033[%d;%dH%*s' "$_screen_row" "$_left" "$_width" '' >/dev/tty

        [[ $_content_row -ge $_count ]] && continue

        local _line
        _shellframe_ed_get_line "$_ctx" "$_content_row" _line

        # Horizontal scroll: keep the cursor column visible on the active row
        local _hscroll=0
        if (( _content_row == _row && _col >= _width )); then
            _hscroll=$(( _col - _width + 1 ))
        fi

        local _vis="${_line:$_hscroll:$_width}"
        local _vlen="${#_vis}"

        printf '\033[%d;%dH' "$_screen_row" "$_left" >/dev/tty

        if (( _focused && _content_row == _row )); then
            local _cur_vis=$(( _col - _hscroll ))

            # Text before cursor
            printf '%s' "${_vis:0:$_cur_vis}" >/dev/tty

            # Cursor character (highlighted)
            if (( _cur_vis < _vlen )); then
                printf '%s%s%s' "$_rev" "${_vis:$_cur_vis:1}" "$_rst" >/dev/tty
                printf '%s' "${_vis:$(( _cur_vis + 1 ))}" >/dev/tty
            else
                printf '%s %s' "$_rev" "$_rst" >/dev/tty
            fi

            # Pad remaining columns
            local _drawn=$(( _vlen < _width ? _vlen : _width ))
            (( _cur_vis >= _vlen )) && (( _drawn++ )) || true
            local _k=0
            while (( _k < _width - _drawn )); do
                printf ' ' >/dev/tty
                (( _k++ ))
            done
        else
            printf '%s' "$_vis" >/dev/tty
        fi
    done

    printf '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left" >/dev/tty
}

# ── shellframe_editor_on_key ──────────────────────────────────────────────────

shellframe_editor_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_EDITOR_CTX:-editor}"

    local _k_bs="${SHELLFRAME_KEY_BACKSPACE:-$'\x7f'}"
    local _k_del="${SHELLFRAME_KEY_DELETE:-$'\033[3~'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_ctrl_a="${SHELLFRAME_KEY_CTRL_A:-$'\x01'}"
    local _k_ctrl_d="${SHELLFRAME_KEY_CTRL_D:-$'\x04'}"
    local _k_ctrl_e="${SHELLFRAME_KEY_CTRL_E:-$'\x05'}"
    local _k_ctrl_k="${SHELLFRAME_KEY_CTRL_K:-$'\x0b'}"
    local _k_ctrl_u="${SHELLFRAME_KEY_CTRL_U:-$'\x15'}"
    local _k_ctrl_w="${SHELLFRAME_KEY_CTRL_W:-$'\x17'}"

    if [[ "$_key" == "$_k_ctrl_d" ]]; then
        shellframe_editor_get_text "$_ctx" SHELLFRAME_EDITOR_RESULT
        return 2

    elif [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]]; then
        _shellframe_ed_newline "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_bs" ]]; then
        _shellframe_ed_backspace "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_del" ]]; then
        _shellframe_ed_delete_char "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_left" ]]; then
        _shellframe_ed_move_left "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_right" ]]; then
        _shellframe_ed_move_right "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_up" ]]; then
        _shellframe_ed_move_up "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_down" ]]; then
        _shellframe_ed_move_down "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_home" ]] || [[ "$_key" == "$_k_ctrl_a" ]]; then
        printf -v "_SHELLFRAME_ED_${_ctx}_COL" '%d' 0
        return 0

    elif [[ "$_key" == "$_k_end" ]] || [[ "$_key" == "$_k_ctrl_e" ]]; then
        local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
        local _row="${!_row_var:-0}"
        local _line
        _shellframe_ed_get_line "$_ctx" "$_row" _line
        printf -v "_SHELLFRAME_ED_${_ctx}_COL" '%d' "${#_line}"
        return 0

    elif [[ "$_key" == "$_k_pgup" ]]; then
        _shellframe_ed_page_up "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_pgdn" ]]; then
        _shellframe_ed_page_down "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_ctrl_k" ]]; then
        _shellframe_ed_kill_to_eol "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_ctrl_u" ]]; then
        _shellframe_ed_kill_to_sol "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_ctrl_w" ]]; then
        _shellframe_ed_kill_word_left "$_ctx"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif _shellframe_ed_is_printable "$_key"; then
        _shellframe_ed_insert_char "$_ctx" "$_key"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0
    fi

    return 1
}

# ── shellframe_editor_on_focus ────────────────────────────────────────────────

shellframe_editor_on_focus() {
    SHELLFRAME_EDITOR_FOCUSED="${1:-0}"
}

# ── shellframe_editor_size ────────────────────────────────────────────────────

# min: 1×1; preferred: fill all available space (0×0)
shellframe_editor_size() {
    printf '%d %d %d %d' 1 1 0 0
}

# ── Public state accessors ────────────────────────────────────────────────────

shellframe_editor_row() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _var="_SHELLFRAME_ED_${_ctx}_ROW"
    printf '%d' "${!_var:-0}"
}

shellframe_editor_col() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _var="_SHELLFRAME_ED_${_ctx}_COL"
    printf '%d' "${!_var:-0}"
}

shellframe_editor_line_count() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _var="_SHELLFRAME_ED_${_ctx}_COUNT"
    printf '%d' "${!_var:-0}"
}

shellframe_editor_line() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _i="${2:-0}"
    _shellframe_ed_get_line "$_ctx" "$_i"
}

shellframe_editor_vtop() {
    local _ctx="${1:-${SHELLFRAME_EDITOR_CTX:-editor}}"
    local _var="_SHELLFRAME_ED_${_ctx}_VTOP"
    printf '%d' "${!_var:-0}"
}
