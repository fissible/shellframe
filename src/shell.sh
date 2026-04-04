#!/usr/bin/env bash
# shellframe/src/shell.sh — Multi-pane application shell (v2 composable runtime)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/screen.sh, src/input.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# shellframe_shell is the v2 composable runtime.  It manages region layout,
# Tab/Shift-Tab focus traversal, and key dispatch to focused components.
# Unlike shellframe_app (v1 FSM), it uses v2 composable widgets.
#
# ── Screen definition ─────────────────────────────────────────────────────────
#
# Each screen is defined by a set of functions under a common prefix:
#
#   PREFIX_SCREEN_render()
#     Called before every draw cycle.  Must call shellframe_shell_region for
#     each region on screen.  May also set per-widget state globals.
#     (Hint: read terminal size via _shellframe_shell_terminal_size here.)
#
#   PREFIX_SCREEN_<region>_render top left width height
#     Called to paint region <region>.  Output goes to /dev/tty.
#
#   PREFIX_SCREEN_<region>_on_key key            (optional)
#     Key handler for the region.  Returns 0/1/2 per component contract.
#     If absent, the region is not focusable (same as passing "nofocus").
#     Tab/Shift-Tab are offered to on_key before focus cycling: returning 0
#     consumes the key and suppresses the default focus advance/retreat.
#
#   PREFIX_SCREEN_<region>_on_focus focused       (optional)
#     Called when the region gains (1) or loses (0) focus.
#
#   PREFIX_SCREEN_<region>_action                 (optional)
#     Called when the region's on_key returns 2.
#     Set _SHELLFRAME_SHELL_NEXT to navigate screens, or "__QUIT__" to exit.
#
#   PREFIX_SCREEN_quit()                          (optional)
#     Called when q/Q/Esc reaches the shell's default handler.
#     Set _SHELLFRAME_SHELL_NEXT or "__QUIT__".  If absent, shell exits.
#
# ── Registering regions ───────────────────────────────────────────────────────
#
#   shellframe_shell_region name top left width height [nofocus]
#
#   Call from within PREFIX_SCREEN_render().  If "nofocus" is given, the
#   region is rendered but skipped during Tab traversal.
#
# ── Requesting focus ──────────────────────────────────────────────────────────
#
#   shellframe_shell_focus_set region_name
#
#   Request that a named region receives focus on the next draw cycle.
#   Use this from action callbacks to redirect focus (e.g. open a modal):
#
#     _myapp_ROOT_list_action() {
#         _MODAL_OPEN=1
#         shellframe_shell_focus_set "modal"   # modal registered in render hook
#         # _SHELLFRAME_SHELL_NEXT="" means: redraw without screen change
#     }
#
# ── Minimal example ───────────────────────────────────────────────────────────
#
#   _myapp_ROOT_render() {
#       local _rows _cols
#       _shellframe_shell_terminal_size _rows _cols
#       shellframe_shell_region topbar 1 1 "$_cols" 1 nofocus
#       shellframe_shell_region main 2 1 "$_cols" $(( _rows - 2 )) focus
#       shellframe_shell_region footer "$_rows" 1 "$_cols" 1 nofocus
#   }
#   _myapp_ROOT_topbar_render() { printf '\033[%d;%dHMy App' "$1" "$2" >&3; }
#   _myapp_ROOT_main_render()   { SHELLFRAME_LIST_CTX="main"; shellframe_list_render "$@"; }
#   _myapp_ROOT_main_on_key()   { SHELLFRAME_LIST_CTX="main"; shellframe_list_on_key "$1"; }
#   _myapp_ROOT_main_on_focus() { shellframe_list_on_focus "$1"; }
#   _myapp_ROOT_main_action()   { _SHELLFRAME_SHELL_NEXT="DETAIL"; }
#   _myapp_ROOT_quit()          { _SHELLFRAME_SHELL_NEXT="__QUIT__"; }
#
#   shellframe_list_init "main" 20
#   SHELLFRAME_LIST_ITEMS=("File 1" "File 2")
#   shellframe_shell "_myapp" "ROOT"
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_shell_region name top left width height [nofocus]
#   shellframe_shell_focus_set region_name
#   shellframe_shell prefix [initial_screen]
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   _SHELLFRAME_SHELL_NEXT   — set in event callbacks to navigate or quit.

