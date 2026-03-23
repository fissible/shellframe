# Coverage Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise shellframe line coverage from 44% to ≥70% by refactoring legacy monolithic widgets to expose testable internals, adding tests for zero-coverage files, and filling branch gaps in low-coverage files.

**Architecture:** Three phases — (1) extract `_on_key` internals from confirm/action-list/alert and unit-test them; (2) add unit+integration tests for genuinely untested files (diff-view, app.sh, screen.sh, table); (3) add targeted tests for low-coverage files (panel, modal, shell, grid, tab-bar, text).

**Tech Stack:** bash 3.2+, ptyunit (assert.sh + pty_run.py), Python 3 (PTY integration tests)

---

## File Map

**Phase 1 — modified:**
- `src/widgets/confirm.sh` — add `SHELLFRAME_CONFIRM_SELECTED/RESULT` globals; extract `_shellframe_confirm_on_key()`
- `src/widgets/action-list.sh` — extract `_shellframe_action_list_on_key()`
- `src/widgets/alert.sh` — extract `_shellframe_alert_render()`

**Phase 1 — created:**
- `tests/unit/test-confirm.sh` — unit tests for `_shellframe_confirm_on_key`
- `tests/unit/test-action-list.sh` — unit tests for `_shellframe_action_list_on_key`
- `tests/unit/test-alert.sh` — unit tests for `_shellframe_alert_render` (render via fd 3 redirect)

**Phase 2 — created:**
- `tests/unit/test-diff-view.sh` — unit tests for diff-view init/on_key/on_focus
- `examples/diff-view.sh` — PTY fixture for diff-view render integration test
- `tests/integration/test-diff-view.sh` — PTY render test
- `tests/unit/test-app.sh` — unit tests for shellframe_app + _shellframe_app_event with mocks
- `tests/integration/test-screen.sh` — integration test for screen.sh enter/exit
- `tests/integration/test-table.sh` — PTY integration test for legacy table widget

**Phase 3 — modified:**
- `tests/unit/test-panel.sh` — add render branch tests
- `tests/unit/test-modal.sh` — add modal_init + render tests
- `tests/unit/test-shell.sh` — add focus edge-case + render tests
- `tests/unit/test-grid.sh` — add render + H-scroll edge-case tests
- `tests/unit/test-tab-bar.sh` — add render tests
- `tests/unit/test-text.sh` — add text_render tests

---

## How to verify after every task

```bash
bash tests/ptyunit/run.sh          # must stay 775+/775+ passes
bash tests/ptyunit/coverage.sh --src=src  # check total % trend upward
```

---

## Phase 1, Task 1 — Refactor confirm.sh: extract `_shellframe_confirm_on_key`

**Files:**
- Modify: `src/widgets/confirm.sh`

- [ ] **Step 1: Add globals and extract `_shellframe_confirm_on_key` above `shellframe_confirm()`**

Add after the header comment block, before `shellframe_confirm()`:

```bash
SHELLFRAME_CONFIRM_SELECTED=0   # 0 = Yes highlighted, 1 = No highlighted
SHELLFRAME_CONFIRM_RESULT=-1    # 0 = Yes, 1 = No (set by _on_key on exit)

# _shellframe_confirm_on_key key
# Handles one keypress. Mutates SHELLFRAME_CONFIRM_SELECTED and SHELLFRAME_CONFIRM_RESULT.
# Returns: 0 = selection changed (redraw needed)
#          1 = key not handled
#          2 = done (check SHELLFRAME_CONFIRM_RESULT: 0=yes, 1=no)
_shellframe_confirm_on_key() {
    local _key="$1"
    if   [[ "$_key" == "$SHELLFRAME_KEY_LEFT"  || "$_key" == 'h' || "$_key" == 'H' ]]; then
        SHELLFRAME_CONFIRM_SELECTED=0; return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == 'l' || "$_key" == 'L' ]]; then
        SHELLFRAME_CONFIRM_SELECTED=1; return 0
    elif [[ "$_key" == 'y' || "$_key" == 'Y' ]]; then
        SHELLFRAME_CONFIRM_RESULT=0; return 2
    elif [[ "$_key" == 'n' || "$_key" == 'N' ]]; then
        SHELLFRAME_CONFIRM_RESULT=1; return 2
    elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
        SHELLFRAME_CONFIRM_RESULT=$SHELLFRAME_CONFIRM_SELECTED; return 2
    elif [[ "$_key" == "$SHELLFRAME_KEY_ESC"   || "$_key" == 'q' || "$_key" == 'Q' ]]; then
        SHELLFRAME_CONFIRM_RESULT=1; return 2
    fi
    return 1
}
```

- [ ] **Step 2: Rewrite the input loop inside `shellframe_confirm()` to use `_shellframe_confirm_on_key`**

Replace the entire `while true; do ... done` loop (lines 201–223) with:

```bash
    # ── input loop ────────────────────────────────────────────────────────────
    SHELLFRAME_CONFIRM_SELECTED=0
    SHELLFRAME_CONFIRM_RESULT=-1
    while true; do
        local _key _krc
        shellframe_read_key _key
        _shellframe_confirm_on_key "$_key"
        _krc=$?
        if   (( _krc == 2 )); then
            _retval=$SHELLFRAME_CONFIRM_RESULT
            break
        elif (( _krc == 0 )); then
            _selected=$SHELLFRAME_CONFIRM_SELECTED
            _dirty=1
            _cf_draw
        fi
    done
```

- [ ] **Step 3: Verify the existing PTY integration test still passes**

```bash
bash tests/ptyunit/run.sh --integration 2>/dev/null | grep -A2 "test-confirm"
```
Expected: `test-confirm.sh ... OK (8/8)`

- [ ] **Step 4: Run full test suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `775/775 assertions passed`

