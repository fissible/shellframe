# Windowed Panel Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `SHELLFRAME_PANEL_MODE=windowed` to `shellframe_panel_render` and `shellframe_panel_inner`, rendering the panel title in a dedicated full-width row inside the border rather than embedded in the border line itself.

**Architecture:** Two new globals (`SHELLFRAME_PANEL_MODE`, `SHELLFRAME_PANEL_TITLE_BG`) are initialized in `panel.sh` alongside existing globals. `shellframe_panel_inner` gains a `_title_row` offset applied when mode is `windowed`. `shellframe_panel_render` gains a title-bar drawing block after the top border when mode is `windowed`. `modal.sh` saves/restores the new globals and mirrors the same `_title_row` adjustment in its manual inner-bounds calculation.

**Tech Stack:** bash 3.2+, ANSI escape sequences, fd 3 for terminal output (matches existing pattern — spec erroneously showed `/dev/tty`)

**Spec:** https://github.com/fissible/shellframe/issues/24

---

### Task 1: Add new globals and unit tests for windowed inner bounds

**Files:**
- Modify: `src/panel.sh:59-63` (global defaults block)
- Modify: `tests/unit/test-panel.sh`

- [ ] **Step 1: Add new global defaults to `src/panel.sh`**

  Insert after line 63 (after `SHELLFRAME_PANEL_FOCUSABLE=1`):

  ```bash
  SHELLFRAME_PANEL_MODE="framed"    # framed (default) | windowed
  SHELLFRAME_PANEL_TITLE_BG=""      # ANSI escape for title bar background (windowed mode only)
  ```

  Also add to the header comment block (around lines 29-36):

  ```bash
  #   SHELLFRAME_PANEL_MODE         — framed (default) | windowed
  #   SHELLFRAME_PANEL_TITLE_BG     — ANSI bg escape for title bar row (windowed mode only)
  ```

- [ ] **Step 2: Write failing tests for windowed inner bounds**

  Append to `tests/unit/test-panel.sh` before `ptyunit_test_summary`:

  ```bash
  # ── shellframe_panel_inner: windowed mode ─────────────────────────────────────

  ptyunit_test_begin "panel_inner: windowed+single — top offset by 2"
  SHELLFRAME_PANEL_STYLE="single"
  SHELLFRAME_PANEL_MODE="windowed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "3" "$_ot" "windowed+single: inner top = outer top + border(1) + title_row(1)"

  ptyunit_test_begin "panel_inner: windowed+single — height reduced by 3"
  SHELLFRAME_PANEL_STYLE="single"
  SHELLFRAME_PANEL_MODE="windowed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "7" "$_oh" "windowed+single: inner height = outer height - border*2(2) - title_row(1)"

  ptyunit_test_begin "panel_inner: windowed+single — left and width unchanged vs framed"
  SHELLFRAME_PANEL_STYLE="single"
  SHELLFRAME_PANEL_MODE="windowed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "2"  "$_ol" "windowed: left still offset by border"
  assert_eq "18" "$_ow" "windowed: width still reduced by border*2"

  ptyunit_test_begin "panel_inner: windowed+none — top offset by 1 (title row only)"
  SHELLFRAME_PANEL_STYLE="none"
  SHELLFRAME_PANEL_MODE="windowed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "2" "$_ot" "windowed+none: inner top = outer top + title_row(1)"

  ptyunit_test_begin "panel_inner: windowed+none — height reduced by 1"
  SHELLFRAME_PANEL_STYLE="none"
  SHELLFRAME_PANEL_MODE="windowed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "9" "$_oh" "windowed+none: inner height = outer height - title_row(1)"

  ptyunit_test_begin "panel_inner: framed mode unaffected by MODE global"
  SHELLFRAME_PANEL_STYLE="single"
  SHELLFRAME_PANEL_MODE="framed"
  _ot="" _ol="" _ow="" _oh=""
  shellframe_panel_inner 1 1 20 10 _ot _ol _ow _oh
  assert_eq "2" "$_ot" "framed: top offset by border only"
  assert_eq "8" "$_oh" "framed: height reduced by border*2 only"
  ```

- [ ] **Step 3: Run tests to confirm they fail**

  ```bash
  cd /path/to/shellframe
  bash tests/ptyunit/run.sh tests/unit/test-panel.sh
  ```

  Expected: new windowed tests FAIL (SHELLFRAME_PANEL_MODE not yet read by `shellframe_panel_inner`)