_SHELLFRAME_SHELL_REGIONS=()      # "name:top:left:width:height:focus|nofocus"
_SHELLFRAME_SHELL_FOCUS_RING=()   # ordered array of focusable region names
_SHELLFRAME_SHELL_FOCUS_IDX=0     # current index into focus ring
_SHELLFRAME_SHELL_FOCUS_REQUEST="" # pending focus-by-name request (applied on next draw)
_SHELLFRAME_SHELL_NEXT=""         # next screen name (set by event callbacks)
_SHELLFRAME_SHELL_DIRTY=0         # 1 = at least one widget changed state; draw needed

# ── shellframe_shell_mark_dirty ───────────────────────────────────────────────

# Signal that visible state has changed and a draw cycle is needed.
# Called by widget on_key handlers when they modify state (selection move,
# text edit, scroll, etc.).  Safe to call outside of shellframe_shell context —
# it just sets the global, which is ignored if not in a shell session.
shellframe_shell_mark_dirty() {
    _SHELLFRAME_SHELL_DIRTY=1
}

# ── shellframe_shell_region ───────────────────────────────────────────────────

# shellframe_shell_region name top left width height [nofocus]
# Register a named region.  Call from within PREFIX_SCREEN_render().
shellframe_shell_region() {
    local _name="$1" _top="$2" _left="$3" _width="$4" _height="$5"
    local _focus="${6:-focus}"
    _SHELLFRAME_SHELL_REGIONS+=("${_name}:${_top}:${_left}:${_width}:${_height}:${_focus}")
    shellframe_widget_register "$_name" "$_top" "$_left" "$_width" "$_height"
}

# ── shellframe_shell_focus_set ────────────────────────────────────────────────

# Request focus move to the named region on the next draw cycle.
shellframe_shell_focus_set() {
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$1"
}

# ── _shellframe_shell_focus_init ──────────────────────────────────────────────

# Build _SHELLFRAME_SHELL_FOCUS_RING from the registered regions.
# Tries to preserve focus on the previously-focused region by name.
# If _SHELLFRAME_SHELL_FOCUS_REQUEST is set, applies it and clears it.
_shellframe_shell_focus_init() {
    # Save current focus owner name before rebuilding
    local _prev_name=""
    _shellframe_shell_focus_owner _prev_name

    # Apply pending focus request (overrides prev name)
    if [[ -n "$_SHELLFRAME_SHELL_FOCUS_REQUEST" ]]; then
        _prev_name="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
        _SHELLFRAME_SHELL_FOCUS_REQUEST=""
    fi

    # Rebuild ring
    _SHELLFRAME_SHELL_FOCUS_RING=()
    local _entry
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        local _f="${_entry##*:}"
        local _n="${_entry%%:*}"
        [[ "$_f" == "focus" ]] && _SHELLFRAME_SHELL_FOCUS_RING+=("$_n")
    done

    # Restore / apply focus by name
    _SHELLFRAME_SHELL_FOCUS_IDX=0
    if [[ -n "$_prev_name" ]]; then
        local _i
        for _i in "${!_SHELLFRAME_SHELL_FOCUS_RING[@]}"; do
            if [[ "${_SHELLFRAME_SHELL_FOCUS_RING[$_i]}" == "$_prev_name" ]]; then
                _SHELLFRAME_SHELL_FOCUS_IDX=$_i
                return 0
            fi
        done
    fi
}

# ── _shellframe_shell_focus_next / prev ───────────────────────────────────────