---

## Phase 1, Task 2 — Unit tests for `_shellframe_confirm_on_key`

**Files:**
- Create: `tests/unit/test-confirm.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/unit/test-confirm.sh — Unit tests for _shellframe_confirm_on_key

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_reset_confirm() {
    SHELLFRAME_CONFIRM_SELECTED=0
    SHELLFRAME_CONFIRM_RESULT=-1
}

# ── Left / Right toggle ──────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Right arrow selects No"
_reset_confirm
_shellframe_confirm_on_key "$SHELLFRAME_KEY_RIGHT"
assert_eq "0" "$?" "returns 0 (redraw)"
assert_eq "1" "$SHELLFRAME_CONFIRM_SELECTED" "No selected"

ptyunit_test_begin "confirm_on_key: Left arrow selects Yes"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "$SHELLFRAME_KEY_LEFT"
assert_eq "0" "$?" "returns 0 (redraw)"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "Yes selected"

ptyunit_test_begin "confirm_on_key: h selects Yes"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "h"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "h → Yes"

ptyunit_test_begin "confirm_on_key: l selects No"
_reset_confirm
_shellframe_confirm_on_key "l"
assert_eq "1" "$SHELLFRAME_CONFIRM_SELECTED" "l → No"

# ── Quick-select keys ────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: y → RESULT=0, returns 2"
_reset_confirm
_shellframe_confirm_on_key "y"
assert_eq "2" "$?" "y returns 2 (done)"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=0 (Yes)"

ptyunit_test_begin "confirm_on_key: Y → RESULT=0, returns 2"
_reset_confirm
_shellframe_confirm_on_key "Y"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "Y → Yes"

ptyunit_test_begin "confirm_on_key: n → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "n"
assert_eq "2" "$?" "n returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=1 (No)"

ptyunit_test_begin "confirm_on_key: N → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "N"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "N → No"

# ── Enter confirms current selection ────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Enter confirms Yes (selected=0)"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=0
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ENTER"
assert_eq "2" "$?" "Enter returns 2"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=0 (Yes)"

ptyunit_test_begin "confirm_on_key: Enter confirms No (selected=1)"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ENTER"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=1 (No)"

ptyunit_test_begin "confirm_on_key: c confirms current selection"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "c"
assert_eq "2" "$?" "c returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "c → No"

# ── Cancel keys ─────────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Esc → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ESC"
assert_eq "2" "$?" "Esc returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "Esc → No"

ptyunit_test_begin "confirm_on_key: q → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "q"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "q → No"

ptyunit_test_begin "confirm_on_key: Q → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "Q"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "Q → No"

# ── Unhandled keys ───────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: unhandled key returns 1"
_reset_confirm
_shellframe_confirm_on_key "x"
assert_eq "1" "$?" "x returns 1 (unhandled)"

ptyunit_test_begin "confirm_on_key: unhandled key does not change selection"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=0
_shellframe_confirm_on_key "x"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "selection unchanged"

ptyunit_test_summary
```

- [ ] **Step 2: Run the new unit test in isolation**

```bash
bash tests/unit/test-confirm.sh 2>/dev/null
```
Expected: `OK  23/23 tests passed`

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `798/798 assertions passed`

- [ ] **Step 4: Commit**

```bash
git add src/widgets/confirm.sh tests/unit/test-confirm.sh
git commit -m "feat(confirm): extract _shellframe_confirm_on_key; add unit tests"
```

---

## Phase 1, Task 3 — Refactor action-list.sh: extract `_shellframe_action_list_on_key`

**Files:**
- Modify: `src/widgets/action-list.sh`

- [ ] **Step 1: Extract `_shellframe_action_list_on_key` above `shellframe_action_list()`**

Add before `SHELLFRAME_AL_SELECTED=0`:

```bash
# _shellframe_action_list_on_key key n_items
# Handles one keypress for the action-list widget.
# Reads/writes: SHELLFRAME_AL_SELECTED, SHELLFRAME_AL_ACTIONS[], SHELLFRAME_AL_IDX[]
# Returns: 0 = cursor/cycle changed (dirty=1)
#          1 = key not handled
#          2 = confirm (Enter/c)
#          3 = quit (q)
_shellframe_action_list_on_key() {
    local _key="$1" _n="$2"
    if   [[ "$_key" == "$SHELLFRAME_KEY_UP" ]]; then
        (( SHELLFRAME_AL_SELECTED > 0 )) && (( SHELLFRAME_AL_SELECTED-- )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN" ]]; then
        (( SHELLFRAME_AL_SELECTED < _n - 1 )) && (( SHELLFRAME_AL_SELECTED++ )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == "$SHELLFRAME_KEY_SPACE" ]]; then
        local -a _cur_acts
        IFS=' ' read -r -a _cur_acts <<< "${SHELLFRAME_AL_ACTIONS[$SHELLFRAME_AL_SELECTED]}"
        SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED]=$(( (SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED] + 1) % ${#_cur_acts[@]} ))
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
        return 2
    elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
        return 3
    fi
    return 1
}
```

- [ ] **Step 2: Rewrite the input loop inside `shellframe_action_list()` to use `_shellframe_action_list_on_key`**

Replace the `while true; do ... done` loop (lines 153–190) with:

```bash
    # ── Input loop ────────────────────────────────────────────────────────
    local _al_retval=1
    while true; do
        local _key _krc
        _prev_sel=$SHELLFRAME_AL_SELECTED
        shellframe_read_key _key

        _shellframe_action_list_on_key "$_key" "$_n"
        _krc=$?

        if (( _krc == 2 )); then
            _al_retval=0; break
        elif (( _krc == 3 )); then
            _al_retval=1; break
        elif (( _krc == 0 )); then
            _dirty=1
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _al_retval=1; break
            elif (( _xrc == 1 )); then
                continue
            fi
            _dirty=2
        else
            continue
        fi
        _al_draw
    done
```

