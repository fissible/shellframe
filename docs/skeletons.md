# shellframe — TUI Skeletons

Copy-paste starting points for common patterns.

---

## Application skeleton (`shellframe_app`)

Use this for any multi-screen application. Define screens as function
triples; `shellframe_app` manages the loop.

```bash
source /path/to/shellframe/shellframe.sh

# Module-level context globals shared between screens
_APP_DATA=()

# ── Screen: MAIN (action-list) ──────────────────────────────────────
_app_MAIN_type()    { printf 'action-list'; }
_app_MAIN_render()  {
    SHELLFRAME_AL_LABELS=(...)
    SHELLFRAME_AL_ACTIONS=(...)
    SHELLFRAME_AL_IDX=(...)
    _SHELLFRAME_APP_DRAW_FN="_app_draw_row"   # optional custom renderer
    _SHELLFRAME_APP_HINT="Space cycle  Enter confirm  q quit"
}
_app_MAIN_confirm() { _SHELLFRAME_APP_NEXT="CONFIRM"; }   # or 'MAIN' if nothing selected
_app_MAIN_quit()    { _SHELLFRAME_APP_NEXT="__QUIT__"; }

# ── Screen: CONFIRM (yes/no modal) ─────────────────────────────────
_app_CONFIRM_type()   { printf 'confirm'; }
_app_CONFIRM_render() { _SHELLFRAME_APP_QUESTION="Apply changes?"; }
_app_CONFIRM_yes()    { _app_apply; _SHELLFRAME_APP_NEXT="RESULT"; }
_app_CONFIRM_no()     { _SHELLFRAME_APP_NEXT="MAIN"; }

# ── Screen: RESULT (alert modal) ───────────────────────────────────
_app_RESULT_type()    { printf 'alert'; }
_app_RESULT_render()  { _SHELLFRAME_APP_TITLE="Done"; _SHELLFRAME_APP_DETAILS=("${_APP_DATA[@]}"); }
_app_RESULT_dismiss() { _SHELLFRAME_APP_NEXT="MAIN"; }

# ── Entry point ────────────────────────────────────────────────────
my_app() {
    shellframe_app "_app" "MAIN"
}
```

---

## Table screen skeleton (inside `shellframe_app`)

Use this when the main screen should be a full-page navigable table with page chrome.

