#!/usr/bin/env bash
# shellframe/src/widgets/autocomplete.sh — Autocomplete overlay
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/cursor.sh, src/widgets/input-field.sh, src/widgets/editor.sh,
#           src/widgets/context-menu.sh sourced first (via shellframe.sh).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Attaches to a field ("field" mode) or editor ("editor" mode) context and
# provides word-completion suggestions via a provider callback.
#
# The autocomplete overlay is triggered by the consumer (on_key handler or
# explicit shellframe_ac_trigger call).  It extracts the word-under-cursor,
# calls the provider, and presents matches in a context-menu popup.
#
# ── Public globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_AC_PROVIDER       — name of the provider function (required)
#                                  Signature: provider_fn prefix out_array_name
#   SHELLFRAME_AC_TRIGGER        — "auto" (default) | "manual"
#   SHELLFRAME_AC_MAX_HEIGHT     — max visible rows in popup (default: 8)
#   SHELLFRAME_AC_RESULT         — set to accepted completion string on accept
#
# ── Internal state ─────────────────────────────────────────────────────────────
#
#   _SHELLFRAME_AC_CTX           — attached context name
#   _SHELLFRAME_AC_MODE          — "field" | "editor"
#   _SHELLFRAME_AC_ACTIVE        — 1 if popup is visible, 0 otherwise
#   _SHELLFRAME_AC_MATCHES       — array of current match strings
#   _SHELLFRAME_AC_PREFIX        — current word prefix
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_ac_attach ctx mode
#     Attach to a context.  mode is "field" or "editor".
#     Resets all internal state.
#
#   shellframe_ac_detach
#     Detach and clear all state.
#
#   _shellframe_ac_prefix out_var
#     Extract the word-under-cursor from the attached context.
#     Word characters: [a-zA-Z0-9_.\-]
#     Sets out_var to the extracted prefix (may be empty).
#
#   shellframe_ac_dismiss
#     Hide the popup — sets _SHELLFRAME_AC_ACTIVE=0, clears matches/prefix.
#
#   _shellframe_ac_accept match
#     Replace the word-under-cursor with match in the attached context.
#     Sets SHELLFRAME_AC_RESULT and calls shellframe_ac_dismiss.
#
#   shellframe_ac_on_key key
#     Key dispatcher.  When active, handles Enter/Tab/Esc/Up/Down.
#     Returns 0 (consumed), 1 (pass-through).
#
#   shellframe_ac_on_key_after
#     Call AFTER the attached field/editor handles a printable key (auto trigger).
#     Re-runs _shellframe_ac_update and marks the shell dirty.

# ── Public globals ─────────────────────────────────────────────────────────────

SHELLFRAME_AC_PROVIDER=""
SHELLFRAME_AC_TRIGGER="auto"
SHELLFRAME_AC_MAX_HEIGHT=8
SHELLFRAME_AC_RESULT=""

# ── Internal state ─────────────────────────────────────────────────────────────

_SHELLFRAME_AC_CTX=""
_SHELLFRAME_AC_MODE=""
_SHELLFRAME_AC_ACTIVE=0
_SHELLFRAME_AC_MATCHES=()
_SHELLFRAME_AC_PREFIX=""

# ── shellframe_ac_attach ───────────────────────────────────────────────────────

# Attach the autocomplete module to a cursor context (field or editor).
# Resets all transient state so a fresh session starts clean.
shellframe_ac_attach() {
    local _ctx="$1" _mode="$2"
    _SHELLFRAME_AC_CTX="$_ctx"
    _SHELLFRAME_AC_MODE="$_mode"
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}

# ── shellframe_ac_detach ───────────────────────────────────────────────────────

# Detach from the current context and clear all autocomplete state.
shellframe_ac_detach() {
    _SHELLFRAME_AC_CTX=""
    _SHELLFRAME_AC_MODE=""
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
    SHELLFRAME_AC_RESULT=""
}

# ── _shellframe_ac_prefix ─────────────────────────────────────────────────────