- [ ] **Step 3: Verify PTY integration tests still pass**

```bash
bash tests/ptyunit/run.sh --integration 2>/dev/null | grep -A2 "test-action-list"
```
Expected: `test-action-list.sh ... OK (6/6)`

- [ ] **Step 4: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `798/798 assertions passed`

---

## Phase 1, Task 4 — Unit tests for `_shellframe_action_list_on_key`

**Files:**
- Create: `tests/unit/test-action-list.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/unit/test-action-list.sh — Unit tests for _shellframe_action_list_on_key

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_reset_al() {
    SHELLFRAME_AL_SELECTED=0
    SHELLFRAME_AL_LABELS=("apple" "banana" "cherry")
    SHELLFRAME_AL_ACTIONS=("eat skip" "eat peel skip" "eat skip")
    SHELLFRAME_AL_IDX=(0 0 0)
    SHELLFRAME_AL_META=("" "" "")
}

# ── Up / Down navigation ────────────────────────────────────────────────────

ptyunit_test_begin "al_on_key: Down moves cursor to next row"
_reset_al
_shellframe_action_list_on_key "$SHELLFRAME_KEY_DOWN" 3
assert_eq "0" "$?" "returns 0 (dirty)"
assert_eq "1" "$SHELLFRAME_AL_SELECTED" "cursor moved to 1"

ptyunit_test_begin "al_on_key: Down clamps at last row"
_reset_al
SHELLFRAME_AL_SELECTED=2
_shellframe_action_list_on_key "$SHELLFRAME_KEY_DOWN" 3
assert_eq "2" "$SHELLFRAME_AL_SELECTED" "clamped at 2"

ptyunit_test_begin "al_on_key: Up moves cursor to previous row"
_reset_al
SHELLFRAME_AL_SELECTED=2
_shellframe_action_list_on_key "$SHELLFRAME_KEY_UP" 3
assert_eq "1" "$SHELLFRAME_AL_SELECTED" "moved up to 1"

ptyunit_test_begin "al_on_key: Up clamps at row 0"
_reset_al
SHELLFRAME_AL_SELECTED=0
_shellframe_action_list_on_key "$SHELLFRAME_KEY_UP" 3
assert_eq "0" "$SHELLFRAME_AL_SELECTED" "clamped at 0"

# ── Action cycling ──────────────────────────────────────────────────────────

ptyunit_test_begin "al_on_key: Right cycles action for selected row"
_reset_al
SHELLFRAME_AL_SELECTED=1    # banana: eat peel skip
_shellframe_action_list_on_key "$SHELLFRAME_KEY_RIGHT" 3
assert_eq "0" "$?" "returns 0 (dirty)"
assert_eq "1" "${SHELLFRAME_AL_IDX[1]}" "banana idx cycled to 1 (peel)"

ptyunit_test_begin "al_on_key: Space cycles action for selected row"
_reset_al
SHELLFRAME_AL_SELECTED=0    # apple: eat skip
_shellframe_action_list_on_key "$SHELLFRAME_KEY_SPACE" 3
assert_eq "1" "${SHELLFRAME_AL_IDX[0]}" "apple idx cycled to 1 (skip)"

ptyunit_test_begin "al_on_key: Right wraps action cycle"
_reset_al
SHELLFRAME_AL_SELECTED=0    # apple: eat skip (2 actions)
SHELLFRAME_AL_IDX[0]=1      # currently on 'skip'
_shellframe_action_list_on_key "$SHELLFRAME_KEY_RIGHT" 3
assert_eq "0" "${SHELLFRAME_AL_IDX[0]}" "wrapped back to 0 (eat)"

# ── Confirm / Quit ──────────────────────────────────────────────────────────

ptyunit_test_begin "al_on_key: Enter returns 2 (confirm)"
_reset_al
_shellframe_action_list_on_key "$SHELLFRAME_KEY_ENTER" 3
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "al_on_key: c returns 2 (confirm)"
_reset_al
_shellframe_action_list_on_key "c" 3
assert_eq "2" "$?" "c returns 2"

ptyunit_test_begin "al_on_key: q returns 3 (quit)"
_reset_al
_shellframe_action_list_on_key "q" 3
assert_eq "3" "$?" "q returns 3"

ptyunit_test_begin "al_on_key: Q returns 3 (quit)"
_reset_al
_shellframe_action_list_on_key "Q" 3
assert_eq "3" "$?" "Q returns 3"

# ── Unhandled keys ───────────────────────────────────────────────────────────

ptyunit_test_begin "al_on_key: unhandled key returns 1"
_reset_al
_shellframe_action_list_on_key "x" 3
assert_eq "1" "$?" "x returns 1 (unhandled)"

ptyunit_test_begin "al_on_key: unhandled key does not change state"
_reset_al
SHELLFRAME_AL_SELECTED=1
_shellframe_action_list_on_key "z" 3
assert_eq "1" "$SHELLFRAME_AL_SELECTED" "cursor unchanged"

ptyunit_test_summary
```

- [ ] **Step 2: Run the new unit test in isolation**

```bash
bash tests/unit/test-action-list.sh 2>/dev/null
```
Expected: `OK  16/16 tests passed`

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `814/814 assertions passed`

- [ ] **Step 4: Commit**

```bash
git add src/widgets/action-list.sh tests/unit/test-action-list.sh
git commit -m "feat(action-list): extract _shellframe_action_list_on_key; add unit tests"
```

---

## Phase 1, Task 5 — Refactor alert.sh: extract `_shellframe_alert_render`

**Files:**
- Modify: `src/widgets/alert.sh`