```bash
source /path/to/shellframe/shellframe.sh

# Module-level context globals
_APP_PENDING=()
_APP_RESULTS=()

# ── Screen: ROOT (table) ────────────────────────────────────────────
_app_ROOT_type()   { printf 'table'; }
_app_ROOT_render() {
    # --- data ---
    SHELLFRAME_TBL_LABELS=("row-a" "row-b" "row-c")
    SHELLFRAME_TBL_ACTIONS=("nothing run" "nothing run" "nothing run")
    SHELLFRAME_TBL_IDX=(0 0 0)
    SHELLFRAME_TBL_SCROLL=0   # reset scroll on fresh data load

    # --- columns ---
    SHELLFRAME_TBL_HEADERS=("Name" "" "Action")
    SHELLFRAME_TBL_COL_WIDTHS=(24 4 14)

    # --- page chrome ---
    SHELLFRAME_TBL_PAGE_TITLE="My App"
    SHELLFRAME_TBL_PAGE_H1="Select actions then press Enter"
    SHELLFRAME_TBL_PAGE_FOOTER="$HOME/bin"

    # --- optional below-hint area ---
    SHELLFRAME_TBL_BELOW_FN="_app_action_desc"
    SHELLFRAME_TBL_BELOW_ROWS=1

    # --- optional callbacks ---
    _SHELLFRAME_APP_DRAW_FN="_app_draw_row"     # omit to use built-in renderer
    _SHELLFRAME_APP_KEY_FN="_app_extra_key"     # omit if no extra keys needed
    _SHELLFRAME_APP_HINT="Space cycle  Enter confirm  q quit"
}
_app_ROOT_confirm() {
    # Build _APP_PENDING from SHELLFRAME_TBL_IDX; if nothing selected, stay
    _SHELLFRAME_APP_NEXT="CONFIRM"
}
_app_ROOT_quit() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

# Optional: custom row renderer
_app_draw_row() {
    local _i="$1" _label="$2" _acts_str="$3" _aidx="$4" _meta="$5"
    local _cursor="  "
    (( _i == SHELLFRAME_TBL_SELECTED )) && _cursor="> "
    local -a _acts; IFS=' ' read -r -a _acts <<< "$_acts_str"
    printf '%s%-24s  [%s]' "$_cursor" "$_label" "${_acts[$_aidx]}"
}

# Optional: below-hint callback — called with (first_row, left_col, cols, height)
_app_action_desc() {
    local _top="$1" _left="$2" _cols="$3" _height="$4"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left"   # clear the area
    local _acts_str="${SHELLFRAME_TBL_ACTIONS[$SHELLFRAME_TBL_SELECTED]:-}"
    local _aidx="${SHELLFRAME_TBL_IDX[$SHELLFRAME_TBL_SELECTED]:-0}"
    local -a _acts; IFS=' ' read -r -a _acts <<< "$_acts_str"
    local _action="${_acts[$_aidx]:-}"
    [[ "$_action" == "nothing" ]] && return 0
    printf '\033[%d;%dH  [ %s ]  %s' "$_top" "$_left" "$_action" "${SHELLFRAME_TBL_LABELS[$SHELLFRAME_TBL_SELECTED]:-}"
}

# ── Screen: CONFIRM (yes/no modal) ─────────────────────────────────
_app_CONFIRM_type()   { printf 'confirm'; }
_app_CONFIRM_render() {
    _SHELLFRAME_APP_QUESTION="Apply changes?"
    _SHELLFRAME_APP_DETAILS=("${_APP_PENDING[@]+"${_APP_PENDING[@]}"}")
}
_app_CONFIRM_yes()    { _app_apply; _SHELLFRAME_APP_NEXT="RESULT"; }
_app_CONFIRM_no()     { _SHELLFRAME_APP_NEXT="ROOT"; }

# ── Screen: RESULT (alert modal) ───────────────────────────────────
_app_RESULT_type()    { printf 'alert'; }
_app_RESULT_render()  {
    _SHELLFRAME_APP_TITLE="Done"
    _SHELLFRAME_APP_DETAILS=("${_APP_RESULTS[@]+"${_APP_RESULTS[@]}"}")
}
_app_RESULT_dismiss() { _SHELLFRAME_APP_NEXT="ROOT"; }

# ── Entry point ────────────────────────────────────────────────────
my_app() {
    shellframe_app "_app" "ROOT"
}
```

---

## Custom widget skeleton

Use this when building a new widget or a single-screen TUI that doesn't
fit the three standard widget types.

```bash
source /path/to/shellframe/shellframe.sh

my_widget() {
    # ── Setup ──────────────────────────────────────────────────────
    local saved_stty
    saved_stty=$(shellframe_raw_save)
    exec 3>&1; exec 1>/dev/tty

    _exit() {
        shellframe_raw_exit "$saved_stty"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_exit; exit 1' INT TERM

    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── Draw ───────────────────────────────────────────────────────
    _draw() {
        shellframe_screen_clear
        # ... printf your UI here using ANSI escape sequences ...
    }
    _draw

    # ── Input loop ─────────────────────────────────────────────────
    local key
    while true; do
        shellframe_read_key key
        if   [[ "$key" == "$SHELLFRAME_KEY_UP"    ]]; then : # handle up
        elif [[ "$key" == "$SHELLFRAME_KEY_DOWN"  ]]; then : # handle down
        elif [[ "$key" == "$SHELLFRAME_KEY_ENTER" ]]; then break
        elif [[ "$key" == 'q' ]]; then break
        fi
        _draw
    done

    # ── Teardown ───────────────────────────────────────────────────
    trap - INT TERM
    _exit
}
```

> **Note:** The `exec 3>&1 / exec 1>/dev/tty` plumbing is required if this
> widget may be called inside `$()` command substitution. See
> [Hard-won lessons](hard-won-lessons.md#9-command-substitution--pipes-stdout-away-from-the-terminal).