_shellframe_shell_focus_next() {
    local _len=${#_SHELLFRAME_SHELL_FOCUS_RING[@]}
    (( _len == 0 )) && return
    _SHELLFRAME_SHELL_FOCUS_IDX=$(( (_SHELLFRAME_SHELL_FOCUS_IDX + 1) % _len ))
}

_shellframe_shell_focus_prev() {
    local _len=${#_SHELLFRAME_SHELL_FOCUS_RING[@]}
    (( _len == 0 )) && return
    if (( _SHELLFRAME_SHELL_FOCUS_IDX == 0 )); then
        _SHELLFRAME_SHELL_FOCUS_IDX=$(( _len - 1 ))
    else
        (( _SHELLFRAME_SHELL_FOCUS_IDX-- )) || true
    fi
}

# ── _shellframe_shell_focus_owner ─────────────────────────────────────────────

# Print the name of the currently focused region, or store in out_var.
_shellframe_shell_focus_owner() {
    local _out="${1:-}"
    local _len=${#_SHELLFRAME_SHELL_FOCUS_RING[@]}
    local _name=""
    if (( _len > 0 && _SHELLFRAME_SHELL_FOCUS_IDX < _len )); then
        _name="${_SHELLFRAME_SHELL_FOCUS_RING[$_SHELLFRAME_SHELL_FOCUS_IDX]}"
    fi
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "$_name"
    else
        printf '%s' "$_name"
    fi
}

# ── _shellframe_shell_region_bounds ───────────────────────────────────────────

# _shellframe_shell_region_bounds name out_top out_left out_w out_h
# Retrieve a region's bounds by name.  Returns 1 if not found.
_shellframe_shell_region_bounds() {
    local _name="$1"
    local _out_top="$2" _out_left="$3" _out_w="$4" _out_h="$5"
    local _entry
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        local _n="${_entry%%:*}"
        if [[ "$_n" == "$_name" ]]; then
            # "name:top:left:width:height:focus"
            local _rest="${_entry#*:}"
            local _top="${_rest%%:*}"; _rest="${_rest#*:}"
            local _left="${_rest%%:*}"; _rest="${_rest#*:}"
            local _w="${_rest%%:*}";   _rest="${_rest#*:}"
            local _h="${_rest%%:*}"
            printf -v "$_out_top"  '%d' "$_top"
            printf -v "$_out_left" '%d' "$_left"
            printf -v "$_out_w"    '%d' "$_w"
            printf -v "$_out_h"    '%d' "$_h"
            return 0
        fi
    done
    return 1
}

# ── _shellframe_shell_terminal_size ──────────────────────────────────────────

# _shellframe_shell_terminal_size out_rows out_cols
# Read terminal dimensions.  Falls back to 24×80 if stty is unavailable.
# Results are cached in _SHELLFRAME_SHELL_ROWS/_COLS — call
# _shellframe_shell_refresh_size to update the cache (done once per draw).
_SHELLFRAME_SHELL_ROWS=24
_SHELLFRAME_SHELL_COLS=80

_shellframe_shell_refresh_size() {
    # Command substitution (not process substitution) to avoid fd leaks
    # on bash 3.2/macOS.  < <(stty ...) leaks /dev/fd/NN per call.
    local _sz
    _sz=$(stty size </dev/tty 2>/dev/null) || _sz="24 80"
    _SHELLFRAME_SHELL_ROWS="${_sz%% *}"
    _SHELLFRAME_SHELL_COLS="${_sz##* }"
}

_shellframe_shell_terminal_size() {
    local _out_rows="$1" _out_cols="$2"
    printf -v "$_out_rows" '%d' "$_SHELLFRAME_SHELL_ROWS"
    printf -v "$_out_cols" '%d' "$_SHELLFRAME_SHELL_COLS"
}

# ── _shellframe_shell_draw ────────────────────────────────────────────────────

# Full draw cycle: re-run the screen render hook, rebuild focus ring,
# call on_focus for each region, then call each region's render function.
_shellframe_shell_draw() {
    local _prefix="$1" _screen="$2"

    # Refresh terminal size once per draw (no per-call stty forks)
    _shellframe_shell_refresh_size

    # Sheet delegation: if a sheet is active, hand off the draw cycle entirely
    if (( ${_SHELLFRAME_SHEET_ACTIVE:-0} )); then
        shellframe_sheet_draw "$_SHELLFRAME_SHELL_ROWS" "$_SHELLFRAME_SHELL_COLS"
        return
    fi

    # Tick toast TTLs; expired toasts are removed and a redraw is scheduled
    if declare -f shellframe_toast_tick >/dev/null 2>&1; then
        local _pre_toast_n=${#_SHELLFRAME_TOAST_QUEUE[@]}
        shellframe_toast_tick
        if (( ${#_SHELLFRAME_TOAST_QUEUE[@]} < _pre_toast_n )); then
            _SHELLFRAME_SHELL_DIRTY=1
        fi
    fi

    # Start a fresh framebuffer frame (resets CURR + DIRTY; keeps PREV)
    shellframe_fb_frame_start "$_SHELLFRAME_SHELL_ROWS" "$_SHELLFRAME_SHELL_COLS"

    # Re-register regions from scratch (layout uses updated focus state)
    _SHELLFRAME_SHELL_REGIONS=()
    shellframe_widget_clear    # hitbox in sync with region re-registration
    "${_prefix}_${_screen}_render"

    # Rebuild focus ring from freshly registered regions, applying any pending
    # focus request (including requests for regions that were previously nofocus).
    _shellframe_shell_focus_init

    # Fire on_focus using the new ring so every region sees the correct focused
    # state before it renders — including regions that just became focusable.
    local _focused
    _shellframe_shell_focus_owner _focused
    local _entry _n
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        if declare -f "${_prefix}_${_screen}_${_n}_on_focus" >/dev/null 2>&1; then
            if [[ "$_n" == "$_focused" ]]; then
                "${_prefix}_${_screen}_${_n}_on_focus" 1
            else
                "${_prefix}_${_screen}_${_n}_on_focus" 0
            fi
        fi
    done

    # Render each region
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        local _rest="${_entry#*:}"
        local _top="${_rest%%:*}"; _rest="${_rest#*:}"
        local _left="${_rest%%:*}"; _rest="${_rest#*:}"
        local _w="${_rest%%:*}"; _rest="${_rest#*:}"
        local _h="${_rest%%:*}"

        if declare -f "${_prefix}_${_screen}_${_n}_render" >/dev/null 2>&1; then
            "${_prefix}_${_screen}_${_n}_render" "$_top" "$_left" "$_w" "$_h"
        fi
    done

    # Flush only changed rows to the terminal
    shellframe_screen_flush
}

# ── _shellframe_shell_draw_if_dirty ──────────────────────────────────────────
#
# Conditional draw: calls _shellframe_shell_draw only when _SHELLFRAME_SHELL_DIRTY=1,
# then resets the flag. Skips rendering entirely when nothing has changed.
# Use in place of a direct _shellframe_shell_draw call wherever a widget's
# on_key result drives the decision to redraw.
#
# On bash 4+, if more input is already queued in the terminal buffer, the
# render is deferred — the dirty flag stays set and the caller loops back to
# process the next event first. This naturally coalesces rapid-fire events
# (especially mouse-scroll ticks) into a single render at the end.
_shellframe_shell_draw_if_dirty() {
    (( _SHELLFRAME_SHELL_DIRTY )) || return 0
    # TODO: Event coalescing — defer render while more input is queued.
    # Disabled pending investigation of crash in raw terminal mode.
    # When re-enabled, use: read -t 0 2>/dev/null && return 0
    # (only under _SHELLFRAME_SHELL_RUNNING=1 && bash 4+)
    _SHELLFRAME_SHELL_DIRTY=0
    _shellframe_shell_draw "$@"
}

# ── _shellframe_shell_read_key ────────────────────────────────────────────────
#
# Like shellframe_read_key but with a 1-second timeout on the initial byte.
# If the timeout expires (or SIGWINCH interrupts the read), the output var
# is set to "" and the caller should loop back to check for resize.

_shellframe_shell_read_key() {
    local _out_var="${1:-_SHELLFRAME_KEY}"
    local _k="" _c=""

    # Timeout: 1 second.  If SIGWINCH fires, bash 3.2 on macOS will NOT
    # interrupt read, but the 1s timeout ensures we re-check the flag.
    IFS= read -r -n1 -d '' -t 1 _k || true

    if [[ -z "$_k" ]]; then
        printf -v "$_out_var" '%s' ""
        return 0
    fi

    if [[ "$_k" == $'\x1b' ]]; then
        # Short timeout for escape sequence detection (50ms on bash 4+, 1s on 3.2)
        local _esc_t=1
        (( BASH_VERSINFO[0] >= 4 )) && _esc_t=0.05
        IFS= read -r -n1 -d '' -t "$_esc_t" _c || true
        _k+="${_c}"
        if [[ "$_c" == '[' || "$_c" == 'O' ]]; then
            while true; do
                IFS= read -r -n1 -d '' -t 1 _c || break
                _k+="${_c}"
                case "$_c" in
                    [A-Za-z~]) break ;;
                esac
            done
            # SGR mouse: ESC [ < Pb ; Px ; Py M (press) or m (release)
            local _sgr_pfx=$'\x1b[<'
            if [[ "$_k" == "${_sgr_pfx}"* ]]; then
                local _params="${_k#"${_sgr_pfx}"}"
                _params="${_params%[Mm]}"
                local _raw_btn="${_params%%;*}"
                SHELLFRAME_MOUSE_SHIFT=$(( (_raw_btn >> 2) & 1 ))
                SHELLFRAME_MOUSE_META=$(( (_raw_btn >> 3) & 1 ))
                SHELLFRAME_MOUSE_CTRL=$(( (_raw_btn >> 4) & 1 ))
                SHELLFRAME_MOUSE_BUTTON=$(( _raw_btn & ~28 ))
                local _rest="${_params#*;}"
                SHELLFRAME_MOUSE_COL="${_rest%%;*}"
                SHELLFRAME_MOUSE_ROW="${_rest#*;}"
                if [[ "$_k" == *M ]]; then
                    SHELLFRAME_MOUSE_ACTION="press"
                else
                    SHELLFRAME_MOUSE_ACTION="release"
                fi
                printf -v "$_out_var" '%s' "$SHELLFRAME_KEY_MOUSE"
                return 0
            fi
        fi
    fi

    printf -v "$_out_var" '%s' "$_k"
}

# ── shellframe_shell ──────────────────────────────────────────────────────────

shellframe_shell() {
    local _prefix="$1"
    local _current="${2:-ROOT}"
    _SHELLFRAME_SHELL_RUNNING=1

    local _saved_stty
    _saved_stty=$(shellframe_raw_save)
    shellframe_screen_enter
    shellframe_mouse_enter
    shellframe_cursor_hide
    shellframe_raw_enter
    # EXIT trap: restore terminal state even if fd 3 is dead.
    # shellframe_mouse_exit / cursor_show / screen_exit all write >&3.
    # If fd 3 is bad (crash, signal, or /dev/tty disconnected), fall back to
    # writing the escape sequences directly to /dev/tty.
    _shellframe_shell_cleanup() {
        local _rc=$?
        shellframe_raw_exit "$1" 2>/dev/null
        # Try fd 3 first; fall back to /dev/tty
        if { true >&3; } 2>/dev/null; then
            shellframe_mouse_exit
            shellframe_cursor_show
            shellframe_screen_exit
        elif [[ -w /dev/tty ]]; then
            # Disable bracketed paste + mouse reporting + show cursor + exit alt screen
            printf '\033[?2004l\033[?1006l\033[?1000l\033[?25h\033[?1049l' >/dev/tty 2>/dev/null
        fi
        # Diagnostic: log unexpected exits when SHQL_DEBUG is set.
        # set -u errors exit with rc=1 and do NOT trigger ERR traps.
        if [[ -n "${SHQL_DEBUG:-}" ]] && (( _rc != 0 )); then
            {
                printf 'EXIT: rc=%d\n' "$_rc"
                printf 'BASH_COMMAND=%s\n' "${BASH_COMMAND:-unknown}"
                printf 'FUNCNAME=%s\n' "${FUNCNAME[*]:-unknown}"
                printf 'BASH_LINENO=%s\n' "${BASH_LINENO[*]:-unknown}"
            } >> /tmp/shql-crash.log 2>/dev/null
        fi
    }
    trap "_shellframe_shell_cleanup '$_saved_stty'" EXIT INT TERM

    local _k_tab="${SHELLFRAME_KEY_TAB:-$'\t'}"
    local _k_shift_tab="${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"

    # SIGWINCH: flag for redraw on terminal resize
    _SHELLFRAME_SHELL_RESIZED=0
    trap '_SHELLFRAME_SHELL_RESIZED=1' WINCH

    while [[ "$_current" != "__QUIT__" ]]; do

        # Enter new screen: clear terminal + framebuffer, then full draw.
        # shellframe_screen_clear resets _SF_FRAME_PREV so the next flush
        # re-emits every cell (ensures no artifacts from the previous screen).
        _SHELLFRAME_SHELL_FOCUS_IDX=0
        shellframe_screen_clear
        _shellframe_shell_draw "$_prefix" "$_current"

        # Input loop for this screen
        local _screen_done=0
        while (( ! _screen_done )); do
            # Check for pending resize
            if (( _SHELLFRAME_SHELL_RESIZED )); then
                _SHELLFRAME_SHELL_RESIZED=0
                shellframe_screen_clear
                _shellframe_shell_draw "$_prefix" "$_current"
            fi

            # Read with timeout so SIGWINCH can interrupt the loop.
            # Safety: if fd 3 is dead, bail out instead of spinning.
            if ! { true >&3; } 2>/dev/null; then
                _current="__QUIT__"; _screen_done=1; continue
            fi

            local _key=""
            _shellframe_shell_read_key _key
            if [[ -z "$_key" ]]; then
                # Timeout: tick toasts so they expire even when user is idle
                if (( ${#_SHELLFRAME_TOAST_QUEUE[@]} > 0 )); then
                    shellframe_shell_mark_dirty
                    _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                fi
                continue
            fi

            # Check for resize after read returns
            if (( _SHELLFRAME_SHELL_RESIZED )); then
                _SHELLFRAME_SHELL_RESIZED=0
                shellframe_screen_clear
                _shellframe_shell_draw "$_prefix" "$_current"
            fi

            # Sheet delegation: hand key to sheet while one is active
            if (( ${_SHELLFRAME_SHEET_ACTIVE:-0} )); then
                shellframe_sheet_on_key "$_key"
                _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                # An action inside the sheet may have set _SHELLFRAME_SHELL_NEXT
                # (e.g. submit_action requesting __QUIT__). Check it here so the
                # outer loop exits immediately rather than waiting for another key.
                if [[ "${_SHELLFRAME_SHELL_NEXT:-}" == "__QUIT__" ]]; then
                    _current="__QUIT__"; _screen_done=1
                elif [[ -n "${_SHELLFRAME_SHELL_NEXT:-}" ]]; then
                    _current="$_SHELLFRAME_SHELL_NEXT"
                    _SHELLFRAME_SHELL_NEXT=""
                    _screen_done=1
                fi
                continue
            fi

            local _focused
            _shellframe_shell_focus_owner _focused

            # ── Tab: offer to on_key first; cycle focus only if unhandled ─
            if [[ "$_key" == "$_k_tab" ]]; then
                local _tab_handled=0
                if [[ -n "$_focused" ]] && \
                   declare -f "${_prefix}_${_current}_${_focused}_on_key" >/dev/null 2>&1; then
                    if "${_prefix}_${_current}_${_focused}_on_key" "$_key"; then
                        _tab_handled=1
                    fi
                fi
                if (( ! _tab_handled )); then
                    [[ -n "$_focused" ]] && \
                        declare -f "${_prefix}_${_current}_${_focused}_on_focus" >/dev/null 2>&1 && \
                        "${_prefix}_${_current}_${_focused}_on_focus" 0 || true
                    _shellframe_shell_focus_next
                fi
                # Focus change is always visible — mark dirty unconditionally.
                shellframe_shell_mark_dirty
                _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                continue
            fi

            # ── Shift-Tab: offer to on_key first; retreat focus if unhandled
            if [[ "$_key" == "$_k_shift_tab" ]]; then
                local _shift_tab_handled=0
                if [[ -n "$_focused" ]] && \
                   declare -f "${_prefix}_${_current}_${_focused}_on_key" >/dev/null 2>&1; then
                    if "${_prefix}_${_current}_${_focused}_on_key" "$_key"; then
                        _shift_tab_handled=1
                    fi
                fi
                if (( ! _shift_tab_handled )); then
                    [[ -n "$_focused" ]] && \
                        declare -f "${_prefix}_${_current}_${_focused}_on_focus" >/dev/null 2>&1 && \
                        "${_prefix}_${_current}_${_focused}_on_focus" 0 || true
                    _shellframe_shell_focus_prev
                fi
                # Focus change is always visible — mark dirty unconditionally.
                shellframe_shell_mark_dirty
                _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                continue
            fi

            # ── Mouse event: hit-test + dispatch ──────────────────────────
            if [[ "$_key" == "$SHELLFRAME_KEY_MOUSE" ]]; then
                local _target=""
                shellframe_widget_at "$SHELLFRAME_MOUSE_ROW" "$SHELLFRAME_MOUSE_COL" _target
                if [[ -n "$_target" ]]; then
                    # Click-to-focus: move focus if press lands on unfocused widget.
                    # Ignore release events — the release from a click that changed
                    # focus (or opened a new tab) must not steal focus back.
                    if [[ "$SHELLFRAME_MOUSE_ACTION" == "press" && "$_target" != "$_focused" ]]; then
                        shellframe_shell_focus_set "$_target"
                        shellframe_shell_mark_dirty
                    fi
                    # Dispatch on_mouse handler if the widget defines one
                    if declare -f "${_prefix}_${_current}_${_target}_on_mouse" >/dev/null 2>&1; then
                        local _rt=1 _rl=1 _rw=0 _rh=0
                        _shellframe_shell_region_bounds "$_target" _rt _rl _rw _rh || true
                        "${_prefix}_${_current}_${_target}_on_mouse" \
                            "$SHELLFRAME_MOUSE_BUTTON" "$SHELLFRAME_MOUSE_ACTION" \
                            "$SHELLFRAME_MOUSE_ROW"    "$SHELLFRAME_MOUSE_COL" \
                            "$_rt" "$_rl" "$_rw" "$_rh"
                    fi
                    # Check for screen transition (same logic as key handler rc=2 path)
                    if [[ "${_SHELLFRAME_SHELL_NEXT:-}" == "__QUIT__" ]]; then
                        _current="__QUIT__"; _screen_done=1
                    elif [[ -n "${_SHELLFRAME_SHELL_NEXT:-}" ]]; then
                        _current="$_SHELLFRAME_SHELL_NEXT"
                        _SHELLFRAME_SHELL_NEXT=""
                        _screen_done=1
                    else
                        _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                    fi
                fi
                # Click outside all registered widgets is a no-op
                continue
            fi

            # ── Ctrl+Q: unconditional quit from any screen/focus ──────────
            if [[ "$_key" == $'\x11' ]]; then
                _current="__QUIT__"; _screen_done=1; continue
            fi

            # ── Deliver key to focused region ──────────────────────────────
            if [[ -n "$_focused" ]] && \
               declare -f "${_prefix}_${_current}_${_focused}_on_key" >/dev/null 2>&1; then
                local _rc=0
                "${_prefix}_${_current}_${_focused}_on_key" "$_key" || _rc=$?

                if (( _rc == 0 )); then
                    # Widget handled the key.  Draw only if the widget (or its
                    # underlying module) called shellframe_shell_mark_dirty.
                    _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                    continue
                elif (( _rc == 2 )); then
                    _SHELLFRAME_SHELL_NEXT=""
                    declare -f "${_prefix}_${_current}_${_focused}_action" >/dev/null 2>&1 && \
                        "${_prefix}_${_current}_${_focused}_action" || true
                    if [[ "${_SHELLFRAME_SHELL_NEXT:-}" == "__QUIT__" ]]; then
                        _current="__QUIT__"; _screen_done=1
                    elif [[ -n "${_SHELLFRAME_SHELL_NEXT:-}" ]]; then
                        _current="$_SHELLFRAME_SHELL_NEXT"
                        _SHELLFRAME_SHELL_NEXT=""
                        _screen_done=1
                    else
                        _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                    fi
                    continue
                fi
                # rc=1: fall through to global handler
            fi

            # ── Global default handler: q/Q/Esc → quit ────────────────────
            if [[ "$_key" == "q" || "$_key" == "Q" || "$_key" == $'\033' ]]; then
                if declare -f "${_prefix}_${_current}_quit" >/dev/null 2>&1; then
                    _SHELLFRAME_SHELL_NEXT=""
                    "${_prefix}_${_current}_quit"
                    if [[ "${_SHELLFRAME_SHELL_NEXT:-}" == "__QUIT__" ]]; then
                        _current="__QUIT__"; _screen_done=1
                    elif [[ -n "${_SHELLFRAME_SHELL_NEXT:-}" ]]; then
                        _current="$_SHELLFRAME_SHELL_NEXT"
                        _SHELLFRAME_SHELL_NEXT=""
                        _screen_done=1
                    else
                        # _quit activated an overlay (e.g. confirm dialog) without
                        # navigating screens — draw immediately so the overlay is
                        # visible before the next key is read.
                        _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                    fi
                else
                    _current="__QUIT__"; _screen_done=1
                fi
            fi

        done
    done

    _SHELLFRAME_SHELL_RUNNING=0
    # Normal exit — clear trap first so cleanup doesn't run twice
    trap - EXIT INT TERM WINCH
    shellframe_raw_exit "$_saved_stty" 2>/dev/null
    if { true >&3; } 2>/dev/null; then
        shellframe_mouse_exit
        shellframe_cursor_show
        shellframe_screen_exit
    elif [[ -w /dev/tty ]]; then
        printf '\033[?2004l\033[?1006l\033[?1000l\033[?25h\033[?1049l' >/dev/tty 2>/dev/null
    fi
}
