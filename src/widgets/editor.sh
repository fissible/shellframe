#!/usr/bin/env bash
# shellframe/src/widgets/editor.sh — Multiline text editor (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/draw.sh, src/input.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A scrollable multiline text editor.  Lines are stored as individually named
# globals (_SHELLFRAME_ED_${ctx}_L0, _L1, …).
#
# WRAP MODE (SHELLFRAME_EDITOR_WRAP=1, the default):
#   Lines are soft-wrapped at word boundaries to fit the viewport width.
#   Up/Down move by visual row (a wrapped segment), not by content line.
#   VTOP is in visual-row space.  No horizontal scroll.
#
# NO-WRAP MODE (SHELLFRAME_EDITOR_WRAP=0):
#   All lines are rendered from a shared horizontal scroll offset (HSCROLL).
#   HSCROLL is lazy/cursor-anchored: it only moves when the cursor would
#   go off-screen, so the view stays put while the cursor moves across it.
#   VTOP is in content-row space.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_EDITOR_LINES[@]  — initial line content (set before init)
#   SHELLFRAME_EDITOR_CTX       — context name (default: "editor")
#   SHELLFRAME_EDITOR_FOCUSED   — 0 (default) | 1
#   SHELLFRAME_EDITOR_FOCUSABLE — 1 (default) | 0
#   SHELLFRAME_EDITOR_WRAP      — 1 (default, soft word wrap) | 0 (h-scroll)
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_EDITOR_RESULT  — full text (newline-joined) set on Ctrl-D (rc=2)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_editor_init [ctx] [viewport_rows]
#   shellframe_editor_render top left width height
#   shellframe_editor_on_key key  → 0 handled | 1 unhandled | 2 submit
#   shellframe_editor_on_focus focused
#   shellframe_editor_size → "1 1 0 0"
#   shellframe_editor_get_text [ctx] [out_var]
#   shellframe_editor_set_text [ctx] text
#   shellframe_editor_row [ctx]        → cursor content row
#   shellframe_editor_col [ctx]        → cursor column
#   shellframe_editor_line_count [ctx] → number of content lines
#   shellframe_editor_line [ctx] idx   → text of content line at idx
#   shellframe_editor_vtop [ctx]       → current scroll offset (visual rows)
#
# ── Keyboard bindings ─────────────────────────────────────────────────────────
#
#   ↑ / ↓               — move up/down one visual row
#   ← / →               — move left/right (wraps across line boundaries)
#   Home / Ctrl-A        — start of current content line
#   End  / Ctrl-E        — end of current content line
#   Page Up / Page Down  — move cursor by viewport height (visual rows)
#   Enter                — insert newline
#   Backspace            — delete char before cursor; at col 0 join with prev line
#   Delete               — delete char at cursor; at EOL join with next line
#   Ctrl-K               — clear to end of line; at EOL join with next line
#   Ctrl-U               — clear to start of line
#   Ctrl-W               — clear last word
#   Ctrl-D               — submit (rc=2, SHELLFRAME_EDITOR_RESULT set)

SHELLFRAME_EDITOR_CTX="editor"
SHELLFRAME_EDITOR_FOCUSED=0
SHELLFRAME_EDITOR_FOCUSABLE=1
SHELLFRAME_EDITOR_LINES=()
SHELLFRAME_EDITOR_RESULT=""
SHELLFRAME_EDITOR_WRAP=1

# ── Internal: line array ──────────────────────────────────────────────────────

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

_shellframe_ed_delete_line_at() {
    local _ctx="$1" _idx="$2"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _count="${!_count_var:-1}"
    local _j
    for (( _j=_idx; _j<_count-1; _j++ )); do
        local _src_var="_SHELLFRAME_ED_${_ctx}_L$(( _j + 1 ))"
        printf -v "_SHELLFRAME_ED_${_ctx}_L${_j}" '%s' "${!_src_var:-}"
    done
    printf -v "_SHELLFRAME_ED_${_ctx}_L$(( _count - 1 ))" '%s' ""
    printf -v "$_count_var" '%d' "$(( _count - 1 ))"
}

# ── Internal: word-wrap vmap ──────────────────────────────────────────────────
#
# The vmap is a space-separated string of "content_row:seg_start:seg_len"
# entries, one per visual row.  It is rebuilt by _shellframe_ed_build_vmap
# and stored in _SHELLFRAME_ED_${ctx}_VMAP.
#
# Soft-wrap rule: wrap at the last space at or before the viewport width
# (the space is included in the segment so the cursor can sit on it);
# fall back to a hard wrap at the viewport width when no space is found.

