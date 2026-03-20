#!/usr/bin/env bash
# shellframe/src/diff.sh — Unified diff parser for side-by-side display
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Parses unified diff output (from `git diff`, `diff -u`, etc.) into parallel
# arrays suitable for a side-by-side diff view widget.  Each array index is a
# "visual row" — a paired left/right line with a type tag.
#
# The parser handles:
#   - File headers (diff --git, --- a/, +++ b/)
#   - Hunk headers (@@ -L,C +L,C @@)
#   - Context lines (same on both sides)
#   - Additions (right side only)
#   - Deletions (left side only)
#   - Changes (paired deletions + additions within a hunk)
#   - Separator rows between hunks (collapsed unchanged regions)
#
# ── Output arrays ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_DIFF_TYPES[]   — row type: "ctx" "add" "del" "chg" "hdr" "sep"
#   SHELLFRAME_DIFF_LEFT[]    — left-side text (empty for pure additions)
#   SHELLFRAME_DIFF_RIGHT[]   — right-side text (empty for pure deletions)
#   SHELLFRAME_DIFF_LNUMS[]   — left line number (empty if no left content)
#   SHELLFRAME_DIFF_RNUMS[]   — right line number (empty if no right content)
#   SHELLFRAME_DIFF_ROW_COUNT — total visual rows
#   SHELLFRAME_DIFF_FILES[]      — file names in order of appearance
#   SHELLFRAME_DIFF_FILE_ROWS[]  — row index where each file's header starts
#   SHELLFRAME_DIFF_FILE_STATUS[] — "added" | "deleted" | "modified" per file
#
# ── Row types ────────────────────────────────────────────────────────────────
#
#   ctx — context: identical on both sides
#   add — addition: right side only (left is blank)
#   del — deletion: left side only (right is blank)
#   chg — change: both sides differ (paired del+add)
#   hdr — file header (file path in LEFT, empty RIGHT)
#   sep — separator between hunks (collapsed unchanged region indicator)
#
# ── Public API ───────────────────────────────────────────────────────────────
#
#   shellframe_diff_parse
#     Reads unified diff from stdin.  Populates the output arrays.
#     IMPORTANT: use process substitution, not a pipe, so the function
#     runs in the current shell and arrays propagate:
#       shellframe_diff_parse < <(git diff)       # correct
#       git diff | shellframe_diff_parse           # WRONG — subshell
#
#   shellframe_diff_parse_string diff_text
#     Parses diff text from a variable (uses heredoc internally).
#
#   shellframe_diff_clear
#     Reset all output arrays.

SHELLFRAME_DIFF_TYPES=()
SHELLFRAME_DIFF_LEFT=()
SHELLFRAME_DIFF_RIGHT=()
SHELLFRAME_DIFF_LNUMS=()
SHELLFRAME_DIFF_RNUMS=()
SHELLFRAME_DIFF_ROW_COUNT=0
SHELLFRAME_DIFF_FILES=()        # file names in order of appearance
SHELLFRAME_DIFF_FILE_ROWS=()    # row index where each file starts
SHELLFRAME_DIFF_FILE_STATUS=()  # "added" | "deleted" | "modified" per file

# ── shellframe_diff_clear ───────────────────────────────────────────────────

shellframe_diff_clear() {
    SHELLFRAME_DIFF_TYPES=()
    SHELLFRAME_DIFF_LEFT=()
    SHELLFRAME_DIFF_RIGHT=()
    SHELLFRAME_DIFF_LNUMS=()
    SHELLFRAME_DIFF_RNUMS=()
    SHELLFRAME_DIFF_FILES=()
    SHELLFRAME_DIFF_FILE_ROWS=()
    SHELLFRAME_DIFF_FILE_STATUS=()
    SHELLFRAME_DIFF_ROW_COUNT=0
}

