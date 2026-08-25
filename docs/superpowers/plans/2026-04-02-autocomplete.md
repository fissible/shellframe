# Autocomplete Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a composable autocomplete widget that layers a filtered suggestion popup on top of an input-field or editor, with consumer-provided suggestion sources.

**Architecture:** The autocomplete module manages a state machine (idle/active), intercepts keys when the popup is visible, and delegates popup rendering to the existing context-menu widget. The consumer provides a provider callback that populates a flat matches array given a prefix. Word extraction from the attached field/editor handles both single-line (cursor.sh) and multi-line (editor.sh) contexts.

**Tech Stack:** bash 3.2+, flat arrays (no associative arrays), existing shellframe primitives (context-menu, cursor, input-field, editor, selection, scroll)

**API deviation from issue spec:** `shellframe_ac_render` takes 6 args (`top left width height cursor_row cursor_col`) instead of the spec's 4. The popup must know the text cursor's screen position to anchor correctly — the bounding region alone is insufficient. Additionally, `shellframe_ac_on_key_after` is added for auto-trigger mode: the caller invokes it after the field processes a printable key so the match list re-filters.

---

### Task 1: Core module — attach, detach, prefix extraction

**Files:**
- Create: `src/widgets/autocomplete.sh`
- Test: `tests/unit/test-autocomplete.sh`

This task creates the autocomplete module with globals, attach/detach, and the internal prefix extraction function that reads the word-under-cursor from either an input-field or editor context.

- [ ] **Step 1: Write the failing tests for attach, detach, and prefix extraction**

Create `tests/unit/test-autocomplete.sh`:

```bash
#!/usr/bin/env bash
# tests/unit/test-autocomplete.sh — Unit tests for src/widgets/autocomplete.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd setup for coverage ────────────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── attach / detach ──────────────────────────────────────────────────────────

ptyunit_test_begin "ac_attach: sets context and mode for input-field"
shellframe_cur_init "testfield"
shellframe_ac_attach "testfield" "field"
assert_eq "testfield" "$_SHELLFRAME_AC_CTX" "ctx set"
assert_eq "field" "$_SHELLFRAME_AC_MODE" "mode set"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "starts idle"

ptyunit_test_begin "ac_attach: sets context and mode for editor"
shellframe_editor_init "testeditor"
shellframe_ac_attach "testeditor" "editor"
assert_eq "testeditor" "$_SHELLFRAME_AC_CTX" "ctx set"
assert_eq "editor" "$_SHELLFRAME_AC_MODE" "mode set"

ptyunit_test_begin "ac_detach: clears state"
shellframe_ac_attach "testfield" "field"
shellframe_ac_detach
assert_eq "" "$_SHELLFRAME_AC_CTX" "ctx cleared"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "active cleared"

# ── prefix extraction: input-field ───────────────────────────────────────────

ptyunit_test_begin "ac_prefix: extracts word at end of input-field"
shellframe_cur_init "pf1" "SELECT * FROM us"
shellframe_ac_attach "pf1" "field"
local _pfx=""
_shellframe_ac_prefix _pfx
assert_eq "us" "$_pfx" "word at cursor"

ptyunit_test_begin "ac_prefix: extracts word at middle of input-field"
shellframe_cur_init "pf2" "SELECT col FROM tbl"
shellframe_cur_set "pf2" "SELECT col FROM tbl" 10
shellframe_ac_attach "pf2" "field"
local _pfx=""
_shellframe_ac_prefix _pfx
assert_eq "col" "$_pfx" "word at cursor mid-text"

ptyunit_test_begin "ac_prefix: empty when cursor at space boundary"
shellframe_cur_init "pf3" "SELECT "
shellframe_ac_attach "pf3" "field"
local _pfx=""
_shellframe_ac_prefix _pfx
assert_eq "" "$_pfx" "empty prefix"

# ── prefix extraction: editor ────────────────────────────────────────────────

ptyunit_test_begin "ac_prefix: extracts word from editor current line"
shellframe_editor_init "pfe1"
shellframe_editor_set_text "pfe1" "SELECT * FROM us"
shellframe_ac_attach "pfe1" "editor"
local _pfx=""
_shellframe_ac_prefix _pfx
assert_eq "us" "$_pfx" "editor word at cursor"

ptyunit_test_summary
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: FAIL — `shellframe_ac_attach: command not found`

- [ ] **Step 3: Create the autocomplete module with globals, attach, detach, prefix**

Create `src/widgets/autocomplete.sh`:

```bash
#!/usr/bin/env bash
# shellframe/src/widgets/autocomplete.sh — Autocomplete layer (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/cursor.sh, src/widgets/input-field.sh, src/widgets/editor.sh,
#           src/widgets/context-menu.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Composable autocomplete that layers a filtered suggestion popup on top of an
# input-field or editor.  The suggestion source is a callback provided by the
# consumer — shellframe handles only the UI mechanics.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_AC_PROVIDER    — name of a function: provider(prefix, out_array)
#   SHELLFRAME_AC_TRIGGER     — "auto" (every keystroke) | "tab" (Tab triggers)
#   SHELLFRAME_AC_MAX_HEIGHT  — max popup rows before scrolling (default: 8)
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_AC_RESULT      — accepted suggestion text (set on accept)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_ac_attach ctx mode
#     Attach autocomplete to an input-field or editor context.
#     ctx:  the cursor context name (input-field) or editor context name
#     mode: "field" | "editor"
#
#   shellframe_ac_detach
#     Remove autocomplete from the attached context.
#
#   shellframe_ac_on_key key → 0 (consumed) | 1 (pass-through)
#     Intercept keys.  When idle, triggers popup on appropriate key.
#     When active, handles navigation/accept/dismiss, or filters.
#
#   shellframe_ac_render top left width height
#     Render the popup if active.  Bounding region is the full screen area.
#
#   shellframe_ac_dismiss
#     Hide the popup without accepting.