# Compute "start:len" pairs for visual segments of one line (stdout).
_shellframe_ed_line_segments() {
    local _line="$1" _width="$2"
    local _len="${#_line}"

    if (( _len == 0 )); then printf '0:0'; return; fi
    if (( _width <= 0 || _len <= _width )); then printf '0:%d' "$_len"; return; fi

    local _result="" _pos=0
    while (( _pos < _len )); do
        local _remaining="${_line:$_pos}"
        local _rlen="${#_remaining}"

        if (( _rlen <= _width )); then
            _result="${_result:+$_result }${_pos}:${_rlen}"
            break
        fi

        # Find last space at or before _width; include it in this segment
        local _seg_len="$_width"
        local _next_pos=$(( _pos + _width ))
        local _i=$(( _width - 1 ))
        while (( _i >= 0 )); do
            if [[ "${_remaining:$_i:1}" == " " ]]; then
                _seg_len=$(( _i + 1 ))
                _next_pos=$(( _pos + _i + 1 ))
                break
            fi
            (( _i-- ))
        done

        _result="${_result:+$_result }${_pos}:${_seg_len}"
        _pos="$_next_pos"
    done

    [[ -z "$_result" ]] && _result="0:0"
    printf '%s' "$_result"
}

# Build (or rebuild) the vmap for the current content and viewport width.
_shellframe_ed_build_vmap() {
    local _ctx="$1"
    local _width_var="_SHELLFRAME_ED_${_ctx}_VWIDTH"
    local _width="${!_width_var:-80}"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _count="${!_count_var:-1}"
    local _vmap="" _i

    for (( _i=0; _i<_count; _i++ )); do
        local _line
        _shellframe_ed_get_line "$_ctx" "$_i" _line
        local _segs
        _segs=$(_shellframe_ed_line_segments "$_line" "$_width")
        local _old_IFS="$IFS"
        local _seg_arr
        IFS=' ' read -r -a _seg_arr <<< "$_segs"
        IFS="$_old_IFS"
        local _s
        for _s in "${_seg_arr[@]+"${_seg_arr[@]}"}"; do
            _vmap="${_vmap:+$_vmap }${_i}:${_s}"
        done
    done

    [[ -z "$_vmap" ]] && _vmap="0:0:0"
    printf -v "_SHELLFRAME_ED_${_ctx}_VMAP" '%s' "$_vmap"
}

# Total number of visual rows.
# Usage: _shellframe_ed_vrow_count ctx [out_var]
# With out_var: sets the variable (no subshell). Without: prints to stdout.
_shellframe_ed_vrow_count() {
    local _ctx="$1" _out_var="${2:-}"
    local _vmap_var="_SHELLFRAME_ED_${_ctx}_VMAP"
    local _vmap="${!_vmap_var:-}"
    local _n
    if [[ -z "$_vmap" ]]; then
        _n=1
    else
        local _arr
        local _old_IFS="$IFS"
        IFS=' ' read -r -a _arr <<< "$_vmap"
        IFS="$_old_IFS"
        _n="${#_arr[@]}"
    fi
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%d' "$_n"
    else
        printf '%d' "$_n"
    fi
}