- [ ] **Step 1: Extract `_shellframe_alert_render` above `shellframe_alert()`**

The render logic (layout computation + all `printf` drawing) moves into `_shellframe_alert_render`. It takes arguments for title and details. Writes to fd 3.

Add before `shellframe_alert()`:

```bash
# _shellframe_alert_render title n_details [detail ...]
# Renders the alert box to fd 3. Caller must have set fd 3 to a tty or capture fd.
# Reads SHELLFRAME_* color globals.
_shellframe_alert_render() {
    local _title="$1" _n_details="$2"
    shift 2
    local -a _details=("$@")

    local _cols _rows
    _cols=$(tput cols  2>/dev/null || printf '80')
    _rows=$(tput lines 2>/dev/null || printf '24')

    local _max_content=${#_title}
    local _line
    for _line in "${_details[@]+"${_details[@]}"}"; do
        (( ${#_line} > _max_content )) && _max_content=${#_line}
    done
    local _inner=$(( _max_content + 4 ))
    (( _inner < 32        )) && _inner=32
    (( _inner > _cols - 4 )) && _inner=$(( _cols - 4 ))
    (( _inner < 20        )) && _inner=20

    local _box_h=$(( 5 + _n_details ))
    (( _n_details > 0 )) && (( _box_h++ ))

    local _box_w=$(( _inner + 2 ))
    local _r0=$(( (_rows - _box_h - 1) / 2 ))
    local _c0=$(( (_cols - _box_w)     / 2 ))
    (( _r0 < 1 )) && _r0=1
    (( _c0 < 1 )) && _c0=1

    local _row="$_r0"
    local _i

    # top border
    printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY" >&3
    for (( _i=0; _i<_inner; _i++ )); do printf '-' >&3; done
    printf '+%b' "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # blank
    printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # title (centered, bold)
    local _tl="${#_title}"
    local _tlpad=$(( (_inner - _tl) / 2 ))
    local _trpad=$(( _inner - _tl - _tlpad ))
    printf '\033[%d;%dH%b|%b%*s%b%s%b%*s%b|%b' \
        "$_row" "$_c0" \
        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
        "$_tlpad" "" \
        "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_title" "$SHELLFRAME_RESET" \
        "$_trpad" "" \
        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # blank
    printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # detail lines
    if (( _n_details > 0 )); then
        for _line in "${_details[@]}"; do
            local _ll="${#_line}"
            local _rpad=$(( _inner - _ll - 2 ))
            (( _rpad < 0 )) && _rpad=0
            printf '\033[%d;%dH%b|%b  %s%*s%b|%b' \
                "$_row" "$_c0" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                "$_line" "$_rpad" "" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" >&3
            (( _row++ ))
        done
        printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
        (( _row++ ))
    fi

    # bottom border
    printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY" >&3
    for (( _i=0; _i<_inner; _i++ )); do printf '-' >&3; done
    printf '+%b' "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # footer hint
    local _hint="Any key to continue"
    local _hcol=$(( _c0 + (_box_w - ${#_hint}) / 2 ))
    (( _hcol < 1 )) && _hcol=1
    printf '\033[%d;%dH%b%s%b' "$_row" "$_hcol" "$SHELLFRAME_GRAY" "$_hint" "$SHELLFRAME_RESET" >&3
}
```

- [ ] **Step 2: Replace the inline draw code in `shellframe_alert()` with a call to `_shellframe_alert_render`**

Replace the block from `shellframe_screen_clear` through the `printf` footer hint (lines 69–129) with:

```bash
    shellframe_screen_clear
    _shellframe_alert_render "$_title" "$_n_details" "${_details[@]+"${_details[@]}"}"
```

- [ ] **Step 3: Verify PTY integration tests still pass**

```bash
bash tests/ptyunit/run.sh --integration 2>/dev/null | grep -A2 "test-alert"
```
Expected: `test-alert.sh ... OK (3/3)`

- [ ] **Step 4: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `814/814 assertions passed`

---

## Phase 1, Task 6 — Unit tests for `_shellframe_alert_render`

**Files:**
- Create: `tests/unit/test-alert.sh`

The strategy: open fd 3 to a temp file, call `_shellframe_alert_render`, strip ANSI from the output, assert on visible text content.

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/unit/test-alert.sh — Unit tests for _shellframe_alert_render

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# Render alert to a temp file, strip ANSI, return plain text
_render_alert() {
    local _title="$1" _n_details="$2"
    shift 2
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-alert.XXXXXX")
    exec 3>"$_out"
    _shellframe_alert_render "$_title" "$_n_details" "$@"
    exec 3>&-
    # Strip ANSI escape sequences
    sed 's/\033\[[0-9;]*m//g; s/\033\[[0-9;]*[A-Za-z]//g' "$_out"
    rm -f "$_out"
}

# ── Title rendering ──────────────────────────────────────────────────────────

ptyunit_test_begin "alert_render: title appears in output"
out=$(_render_alert "File saved" 0)
assert_contains "$out" "File saved"

ptyunit_test_begin "alert_render: footer hint appears"
out=$(_render_alert "Done" 0)
assert_contains "$out" "Any key to continue"

ptyunit_test_begin "alert_render: border chars present"
out=$(_render_alert "Done" 0)
assert_contains "$out" "+"
assert_contains "$out" "|"

# ── Detail lines ─────────────────────────────────────────────────────────────

ptyunit_test_begin "alert_render: single detail line appears"
out=$(_render_alert "Done" 1 "Changes applied successfully")
assert_contains "$out" "Changes applied successfully"

ptyunit_test_begin "alert_render: multiple detail lines appear"
out=$(_render_alert "Error" 2 "Connection failed" "Retry in 5 seconds")
assert_contains "$out" "Connection failed"
assert_contains "$out" "Retry in 5 seconds"