# Extract the word-under-cursor from the attached context.
#
# For "field" mode: reads text and position via shellframe_cur_text / shellframe_cur_pos.
# For "editor" mode: reads the current line and column via shellframe_editor_line
#   and shellframe_editor_col / shellframe_editor_row.
#
# Word characters are [a-zA-Z0-9_.\-].  Walks leftward from the cursor position
# until a non-word character (or the start of the string) is found.
#
# Usage: _shellframe_ac_prefix out_var
_shellframe_ac_prefix() {
    local _out_var="$1"
    local _ctx="$_SHELLFRAME_AC_CTX"
    local _mode="$_SHELLFRAME_AC_MODE"
    local _text="" _pos=0

    if [[ "$_mode" == "field" ]]; then
        shellframe_cur_text "$_ctx" _text
        shellframe_cur_pos  "$_ctx" _pos
    else
        # editor mode
        local _row
        _row="$(shellframe_editor_row "$_ctx")"
        _text="$(shellframe_editor_line "$_ctx" "$_row")"
        _pos="$(shellframe_editor_col "$_ctx")"
    fi

    # Walk leftward from _pos matching word characters [a-zA-Z0-9_.\-]
    local _start="$_pos"
    while (( _start > 0 )); do
        local _ch="${_text:$(( _start - 1 )):1}"
        case "$_ch" in
            [a-zA-Z0-9_.\-]) (( _start-- )) ;;
            *) break ;;
        esac
    done

    local _prefix="${_text:$_start:$(( _pos - _start ))}"
    printf -v "$_out_var" '%s' "$_prefix"
}

# ── shellframe_ac_dismiss ──────────────────────────────────────────────────────

# Hide the autocomplete popup.  Sets _SHELLFRAME_AC_ACTIVE=0 and clears
# transient match/prefix state.
shellframe_ac_dismiss() {
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}

# ── _shellframe_ac_update ─────────────────────────────────────────────────────

# Call the provider with the current prefix and manage popup state.
#
# Steps:
#   1. Extract the current word-under-cursor via _shellframe_ac_prefix.
#   2. Store result in _SHELLFRAME_AC_PREFIX.
#   3. If provider is set AND prefix is non-empty, invoke the provider:
#        "$SHELLFRAME_AC_PROVIDER" "$_prefix" "_SHELLFRAME_AC_MATCHES"
#   4. 0 matches  → deactivate (_SHELLFRAME_AC_ACTIVE=0), return.
#   5. 1 match AND SHELLFRAME_AC_TRIGGER=="tab" → deactivate, return
#        (Tab path will auto-complete without showing a popup).
#   6. Otherwise → activate popup: set _SHELLFRAME_AC_ACTIVE=1, copy matches
#        to SHELLFRAME_CMENU_ITEMS, set SHELLFRAME_CMENU_CTX="ac_popup",
#        set SHELLFRAME_CMENU_MAX_HEIGHT from SHELLFRAME_AC_MAX_HEIGHT, and
#        call shellframe_cmenu_init "ac_popup".
_shellframe_ac_update() {
    local _cur_prefix=""
    _shellframe_ac_prefix _cur_prefix
    _SHELLFRAME_AC_PREFIX="$_cur_prefix"
    local _prefix="$_cur_prefix"

    _SHELLFRAME_AC_MATCHES=()

    if [[ -n "$SHELLFRAME_AC_PROVIDER" && -n "$_prefix" ]]; then
        "$SHELLFRAME_AC_PROVIDER" "$_prefix" "_SHELLFRAME_AC_MATCHES"
    fi

    local _n="${#_SHELLFRAME_AC_MATCHES[@]}"

    if (( _n == 0 )); then
        _SHELLFRAME_AC_ACTIVE=0
        return
    fi

    if (( _n == 1 )) && [[ "${SHELLFRAME_AC_TRIGGER:-auto}" == "tab" ]]; then
        _SHELLFRAME_AC_ACTIVE=0
        return
    fi

    _SHELLFRAME_AC_ACTIVE=1
    SHELLFRAME_CMENU_ITEMS=("${_SHELLFRAME_AC_MATCHES[@]+"${_SHELLFRAME_AC_MATCHES[@]}"}")
    SHELLFRAME_CMENU_CTX="ac_popup"
    SHELLFRAME_CMENU_MAX_HEIGHT="${SHELLFRAME_AC_MAX_HEIGHT:-8}"
    shellframe_cmenu_init "ac_popup"
}

# ── _shellframe_ac_accept ─────────────────────────────────────────────────────