# ── _shellframe_diff_flush_pending ──────────────────────────────────────────
#
# Pair up pending deletions and additions.  Called at the end of each
# contiguous del/add block (when we hit a context line, hunk header, or EOF).
#
# Globals read:  _sd_pending_del[], _sd_pending_add[], _sd_pending_dlnums[],
#                _sd_pending_alnums[]
# Globals write: SHELLFRAME_DIFF_* output arrays

_shellframe_diff_flush_pending() {
    local _del_count="${#_sd_pending_del[@]}"
    local _add_count="${#_sd_pending_add[@]}"
    local _max="$_del_count"
    (( _add_count > _max )) && _max="$_add_count"

    local _i
    for (( _i=0; _i < _max; _i++ )); do
        local _has_del=0 _has_add=0
        (( _i < _del_count )) && _has_del=1
        (( _i < _add_count )) && _has_add=1

        local _type
        if (( _has_del && _has_add )); then
            _type="chg"
        elif (( _has_del )); then
            _type="del"
        else
            _type="add"
        fi

        local _left="" _right="" _lnum="" _rnum=""
        if (( _has_del )); then
            _left="${_sd_pending_del[$_i]}"
            _lnum="${_sd_pending_dlnums[$_i]}"
        fi
        if (( _has_add )); then
            _right="${_sd_pending_add[$_i]}"
            _rnum="${_sd_pending_alnums[$_i]}"
        fi

        SHELLFRAME_DIFF_TYPES+=("$_type")
        SHELLFRAME_DIFF_LEFT+=("$_left")
        SHELLFRAME_DIFF_RIGHT+=("$_right")
        SHELLFRAME_DIFF_LNUMS+=("$_lnum")
        SHELLFRAME_DIFF_RNUMS+=("$_rnum")
    done

    _sd_pending_del=()
    _sd_pending_add=()
    _sd_pending_dlnums=()
    _sd_pending_alnums=()
}

# ── shellframe_diff_parse ───────────────────────────────────────────────────

