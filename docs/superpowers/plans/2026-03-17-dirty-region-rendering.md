# Dirty-Region Rendering Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate per-keypress flicker in `action-list`, `table`, and `confirm` widgets by introducing a two-level dirty flag that skips `shellframe_screen_clear` on cursor movement and button toggles.

**Architecture:** Each widget's event loop gets a `local _dirty` integer (2=full, 1=partial, 0=none). On cursor movement (`_dirty=1`), the draw function skips `shellframe_screen_clear` and overwrites only the changed rows using absolute ANSI cursor positioning + `\033[2K`. Full redraws (`_dirty=2`) still call `shellframe_screen_clear`. Render functions continue to write to `/dev/tty`; no API changes.

**Tech Stack:** bash 3.2+, ANSI/VT100 terminal sequences, Python 3 PTY test harness (`tests/ptyunit/pty_run.py`).

**Spec:** `docs/superpowers/specs/2026-03-17-dirty-region-rendering-design.md`

---

## Task 0: Create GitHub issue and feature branch

**Files:** none

- [ ] **Step 1: Create GitHub issue**

```bash
gh issue create \
  --title "[Phase 7B] Dirty-region rendering: widget dirty flags + conditional re-render" \
  --body "$(cat <<'EOF'
## Summary

Implement Stage 1 dirty-region rendering as described in the roadmap comment in \`src/screen.sh\`.

Each in-scope widget (\`action-list\`, \`table\`, \`confirm\`) gains a \`local _dirty\` integer (2=full, 1=partial, 0=none). On cursor movement or button toggle, the widget skips \`shellframe_screen_clear\` and rewrites only the changed rows in-place using absolute ANSI positioning + \`\\033[2K\`. Full redraws still call \`shellframe_screen_clear\` on first draw, resize, and data change.

## Acceptance criteria

- No visible flicker on ↑/↓ cursor movement in \`action-list\` and \`table\`
- No visible flicker on ←/→ button toggle in \`confirm\`
- \`shellframe_screen_clear\` still fires on first draw, terminal resize, and data change
- All existing integration tests continue to pass
- Docker matrix (bash 3.2, 4.4, 5.2) passes

## Spec

\`docs/superpowers/specs/2026-03-17-dirty-region-rendering-design.md\`

## Out of scope

Stage 2 (full per-cell framebuffer diff) — this is its prerequisite.
EOF
)"
```

Expected: Issue URL printed. Note the issue number (e.g. `#42`).

- [ ] **Step 2: Create and check out feature branch**

```bash
git checkout -b feat/dirty-region-rendering
```

Expected: `Switched to a new branch 'feat/dirty-region-rendering'`

---

## Task 1: Add PTY_RAW=1 mode to pty_run.py

Dirty-region tests need to inspect raw ANSI sequences (specifically check for presence/absence of `\033[H\033[3J\033[2J`). The current `pty_run.py` strips all ANSI sequences. Add `PTY_RAW=1` env var support that skips stripping.

**Files:**
- Modify: `tests/ptyunit/pty_run.py:185-192`

- [ ] **Step 1: Write the failing test** (verify the env var is not yet supported)

```bash
# manual check — PTY_RAW=1 should currently produce same (stripped) output as normal mode
PTY_RAW=1 python3 tests/ptyunit/pty_run.py tests/ptyunit/examples/menu.sh ENTER 2>/dev/null | cat -v | grep -c 'ESC' || true
```

Expected: `0` (ANSI is stripped — PTY_RAW is not yet implemented)

- [ ] **Step 2: Add PTY_RAW support**

Follow the existing pattern: parse the env var in `main()` and forward it as an explicit keyword argument to `run()`. All other env-var options (`PTY_COLS`, `PTY_ROWS`, etc.) use this same pattern.

**2a. Add `raw_mode` parameter to `run()`:**

Change the `run()` signature from:

```python
def run(
    script: str,
    keys: list,
    *,
    key_delay: float = 0.15,
    init_delay: float = 0.30,
    timeout: float = 10.0,
    cols: int = 80,
    rows: int = 24,
) -> tuple:
```

to:

```python
def run(
    script: str,
    keys: list,
    *,
    key_delay: float = 0.15,
    init_delay: float = 0.30,
    timeout: float = 10.0,
    cols: int = 80,
    rows: int = 24,
    raw_mode: bool = False,
) -> tuple:
```

**2b. Replace the strip/return block inside `run()` (around line 189):**

Change:

```python
    stripped = ANSI_RE.sub(b"", output)
    stripped = stripped.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

    return stripped.decode("utf-8", errors="replace"), exit_code
```

to:

```python
    if raw_mode:
        result = output.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    else:
        result = ANSI_RE.sub(b"", output)
        result = result.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

    return result.decode("utf-8", errors="replace"), exit_code
```

**2c. Parse `PTY_RAW` in `main()` and pass it to `run()`:**

In `main()`, after the existing env-var parsing block:

```python
    cols   = int(os.environ.get("PTY_COLS",    80))
    rows   = int(os.environ.get("PTY_ROWS",    24))
    delay  = float(os.environ.get("PTY_DELAY", 0.15))
    init   = float(os.environ.get("PTY_INIT",  0.30))
    tmt    = float(os.environ.get("PTY_TIMEOUT", 10))
```

Add one more line:

```python
    raw    = os.environ.get("PTY_RAW", "0") == "1"
```

Then change the `run()` call from:

```python
    out, rc = run(script, keys, key_delay=delay, init_delay=init,
                  timeout=tmt, cols=cols, rows=rows)
```

to:

```python
    out, rc = run(script, keys, key_delay=delay, init_delay=init,
                  timeout=tmt, cols=cols, rows=rows, raw_mode=raw)
```

**2d. Update the module docstring to document the env var:**

Find:
```
Options (set via env vars):
    PTY_COLS=80     terminal width  (default: 80)
    PTY_ROWS=24     terminal height (default: 24)
    PTY_DELAY=0.15  seconds between keys (default: 0.15)
    PTY_INIT=0.30   seconds to wait before first key (default: 0.30)
    PTY_TIMEOUT=10  seconds to wait for process exit (default: 10)
```

Change to:
```
Options (set via env vars):
    PTY_COLS=80     terminal width  (default: 80)
    PTY_ROWS=24     terminal height (default: 24)
    PTY_DELAY=0.15  seconds between keys (default: 0.15)
    PTY_INIT=0.30   seconds to wait before first key (default: 0.30)
    PTY_TIMEOUT=10  seconds to wait for process exit (default: 10)
    PTY_RAW=0       set to 1 to skip ANSI stripping (raw output including escape sequences)
```

- [ ] **Step 3: Verify PTY_RAW=1 now produces raw output**

```bash
PTY_RAW=1 python3 tests/ptyunit/pty_run.py tests/ptyunit/examples/menu.sh ENTER 2>/dev/null | cat -v | grep -c '\^[' || true
```

Expected: a number greater than 0 (ANSI sequences now present in output)

---

## Task 2: Add assert_count to assert.sh

**Files:**
- Modify: `tests/ptyunit/assert.sh` (after `assert_not_contains`, before `ptyunit_test_summary`)

- [ ] **Step 1: Add assert_count function**

```bash
# Assert a string contains exactly N occurrences of a substring.
assert_count() {
    local haystack="$1" needle="$2" expected="$3" msg="${4:-}"
    local count=0 remaining="$haystack"
    while [[ "$remaining" == *"$needle"* ]]; do
        remaining="${remaining#*"$needle"}"
        (( count++ ))
    done
    assert_eq "$expected" "$count" "${msg:-occurrence count of substring}"
}
```

- [ ] **Step 2: Run existing assert unit tests to confirm nothing broken**

```bash
bash tests/ptyunit/self-tests/unit/test-assert.sh
```

Expected: `OK  N/N tests passed`

---

## Task 3: Create examples/table.sh fixture

The dirty-region tests for `table` need a fixture script that sources shellframe and runs `shellframe_table`. No such example currently exists.

**Files:**
- Create: `examples/table.sh`

- [ ] **Step 1: Create the fixture**

```bash
#!/usr/bin/env bash
# examples/table.sh — Table widget demo (used by integration tests)
#
# Renders a navigable table of fruits. ENTER confirms selection; q quits.
# Prints "Selected: <label>" or "Aborted." to stdout on exit.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

SHELLFRAME_TBL_LABELS=("apple" "banana" "cherry" "date" "elderberry")
SHELLFRAME_TBL_ACTIONS=("nothing" "nothing" "nothing" "nothing" "nothing")
SHELLFRAME_TBL_IDX=(0 0 0 0 0)
SHELLFRAME_TBL_META=("" "" "" "" "")
SHELLFRAME_TBL_SCROLL=0
SHELLFRAME_TBL_SELECTED=0

shellframe_table "" "" "↑/↓ move  Enter confirm  q quit"
_result=$?

if (( _result == 0 )); then
    printf 'Selected: %s\n' "${SHELLFRAME_TBL_LABELS[$SHELLFRAME_TBL_SELECTED]}"
else
    printf 'Aborted.\n'
fi
```

- [ ] **Step 2: Smoke-test the fixture is wired up correctly (functional test)**

```bash
python3 tests/ptyunit/pty_run.py examples/table.sh ENTER 2>/dev/null
```

Expected output contains `Selected: apple`

```bash
python3 tests/ptyunit/pty_run.py examples/table.sh DOWN ENTER 2>/dev/null
```

Expected output contains `Selected: banana`

```bash
python3 tests/ptyunit/pty_run.py examples/table.sh q 2>/dev/null
```

Expected output contains `Aborted.`

---

## Task 4: Commit test infrastructure

- [ ] **Step 1: Commit**