---

### Task 2: Implement windowed mode in `shellframe_panel_inner`

**Files:**
- Modify: `src/panel.sh:185-196`

- [ ] **Step 1: Update `shellframe_panel_inner` to apply title row offset**

  Replace the current function body (lines 189-195):

  ```bash
  shellframe_panel_inner() {
      local _top="$1" _left="$2" _width="$3" _height="$4"
      local _out_top="$5" _out_left="$6" _out_width="$7" _out_height="$8"

      local _border=0
      [[ "${SHELLFRAME_PANEL_STYLE:-single}" != "none" ]] && _border=1

      local _title_row=0
      [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1

      printf -v "$_out_top"    '%d' "$(( _top    + _border + _title_row ))"
      printf -v "$_out_left"   '%d' "$(( _left   + _border ))"
      printf -v "$_out_width"  '%d' "$(( _width  - _border * 2 ))"
      printf -v "$_out_height" '%d' "$(( _height - _border * 2 - _title_row ))"
  }
  ```

- [ ] **Step 2: Run tests to confirm they pass**

  ```bash
  bash tests/ptyunit/run.sh tests/unit/test-panel.sh
  ```

  Expected: all tests PASS

- [ ] **Step 3: Commit**

  ```bash
  git add src/panel.sh tests/unit/test-panel.sh
  git commit -m "feat(panel): add SHELLFRAME_PANEL_MODE=windowed inner-bounds support"
  ```

---

### Task 3: Implement windowed title bar rendering in `shellframe_panel_render`

**Files:**
- Modify: `src/panel.sh:139-174`

- [ ] **Step 1: Update `shellframe_panel_render` to draw title bar row in windowed mode**

  In `shellframe_panel_render`, after the top border block (after line 158, the `_shellframe_panel_hline` call for the top border), insert the windowed title bar block. Also update the top border call to suppress title embedding when in windowed mode.

  Replace the top border line (line 158):
  ```bash
  _shellframe_panel_hline "$_top" "$_left" "$_width" "$_tl" "$_hr" "$_tr" "$_title" "$_talign"
  ```

  With:
  ```bash
  local _mode="${SHELLFRAME_PANEL_MODE:-framed}"
  if [[ "$_mode" == "windowed" ]]; then
      # Top border: no title embedded in border line
      _shellframe_panel_hline "$_top" "$_left" "$_width" "$_tl" "$_hr" "$_tr"

      # Title bar row: full-width colored row immediately inside top border
      local _title_row=$(( _top + _border ))
      local _title_bg="${SHELLFRAME_PANEL_TITLE_BG:-}"
      local _title_rst="${SHELLFRAME_RESET:-$'\033[0m'}"
      local _title_text=" ${_title}"
      local _title_tlen=$(( ${#_title} + 1 ))
      local _inner_w=$(( _width - _border * 2 ))
      local _title_pad=$(( _inner_w - _title_tlen ))
      (( _title_pad < 0 )) && _title_pad=0
      local _title_spaces
      printf -v _title_spaces '%*s' "$_title_pad" ''
      printf '\033[%d;%dH%s%s%s%s%s' \
          "$_title_row" "$(( _left + _border ))" \
          "${_on}${_vr}${_off}" \
          "$_title_bg" "$_title_text" "$_title_spaces" "$_title_rst" >&3
      printf '\033[%d;%dH%s' \
          "$_title_row" "$(( _left + _width - 1 ))" \
          "${_on}${_vr}${_off}" >&3
  else
      # framed mode: title embedded in top border line
      _shellframe_panel_hline "$_top" "$_left" "$_width" "$_tl" "$_hr" "$_tr" "$_title" "$_talign"
  fi
  ```

  Note: `_border` is not a local in the current function — derive it before this block:
  ```bash
  local _border=0
  [[ "$_style" != "none" ]] && _border=1
  ```
  Add this line after `_shellframe_panel_chars "$_style"` (line 147).