# Read unified diff from stdin, populate output arrays.
shellframe_diff_parse() {
    shellframe_diff_clear

    local _sd_pending_del=()
    local _sd_pending_add=()
    local _sd_pending_dlnums=()
    local _sd_pending_alnums=()

    local _lnum=0 _rnum=0
    local _in_hunk=0
    local _hunk_count=0
    local _line

    while IFS= read -r _line || [[ -n "$_line" ]]; do

        # ── File header: diff --git a/... b/... ────────────────────────
        if [[ "$_line" == "diff --git "* ]]; then
            # Flush any pending changes from previous hunk
            _shellframe_diff_flush_pending
            _in_hunk=0
            _hunk_count=0

            # Extract file name from "diff --git a/foo b/foo"
            local _fname="${_line#diff --git a/}"
            _fname="${_fname%% b/*}"

            # Insert a blank separator line before each file (except the first)
            if (( ${#SHELLFRAME_DIFF_FILES[@]} > 0 )); then
                SHELLFRAME_DIFF_TYPES+=("file_sep")
                SHELLFRAME_DIFF_LEFT+=("")
                SHELLFRAME_DIFF_RIGHT+=("")
                SHELLFRAME_DIFF_LNUMS+=("")
                SHELLFRAME_DIFF_RNUMS+=("")
            fi

            # Track file index (default status "modified"; updated by ---/+++ parsing)
            SHELLFRAME_DIFF_FILES+=("$_fname")
            SHELLFRAME_DIFF_FILE_ROWS+=("${#SHELLFRAME_DIFF_TYPES[@]}")
            SHELLFRAME_DIFF_FILE_STATUS+=("modified")

            SHELLFRAME_DIFF_TYPES+=("hdr")
            SHELLFRAME_DIFF_LEFT+=("$_fname")
            SHELLFRAME_DIFF_RIGHT+=("$_fname")
            SHELLFRAME_DIFF_LNUMS+=("")
            SHELLFRAME_DIFF_RNUMS+=("")
            continue
        fi

        # Track file status from --- / +++ lines
        [[ "$_line" == "index "* ]] && continue
        if [[ "$_line" == "--- /dev/null" ]]; then
            # New file — mark the last file as "added"
            local _fi=$(( ${#SHELLFRAME_DIFF_FILE_STATUS[@]} - 1 ))
            (( _fi >= 0 )) && SHELLFRAME_DIFF_FILE_STATUS[$_fi]="added"
            continue
        fi
        if [[ "$_line" == "+++ /dev/null" ]]; then
            # Deleted file — mark the last file as "deleted"
            local _fi=$(( ${#SHELLFRAME_DIFF_FILE_STATUS[@]} - 1 ))
            (( _fi >= 0 )) && SHELLFRAME_DIFF_FILE_STATUS[$_fi]="deleted"
            continue
        fi
        [[ "$_line" == "--- "* ]] && continue
        [[ "$_line" == "+++ "* ]] && continue

        # ── Hunk header: @@ -L,C +L,C @@ ─────────────────────────────
        if [[ "$_line" == "@@"* ]]; then
            _shellframe_diff_flush_pending

            # Insert separator between hunks (not before the first)
            if (( _hunk_count > 0 )); then
                SHELLFRAME_DIFF_TYPES+=("sep")
                SHELLFRAME_DIFF_LEFT+=("")
                SHELLFRAME_DIFF_RIGHT+=("")
                SHELLFRAME_DIFF_LNUMS+=("")
                SHELLFRAME_DIFF_RNUMS+=("")
            fi
            (( _hunk_count++ ))

            # Parse line numbers: @@ -OLD_START[,OLD_COUNT] +NEW_START[,NEW_COUNT] @@
            local _hdr="${_line#@@}"
            _hdr="${_hdr%%@@*}"
            # _hdr is now like " -1,5 +1,7 "
            local _old_part _new_part
            _old_part=$(printf '%s' "$_hdr" | grep -oE '\-[0-9]+(,[0-9]+)?')
            _new_part=$(printf '%s' "$_hdr" | grep -oE '\+[0-9]+(,[0-9]+)?')
            _lnum="${_old_part#-}"
            _lnum="${_lnum%%,*}"
            _rnum="${_new_part#+}"
            _rnum="${_rnum%%,*}"

            _in_hunk=1
            continue
        fi

        # ── Inside a hunk: process content lines ──────────────────────
        if (( _in_hunk )); then
            local _type_char="${_line:0:1}"
            local _content="${_line:1}"

            case "$_type_char" in
                " ")
                    # Context line — flush pending first
                    _shellframe_diff_flush_pending

                    SHELLFRAME_DIFF_TYPES+=("ctx")
                    SHELLFRAME_DIFF_LEFT+=("$_content")
                    SHELLFRAME_DIFF_RIGHT+=("$_content")
                    SHELLFRAME_DIFF_LNUMS+=("$_lnum")
                    SHELLFRAME_DIFF_RNUMS+=("$_rnum")
                    (( _lnum++ ))
                    (( _rnum++ ))
                    ;;
                "-")
                    _sd_pending_del+=("$_content")
                    _sd_pending_dlnums+=("$_lnum")
                    (( _lnum++ ))
                    ;;
                "+")
                    _sd_pending_add+=("$_content")
                    _sd_pending_alnums+=("$_rnum")
                    (( _rnum++ ))
                    ;;
                "\\")
                    # "\ No newline at end of file" — skip
                    ;;
            esac
        fi

    done

    # Flush any remaining pending changes
    _shellframe_diff_flush_pending

    SHELLFRAME_DIFF_ROW_COUNT=${#SHELLFRAME_DIFF_TYPES[@]}
}

# ── shellframe_diff_parse_string ────────────────────────────────────────────

# Parse diff from a variable instead of stdin.
# Uses heredoc to avoid subshell (pipe would lose array state).
shellframe_diff_parse_string() {
    shellframe_diff_parse <<< "$1"
}