# Given (content_row, col), find the visual row index.
# The last segment whose seg_start <= col (for the given content row) wins,
# so the cursor always resolves to a unique visual row.
_shellframe_ed_cursor_to_vrow() {
    local _ctx="$1" _crow="$2" _ccol="$3" _out_var="$4"
    local _vmap_var="_SHELLFRAME_ED_${_ctx}_VMAP"
    local _vmap="${!_vmap_var:-0:0:0}"
    local _arr
    local _old_IFS="$IFS"
    IFS=' ' read -r -a _arr <<< "$_vmap"
    IFS="$_old_IFS"

    local _vi _result=0
    for (( _vi=0; _vi<${#_arr[@]}; _vi++ )); do
        local _e="${_arr[$_vi]}"
        local _c="${_e%%:*}"; local _r="${_e#*:}"; local _s="${_r%%:*}"
        if (( _c < _crow )); then continue; fi
        if (( _c > _crow )); then break; fi
        # same content row: update result as long as cursor is at or past seg_start
        (( _ccol >= _s )) && _result="$_vi"
    done
    printf -v "$_out_var" '%d' "$_result"
}

# Info for one visual row: sets content_row, seg_start, seg_len in named vars.
_shellframe_ed_vrow_info() {
    local _ctx="$1" _vrow="$2" _c_out="$3" _s_out="$4" _l_out="$5"
    local _vmap_var="_SHELLFRAME_ED_${_ctx}_VMAP"
    local _vmap="${!_vmap_var:-0:0:0}"
    local _arr
    local _old_IFS="$IFS"
    IFS=' ' read -r -a _arr <<< "$_vmap"
    IFS="$_old_IFS"
    local _e="${_arr[$_vrow]:-0:0:0}"
    local _c="${_e%%:*}"; local _r="${_e#*:}"; local _s="${_r%%:*}"; local _l="${_r##*:}"
    printf -v "$_c_out" '%d' "$_c"
    printf -v "$_s_out" '%d' "$_s"
    printf -v "$_l_out" '%d' "$_l"
}

# ── Internal: scroll ──────────────────────────────────────────────────────────

_shellframe_ed_ensure_visible() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _vtop_var="_SHELLFRAME_ED_${_ctx}_VTOP"
    local _vrows_var="_SHELLFRAME_ED_${_ctx}_VROWS"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _vtop="${!_vtop_var:-0}"
    local _vrows="${!_vrows_var:-10}"
    local _count="${!_count_var:-1}"
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    if (( _wrap )); then
        # VTOP is in visual-row space
        _shellframe_ed_build_vmap "$_ctx"
        local _cursor_vrow
        _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cursor_vrow

        if (( _cursor_vrow < _vtop )); then
            _vtop="$_cursor_vrow"
        elif (( _vrows > 0 && _cursor_vrow >= _vtop + _vrows )); then
            _vtop=$(( _cursor_vrow - _vrows + 1 ))
        fi

        local _total_vrows
        _total_vrows=$(_shellframe_ed_vrow_count "$_ctx")
        local _max_vtop=$(( _total_vrows - _vrows ))
        (( _max_vtop < 0 )) && _max_vtop=0
    else
        # VTOP is in content-row space
        if (( _row < _vtop )); then
            _vtop="$_row"
        elif (( _vrows > 0 && _row >= _vtop + _vrows )); then
            _vtop=$(( _row - _vrows + 1 ))
        fi

        local _max_vtop=$(( _count - _vrows ))
        (( _max_vtop < 0 )) && _max_vtop=0

        # Lazy horizontal scroll: only move when cursor goes off-screen
        local _hscroll_var="_SHELLFRAME_ED_${_ctx}_HSCROLL"
        local _hscroll="${!_hscroll_var:-0}"
        local _width_var="_SHELLFRAME_ED_${_ctx}_VWIDTH"
        local _width="${!_width_var:-80}"

        if (( _col < _hscroll )); then
            _hscroll="$_col"
        elif (( _width > 0 && _col >= _hscroll + _width )); then
            _hscroll=$(( _col - _width + 1 ))
        fi
        (( _hscroll < 0 )) && _hscroll=0
        printf -v "$_hscroll_var" '%d' "$_hscroll"
    fi

    (( _vtop < 0 ))         && _vtop=0
    (( _vtop > _max_vtop )) && _vtop="$_max_vtop"
    printf -v "$_vtop_var" '%d' "$_vtop"
}

# ── Internal: bulk insertion (for bracketed paste) ───────────────────────────

# Insert a plain string at the cursor without calling ensure_visible.
# Used internally; callers are responsible for calling ensure_visible after.
_shellframe_ed_insert_string() {
    local _ctx="$1" _str="$2"
    [[ -z "$_str" ]] && return 0
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _line
    _shellframe_ed_get_line "$_ctx" "$_row" _line
    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_col}${_str}${_line:$_col}"
    printf -v "$_col_var" '%d' "$(( _col + ${#_str} ))"
}

# Insert a (possibly multi-line) text block at the cursor.
# Splits on \n; calls _shellframe_ed_insert_string + _shellframe_ed_newline
# per segment.  Does NOT call ensure_visible — callers do that once at the end.
_shellframe_ed_insert_text() {
    local _ctx="$1" _text="$2"
    local _remaining="$_text"
    while true; do
        if [[ "$_remaining" == *$'\n'* ]]; then
            local _part="${_remaining%%$'\n'*}"
            _shellframe_ed_insert_string "$_ctx" "$_part"
            _shellframe_ed_newline "$_ctx"
            _remaining="${_remaining#*$'\n'}"
        else
            _shellframe_ed_insert_string "$_ctx" "$_remaining"
            break
        fi
    done
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
    _shellframe_ed_set_line "$_ctx" "$_row" "${_line:0:$_col}"
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
    while (( _p > 0 )) && [[ "${_line:$(( _p - 1 )):1}" == ' ' ]]; do (( _p-- )); done
    while (( _p > 0 )) && [[ "${_line:$(( _p - 1 )):1}" != ' ' ]]; do (( _p-- )); done

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

# Move up/down by one visual row (wrap=1) or one content row (wrap=0).
# visual_col = col - seg_start is preserved across the move.
_shellframe_ed_move_up() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    if (( _wrap )); then
        _shellframe_ed_build_vmap "$_ctx"
        local _cur_vrow
        _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cur_vrow
        (( _cur_vrow == 0 )) && return 0
        local _target_vrow=$(( _cur_vrow - 1 ))

        local _cur_c _cur_s _cur_l
        _shellframe_ed_vrow_info "$_ctx" "$_cur_vrow" _cur_c _cur_s _cur_l
        local _vis_col=$(( _col - _cur_s ))

        local _tgt_c _tgt_s _tgt_l
        _shellframe_ed_vrow_info "$_ctx" "$_target_vrow" _tgt_c _tgt_s _tgt_l

        local _new_col=$(( _tgt_s + _vis_col ))
        (( _tgt_l > 0 && _new_col > _tgt_s + _tgt_l )) && _new_col=$(( _tgt_s + _tgt_l ))

        printf -v "$_row_var" '%d' "$_tgt_c"
        printf -v "$_col_var" '%d' "$_new_col"
    else
        (( _row == 0 )) && return 0
        local _new_row=$(( _row - 1 ))
        printf -v "$_row_var" '%d' "$_new_row"
        local _line
        _shellframe_ed_get_line "$_ctx" "$_new_row" _line
        local _len="${#_line}"
        (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
    fi
}

_shellframe_ed_move_down() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _count_var="_SHELLFRAME_ED_${_ctx}_COUNT"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _count="${!_count_var:-1}"
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    if (( _wrap )); then
        _shellframe_ed_build_vmap "$_ctx"
        local _cur_vrow
        _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cur_vrow
        local _total_vrows
        _shellframe_ed_vrow_count "$_ctx" _total_vrows
        (( _cur_vrow >= _total_vrows - 1 )) && return 0
        local _target_vrow=$(( _cur_vrow + 1 ))

        local _cur_c _cur_s _cur_l
        _shellframe_ed_vrow_info "$_ctx" "$_cur_vrow" _cur_c _cur_s _cur_l
        local _vis_col=$(( _col - _cur_s ))

        local _tgt_c _tgt_s _tgt_l
        _shellframe_ed_vrow_info "$_ctx" "$_target_vrow" _tgt_c _tgt_s _tgt_l

        local _new_col=$(( _tgt_s + _vis_col ))
        (( _tgt_l > 0 && _new_col > _tgt_s + _tgt_l )) && _new_col=$(( _tgt_s + _tgt_l ))

        printf -v "$_row_var" '%d' "$_tgt_c"
        printf -v "$_col_var" '%d' "$_new_col"
    else
        (( _row >= _count - 1 )) && return 0
        local _new_row=$(( _row + 1 ))
        printf -v "$_row_var" '%d' "$_new_row"
        local _line
        _shellframe_ed_get_line "$_ctx" "$_new_row" _line
        local _len="${#_line}"
        (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
    fi
}

_shellframe_ed_page_up() {
    local _ctx="$1"
    local _row_var="_SHELLFRAME_ED_${_ctx}_ROW"
    local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
    local _vrows_var="_SHELLFRAME_ED_${_ctx}_VROWS"
    local _row="${!_row_var:-0}"
    local _col="${!_col_var:-0}"
    local _vrows="${!_vrows_var:-10}"
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    if (( _wrap )); then
        _shellframe_ed_build_vmap "$_ctx"
        local _cur_vrow
        _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cur_vrow
        local _target_vrow=$(( _cur_vrow - _vrows ))
        (( _target_vrow < 0 )) && _target_vrow=0

        local _cur_c _cur_s _cur_l
        _shellframe_ed_vrow_info "$_ctx" "$_cur_vrow" _cur_c _cur_s _cur_l
        local _vis_col=$(( _col - _cur_s ))

        local _tgt_c _tgt_s _tgt_l
        _shellframe_ed_vrow_info "$_ctx" "$_target_vrow" _tgt_c _tgt_s _tgt_l

        local _new_col=$(( _tgt_s + _vis_col ))
        (( _tgt_l > 0 && _new_col > _tgt_s + _tgt_l )) && _new_col=$(( _tgt_s + _tgt_l ))

        printf -v "$_row_var" '%d' "$_tgt_c"
        printf -v "$_col_var" '%d' "$_new_col"
    else
        local _new_row=$(( _row - _vrows ))
        (( _new_row < 0 )) && _new_row=0
        printf -v "$_row_var" '%d' "$_new_row"
        local _line
        _shellframe_ed_get_line "$_ctx" "$_new_row" _line
        local _len="${#_line}"
        (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
    fi
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
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    if (( _wrap )); then
        _shellframe_ed_build_vmap "$_ctx"
        local _cur_vrow
        _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cur_vrow
        local _total_vrows
        _shellframe_ed_vrow_count "$_ctx" _total_vrows
        local _target_vrow=$(( _cur_vrow + _vrows ))
        (( _target_vrow >= _total_vrows )) && _target_vrow=$(( _total_vrows - 1 ))

        local _cur_c _cur_s _cur_l
        _shellframe_ed_vrow_info "$_ctx" "$_cur_vrow" _cur_c _cur_s _cur_l
        local _vis_col=$(( _col - _cur_s ))

        local _tgt_c _tgt_s _tgt_l
        _shellframe_ed_vrow_info "$_ctx" "$_target_vrow" _tgt_c _tgt_s _tgt_l

        local _new_col=$(( _tgt_s + _vis_col ))
        (( _tgt_l > 0 && _new_col > _tgt_s + _tgt_l )) && _new_col=$(( _tgt_s + _tgt_l ))

        printf -v "$_row_var" '%d' "$_tgt_c"
        printf -v "$_col_var" '%d' "$_new_col"
    else
        local _new_row=$(( _row + _vrows ))
        (( _new_row >= _count )) && _new_row=$(( _count - 1 ))
        printf -v "$_row_var" '%d' "$_new_row"
        local _line
        _shellframe_ed_get_line "$_ctx" "$_new_row" _line
        local _len="${#_line}"
        (( _col > _len )) && printf -v "$_col_var" '%d' "$_len"
    fi
}

# ── shellframe_editor_get_text ────────────────────────────────────────────────

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

    printf -v "_SHELLFRAME_ED_${_ctx}_VTOP"    '%d' 0
    printf -v "_SHELLFRAME_ED_${_ctx}_VROWS"   '%d' "$_vrows"
    printf -v "_SHELLFRAME_ED_${_ctx}_VWIDTH"  '%d' 80
    printf -v "_SHELLFRAME_ED_${_ctx}_HSCROLL" '%d' 0

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
    local _wrap="${SHELLFRAME_EDITOR_WRAP:-1}"

    printf -v "_SHELLFRAME_ED_${_ctx}_VROWS"  '%d' "$_height"
    printf -v "_SHELLFRAME_ED_${_ctx}_VWIDTH" '%d' "$_width"
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

    # Accumulate all output into _buf; write once to eliminate mid-frame flicker.
    local _buf="" _tmp=""

    if (( _wrap )); then
        # ── Wrap mode ────────────────────────────────────────────────────────
        # vmap was just rebuilt by ensure_visible
        local _vmap_var="_SHELLFRAME_ED_${_ctx}_VMAP"
        local _vmap="${!_vmap_var:-0:0:0}"
        local _vmap_arr
        local _old_IFS="$IFS"
        IFS=' ' read -r -a _vmap_arr <<< "$_vmap"
        IFS="$_old_IFS"
        local _total_vrows="${#_vmap_arr[@]}"

        # Pre-compute cursor's visual row for highlight matching
        local _cursor_vrow=0
        (( _focused )) && _shellframe_ed_cursor_to_vrow "$_ctx" "$_row" "$_col" _cursor_vrow

        local _r
        for (( _r=0; _r<_height; _r++ )); do
            local _screen_row=$(( _top + _r ))
            local _vr=$(( _vtop + _r ))

            printf -v _tmp '\033[%d;%dH%*s' "$_screen_row" "$_left" "$_width" ''
            _buf+="$_tmp"
            [[ $_vr -ge $_total_vrows ]] && continue

            local _e="${_vmap_arr[$_vr]}"
            local _c="${_e%%:*}"; local _rest="${_e#*:}"
            local _s="${_rest%%:*}"; local _l="${_rest##*:}"

            local _line
            _shellframe_ed_get_line "$_ctx" "$_c" _line
            local _vis="${_line:$_s:$_l}"
            local _vlen="${#_vis}"

            printf -v _tmp '\033[%d;%dH' "$_screen_row" "$_left"
            _buf+="$_tmp"

            if (( _focused && _vr == _cursor_vrow )); then
                local _cur_vis=$(( _col - _s ))
                _buf+="${_vis:0:$_cur_vis}"
                if (( _cur_vis < _vlen )); then
                    _buf+="${_rev}${_vis:$_cur_vis:1}${_rst}"
                    _buf+="${_vis:$(( _cur_vis + 1 ))}"
                else
                    _buf+="${_rev} ${_rst}"
                fi
                local _drawn=$(( _vlen < _width ? _vlen : _width ))
                (( _cur_vis >= _vlen )) && (( _drawn++ )) || true
                local _pad=$(( _width - _drawn ))
                if (( _pad > 0 )); then
                    printf -v _tmp '%*s' "$_pad" ''
                    _buf+="$_tmp"
                fi
            else
                _buf+="$_vis"
            fi
        done

    else
        # ── No-wrap mode: all rows share HSCROLL ────────────────────────────
        local _hscroll_var="_SHELLFRAME_ED_${_ctx}_HSCROLL"
        local _hscroll="${!_hscroll_var:-0}"

        local _r
        for (( _r=0; _r<_height; _r++ )); do
            local _screen_row=$(( _top + _r ))
            local _content_row=$(( _vtop + _r ))

            printf -v _tmp '\033[%d;%dH%*s' "$_screen_row" "$_left" "$_width" ''
            _buf+="$_tmp"
            [[ $_content_row -ge $_count ]] && continue

            local _line
            _shellframe_ed_get_line "$_ctx" "$_content_row" _line
            local _vis="${_line:$_hscroll:$_width}"
            local _vlen="${#_vis}"

            printf -v _tmp '\033[%d;%dH' "$_screen_row" "$_left"
            _buf+="$_tmp"

            if (( _focused && _content_row == _row )); then
                local _cur_vis=$(( _col - _hscroll ))
                _buf+="${_vis:0:$_cur_vis}"
                if (( _cur_vis < _vlen )); then
                    _buf+="${_rev}${_vis:$_cur_vis:1}${_rst}"
                    _buf+="${_vis:$(( _cur_vis + 1 ))}"
                else
                    _buf+="${_rev} ${_rst}"
                fi
                local _drawn=$(( _vlen < _width ? _vlen : _width ))
                (( _cur_vis >= _vlen )) && (( _drawn++ )) || true
                local _pad=$(( _width - _drawn ))
                if (( _pad > 0 )); then
                    printf -v _tmp '%*s' "$_pad" ''
                    _buf+="$_tmp"
                fi
            else
                _buf+="$_vis"
            fi
        done
    fi

    printf -v _tmp '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left"
    _buf+="$_tmp"
    printf '%s' "$_buf" >/dev/tty
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

    local _k_paste_start="${SHELLFRAME_KEY_PASTE_START:-$'\033[200~'}"
    local _k_paste_end="${SHELLFRAME_KEY_PASTE_END:-$'\033[201~'}"

    if [[ "$_key" == "$_k_paste_start" ]]; then
        # Bracketed paste: drain all keys until paste-end, then insert as one
        # batch — single ensure_visible / vmap rebuild at the end.
        local _paste_buf="" _paste_key=""
        while true; do
            shellframe_read_key _paste_key
            [[ "$_paste_key" == "$_k_paste_end" ]] && break
            _paste_buf="${_paste_buf}${_paste_key}"
        done
        _shellframe_ed_insert_text "$_ctx" "$_paste_buf"
        _shellframe_ed_ensure_visible "$_ctx"
        return 0

    elif [[ "$_key" == "$_k_ctrl_d" ]]; then
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