- [ ] **Step 2: Run the full unit test suite**

  ```bash
  bash tests/ptyunit/run.sh
  ```

  Expected: all tests PASS (rendering changes are not covered by unit tests — that's expected per the test file comment)

- [ ] **Step 3: Smoke test interactively**

  ```bash
  SHELLFRAME_PANEL_MODE=windowed \
  SHELLFRAME_PANEL_TITLE="Row Inspector" \
  SHELLFRAME_PANEL_TITLE_BG=$'\033[1;30;102m' \
  bash -c '
    source shellframe.sh
    SHELLFRAME_PANEL_STYLE=rounded
    shellframe_panel_render 3 5 40 12
    read -r _
  '
  ```

  Expected: modal with rounded border, dedicated green title bar row reading "Row Inspector", content area starting one row below the title bar.

- [ ] **Step 4: Commit**

  ```bash
  git add src/panel.sh
  git commit -m "feat(panel): render windowed title bar row in shellframe_panel_render"
  ```

---

### Task 4: Update `modal.sh` to handle windowed mode

**Files:**
- Modify: `src/widgets/modal.sh:208-230`

- [ ] **Step 1: Add save/restore for new globals**

  In the save block (lines 208-211), add:
  ```bash
  local _save_pmode="${SHELLFRAME_PANEL_MODE:-framed}"
  local _save_ptitlebg="${SHELLFRAME_PANEL_TITLE_BG:-}"
  ```

  In the restore block (lines 219-222), add:
  ```bash
  SHELLFRAME_PANEL_MODE="$_save_pmode"
  SHELLFRAME_PANEL_TITLE_BG="$_save_ptitlebg"
  ```

- [ ] **Step 2: Update `_shellframe_modal_dims` to add title row to auto-computed height**

  `_shellframe_modal_dims` computes `_need_h` as `_inner_h + 2` (line 180 — the +2 covers top and bottom border rows). In windowed mode the title bar is an additional row. Without this fix, auto-computed modal height is 1 short and the title bar clips the content area.

  Replace line 180:
  ```bash
  local _need_h=$(( _inner_h + 2 ))   # + 2 for border rows
  ```

  With:
  ```bash
  local _title_row=0
  [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1
  local _need_h=$(( _inner_h + 2 + _title_row ))   # + 2 for border rows, + 1 for windowed title bar
  ```

- [ ] **Step 3: Update manual inner bounds calculation to account for windowed title row**

  Replace lines 225-230:
  ```bash
  local _border=0
  [[ "$_style" != "none" ]] && _border=1
  local _inner_top=$(( _modal_top  + _border ))
  local _inner_left=$(( _modal_left + _border ))
  local _inner_w=$(( _modal_w - _border * 2 ))
  local _inner_h=$(( _modal_h - _border * 2 ))
  ```

  With:
  ```bash
  local _border=0
  [[ "$_style" != "none" ]] && _border=1
  local _title_row=0
  [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1
  local _inner_top=$(( _modal_top  + _border + _title_row ))
  local _inner_left=$(( _modal_left + _border ))
  local _inner_w=$(( _modal_w - _border * 2 ))
  local _inner_h=$(( _modal_h - _border * 2 - _title_row ))
  ```

- [ ] **Step 4: Run the full test suite**

  ```bash
  bash tests/ptyunit/run.sh
  ```

  Expected: all tests PASS

- [ ] **Step 5: Commit**

  ```bash
  git add src/widgets/modal.sh
  git commit -m "feat(modal): save/restore PANEL_MODE globals; adjust dims and inner bounds for windowed mode"
  ```

---

### Task 5: Update panel.sh header comment and close issue

**Files:**
- Modify: `src/panel.sh:37-57` (Public API comment block)

- [ ] **Step 1: Update header comment for `shellframe_panel_render`**

  In the Public API comment, update the `shellframe_panel_render` entry to document the windowed mode behaviour:

  ```bash
  #   shellframe_panel_render top left width height
  #     Draw the border and title within the region.  In framed mode (default),
  #     the title is embedded in the top border line.  In windowed mode
  #     (SHELLFRAME_PANEL_MODE=windowed), the title is rendered in a dedicated
  #     full-width row inside the top border, styled with SHELLFRAME_PANEL_TITLE_BG.
  #     Output goes to fd 3.
  ```

- [ ] **Step 2: Run the full test suite one final time**

  ```bash
  bash tests/ptyunit/run.sh
  ```

  Expected: all tests PASS

- [ ] **Step 3: Commit and push**

  ```bash
  git add src/panel.sh
  git commit -m "docs(panel): document windowed mode in header comment"
  git push
  ```

- [ ] **Step 4: Close GitHub issue**

  ```bash
  gh issue close 24 --repo fissible/shellframe --comment "Implemented in tasks 1–5 of the windowed panel mode plan."
  ```