SHELLFRAME_AC_PROVIDER=""
SHELLFRAME_AC_TRIGGER="auto"
SHELLFRAME_AC_MAX_HEIGHT=8
SHELLFRAME_AC_RESULT=""

# ── Internal state ───────────────────────────────────────────────────────────

_SHELLFRAME_AC_CTX=""          # attached cursor/editor context name
_SHELLFRAME_AC_MODE=""         # "field" | "editor"
_SHELLFRAME_AC_ACTIVE=0        # 0=idle, 1=popup visible
_SHELLFRAME_AC_MATCHES=()      # current filtered matches (flat array)
_SHELLFRAME_AC_PREFIX=""        # current prefix being completed
_SHELLFRAME_AC_ANCHOR_ROW=1    # popup anchor screen row
_SHELLFRAME_AC_ANCHOR_COL=1    # popup anchor screen col

# ── shellframe_ac_attach ─────────────────────────────────────────────────────

shellframe_ac_attach() {
    _SHELLFRAME_AC_CTX="$1"
    _SHELLFRAME_AC_MODE="${2:-field}"
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
    SHELLFRAME_AC_RESULT=""
}

# ── shellframe_ac_detach ─────────────────────────────────────────────────────

shellframe_ac_detach() {
    _SHELLFRAME_AC_CTX=""
    _SHELLFRAME_AC_MODE=""
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}

# ── _shellframe_ac_prefix ────────────────────────────────────────────────────
# Extract the word-under-cursor from the attached context.
# Walks leftward from cursor position to find the start of the current word.
# Usage: _shellframe_ac_prefix out_var

_shellframe_ac_prefix() {
    local _out="$1"
    local _ctx="$_SHELLFRAME_AC_CTX"
    local _text="" _pos=0

    if [[ "$_SHELLFRAME_AC_MODE" == "editor" ]]; then
        local _row
        _row=$(shellframe_editor_row "$_ctx")
        _text=$(shellframe_editor_line "$_ctx" "$_row")
        _pos=$(shellframe_editor_col "$_ctx")
    else
        shellframe_cur_text "$_ctx" _text
        shellframe_cur_pos "$_ctx" _pos
    fi

    # Walk left from cursor to find word start
    local _start="$_pos"
    while (( _start > 0 )); do
        local _ch="${_text:$(( _start - 1 )):1}"
        case "$_ch" in
            [a-zA-Z0-9_.\-]) (( _start-- )) ;;
            *) break ;;
        esac
    done

    local _prefix="${_text:$_start:$(( _pos - _start ))}"
    printf -v "$_out" '%s' "$_prefix"
}