ptyunit_test_begin "alert_render: title still present with details"
out=$(_render_alert "Error" 1 "Something went wrong")
assert_contains "$out" "Error"

ptyunit_test_summary
```

- [ ] **Step 2: Run the new test in isolation**

```bash
bash tests/unit/test-alert.sh 2>/dev/null
```
Expected: `OK  8/8 tests passed` (8 assertions — border has 2, details has 2)

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `822/822 assertions passed`

- [ ] **Step 4: Commit**

```bash
git add src/widgets/alert.sh tests/unit/test-alert.sh
git commit -m "feat(alert): extract _shellframe_alert_render; add unit tests"
```

---

## Phase 2, Task 7 — Unit tests for diff-view

**Files:**
- Create: `tests/unit/test-diff-view.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/unit/test-diff-view.sh — Unit tests for src/widgets/diff-view.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_setup_diff() {
    # Minimal parsed diff: one context line, one add, one del
    SHELLFRAME_DIFF_TYPES=("ctx" "add" "del")
    SHELLFRAME_DIFF_LEFT=("unchanged" "" "removed line")
    SHELLFRAME_DIFF_RIGHT=("unchanged" "added line" "")
    SHELLFRAME_DIFF_LNUMS=("1" "" "3")
    SHELLFRAME_DIFF_RNUMS=("1" "2" "")
    SHELLFRAME_DIFF_ROW_COUNT=3
    SHELLFRAME_DIFF_FILE_ROWS=()
    SHELLFRAME_DIFF_FILE_STATUS=()
}

# ── shellframe_diff_view_init ────────────────────────────────────────────────

ptyunit_test_begin "diff_view_init: initialises scroll context dv_left"
_setup_diff
shellframe_diff_view_init
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "dv_left scroll top = 0"

ptyunit_test_begin "diff_view_init: initialises scroll context dv_right"
_setup_diff
shellframe_diff_view_init
_top=""
shellframe_scroll_top "dv_right" _top
assert_eq "0" "$_top" "dv_right scroll top = 0"

ptyunit_test_begin "diff_view_init: sync scroll context dv_sync locks dv_left/right"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_locked "dv_sync"
assert_eq "0" "$?" "dv_sync is locked (returns 0)"

# ── shellframe_diff_view_on_key ──────────────────────────────────────────────

ptyunit_test_begin "diff_view_on_key: Down scrolls dv_left down"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_DOWN"
assert_eq "0" "$?" "Down returns 0 (handled)"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "3" "$_top" "scrolled down by 3"

ptyunit_test_begin "diff_view_on_key: Up scrolls dv_left up"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
shellframe_diff_view_on_key "$SHELLFRAME_KEY_UP"
assert_eq "0" "$?" "Up returns 0 (handled)"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "scrolled back to top"

ptyunit_test_begin "diff_view_on_key: Home scrolls to top"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
shellframe_diff_view_on_key "$SHELLFRAME_KEY_HOME"
assert_eq "0" "$?" "Home returns 0"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "back at top"

ptyunit_test_begin "diff_view_on_key: Page Down handled"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_PAGE_DOWN"
assert_eq "0" "$?" "Page Down returns 0"

ptyunit_test_begin "diff_view_on_key: End handled"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_END"
assert_eq "0" "$?" "End returns 0"

ptyunit_test_begin "diff_view_on_key: unhandled key returns 1"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "x"
assert_eq "1" "$?" "x returns 1 (not handled)"

# ── shellframe_diff_view_on_focus ────────────────────────────────────────────

ptyunit_test_begin "diff_view_on_focus: sets FOCUSED=1"
SHELLFRAME_DIFF_VIEW_FOCUSED=0
shellframe_diff_view_on_focus 1
assert_eq "1" "$SHELLFRAME_DIFF_VIEW_FOCUSED" "FOCUSED=1"

ptyunit_test_begin "diff_view_on_focus: sets FOCUSED=0"
SHELLFRAME_DIFF_VIEW_FOCUSED=1
shellframe_diff_view_on_focus 0
assert_eq "0" "$SHELLFRAME_DIFF_VIEW_FOCUSED" "FOCUSED=0"

ptyunit_test_summary
```

- [ ] **Step 2: Run the new test in isolation**

```bash
bash tests/unit/test-diff-view.sh 2>/dev/null
```
Expected: `OK  14/14 tests passed`

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `836/836 assertions passed`

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-diff-view.sh
git commit -m "test(diff-view): add unit tests for init, on_key, on_focus"
```

---

## Phase 2, Task 8 — PTY integration test for diff-view render

**Files:**
- Create: `examples/diff-view.sh`
- Create: `tests/integration/test-diff-view.sh`

- [ ] **Step 1: Write the fixture script `examples/diff-view.sh`**

```bash
#!/usr/bin/env bash
# examples/diff-view.sh — Minimal diff-view fixture for integration tests

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

# Build a minimal diff
shellframe_diff_parse_string \
    "--- a/foo.sh
+++ b/foo.sh
@@ -1,3 +1,3 @@
 context line
-old line
+new line
 another context"

shellframe_diff_view_init

SHELLFRAME_DIFF_VIEW_LEFT_FOOTER="a/foo.sh"
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER="b/foo.sh"

# Render once to a fake alternate screen (use tput to get dimensions)
exec 3>/dev/tty
shellframe_screen_enter
shellframe_screen_clear
shellframe_diff_view_render 1 1 "$(tput cols)" "$(( $(tput lines) - 1 ))"

# Wait for a keypress then exit
shellframe_raw_enter
_k=""
shellframe_read_key _k
shellframe_raw_exit "$(shellframe_raw_save)"
shellframe_screen_exit
printf 'diff-view rendered\n'
```