```bash
git add tests/ptyunit/pty_run.py tests/ptyunit/assert.sh examples/table.sh
git commit -m "$(cat <<'EOF'
test: add PTY_RAW mode, assert_count, and table fixture for dirty-region tests

- pty_run.py: PTY_RAW=1 env var skips ANSI stripping for sequence inspection
- assert.sh: assert_count counts substring occurrences
- examples/table.sh: minimal table fixture sourcing shellframe

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Write failing dirty-region tests

All three widgets tested in one file. Tests must FAIL before the implementation.

**Files:**
- Create: `tests/integration/test-dirty-region.sh`

The sentinel for a full redraw is the complete `shellframe_screen_clear` sequence: `\033[H\033[3J\033[2J`.

On entry into any widget, this sequence appears **exactly twice**: once from `shellframe_screen_enter` and once from the first draw. After the fix, navigation keys must not add more occurrences.

The `_al_raw`, `_tbl_raw`, and `_cf_raw` helper wrappers are defined inline at the top of each widget's test section inside `test-dirty-region.sh` — they are not defined elsewhere. No separate file is needed.

- [ ] **Step 1: Create the test file**

```bash
#!/usr/bin/env bash
# tests/integration/test-dirty-region.sh
# Verify that navigation events skip shellframe_screen_clear (dirty=1 partial draw).
#
# Strategy: capture raw ANSI output (PTY_RAW=1), count occurrences of the
# screen-clear sequence \033[H\033[3J\033[2J.
#
# Expected counts:
#   Initial render only (no navigation): 2 (screen_enter + first _draw call)
#   After navigation keys:               still 2 (no additional screen_clear)
#
# These tests FAIL before the dirty-rendering implementation and PASS after.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"

source "$TESTS_DIR/ptyunit/assert.sh"

_SCREEN_CLEAR=$'\033[H\033[3J\033[2J'

# ── action-list ───────────────────────────────────────────────────────────────

SCRIPT_AL="$SHELLFRAME_DIR/examples/action-list.sh"
_al_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_AL" "$@" 2>/dev/null; }
_al()     {            python3 "$PTY_RUN" "$SCRIPT_AL" "$@" 2>/dev/null; }

ptyunit_test_begin "action-list dirty: baseline — 2 screen_clears on initial render"
out=$(_al_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after DOWN"
out=$(_al_raw DOWN ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after multiple DOWN/UP"
out=$(_al_raw DOWN DOWN UP ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after action cycle (Space)"
out=$(_al_raw SPACE ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: partial update targets old cursor row (row 1;1)"
out=$(_al_raw DOWN q)
# After DOWN, item 0 (row 1) must be redrawn (deselected) and item 1 (row 2) selected.
# Partial draw uses printf '\033[%d;1H\033[2K' — check for \033[2K which does NOT appear
# in the sequential full draw (action-list draws rows with \n, not absolute positioning).
assert_contains "$out" $'\033[1;1H\033[2K'
assert_contains "$out" $'\033[2;1H\033[2K'

ptyunit_test_begin "action-list dirty: behavior unchanged — DOWN then ENTER selects banana"
out=$(_al DOWN ENTER)
assert_contains "$out" "banana"

# ── table ─────────────────────────────────────────────────────────────────────

SCRIPT_TBL="$SHELLFRAME_DIR/examples/table.sh"
_tbl_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_TBL" "$@" 2>/dev/null; }
_tbl()     {            python3 "$PTY_RUN" "$SCRIPT_TBL" "$@" 2>/dev/null; }

ptyunit_test_begin "table dirty: baseline — 2 screen_clears on initial render"
out=$(_tbl_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: no extra screen_clear after DOWN"
out=$(_tbl_raw DOWN ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: no extra screen_clear after multiple DOWN/UP"
out=$(_tbl_raw DOWN DOWN UP ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: partial update targets correct rows after DOWN"
out=$(_tbl_raw DOWN q)
# In examples/table.sh there is no page chrome and no column headers, so:
#   _content_top=1, _first_data_row=1
# After DOWN: old cursor = row 0 (terminal row 1), new cursor = row 1 (terminal row 2).
# Full draw  : all rows written once → row1=1, row2=1, row3=1 occurrence(s)
# Partial draw: only old+new cursor rows redrawn → row1+2 each get +1
# Total expected: row1=2, row2=2, row3=1 (untouched by partial draw)
assert_count "$out" $'\033[1;1H\033[2K' 2   # old cursor row: full draw + partial
assert_count "$out" $'\033[2;1H\033[2K' 2   # new cursor row: full draw + partial
assert_count "$out" $'\033[3;1H\033[2K' 1   # untouched row: full draw only

ptyunit_test_begin "table dirty: behavior unchanged — DOWN then ENTER selects banana"
out=$(_tbl DOWN ENTER)
assert_contains "$out" "banana"

# ── confirm ───────────────────────────────────────────────────────────────────

SCRIPT_CF="$SHELLFRAME_DIR/examples/confirm.sh"
_cf_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_CF" "$@" 2>/dev/null; }
_cf()     {            python3 "$PTY_RUN" "$SCRIPT_CF" "$@" 2>/dev/null; }

ptyunit_test_begin "confirm dirty: baseline — 2 screen_clears on initial render"
out=$(_cf_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: no extra screen_clear after RIGHT button toggle"
out=$(_cf_raw RIGHT ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: no extra screen_clear after RIGHT then LEFT"
out=$(_cf_raw RIGHT LEFT ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: behavior unchanged — RIGHT then ENTER cancels"
out=$(_cf RIGHT ENTER)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm dirty: behavior unchanged — ENTER confirms"
out=$(_cf ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_summary
```

- [ ] **Step 2: Run tests — verify the NEW dirty-region tests FAIL**

```bash
bash tests/integration/test-dirty-region.sh
```

Expected: Several FAIL lines for the `assert_count` tests (counts will be 3+, not 2). The behavior tests (`behavior unchanged`) and baseline tests (`initial render`) should PASS. Example:
```
FAIL [action-list dirty: no extra screen_clear after DOWN]
  expected: 2
  actual:   3
```

The baseline test (`ENTER` with no navigation) may also pass since no extra screen_clears occur with no navigation keys. If it fails, check the count manually.

- [ ] **Step 3: Verify existing tests still pass (no regressions introduced by test infrastructure)**

```bash
bash tests/ptyunit/run.sh
bash tests/integration/test-action-list.sh
bash tests/integration/test-confirm.sh
```

Expected: `OK  N/N tests passed` for each. If any existing test breaks here, fix it before proceeding — the test infrastructure (PTY_RAW mode, assert_count) must be additive only.

- [ ] **Step 4: Commit failing tests**

```bash
git add tests/integration/test-dirty-region.sh
git commit -m "$(cat <<'EOF'
test: add failing dirty-region rendering tests for action-list, table, confirm

Tests assert screen_clear count == 2 (screen_enter + first draw only) after
navigation keys. All navigation tests currently FAIL — they will pass once
the dirty-flag implementation lands.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Implement action-list dirty rendering

**Files:**
- Modify: `src/widgets/action-list.sh`

The changes are entirely inside `shellframe_action_list()`. No public API changes.

- [ ] **Step 1: Add dirty state locals and resize-tracking locals**

After line 53 (`local _n=${#SHELLFRAME_AL_LABELS[@]}`), add:

```bash
    local _dirty=2       # 2=full  1=partial(cursor rows only)  0=none
    local _prev_sel=0    # cursor position before this key event
    local _prev_rows=0 _prev_cols=0   # for resize detection
```

- [ ] **Step 2: Rewrite `_al_draw` to branch on `_dirty`**

Replace the entire `_al_draw()` function body (lines 95–110) with:

```bash
    _al_draw() {
        # Resize detection: if terminal size changed, escalate to full redraw
        local _cur_rows=24 _cur_cols=80
        { read -r _cur_rows _cur_cols; } < <(stty size </dev/tty 2>/dev/null) || true
        if (( _cur_rows != _prev_rows || _cur_cols != _prev_cols )); then
            _dirty=2
            _prev_rows=$_cur_rows
            _prev_cols=$_cur_cols
        fi

        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear
            local _dai
            for (( _dai=0; _dai<_n; _dai++ )); do
                local _dlabel="${SHELLFRAME_AL_LABELS[$_dai]}"
                local _dacts_str="${SHELLFRAME_AL_ACTIONS[$_dai]}"
                local _daidx="${SHELLFRAME_AL_IDX[$_dai]}"
                local _dmeta="${SHELLFRAME_AL_META[$_dai]:-}"
                if [[ -n "$_draw_row_fn" ]]; then
                    "$_draw_row_fn" "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                else
                    _al_default_draw_row "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                fi
            done
            printf "\n  ${SHELLFRAME_GRAY}%s${SHELLFRAME_RESET}\n" "$_footer"
        else
            # ── Partial redraw (_dirty=1): overwrite old and new cursor rows ──
            # Terminal row = item index + 1 (items start at row 1, no scroll offset).
            # For action cycle (Right/Space), _prev_sel == SHELLFRAME_AL_SELECTED;
            # the loop still works — it redraws the same row twice (idempotent).
            local _dr
            for _dr in "$_prev_sel" "$SHELLFRAME_AL_SELECTED"; do
                printf '\033[%d;1H\033[2K' "$(( _dr + 1 ))"
                local _dlabel="${SHELLFRAME_AL_LABELS[$_dr]}"
                local _dacts_str="${SHELLFRAME_AL_ACTIONS[$_dr]}"
                local _daidx="${SHELLFRAME_AL_IDX[$_dr]}"
                local _dmeta="${SHELLFRAME_AL_META[$_dr]:-}"
                if [[ -n "$_draw_row_fn" ]]; then
                    "$_draw_row_fn" "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                else
                    _al_default_draw_row "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                fi
            done
        fi

        _dirty=0
    }
```

- [ ] **Step 3: Update the input loop to snapshot `_prev_sel` and set `_dirty`**

Replace the entire input loop (lines 113–147) with:

```bash
    # ── Input loop ────────────────────────────────────────────────────────────
    local _al_retval=1
    while true; do
        local _key
        _prev_sel=$SHELLFRAME_AL_SELECTED   # snapshot before key handling
        shellframe_read_key _key

        if   [[ "$_key" == "$SHELLFRAME_KEY_UP" ]]; then
            (( SHELLFRAME_AL_SELECTED > 0 )) && (( SHELLFRAME_AL_SELECTED-- )) || true
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN" ]]; then
            (( SHELLFRAME_AL_SELECTED < _n - 1 )) && (( SHELLFRAME_AL_SELECTED++ )) || true
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == "$SHELLFRAME_KEY_SPACE" ]]; then
            local -a _cur_acts
            IFS=' ' read -r -a _cur_acts <<< "${SHELLFRAME_AL_ACTIONS[$SHELLFRAME_AL_SELECTED]}"
            SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED]=$(( (SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED] + 1) % ${#_cur_acts[@]} ))
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
            _al_retval=0
            break
        elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
            _al_retval=1
            break
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _al_retval=1; break
            elif (( _xrc == 1 )); then
                continue   # not handled — skip redraw
            fi
            _dirty=2   # _xrc == 0: handled — conservative full redraw (caller may have
                       # re-entered via shellframe_screen_enter after a sub-TUI)
        else
            continue  # unrecognized key — skip redraw
        fi

        _al_draw
    done
```

- [ ] **Step 4: Run action-list dirty tests**

```bash
bash tests/integration/test-dirty-region.sh 2>&1 | grep -E '(action-list|OK|FAIL)'
```

Expected: all `action-list dirty:` tests pass.

- [ ] **Step 5: Run existing action-list integration tests (regression)**

```bash
bash tests/integration/test-action-list.sh
```

Expected: `OK  N/N tests passed`

- [ ] **Step 6: Commit**

```bash
git add src/widgets/action-list.sh
git commit -m "$(cat <<'EOF'
feat(action-list): dirty-region rendering — skip screen_clear on cursor movement

Add local _dirty integer (2=full, 1=partial, 0=none) to shellframe_action_list.
Cursor up/down and action cycle (Right/Space) set _dirty=1; the draw function
skips shellframe_screen_clear and overwrites only the old and new cursor rows
using absolute ANSI positioning + \033[2K. Full redraws still fire on entry,
terminal resize, and when the extra_key_fn signals a handled event.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Implement table dirty rendering

This is the most complex widget. The key challenge is that layout variables (`_content_top`, `_first_data_row`, `_visible_rows`, panel geometry) are computed inside `_tbl_draw` as locals but must persist between draw calls for the partial-draw path. We use outer-scope `local` declarations in `shellframe_table` that `_tbl_draw` assigns to without `local`, leveraging bash dynamic scoping.

**Files:**
- Modify: `src/widgets/table.sh`

- [ ] **Step 1: Add dirty state locals and layout cache to `shellframe_table`**

After line 95 (`local _n=${#SHELLFRAME_TBL_LABELS[@]}`), add:

```bash
    local _dirty=2       # 2=full  1=partial  0=none
    local _prev_sel=0    # cursor position before this key event
    local _prev_rows=0 _prev_cols=0   # for resize detection

    # Layout cache — set by full draw, read by partial draw.
    # These are declared here with 'local' in shellframe_table's scope.
    # _tbl_draw assigns to them WITHOUT 'local', so the assignments propagate
    # back to shellframe_table via bash dynamic scoping (inner function reads/
    # writes the enclosing function's local variables).
    #
    # Mapping to existing _tbl_draw variable names:
    #   _tbl_ct  ← _content_top       (first row of the content area)
    #   _tbl_fdr ← _first_data_row    (first data row, after headers)
    #   _tbl_vr  ← _visible_rows      (number of visible data rows in viewport)
    #   _tbl_sp  ← _show_panel        (1 if side panel is active)
    #   _tbl_pl  ← _panel_left        (panel start column)
    #   _tbl_pw  ← _panel_width       (panel column count)
    #   _tbl_ch  ← _content_height    (rows from _content_top to _content_bottom)
    local _tbl_ct=1
    local _tbl_fdr=1
    local _tbl_vr=1
    local _tbl_sp=0
    local _tbl_pl=0
    local _tbl_pw=0
    local _tbl_ch=0
```

- [ ] **Step 2: Rewrite `_tbl_draw` to branch on `_dirty`**

Replace the entire `_tbl_draw()` function body (lines 132–301) with the following. The full-draw path is identical to today except: (a) the `shellframe_screen_clear` is now guarded by `_dirty == 2`, and (b) layout cache variables are saved before the full draw returns.

```bash
    _tbl_draw() {
        # ── Terminal size and resize check ────────────────────────────────
        local _rows=24 _cols=80
        { read -r _rows _cols; } < <(stty size </dev/tty 2>/dev/null) || true
        SHELLFRAME_TBL_COLS=$_cols

        if (( _rows != _prev_rows || _cols != _prev_cols )); then
            _dirty=2
            _prev_rows=$_rows
            _prev_cols=$_cols
        fi

        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 1 )); then
            # ── Partial redraw: scroll-boundary check ─────────────────────
            # We must NOT modify SHELLFRAME_TBL_SCROLL here (the actual
            # clamping only happens inside the full-draw path below).
            #
            # Strategy: simulate what the clamping would produce into a local
            # _new_scroll, starting from the current SHELLFRAME_TBL_SCROLL
            # (the "snapshot before"). Compare _new_scroll to the original
            # SHELLFRAME_TBL_SCROLL ("check after"). If they differ, the
            # viewport would shift — escalate to _dirty=2 so the full-draw
            # path can apply the actual clamp and repaint the whole viewport.
            local _new_scroll=$SHELLFRAME_TBL_SCROLL   # snapshot before clamping
            if (( SHELLFRAME_TBL_SELECTED < _new_scroll )); then
                _new_scroll=$SHELLFRAME_TBL_SELECTED
            fi
            if (( SHELLFRAME_TBL_SELECTED >= _new_scroll + _tbl_vr )); then
                _new_scroll=$(( SHELLFRAME_TBL_SELECTED - _tbl_vr + 1 ))
            fi
            # compare simulated post-clamp value to the snapshot
            if (( _new_scroll != SHELLFRAME_TBL_SCROLL )); then
                _dirty=2   # viewport shift — need full redraw
            fi
        fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear

            # ── Page chrome: top ──────────────────────────────────────────
            local _content_top=1
            local _fi
            if [[ -n "$SHELLFRAME_TBL_PAGE_TITLE" || -n "$SHELLFRAME_TBL_PAGE_H1" ]]; then
                printf '\033[1;1H%b%b %s\033[K%b' \
                    "$SHELLFRAME_REVERSE" "$SHELLFRAME_BOLD" \
                    "$SHELLFRAME_TBL_PAGE_TITLE" \
                    "$SHELLFRAME_RESET"
                printf '\033[2;1H%b %s%b' \
                    "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" \
                    "$SHELLFRAME_TBL_PAGE_H1" \
                    "$SHELLFRAME_RESET"
                printf '\033[3;1H%b' "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_cols; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                _content_top=4
            fi

            # ── Page chrome: bottom ───────────────────────────────────────
            local _content_bottom=$_rows
            if [[ -n "$SHELLFRAME_TBL_PAGE_FOOTER" ]]; then
                printf '\033[%d;1H%b' "$(( _rows - 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_cols; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                printf '\033[%d;1H%b %s\033[K%b' \
                    "$_rows" \
                    "$SHELLFRAME_GRAY" \
                    "$SHELLFRAME_TBL_PAGE_FOOTER" \
                    "$SHELLFRAME_RESET"
                _content_bottom=$(( _rows - 2 ))
            fi

            local _content_height=$(( _content_bottom - _content_top + 1 ))

            # ── Table width and optional panel layout ─────────────────────
            local _table_width=$_cols
            local _show_panel=0
            local _panel_left=0 _panel_width=0

            if [[ -n "$SHELLFRAME_TBL_PANEL_FN" ]]; then
                local _tbl_min_w=2
                local _cwi
                for _cwi in "${SHELLFRAME_TBL_COL_WIDTHS[@]+"${SHELLFRAME_TBL_COL_WIDTHS[@]}"}"; do
                    _tbl_min_w=$(( _tbl_min_w + _cwi ))
                done
                local _half=$(( _cols / 2 ))
                (( _half < _tbl_min_w )) && _half=$_tbl_min_w
                if (( _half + 1 + 20 <= _cols )); then
                    _table_width=$_half
                    _panel_left=$(( _table_width + 2 ))
                    _panel_width=$(( _cols - _table_width - 1 ))
                    _show_panel=1
                fi
            fi

            # ── Table column headers ───────────────────────────────────────
            local _n_headers=${#SHELLFRAME_TBL_HEADERS[@]}
            local _table_header_rows=0
            if (( _n_headers > 0 )); then
                _table_header_rows=2
                printf '\033[%d;1H  ' "$_content_top"
                local _hi
                for (( _hi=0; _hi<_n_headers; _hi++ )); do
                    local _hdr="${SHELLFRAME_TBL_HEADERS[$_hi]}"
                    local _hw="${SHELLFRAME_TBL_COL_WIDTHS[$_hi]:-${#_hdr}}"
                    printf '%b%-*s%b' \
                        "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_hw" "$_hdr" \
                        "$SHELLFRAME_RESET"
                done
                printf '\033[%d;1H  %b' "$(( _content_top + 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_table_width-2; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
            fi

            # ── Data rows ─────────────────────────────────────────────────
            local _first_data_row=$(( _content_top + _table_header_rows ))
            local _below_rows=${SHELLFRAME_TBL_BELOW_ROWS:-0}
            local _below_total=0
            (( _below_rows > 0 )) && _below_total=$(( _below_rows + 1 )) || true
            local _hint_row=$(( _content_bottom - _below_total ))
            local _visible_rows=$(( _hint_row - _first_data_row ))
            (( _visible_rows < 1 )) && _visible_rows=1

            # Scroll adjustment
            if (( SHELLFRAME_TBL_SELECTED < SHELLFRAME_TBL_SCROLL )); then
                SHELLFRAME_TBL_SCROLL=$SHELLFRAME_TBL_SELECTED
            fi
            if (( SHELLFRAME_TBL_SELECTED >= SHELLFRAME_TBL_SCROLL + _visible_rows )); then
                SHELLFRAME_TBL_SCROLL=$(( SHELLFRAME_TBL_SELECTED - _visible_rows + 1 ))
            fi

            local _dai
            for (( _dai=0; _dai<_visible_rows; _dai++ )); do
                local _ridx=$(( SHELLFRAME_TBL_SCROLL + _dai ))
                local _drow=$(( _first_data_row + _dai ))
                printf '\033[%d;1H\033[2K' "$_drow"
                if (( _ridx < _n )); then
                    local _dlabel="${SHELLFRAME_TBL_LABELS[$_ridx]}"
                    local _dacts_str="${SHELLFRAME_TBL_ACTIONS[$_ridx]}"
                    local _daidx="${SHELLFRAME_TBL_IDX[$_ridx]}"
                    local _dmeta="${SHELLFRAME_TBL_META[$_ridx]:-}"
                    if [[ -n "$_draw_row_fn" ]]; then
                        "$_draw_row_fn" "$_ridx" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    else
                        _tbl_default_draw_row "$_ridx" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    fi
                fi
            done

            printf '\033[%d;1H\033[2K  %b%s%b' \
                "$_hint_row" \
                "$SHELLFRAME_GRAY" "$_footer" "$SHELLFRAME_RESET"

            if (( _show_panel )); then
                local _sep_row
                for (( _sep_row=_content_top; _sep_row<=_content_bottom; _sep_row++ )); do
                    printf '\033[%d;%dH%b│%b' \
                        "$_sep_row" "$(( _table_width + 1 ))" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
                done
                "$SHELLFRAME_TBL_PANEL_FN" \
                    "$_content_top" "$_panel_left" "$_panel_width" \
                    "$_content_height"
            fi

            if (( _below_total > 0 )) && [[ -n "$SHELLFRAME_TBL_BELOW_FN" ]]; then
                printf '\033[%d;1H\033[2K  %b' "$(( _hint_row + 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_table_width-2; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                "$SHELLFRAME_TBL_BELOW_FN" \
                    "$(( _hint_row + 2 ))" 1 "$_cols" "$_below_rows"
            fi

            # Save layout cache for partial draws (assigned without 'local' —
            # updates shellframe_table's outer-scope locals via dynamic scoping)
            _tbl_ct=$_content_top
            _tbl_fdr=$_first_data_row
            _tbl_vr=$_visible_rows
            _tbl_sp=$_show_panel
            _tbl_pl=$_panel_left
            _tbl_pw=$_panel_width
            _tbl_ch=$_content_height

        else
            # ── Partial redraw (_dirty=1) ─────────────────────────────────
            # Overwrite old and new cursor rows using cached layout.
            # Terminal row = _tbl_fdr + (item_index - SHELLFRAME_TBL_SCROLL)
            local _dr
            for _dr in "$_prev_sel" "$SHELLFRAME_TBL_SELECTED"; do
                local _term_row=$(( _tbl_fdr + _dr - SHELLFRAME_TBL_SCROLL ))
                printf '\033[%d;1H\033[2K' "$_term_row"
                if (( _dr < _n )); then
                    local _dlabel="${SHELLFRAME_TBL_LABELS[$_dr]}"
                    local _dacts_str="${SHELLFRAME_TBL_ACTIONS[$_dr]}"
                    local _daidx="${SHELLFRAME_TBL_IDX[$_dr]}"
                    local _dmeta="${SHELLFRAME_TBL_META[$_dr]:-}"
                    if [[ -n "$_draw_row_fn" ]]; then
                        "$_draw_row_fn" "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    else
                        _tbl_default_draw_row "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    fi
                fi
            done

            # Panel repaints on every cursor movement (selection change drives content)
            # but does NOT clear the whole screen first.
            if (( _tbl_sp )); then
                "$SHELLFRAME_TBL_PANEL_FN" "$_tbl_ct" "$_tbl_pl" "$_tbl_pw" "$_tbl_ch"
            fi
        fi

        _dirty=0
    }
```

- [ ] **Step 3: Update the table input loop to snapshot `_prev_sel` and set `_dirty`**

Replace the input loop (lines that were 304–338) with:

```bash
    # ── Input loop ────────────────────────────────────────────────────────────
    local _tbl_retval=1
    while true; do
        local _key
        _prev_sel=$SHELLFRAME_TBL_SELECTED   # snapshot before key handling
        shellframe_read_key _key

        if   [[ "$_key" == "$SHELLFRAME_KEY_UP" ]]; then
            (( SHELLFRAME_TBL_SELECTED > 0 )) && (( SHELLFRAME_TBL_SELECTED-- )) || true
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN" ]]; then
            (( SHELLFRAME_TBL_SELECTED < _n - 1 )) && (( SHELLFRAME_TBL_SELECTED++ )) || true
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == "$SHELLFRAME_KEY_SPACE" ]]; then
            local -a _cur_acts
            IFS=' ' read -r -a _cur_acts <<< "${SHELLFRAME_TBL_ACTIONS[$SHELLFRAME_TBL_SELECTED]}"
            SHELLFRAME_TBL_IDX[$SHELLFRAME_TBL_SELECTED]=$(( (SHELLFRAME_TBL_IDX[$SHELLFRAME_TBL_SELECTED] + 1) % ${#_cur_acts[@]} ))
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
            _tbl_retval=0
            break
        elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
            _tbl_retval=1
            break
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _tbl_retval=1; break
            elif (( _xrc == 1 )); then
                continue   # not handled — skip redraw
            fi
            _dirty=2   # _xrc == 0: handled — conservative full redraw
        else
            continue  # unrecognized key — skip redraw
        fi

        _tbl_draw
    done
```

- [ ] **Step 4: Run table dirty tests**

```bash
bash tests/integration/test-dirty-region.sh 2>&1 | grep -E '(table dirty|OK|FAIL)'
```

Expected: all `table dirty:` tests pass.

- [ ] **Step 5: Run existing tests and confirm all dirty-region tests still pass**

```bash
bash tests/integration/test-dirty-region.sh
bash tests/integration/test-action-list.sh
bash tests/integration/test-confirm.sh
```

Expected: all pass. The `test-dirty-region.sh` run confirms the action-list dirty tests were not broken by the table changes.

- [ ] **Step 6: Commit**

```bash
git add src/widgets/table.sh
git commit -m "$(cat <<'EOF'
feat(table): dirty-region rendering — skip screen_clear on cursor movement

Add local _dirty integer and layout cache (_tbl_ct/_tbl_fdr/_tbl_vr etc.) to
shellframe_table. Cursor up/down and action cycle set _dirty=1; the partial
draw path rewrites only the old and new cursor rows (and the panel if shown)
without calling shellframe_screen_clear. Scroll-boundary check inside the draw
function escalates _dirty=1 to _dirty=2 when the viewport shifts.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Implement confirm dirty rendering

**Files:**
- Modify: `src/widgets/confirm.sh`

- [ ] **Step 1: Add dirty state local and pre-compute `_btn_row`**

After the layout block (after line 81, `(( _c0 < 1 )) && _c0=1`), add:

```bash
    # Pre-compute button row for partial draw.
    # Derivation: top border(+0) blank(+1) details(+n) [blank-sep(+1 if n>0)]
    #             question(+1) blank(+1) buttons → constant = 4
    local _btn_row=$(( _r0 + 4 + _n_details ))
    (( _n_details > 0 )) && (( _btn_row++ )) || true

    local _dirty=2   # 2=full  1=partial(button row only)  0=none
```

- [ ] **Step 2: Rewrite `_cf_draw` to branch on `_dirty`**

Replace the entire `_cf_draw()` body (lines 84–169) with:

```bash
    _cf_draw() {
        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear

            local _row="$_r0"
            local _i

            # top border
            printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY"
            for (( _i=0; _i<_inner; _i++ )); do printf '-'; done
            printf '+%b' "$SHELLFRAME_RESET"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # detail lines
            local _line
            if (( _n_details > 0 )); then
                for _line in "${_details[@]}"; do
                    local _ll="${#_line}"
                    local _rpad=$(( _inner - _ll - 2 ))
                    (( _rpad < 0 )) && _rpad=0
                    printf '\033[%d;%dH%b|%b  %s%*s%b|%b' \
                        "$_row" "$_c0" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                        "$_line" "$_rpad" "" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
                    (( _row++ ))
                done
                # blank separator
                printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
                (( _row++ ))
            fi

            # question (centered, bold)
            local _ql="${#_question}"
            local _qlpad=$(( (_inner - _ql) / 2 ))
            local _qrpad=$(( _inner - _ql - _qlpad ))
            printf '\033[%d;%dH%b|%b%*s%b%s%b%*s%b|%b' \
                "$_row" "$_c0" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                "$_qlpad" "" \
                "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_question" "$SHELLFRAME_RESET" \
                "$_qrpad" "" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # buttons (row == _btn_row)
            _cf_draw_buttons "$_row"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # bottom border
            printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY"
            for (( _i=0; _i<_inner; _i++ )); do printf '-'; done
            printf '+%b' "$SHELLFRAME_RESET"
            (( _row++ ))

            # footer hint
            local _hint="←/→ select   y/n quick   Enter confirm"
            local _hcol=$(( _c0 + (_box_w - ${#_hint}) / 2 ))
            (( _hcol < 1 )) && _hcol=1
            printf '\033[%d;%dH%b%s%b' "$_row" "$_hcol" "$SHELLFRAME_GRAY" "$_hint" "$SHELLFRAME_RESET"

        else
            # ── Partial redraw (_dirty=1): button row only ─────────────────
            _cf_draw_buttons "$_btn_row"
        fi

        _dirty=0
    }
```

- [ ] **Step 3: Extract button renderer helper `_cf_draw_buttons`**

Add this function BEFORE `_cf_draw` (after the layout block):

```bash
    # Render the button row at absolute terminal row $1.
    _cf_draw_buttons() {
        local _brow="$1"
        local _yes_str _no_str
        if (( _selected == 0 )); then
            _yes_str="${SHELLFRAME_BOLD}${SHELLFRAME_WHITE}[ Yes ]${SHELLFRAME_RESET}"
            _no_str="${SHELLFRAME_GRAY}[ No  ]${SHELLFRAME_RESET}"
        else
            _yes_str="${SHELLFRAME_GRAY}[ Yes ]${SHELLFRAME_RESET}"
            _no_str="${SHELLFRAME_BOLD}${SHELLFRAME_WHITE}[ No  ]${SHELLFRAME_RESET}"
        fi
        local _btn_raw=20
        local _blpad=$(( (_inner - _btn_raw) / 2 ))
        local _brpad=$(( _inner - _btn_raw - _blpad ))
        (( _blpad < 1 )) && _blpad=1
        (( _brpad < 0 )) && _brpad=0
        printf '\033[%d;%dH%b|%b' "$_brow" "$_c0" "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
        printf '%*s%b      %b%*s' "$_blpad" "" "$_yes_str" "$_no_str" "$_brpad" ""
        printf '%b|%b' "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
    }
```

- [ ] **Step 4: Update the confirm input loop to set `_dirty`**

In the input loop (lines 173–193), replace the branch for left/right with `_dirty=1` set:

```bash
    while true; do
        local _key
        shellframe_read_key _key

        if   [[ "$_key" == "$SHELLFRAME_KEY_LEFT"  || "$_key" == 'h' || "$_key" == 'H' ]]; then
            _selected=0
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == 'l' || "$_key" == 'L' ]]; then
            _selected=1
            _dirty=1
        elif [[ "$_key" == 'y' || "$_key" == 'Y' ]]; then
            _retval=0; break
        elif [[ "$_key" == 'n' || "$_key" == 'N' ]]; then
            _retval=1; break
        elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
            _retval=$_selected; break
        elif [[ "$_key" == "$SHELLFRAME_KEY_ESC"   || "$_key" == 'q' || "$_key" == 'Q' ]]; then
            _retval=1; break
        else
            continue
        fi
        _cf_draw
    done
```

- [ ] **Step 5: Run confirm dirty tests**

```bash
bash tests/integration/test-dirty-region.sh 2>&1 | grep -E '(confirm dirty|OK|FAIL)'
```

Expected: all `confirm dirty:` tests pass.

- [ ] **Step 6: Run all dirty-region tests**

```bash
bash tests/integration/test-dirty-region.sh
```

Expected: `OK  N/N tests passed`

- [ ] **Step 7: Run existing confirm integration tests (regression)**

```bash
bash tests/integration/test-confirm.sh
```

Expected: `OK  N/N tests passed`

- [ ] **Step 8: Commit**

```bash
git add src/widgets/confirm.sh
git commit -m "$(cat <<'EOF'
feat(confirm): dirty-region rendering — skip screen_clear on button toggle

Add local _dirty integer and pre-computed _btn_row to shellframe_confirm.
Left/right arrow (button toggle) sets _dirty=1; the partial draw path calls
the extracted _cf_draw_buttons helper at the pre-computed button row without
calling shellframe_screen_clear. y/n/Enter/Esc quick-exit bindings are
unaffected (they break before reaching the draw path).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Full regression suite

- [ ] **Step 1: Run all integration tests**

```bash
bash tests/integration/run.sh --integration 2>/dev/null || bash tests/ptyunit/run.sh --integration 2>/dev/null
```

If the project uses its own `run.sh`:

```bash
bash tests/run.sh
```

Expected: all tests pass.

- [ ] **Step 2: Run Docker cross-version matrix**

```bash
bash tests/docker/run-matrix.sh
```

Expected: bash 3.2, 4.4, and 5.2 images all pass. If Docker is not available locally, note this for CI.

- [ ] **Step 3: Update screen.sh roadmap comment**

In `src/screen.sh`, update the Stage 1 comment from `(Phase 7 task B, GH #TBD)` to include the actual issue number. Find:

```bash
#   Stage 1 — Dirty-region tracking (Phase 7 task B, GH #TBD):
```

Replace `#TBD` with the issue number from Task 0.

- [ ] **Step 4: Commit roadmap update**

```bash
git add src/screen.sh
git commit -m "$(cat <<'EOF'
docs(screen): update Stage 1 roadmap comment with issue number

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
