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

# ── shellframe_shell_region ───────────────────────────────────────────────────

# shellframe_shell_region name top left width height [nofocus]
# Register a named region.  Call from within PREFIX_SCREEN_render().
shellframe_shell_region() {
    local _name="$1" _top="$2" _left="$3" _width="$4" _height="$5"
    local _focus="${6:-focus}"
    _SHELLFRAME_SHELL_REGIONS+=("${_name}:${_top}:${_left}:${_width}:${_height}:${_focus}")
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

    # Apply any pending focus request to the PREVIOUS cycle's ring
    # so on_focus sees the correct owner before regions are re-registered.
    if [[ -n "$_SHELLFRAME_SHELL_FOCUS_REQUEST" ]]; then
        local _req_name="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
        local _req_found=0 _ri
        for _ri in "${!_SHELLFRAME_SHELL_FOCUS_RING[@]}"; do
            if [[ "${_SHELLFRAME_SHELL_FOCUS_RING[$_ri]}" == "$_req_name" ]]; then
                _SHELLFRAME_SHELL_FOCUS_IDX=$_ri
                _SHELLFRAME_SHELL_FOCUS_REQUEST=""
                _req_found=1
                break
            fi
        done
        # If not found in old ring, leave the request for focus_init
        # (the region may be registered in the upcoming render)
    fi

    # Fire on_focus using the (now updated) focus ring
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

    # Re-register regions from scratch (layout uses updated focus state)
    _SHELLFRAME_SHELL_REGIONS=()
    "${_prefix}_${_screen}_render"

    # Rebuild focus ring, preserving current focus owner by name
    _shellframe_shell_focus_init

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
        IFS= read -r -n1 -d '' -t 1 _c || true
        _k+="${_c}"
        if [[ "$_c" == '[' || "$_c" == 'O' ]]; then
            while true; do
                IFS= read -r -n1 -d '' -t 1 _c || break
                _k+="${_c}"
                case "$_c" in
                    [A-Za-z~]) break ;;
                esac
            done
        fi
    fi

    printf -v "$_out_var" '%s' "$_k"
}

# ── shellframe_shell ──────────────────────────────────────────────────────────

shellframe_shell() {
    local _prefix="$1"
    local _current="${2:-ROOT}"

    local _saved_stty
    _saved_stty=$(shellframe_raw_save)
    shellframe_screen_enter
    shellframe_cursor_hide
    shellframe_raw_enter
    trap "shellframe_raw_exit '$_saved_stty'; shellframe_cursor_show; shellframe_screen_exit" EXIT INT TERM

    local _k_tab="${SHELLFRAME_KEY_TAB:-$'\t'}"
    local _k_shift_tab="${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"

    # SIGWINCH: flag for redraw on terminal resize
    _SHELLFRAME_SHELL_RESIZED=0
    trap '_SHELLFRAME_SHELL_RESIZED=1' WINCH

    while [[ "$_current" != "__QUIT__" ]]; do

        # Enter new screen: reset focus ring index to 0, full draw
        # Preserve any pending focus request (e.g. set before shell launch)
        _SHELLFRAME_SHELL_FOCUS_IDX=0
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
            [[ -z "$_key" ]] && continue   # timeout or resize — loop back

            # Check for resize after read returns
            if (( _SHELLFRAME_SHELL_RESIZED )); then
                _SHELLFRAME_SHELL_RESIZED=0
                shellframe_screen_clear
                _shellframe_shell_draw "$_prefix" "$_current"
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
                _shellframe_shell_draw "$_prefix" "$_current"
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
                _shellframe_shell_draw "$_prefix" "$_current"
                continue
            fi

            # ── Deliver key to focused region ──────────────────────────────
            if [[ -n "$_focused" ]] && \
               declare -f "${_prefix}_${_current}_${_focused}_on_key" >/dev/null 2>&1; then
                local _rc=0
                "${_prefix}_${_current}_${_focused}_on_key" "$_key" || _rc=$?

                if (( _rc == 0 )); then
                    _shellframe_shell_draw "$_prefix" "$_current"
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
                        _shellframe_shell_draw "$_prefix" "$_current"
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
                    fi
                else
                    _current="__QUIT__"; _screen_done=1
                fi
            fi

        done
    done

    shellframe_raw_exit "$_saved_stty"
    shellframe_cursor_show
    shellframe_screen_exit
    trap - EXIT INT TERM WINCH
}