# ── shellframe_ac_dismiss ────────────────────────────────────────────────────

shellframe_ac_dismiss() {
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}
```

- [ ] **Step 4: Source the new module in shellframe.sh**

Add after the `context-menu.sh` source line in `shellframe.sh`:

```bash
source "$SHELLFRAME_DIR/src/widgets/autocomplete.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: OK — all assertions pass

- [ ] **Step 6: Run full unit suite to verify no regressions**

Run: `bash tests/run.sh --unit`
Expected: all pass (previous 1323 + new autocomplete tests)

- [ ] **Step 7: Commit**

```bash
git add src/widgets/autocomplete.sh tests/unit/test-autocomplete.sh shellframe.sh
git commit -m "feat(autocomplete): add module with attach/detach and prefix extraction (shellframe#38)"
```

---

### Task 2: Provider invocation and popup activation

**Files:**
- Modify: `src/widgets/autocomplete.sh`
- Modify: `tests/unit/test-autocomplete.sh`

Add the internal function that calls the consumer's provider to populate matches, and the activation logic (open popup when matches exist, auto-complete when exactly 1 match in tab mode).

- [ ] **Step 1: Write failing tests for provider invocation and activation**

Append to `tests/unit/test-autocomplete.sh` (before `ptyunit_test_summary`):

```bash
# ── provider + activation ────────────────────────────────────────────────────

# Test provider function — returns items starting with prefix
_test_provider() {
    local _prefix="$1" _out="$2"
    local _all=("users" "user_roles" "products" "profiles")
    local _matches=()
    local _i
    for _i in "${_all[@]}"; do
        case "$_i" in
            "${_prefix}"*) _matches+=("$_i") ;;
        esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

ptyunit_test_begin "ac_update: populates matches from provider"
shellframe_cur_init "prov1" "us"
shellframe_ac_attach "prov1" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "2" "${#_SHELLFRAME_AC_MATCHES[@]}" "2 matches for 'us'"
assert_eq "users" "${_SHELLFRAME_AC_MATCHES[0]}" "first match"
assert_eq "user_roles" "${_SHELLFRAME_AC_MATCHES[1]}" "second match"

ptyunit_test_begin "ac_update: activates popup when matches > 1"
shellframe_cur_init "prov2" "us"
shellframe_ac_attach "prov2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE" "popup active"

ptyunit_test_begin "ac_update: deactivates when 0 matches"
shellframe_cur_init "prov3" "xyz"
shellframe_ac_attach "prov3" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "popup hidden"
assert_eq "0" "${#_SHELLFRAME_AC_MATCHES[@]}" "no matches"

ptyunit_test_begin "ac_update: single match does not open popup (tab trigger)"
shellframe_cur_init "prov4" "prod"
shellframe_ac_attach "prov4" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
_shellframe_ac_update
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "popup not shown for single match in tab mode"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_update: single match opens popup in auto mode"
shellframe_cur_init "prov5" "prod"
shellframe_ac_attach "prov5" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="auto"
_shellframe_ac_update
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE" "popup shown for single match in auto mode"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: FAIL — `_shellframe_ac_update: command not found`

- [ ] **Step 3: Implement _shellframe_ac_update**

Add to `src/widgets/autocomplete.sh` after `shellframe_ac_dismiss`:

```bash
# ── _shellframe_ac_update ────────────────────────────────────────────────────
# Call the provider with the current prefix, populate matches, manage popup state.