- [ ] **Step 2: Write the integration test `tests/integration/test-diff-view.sh`**

```bash
#!/usr/bin/env bash
# tests/integration/test-diff-view.sh — PTY test for diff-view render

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/diff-view.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "diff-view: renders without error — exit sentinel present"
out=$(_pty ENTER)
assert_contains "$out" "diff-view rendered"

ptyunit_test_begin "diff-view: left footer visible"
out=$(_pty ENTER)
assert_contains "$out" "a/foo.sh"

ptyunit_test_begin "diff-view: right footer visible"
out=$(_pty ENTER)
assert_contains "$out" "b/foo.sh"

ptyunit_test_summary
```

- [ ] **Step 3: Run the integration test in isolation**

```bash
bash tests/integration/test-diff-view.sh 2>/dev/null
```
Expected: `OK  3/3 tests passed`

- [ ] **Step 4: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `839/839 assertions passed`

- [ ] **Step 5: Commit**

```bash
git add examples/diff-view.sh tests/integration/test-diff-view.sh
git commit -m "test(diff-view): add PTY integration test for render path"
```

---

## Phase 2, Task 9 — Unit tests for app.sh

**Files:**
- Create: `tests/unit/test-app.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/unit/test-app.sh — Unit tests for shellframe_app + _shellframe_app_event

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── _shellframe_app_event ────────────────────────────────────────────────────

ptyunit_test_begin "app_event: action-list rc=0 → confirm"
assert_output "confirm" _shellframe_app_event "action-list" 0

ptyunit_test_begin "app_event: action-list rc=1 → quit"
assert_output "quit" _shellframe_app_event "action-list" 1

ptyunit_test_begin "app_event: table rc=0 → confirm"
assert_output "confirm" _shellframe_app_event "table" 0

ptyunit_test_begin "app_event: table rc=1 → quit"
assert_output "quit" _shellframe_app_event "table" 1

ptyunit_test_begin "app_event: confirm rc=0 → yes"
assert_output "yes" _shellframe_app_event "confirm" 0

ptyunit_test_begin "app_event: confirm rc=1 → no"
assert_output "no" _shellframe_app_event "confirm" 1

ptyunit_test_begin "app_event: alert rc=0 → dismiss"
assert_output "dismiss" _shellframe_app_event "alert" 0

ptyunit_test_begin "app_event: alert rc=1 → dismiss (any rc)"
assert_output "dismiss" _shellframe_app_event "alert" 1

# ── shellframe_app event loop ────────────────────────────────────────────────
# Mock all four widget functions so no TTY is needed.

ptyunit_test_begin "shellframe_app: alert screen → dismiss → quit"
ptyunit_mock shellframe_alert --exit 0
ptyunit_mock shellframe_action_list --exit 0
ptyunit_mock shellframe_confirm --exit 0
ptyunit_mock shellframe_table --exit 0

_app_ROOT_type()    { printf 'alert'; }
_app_ROOT_render()  { _SHELLFRAME_APP_TITLE="Hello"; }
_app_ROOT_dismiss() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app" "ROOT"
assert_called "shellframe_alert"
assert_called_with "shellframe_alert" "Hello"

ptyunit_test_begin "shellframe_app: confirm yes → next screen → quit"
ptyunit_mock shellframe_alert --exit 0
ptyunit_mock shellframe_confirm --exit 0   # rc=0 → yes

_app2_ROOT_type()    { printf 'confirm'; }
_app2_ROOT_render()  { _SHELLFRAME_APP_QUESTION="Apply?"; }
_app2_ROOT_yes()     { _SHELLFRAME_APP_NEXT="DONE"; }
_app2_ROOT_no()      { _SHELLFRAME_APP_NEXT="__QUIT__"; }

_app2_DONE_type()    { printf 'alert'; }
_app2_DONE_render()  { _SHELLFRAME_APP_TITLE="Done"; }
_app2_DONE_dismiss() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app2" "ROOT"
assert_called "shellframe_confirm"
assert_called "shellframe_alert"

ptyunit_test_begin "shellframe_app: confirm no → quit"
ptyunit_mock shellframe_confirm --exit 1   # rc=1 → no

_app3_ROOT_type()    { printf 'confirm'; }
_app3_ROOT_render()  { _SHELLFRAME_APP_QUESTION="Proceed?"; }
_app3_ROOT_yes()     { _SHELLFRAME_APP_NEXT="DONE"; }
_app3_ROOT_no()      { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app3" "ROOT"
assert_called_times "shellframe_confirm" 1
assert_not_called "shellframe_alert"

ptyunit_test_summary
```

- [ ] **Step 2: Run the test in isolation**

```bash
bash tests/unit/test-app.sh 2>/dev/null
```
Expected: `OK  14/14 tests passed`

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```
Expected: `853/853 assertions passed`

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-app.sh
git commit -m "test(app): add unit tests for shellframe_app and _shellframe_app_event"
```

---

## Phase 2, Task 10 — Integration test for screen.sh