# Replace the word-under-cursor in the attached context with $match.
#
# For "field" mode: uses shellframe_cur_text/pos to rebuild the text around
#   the current prefix, then calls shellframe_cur_set with the new text and pos.
# For "editor" mode: reads the line/col internals directly and rewrites the
#   named globals _SHELLFRAME_ED_${ctx}_LINE_${row} and _SHELLFRAME_ED_${ctx}_COL.
#
# Sets SHELLFRAME_AC_RESULT="$match" and calls shellframe_ac_dismiss.
#
# Usage: _shellframe_ac_accept match
_shellframe_ac_accept() {
    local _match="$1"
    local _ctx="$_SHELLFRAME_AC_CTX"
    local _mode="$_SHELLFRAME_AC_MODE"
    local _prefix_len="${#_SHELLFRAME_AC_PREFIX}"

    SHELLFRAME_AC_RESULT="$_match"

    if [[ "$_mode" == "field" ]]; then
        local _text="" _col=0
        shellframe_cur_text "$_ctx" _text
        shellframe_cur_pos  "$_ctx" _col
        local _start=$(( _col - _prefix_len ))
        (( _start < 0 )) && _start=0
        local _new_text="${_text:0:$_start}${_match}${_text:$_col}"
        local _new_pos=$(( _start + ${#_match} ))
        shellframe_cur_set "$_ctx" "$_new_text" "$_new_pos"
    else
        # editor mode
        local _row
        _row="$(shellframe_editor_row "$_ctx")"
        local _col_var="_SHELLFRAME_ED_${_ctx}_COL"
        local _col="${!_col_var:-0}"
        local _line_var="_SHELLFRAME_ED_${_ctx}_LINE_${_row}"
        local _line="${!_line_var:-}"
        local _start=$(( _col - _prefix_len ))
        (( _start < 0 )) && _start=0
        local _new_line="${_line:0:$_start}${_match}${_line:$_col}"
        local _new_col=$(( _start + ${#_match} ))
        printf -v "$_line_var" '%s' "$_new_line"
        printf -v "$_col_var"  '%d' "$_new_col"
    fi

    shellframe_ac_dismiss
}

# ── shellframe_ac_on_key ──────────────────────────────────────────────────────

# Dispatch a key event for the autocomplete overlay.
#
# When popup is active (_SHELLFRAME_AC_ACTIVE==1):
#   Enter ($'\r'/$'\n') or Tab ($'\t') — accept current selection → return 0
#   Esc ($'\033')                       — dismiss popup            → return 0
#   Up/Down                             — delegate to cmenu_on_key → return 0
#   Any other key                       — dismiss, return 1 (pass-through)
#
# When idle:
#   Tab + trigger=="tab" — run _shellframe_ac_update; if single match,
#                          auto-complete it; return 0 if active/accepted, 1 otherwise
#   All other keys       — return 1 (pass-through)
#
# Usage: shellframe_ac_on_key key
shellframe_ac_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"

    if (( _SHELLFRAME_AC_ACTIVE )); then
        # Enter or Tab — accept
        if [[ "$_key" == $'\r' || "$_key" == $'\n' || "$_key" == $'\t' ]]; then
            local _cur=0
            shellframe_sel_cursor "ac_popup" _cur 2>/dev/null || _cur=0
            local _match="${_SHELLFRAME_AC_MATCHES[$_cur]:-}"
            _shellframe_ac_accept "$_match"
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Esc — dismiss
        if [[ "$_key" == $'\033' ]]; then
            shellframe_ac_dismiss
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Up/Down — navigate
        if [[ "$_key" == "$_k_up" || "$_key" == "$_k_down" ]]; then
            shellframe_cmenu_on_key "$_key"
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Any other key — dismiss and pass through
        shellframe_ac_dismiss
        return 1
    fi

    # Idle — only respond to Tab in tab-trigger mode
    if [[ "$_key" == $'\t' && "${SHELLFRAME_AC_TRIGGER:-auto}" == "tab" ]]; then
        _shellframe_ac_update
        if (( _SHELLFRAME_AC_ACTIVE )); then
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi
        # Single match after update → auto-complete without popup
        local _n="${#_SHELLFRAME_AC_MATCHES[@]}"
        if (( _n == 1 )); then
            _shellframe_ac_accept "${_SHELLFRAME_AC_MATCHES[0]}"
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi
        return 1
    fi

    return 1
}

# ── shellframe_ac_on_key_after ────────────────────────────────────────────────

# Called AFTER the attached field/editor processes a printable key (auto-trigger
# mode).  Re-evaluates the current prefix against the provider and marks the
# shell dirty so the next draw loop picks up the popup state change.
#
# No-op if trigger != "auto" or no context is attached.
shellframe_ac_on_key_after() {
    if [[ "${SHELLFRAME_AC_TRIGGER:-auto}" != "auto" || -z "$_SHELLFRAME_AC_CTX" ]]; then
        return 0
    fi
    _shellframe_ac_update
    shellframe_shell_mark_dirty 2>/dev/null || true
}