_shellframe_ac_update() {
    local _prefix=""
    _shellframe_ac_prefix _prefix
    _SHELLFRAME_AC_PREFIX="$_prefix"

    # Call provider
    _SHELLFRAME_AC_MATCHES=()
    if [[ -n "$SHELLFRAME_AC_PROVIDER" && -n "$_prefix" ]]; then
        "$SHELLFRAME_AC_PROVIDER" "$_prefix" "_SHELLFRAME_AC_MATCHES"
    fi

    local _n=${#_SHELLFRAME_AC_MATCHES[@]}

    if (( _n == 0 )); then
        _SHELLFRAME_AC_ACTIVE=0
        return
    fi

    # Single match in tab mode: don't open popup (Tab will auto-complete)
    if (( _n == 1 )) && [[ "$SHELLFRAME_AC_TRIGGER" == "tab" ]]; then
        _SHELLFRAME_AC_ACTIVE=0
        return
    fi

    # Activate popup and initialise context-menu selection
    _SHELLFRAME_AC_ACTIVE=1
    SHELLFRAME_CMENU_ITEMS=("${_SHELLFRAME_AC_MATCHES[@]}")
    SHELLFRAME_CMENU_CTX="ac_popup"
    SHELLFRAME_CMENU_MAX_HEIGHT="${SHELLFRAME_AC_MAX_HEIGHT:-8}"
    shellframe_cmenu_init "ac_popup"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add src/widgets/autocomplete.sh tests/unit/test-autocomplete.sh
git commit -m "feat(autocomplete): add provider invocation and popup activation (shellframe#38)"
```

---

### Task 3: on_key — key interception and accept/dismiss

**Files:**
- Modify: `src/widgets/autocomplete.sh`
- Modify: `tests/unit/test-autocomplete.sh`

Implement `shellframe_ac_on_key` — the key dispatcher that:
- When idle + auto trigger: calls update after printable keys
- When idle + tab trigger: opens popup on Tab
- When active: Enter/Tab accepts, Esc dismisses, Up/Down navigate, printable keys filter
- Accept logic: replace the prefix in the attached context with the selected suggestion

- [ ] **Step 1: Write failing tests for on_key**

Append to `tests/unit/test-autocomplete.sh` (before `ptyunit_test_summary`):

```bash
# ── on_key: idle passthrough ─────────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: idle returns 1 for unrelated key"
shellframe_cur_init "ok1"
shellframe_ac_attach "ok1" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
shellframe_ac_on_key "x"
assert_eq "1" "$?" "passthrough when idle"

# ── on_key: tab trigger ─────────────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: Tab triggers popup in tab mode"
shellframe_cur_init "ok2" "us"
shellframe_ac_attach "ok2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "0" "$?" "Tab consumed"
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE" "popup opened"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_on_key: Tab auto-completes single match"
shellframe_cur_init "ok3" "prod"
shellframe_ac_attach "ok3" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "0" "$?" "Tab consumed"
local _text=""
shellframe_cur_text "ok3" _text
assert_eq "products" "$_text" "auto-completed"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "popup not shown"
SHELLFRAME_AC_TRIGGER="auto"

# ── on_key: active — accept ─────────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: Enter accepts selected suggestion"
shellframe_cur_init "ok4" "us"
shellframe_ac_attach "ok4" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'   # open popup, "users" at cursor 0
shellframe_ac_on_key $'\r'   # accept
assert_eq "0" "$?" "Enter consumed"
local _text=""
shellframe_cur_text "ok4" _text
assert_eq "users" "$_text" "prefix replaced with selection"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "popup closed"

# ── on_key: active — dismiss ────────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: Esc dismisses popup"
shellframe_cur_init "ok5" "us"
shellframe_ac_attach "ok5" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE" "popup open"
shellframe_ac_on_key $'\033'
assert_eq "0" "$?" "Esc consumed"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE" "popup dismissed"

# ── on_key: active — navigation ─────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: Down moves selection in active popup"
shellframe_cur_init "ok6" "us"
shellframe_ac_attach "ok6" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'   # open: cursor at 0 ("users")
shellframe_ac_on_key "$SHELLFRAME_KEY_DOWN"
local _cur=0
shellframe_sel_cursor "ac_popup" _cur 2>/dev/null || true
assert_eq "1" "$_cur" "moved to second item"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: FAIL — `shellframe_ac_on_key: command not found`

- [ ] **Step 3: Implement _shellframe_ac_accept and shellframe_ac_on_key**

Add to `src/widgets/autocomplete.sh`:

```bash
# ── _shellframe_ac_accept ────────────────────────────────────────────────────
# Replace the prefix in the attached context with the selected match.

_shellframe_ac_accept() {
    local _match="$1"
    local _ctx="$_SHELLFRAME_AC_CTX"
    local _prefix="$_SHELLFRAME_AC_PREFIX"
    local _plen=${#_prefix}

    SHELLFRAME_AC_RESULT="$_match"

    if [[ "$_SHELLFRAME_AC_MODE" == "editor" ]]; then
        # In editor mode: get current line, replace prefix, set line back
        local _row _col _line
        _row=$(shellframe_editor_row "$_ctx")
        _col=$(shellframe_editor_col "$_ctx")
        _line=$(shellframe_editor_line "$_ctx" "$_row")
        local _start=$(( _col - _plen ))
        local _new="${_line:0:$_start}${_match}${_line:$_col}"
        local _new_col=$(( _start + ${#_match} ))
        # Use cur_set on the editor's internal line storage
        local _line_var="_SHELLFRAME_ED_${_ctx}_LINE_${_row}"
        printf -v "$_line_var" '%s' "$_new"
        printf -v "_SHELLFRAME_ED_${_ctx}_COL" '%d' "$_new_col"
    else
        # Input-field mode: operate on cursor context
        local _text _pos
        shellframe_cur_text "$_ctx" _text
        shellframe_cur_pos "$_ctx" _pos
        local _start=$(( _pos - _plen ))
        local _new="${_text:0:$_start}${_match}${_text:$_pos}"
        local _new_pos=$(( _start + ${#_match} ))
        shellframe_cur_set "$_ctx" "$_new" "$_new_pos"
    fi

    shellframe_ac_dismiss
}

# ── shellframe_ac_on_key ─────────────────────────────────────────────────────

shellframe_ac_on_key() {
    local _key="$1"

    # No context attached — pass through
    [[ -z "$_SHELLFRAME_AC_CTX" ]] && return 1

    local _k_tab=$'\t'
    local _k_esc=$'\033'
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"

    # ── Active popup: intercept navigation/accept/dismiss ────────────
    if (( _SHELLFRAME_AC_ACTIVE )); then
        # Enter or Tab: accept current selection
        if [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]] || [[ "$_key" == "$_k_tab" ]]; then
            local _cursor=0
            shellframe_sel_cursor "ac_popup" _cursor 2>/dev/null || _cursor=0
            local _n=${#_SHELLFRAME_AC_MATCHES[@]}
            if (( _cursor >= 0 && _cursor < _n )); then
                _shellframe_ac_accept "${_SHELLFRAME_AC_MATCHES[$_cursor]}"
            else
                shellframe_ac_dismiss
            fi
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Esc: dismiss
        if [[ "$_key" == "$_k_esc" ]]; then
            shellframe_ac_dismiss
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Up/Down: navigate popup
        if [[ "$_key" == "$_k_up" ]] || [[ "$_key" == "$_k_down" ]]; then
            shellframe_cmenu_on_key "$_key"
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi

        # Printable key while active: pass through to field, then re-filter
        # The caller's on_key will handle the character insertion.
        # We return 1 so the field processes it, then the caller should
        # call _shellframe_ac_update after the field processes the key.
        shellframe_ac_dismiss
        return 1
    fi

    # ── Idle: check triggers ─────────────────────────────────────────

    # Tab trigger mode
    if [[ "$SHELLFRAME_AC_TRIGGER" == "tab" && "$_key" == "$_k_tab" ]]; then
        _shellframe_ac_update
        # Single match: auto-complete immediately without popup
        if (( ! _SHELLFRAME_AC_ACTIVE && ${#_SHELLFRAME_AC_MATCHES[@]} == 1 )); then
            _shellframe_ac_accept "${_SHELLFRAME_AC_MATCHES[0]}"
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi
        # Multiple matches: popup is now active (set by _update)
        if (( _SHELLFRAME_AC_ACTIVE )); then
            shellframe_shell_mark_dirty 2>/dev/null || true
            return 0
        fi
        # No matches: pass Tab through
        return 1
    fi

    # Auto trigger: pass through (caller invokes ac_on_key_after)
    return 1
}

# ── shellframe_ac_on_key_after ───────────────────────────────────────────────
# Call AFTER the attached field/editor has processed a printable key in auto
# trigger mode.  Updates the match list based on the new prefix.

shellframe_ac_on_key_after() {
    [[ "$SHELLFRAME_AC_TRIGGER" != "auto" ]] && return
    [[ -z "$_SHELLFRAME_AC_CTX" ]] && return
    _shellframe_ac_update
    shellframe_shell_mark_dirty 2>/dev/null || true
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add src/widgets/autocomplete.sh tests/unit/test-autocomplete.sh
git commit -m "feat(autocomplete): add on_key with accept/dismiss/navigate/filter (shellframe#38)"
```

---

### Task 4: Render — popup positioning and display

**Files:**
- Modify: `src/widgets/autocomplete.sh`
- Modify: `tests/unit/test-autocomplete.sh`

Implement `shellframe_ac_render` which positions the popup below the cursor and delegates to `shellframe_cmenu_render`. Also add anchor positioning logic for both field and editor modes.

- [ ] **Step 1: Write failing tests for render**

Append to `tests/unit/test-autocomplete.sh` (before `ptyunit_test_summary`):

```bash
# ── render ───────────────────────────────────────────────────────────────────

ptyunit_test_begin "ac_render: inactive produces no framebuffer output"
shellframe_cur_init "rn1" "hello"
shellframe_ac_attach "rn1" "field"
_SHELLFRAME_AC_ACTIVE=0
_SF_ROW_PREV=()
shellframe_fb_frame_start 24 80
local _f
_f=$(mktemp "${TMPDIR:-/tmp}/sf-test-ac.XXXXXX")
exec 3>"$_f"
shellframe_ac_render 1 1 80 24 5 10
shellframe_screen_flush
exec 3>&- 2>/dev/null || true
local _content
_content=$(cat "$_f")
rm -f "$_f"
assert_eq "" "$_content" "no output when inactive"

ptyunit_test_begin "ac_render: active renders popup with matches"
shellframe_cur_init "rn2" "us"
shellframe_ac_attach "rn2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE" "popup active before render"
_SF_ROW_PREV=()
shellframe_fb_frame_start 24 80
_f=$(mktemp "${TMPDIR:-/tmp}/sf-test-ac.XXXXXX")
exec 3>"$_f"
shellframe_ac_render 1 1 80 24 5 10
shellframe_screen_flush
exec 3>&- 2>/dev/null || true
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_f")
rm -f "$_f"
assert_contains "$_content" "users" "first match in popup"
assert_contains "$_content" "user_roles" "second match in popup"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: FAIL — wrong argument count or missing function

- [ ] **Step 3: Implement shellframe_ac_render**

Add to `src/widgets/autocomplete.sh`:

```bash
# ── shellframe_ac_render ─────────────────────────────────────────────────────
# Render the autocomplete popup if active.
#   shellframe_ac_render top left width height cursor_row cursor_col
# top/left/width/height: bounding region (full screen area for clipping)
# cursor_row/cursor_col: screen position of the text cursor (anchor point)

shellframe_ac_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _cursor_row="${5:-1}" _cursor_col="${6:-1}"

    (( ! _SHELLFRAME_AC_ACTIVE )) && return

    local _n=${#_SHELLFRAME_AC_MATCHES[@]}
    (( _n == 0 )) && return

    # Anchor popup one row below cursor
    SHELLFRAME_CMENU_ANCHOR_ROW=$(( _cursor_row + 1 ))
    SHELLFRAME_CMENU_ANCHOR_COL="$_cursor_col"
    SHELLFRAME_CMENU_ITEMS=("${_SHELLFRAME_AC_MATCHES[@]}")
    SHELLFRAME_CMENU_CTX="ac_popup"
    SHELLFRAME_CMENU_FOCUSED=1
    SHELLFRAME_CMENU_STYLE="single"
    SHELLFRAME_CMENU_MAX_HEIGHT="${SHELLFRAME_AC_MAX_HEIGHT:-8}"
    SHELLFRAME_CMENU_BG=""

    shellframe_cmenu_render "$_top" "$_left" "$_width" "$_height"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PTYUNIT_HOME="$(brew --prefix ptyunit)/libexec" bash tests/unit/test-autocomplete.sh`
Expected: all pass

- [ ] **Step 5: Run full unit suite**

Run: `bash tests/run.sh --unit`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add src/widgets/autocomplete.sh tests/unit/test-autocomplete.sh
git commit -m "feat(autocomplete): add render with cursor-anchored popup positioning (shellframe#38)"
```

---

### Task 5: Example script and integration test

**Files:**
- Create: `examples/autocomplete.sh`
- Create: `tests/integration/test-autocomplete.sh`

- [ ] **Step 1: Create the example script**

Create `examples/autocomplete.sh`:

```bash
#!/usr/bin/env bash
# examples/autocomplete.sh — Autocomplete demo
#
# A single input field with Tab-triggered autocomplete.
# Type a few characters, press Tab to see suggestions.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
source "$SCRIPT_DIR/shellframe.sh"

# ── Provider: SQL keywords + table names ────────────────────────────────────

_demo_tables=("users" "user_roles" "products" "profiles" "orders" "order_items")

_demo_provider() {
    local _prefix="$1" _out="$2"
    local _matches=()
    local _i
    for _i in "${_demo_tables[@]}"; do
        case "$_i" in
            "${_prefix}"*) _matches+=("$_i") ;;
        esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

# ── App setup ───────────────────────────────────────────────────────────────

_ac_demo_field_ctx="demo_input"
_ac_demo_result=""

_ac_demo_init() {
    shellframe_field_init "$_ac_demo_field_ctx"
    SHELLFRAME_FIELD_CTX="$_ac_demo_field_ctx"
    SHELLFRAME_FIELD_PLACEHOLDER="Type a table name and press Tab..."
    SHELLFRAME_FIELD_FOCUSED=1

    SHELLFRAME_AC_PROVIDER="_demo_provider"
    SHELLFRAME_AC_TRIGGER="tab"
    shellframe_ac_attach "$_ac_demo_field_ctx" "field"
}

_ac_demo_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Header
    shellframe_fb_fill 1 1 "$_width" " " $'\033[44m'
    shellframe_fb_print 1 2 " Autocomplete Demo " $'\033[44m\033[97m'

    # Label
    shellframe_fb_print 3 2 "Table name:" ""

    # Input field
    local _field_left=14 _field_width=$(( _width - 16 ))
    SHELLFRAME_FIELD_CTX="$_ac_demo_field_ctx"
    shellframe_field_render 3 "$_field_left" "$_field_width" 1

    # Footer
    shellframe_fb_fill "$_height" 1 "$_width" " " $'\033[44m'
    shellframe_fb_print "$_height" 2 " Tab: complete | Enter: confirm | Esc: quit " $'\033[44m\033[97m'

    # Autocomplete popup (anchored below field cursor)
    local _cursor_col=$(( _field_left ))
    local _pos=0
    shellframe_cur_pos "$_ac_demo_field_ctx" _pos
    _cursor_col=$(( _field_left + _pos ))
    shellframe_ac_render 1 1 "$_width" "$_height" 3 "$_cursor_col"
}

_ac_demo_on_key() {
    local _key="$1"

    # Autocomplete intercepts first
    shellframe_ac_on_key "$_key"
    local _rc=$?
    if (( _rc == 0 )); then
        shellframe_shell_mark_dirty
        return 0
    fi

    # Esc when popup not active: quit
    if [[ "$_key" == $'\033' ]]; then
        return 2
    fi

    # Enter: confirm field value
    SHELLFRAME_FIELD_CTX="$_ac_demo_field_ctx"
    shellframe_field_on_key "$_key"
    _rc=$?

    # After field processes key, update autocomplete
    shellframe_ac_on_key_after

    if (( _rc == 2 )); then
        shellframe_cur_text "$_ac_demo_field_ctx" _ac_demo_result
        return 2
    fi
    return "$_rc"
}

# ── Run ─────────────────────────────────────────────────────────────────────

_ac_demo_init

shellframe_shell \
    _ac_demo_render \
    _ac_demo_on_key \
    "" ""

if [[ -n "$_ac_demo_result" ]]; then
    printf 'Selected: %s\n' "$_ac_demo_result"
fi
```

- [ ] **Step 2: Write integration tests**

Create `tests/integration/test-autocomplete.sh`:

```bash
#!/usr/bin/env bash
# tests/integration/test-autocomplete.sh — PTY integration tests for autocomplete

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$PTYUNIT_HOME/assert.sh"

_example="$SHELLFRAME_DIR/examples/autocomplete.sh"

# Tab-complete single match
ptyunit_test_begin "autocomplete: Tab completes single match 'prod' → 'products'"
_out=$(ptyunit_run "$_example" 0.3 \
    0.2 "prod" \
    0.1 $'\t' \
    0.1 $'\r' \
)
assert_contains "$_out" "products" "auto-completed to products"

# Tab with multiple matches shows popup, Down+Enter selects second
ptyunit_test_begin "autocomplete: Tab shows popup, navigate and accept"
_out=$(ptyunit_run "$_example" 0.3 \
    0.2 "us" \
    0.1 $'\t' \
    0.2 $'\033[B' \
    0.1 $'\r' \
)
assert_contains "$_out" "user_roles" "selected second match"

# Esc dismisses popup, then Esc quits
ptyunit_test_begin "autocomplete: Esc dismisses popup"
_out=$(ptyunit_run "$_example" 0.3 \
    0.2 "us" \
    0.1 $'\t' \
    0.1 $'\033' \
    0.2 $'\033' \
)
# Should exit without a "Selected:" line (popup dismissed, then quit)
assert_not_contains "$_out" "Selected:" "no selection after dismiss+quit"

ptyunit_test_summary
```

- [ ] **Step 3: Test the example manually**

Run: `bash examples/autocomplete.sh`
Verify: field renders, Tab shows popup, navigation works, Enter accepts.

- [ ] **Step 4: Run integration tests**

Run: `bash tests/run.sh --all`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add examples/autocomplete.sh tests/integration/test-autocomplete.sh
git commit -m "feat(autocomplete): add example and integration tests (shellframe#38)"
```

---

### Task 6: Documentation and cleanup

**Files:**
- Modify: `docs/showcase.md`
- Modify: `shellframe.sh` (verify source order)

- [ ] **Step 1: Add showcase entry**

Append to `docs/showcase.md` under the widgets section:

````markdown
### Autocomplete

Layers a filtered suggestion popup on any input field or editor.
Consumer provides a callback; shellframe handles the UI.

```
┌──────────────────────────────────────┐
│ Table name: us█                      │
│              ┌──────────────┐        │
│              │ users        │        │
│              │ user_roles   │        │
│              └──────────────┘        │
│                                      │
│  Tab: complete  Esc: dismiss         │
└──────────────────────────────────────┘
```

```bash
# Provider: return matches for prefix
_my_provider() {
    local _prefix="$1" _out="$2"
    local _items=("users" "user_roles" "products")
    local _matches=()
    for _i in "${_items[@]}"; do
        case "$_i" in "${_prefix}"*) _matches+=("$_i") ;; esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

# Attach to an input field
shellframe_field_init "myfield"
SHELLFRAME_AC_PROVIDER="_my_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_attach "myfield" "field"

# In your on_key handler:
shellframe_ac_on_key "$key" && return 0
# ... field processes key ...
shellframe_ac_on_key_after   # re-filter in auto mode
```
````

- [ ] **Step 2: Verify source order in shellframe.sh**

Confirm `autocomplete.sh` is sourced after `context-menu.sh` (its dependency). Read `shellframe.sh` and verify.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run.sh --unit`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add docs/showcase.md
git commit -m "docs(autocomplete): add showcase entry (shellframe#38)"
```

- [ ] **Step 5: Close the issue**

Run: `gh issue close 38 --repo fissible/shellframe --comment "Implemented: autocomplete layer with tab/auto trigger, provider callback, context-menu popup. Unit + integration tests + example + showcase."`