**Files:**
- Create: `tests/integration/test-screen.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/integration/test-screen.sh — Integration tests for src/screen.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"

source "$TESTS_DIR/ptyunit/assert.sh"

# Fixture: a minimal script that enters/exits raw mode and the alternate screen
_FIXTURE=$(mktemp "${TMPDIR:-/tmp}/sf-test-screen.XXXXXX.sh")
cat > "$_FIXTURE" << 'FIXTURE'
#!/usr/bin/env bash
set -u
source "$(dirname "$0")/shellframe.sh" 2>/dev/null || \
    source "SHELLFRAME_DIR/shellframe.sh"
exec 3>/dev/tty
shellframe_screen_enter
shellframe_cursor_hide
shellframe_raw_enter
printf '\033[1;1HScreen entered\n' >&3
saved=$(shellframe_raw_save)
shellframe_raw_exit "$saved"
shellframe_cursor_show
shellframe_screen_exit
printf 'screen-test-done\n'
FIXTURE
sed -i.bak "s|SHELLFRAME_DIR|$SHELLFRAME_DIR|g" "$_FIXTURE" && rm -f "$_FIXTURE.bak"

_pty() { python3 "$PTY_RUN" "$_FIXTURE" "$@" 2>/dev/null; }

ptyunit_test_begin "screen: enter/exit completes without error"
out=$(_pty)
assert_contains "$out" "screen-test-done"

ptyunit_test_begin "screen: raw_save/enter/exit roundtrip succeeds"
out=$(_pty)
assert_contains "$out" "screen-test-done"

rm -f "$_FIXTURE"

ptyunit_test_summary
```

- [ ] **Step 2: Run in isolation**

```bash
bash tests/integration/test-screen.sh 2>/dev/null
```
Expected: `OK  2/2 tests passed`

- [ ] **Step 3: Run full suite**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test-screen.sh
git commit -m "test(screen): add integration test for enter/exit/raw roundtrip"
```

---

## Phase 2, Task 11 — PTY integration test for legacy table widget

**Files:**
- Create: `tests/integration/test-table.sh`

- [ ] **Step 1: Check if `examples/table.sh` exists and works**

```bash
python3 tests/ptyunit/pty_run.py examples/table.sh ENTER 2>/dev/null | head -5
```

If it exits cleanly, proceed. If not, fix the fixture first.

- [ ] **Step 2: Write the test file**

```bash
#!/usr/bin/env bash
# tests/integration/test-table.sh — PTY tests for examples/table.sh (legacy table widget)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/table.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "table: renders without crash — confirm on Enter"
out=$(_pty ENTER)
assert_contains "$out" "Selected: "

ptyunit_test_begin "table: q quits"
out=$(_pty q)
assert_contains "$out" "Aborted."

ptyunit_test_summary
```

- [ ] **Step 3: Run in isolation**

```bash
bash tests/integration/test-table.sh 2>/dev/null
```
Expected: `OK  2/2 tests passed`

- [ ] **Step 5: Commit**

```bash
git add tests/integration/test-table.sh
git commit -m "test(table): add PTY integration test for legacy table widget"
```

---

## Phase 3, Task 12 — Branch coverage for panel.sh

**Files:**
- Modify: `tests/unit/test-panel.sh`

- [ ] **Step 1: Run coverage to identify uncovered lines**

```bash
bash tests/ptyunit/coverage.sh --src=src --report=html 2>/dev/null
open coverage/index.html   # navigate to panel.sh
```

- [ ] **Step 2: Add unit tests for uncovered branches in `shellframe_panel_inner` and `shellframe_panel_size`**

Key gaps to look for: border style variations (double, rounded, none), title alignment (left, center, right), focused vs unfocused state. Add to `tests/unit/test-panel.sh`.

Pattern for each missing branch:

```bash
ptyunit_test_begin "panel_inner: rounded border style"
SHELLFRAME_PANEL_STYLE="rounded"
shellframe_panel_inner 1 1 20 10 _pt _pl _pw _ph
assert_eq "2" "$_pt" "top adjusted for border"
```

Read `src/panel.sh` to identify all branches and add one test per uncovered case.

- [ ] **Step 3: For `shellframe_panel_render`: add a unit test using fd 3 redirect**

```bash
ptyunit_test_begin "panel_render: double border writes output"
_out=$(mktemp)
exec 3>"$_out"
SHELLFRAME_PANEL_STYLE="double"
shellframe_panel_render 1 1 20 5
exec 3>&-
content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$content" "╔"
rm -f "$_out"
```

- [ ] **Step 4: Run tests**

```bash
bash tests/unit/test-panel.sh 2>/dev/null
```

- [ ] **Step 5: Run full suite and check coverage improvement**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
bash tests/ptyunit/coverage.sh --src=src 2>/dev/null | grep "panel"
```

- [ ] **Step 6: Commit**

```bash
git add tests/unit/test-panel.sh
git commit -m "test(panel): add branch coverage for render and border styles"
```

---

## Phase 3, Task 13 — Branch coverage for modal.sh

**Files:**
- Modify: `tests/unit/test-modal.sh`

- [ ] **Step 1: Identify uncovered lines in modal.sh via HTML report**

Key gaps: `shellframe_modal_init` (never called in tests), `shellframe_modal_render`.

- [ ] **Step 2: Add tests for `shellframe_modal_init`**

`shellframe_modal_init` accepts only an optional context name (defaults to `modal_input`) and calls `shellframe_field_init`. Set globals directly before calling render:

```bash
ptyunit_test_begin "modal_init: returns 0 with no args"
shellframe_modal_init
assert_eq "0" "$?" "modal_init returns 0"

ptyunit_test_begin "modal_init: accepts custom context name"
shellframe_modal_init "my_modal"
assert_eq "0" "$?" "modal_init with custom ctx returns 0"
```

Read `src/widgets/modal.sh` to check for any additional branches in `shellframe_modal_init`, then add one test per branch.

- [ ] **Step 3: Add `shellframe_modal_render` unit test with fd 3 redirect**

```bash
ptyunit_test_begin "modal_render: output contains message text"
SHELLFRAME_MODAL_MESSAGE="Delete file?"
SHELLFRAME_MODAL_BUTTONS=("OK" "Cancel")
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_init
_out=$(mktemp)
exec 3>"$_out"
shellframe_modal_render 5 10 40 10
exec 3>&-
content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$content" "Delete file?"
rm -f "$_out"
```

- [ ] **Step 4: Run tests, check coverage, commit**

```bash
bash tests/unit/test-modal.sh 2>/dev/null
bash tests/ptyunit/coverage.sh --src=src 2>/dev/null | grep "modal"
git add tests/unit/test-modal.sh
git commit -m "test(modal): add modal_init and render coverage"
```

---

## Phase 3, Task 14 — Branch coverage for shell.sh

**Files:**
- Modify: `tests/unit/test-shell.sh`

- [ ] **Step 1: Identify uncovered lines via HTML report**

Key gaps: Tab/Shift-Tab focus cycle with `on_key` consumption (the `shellframe_shell` on_key-before-cycle path added in the March 17 session), multi-region edge cases.

- [ ] **Step 2: Add unit tests for focus edge cases**

```bash
ptyunit_test_begin "shell_focus: Shift-Tab retreats focus"
_reset_shell
shellframe_shell_region a 1 1 80 10 focus
shellframe_shell_region b 11 1 80 10 focus
_shellframe_shell_focus_init
_SHELLFRAME_SHELL_FOCUS_IDX=1
_shellframe_shell_focus_prev
assert_eq "0" "$_SHELLFRAME_SHELL_FOCUS_IDX" "focus retreated to first region"
```

Read `src/shell.sh` and `tests/unit/test-shell.sh` to understand existing tests, then add targeted cases for uncovered branches identified in the HTML report.

- [ ] **Step 3: Add render test with fd 3 redirect (for `_shellframe_shell_draw` if present)**

If shell.sh has a render function, use the same fd 3 redirect pattern.

- [ ] **Step 4: Run tests, check coverage, commit**

```bash
bash tests/unit/test-shell.sh 2>/dev/null
bash tests/ptyunit/coverage.sh --src=src 2>/dev/null | grep "shell.sh"
git add tests/unit/test-shell.sh
git commit -m "test(shell): add branch coverage for focus-cycle edge cases"
```

---

## Phase 3, Task 15 — Branch coverage for grid.sh

**Files:**
- Modify: `tests/unit/test-grid.sh`

- [ ] **Step 1: Identify uncovered lines via HTML report**

Key gaps: `shellframe_grid_render` (render path), H-scroll edge cases (Left key when at column 0, Right key when at last column).

- [ ] **Step 2: Add H-scroll edge-case unit tests**

Read `src/widgets/grid.sh` and existing `tests/unit/test-grid.sh` to understand current coverage, then add:
- Left key at first column (clamped)
- Right key past last column (clamped)
- Multiselect toggle (Space key) if not already covered

- [ ] **Step 3: Add render test with fd 3 redirect**

```bash
ptyunit_test_begin "grid_render: renders without error"
shellframe_grid_init "gtest" 3
SHELLFRAME_GRID_DATA=("a" "b" "c" "d" "e" "f")
shellframe_sel_init "gtest" 2
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 30 5 "gtest"
exec 3>&-
content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$content" "a"
rm -f "$_out"
```

- [ ] **Step 4: Run tests, check coverage, commit**

```bash
bash tests/unit/test-grid.sh 2>/dev/null
bash tests/ptyunit/coverage.sh --src=src 2>/dev/null | grep "grid"
git add tests/unit/test-grid.sh
git commit -m "test(grid): add render and H-scroll edge-case coverage"
```

---

## Phase 3, Task 16 — Branch coverage for tab-bar.sh, text.sh

**Files:**
- Modify: `tests/unit/test-tab-bar.sh`
- Modify: `tests/unit/test-text.sh`

- [ ] **Step 1: Check HTML coverage report for both files, identify uncovered branches**

- [ ] **Step 2: Add render test for tab-bar with fd 3 redirect**

```bash
ptyunit_test_begin "tabbar_render: renders tab labels"
shellframe_tabbar_init "tb" "Home" "Schema" "Query"
_out=$(mktemp)
exec 3>"$_out"
shellframe_tabbar_render 1 1 60 1 "tb"
exec 3>&-
content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$content" "Home"
assert_contains "$content" "Schema"
rm -f "$_out"
```

- [ ] **Step 3: Add `shellframe_text_render` test**

```bash
ptyunit_test_begin "text_render: renders text to fd 3"
_out=$(mktemp)
exec 3>"$_out"
shellframe_text_render 1 1 40 5 "Hello world" "left" "top"
exec 3>&-
content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$content" "Hello world"
rm -f "$_out"
```

- [ ] **Step 4: Run tests, check coverage, commit**

```bash
bash tests/unit/test-tab-bar.sh 2>/dev/null
bash tests/unit/test-text.sh 2>/dev/null
bash tests/ptyunit/coverage.sh --src=src 2>/dev/null | grep -E "tab-bar|text.sh"
git add tests/unit/test-tab-bar.sh tests/unit/test-text.sh
git commit -m "test(tab-bar, text): add render coverage"
```

---

## Final Task — Coverage check and memory update

- [ ] **Step 1: Run final coverage report**

```bash
bash tests/ptyunit/coverage.sh --src=src --report=html 2>/dev/null
```

- [ ] **Step 2: Verify ≥70% total coverage**

Check the TOTAL line at the bottom of the text report.

- [ ] **Step 3: Run full test suite — confirm all pass**

```bash
bash tests/ptyunit/run.sh 2>/dev/null | tail -3
```

- [ ] **Step 4: Update the submodule ref in shellframe's parent commit**

```bash
git add tests/ptyunit
git commit -m "chore: bump ptyunit submodule to include coverage tooling"
```

- [ ] **Step 5: Update coverage_report.md in Claude memory with new numbers**

File: `/Users/allenmccabe/.claude/projects/-Users-allenmccabe-lib-fissible-shellframe/memory/coverage_report.md`

Update the Generated date, method note, and all table values to reflect the final run.
