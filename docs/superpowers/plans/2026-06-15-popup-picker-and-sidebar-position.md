# Popup Picker + Sidebar Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an fzf-based popup picker as a second view over existing session state, and make the sidebar always open pinned to the far-left edge of the window.

**Architecture:** The state layer (`claude-hook.sh`, `state.sh` writes/aggregation) is untouched. The sidebar position fix is a single tmux flag (`-f`) added to the two spawn sites. The popup is two new additive scripts (`popup.sh` launcher + `picker.sh` body) that read the same per-pane `$STATE_DIR` files via `state.sh`. A new read-only helper `state_latest_epoch_for_session` is added to `state.sh` so the picker can show session age. New keybind `@ai_popup_key` (default `S`) is registered alongside the existing sidebar bind.

**Tech Stack:** Bash (macOS system bash 3.2 compatible), tmux, fzf, the repo's `selftest.sh` harness.

---

## File Structure

- `scripts/state.sh` — MODIFY: add read-only `state_latest_epoch_for_session`.
- `scripts/toggle-sidebar.sh` — MODIFY: spawn with `-fhb`.
- `scripts/jump.sh` — MODIFY: re-spawn with `-fhb` so jumps stay far-left.
- `scripts/picker.sh` — CREATE: sourced-safe row builder + age helper + fzf main.
- `scripts/popup.sh` — CREATE: fzf-presence check + `display-popup` launcher.
- `ai-workspaces.tmux` — MODIFY: bind `@ai_popup_key`, document popup size options.
- `scripts/selftest.sh` — MODIFY: unit tests for new helper + row builder, file-exists checks, flag-regression guard, far-left geometry integration test.
- `README.md` — MODIFY: popup section + options table + fzf note.

Bash-testing note: interactive paths (the fzf TUI, `display-popup`, `switch-client`, the sidebar's render loop) cannot be unit tested. We make the *data* logic sourced-safe and pure so it can be tested with seeded state, guard the new scripts behind a `[ "${BASH_SOURCE[0]}" = "$0" ]` main block, and cover geometry with a tmux integration test on a private socket (the pattern `selftest.sh` already uses).

---

### Task 1: Add `state_latest_epoch_for_session` helper

**Files:**
- Modify: `scripts/state.sh`
- Test: `scripts/selftest.sh`

- [ ] **Step 1: Write the failing test**

Add to `scripts/selftest.sh`, immediately after the existing `state_for_session` block (the `"wait beats done beats busy"` assert, around line 30, still inside the `unset TMUX` unit section):

```bash
state_write "%40" "proj-age" "busy"
printf '%s\t%s\t%s\n' "proj-age" "busy" "1700000000" > "$STATE_DIR/p40"
state_write "%41" "proj-age" "wait"
printf '%s\t%s\t%s\n' "proj-age" "wait" "1700000050" > "$STATE_DIR/p41"
assert_eq "latest epoch picks max across panes" "1700000050" "$(state_latest_epoch_for_session proj-age)"
assert_eq "latest epoch empty for unknown session" "" "$(state_latest_epoch_for_session nope)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/selftest.sh`
Expected: FAIL on `latest epoch picks max across panes` (function prints nothing / `command not found`).

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/state.sh` (after `state_for_session`, before any trailing code). Follow the file's existing per-file loop style:

```bash
# Echo the highest (most recent) epoch recorded for a session across all its
# panes, or nothing if the session has no state files. Read-only; does not prune.
state_latest_epoch_for_session() {
  local target="$1" fpath best=""
  [ -d "$STATE_DIR" ] || return 0
  for fpath in "$STATE_DIR"/p*; do
    [ -f "$fpath" ] || continue
    local sess st epoch
    IFS=$'\t' read -r sess st epoch < "$fpath"
    [ "$sess" = "$target" ] || continue
    case "$epoch" in ''|*[!0-9]*) continue ;; esac
    if [ -z "$best" ] || [ "$epoch" -gt "$best" ]; then best="$epoch"; fi
  done
  [ -n "$best" ] && printf '%s' "$best"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/selftest.sh`
Expected: PASS on both new asserts; final line `Results: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/state.sh scripts/selftest.sh
git commit -m "Add state_latest_epoch_for_session helper for picker age column"
```

---

### Task 2: Picker row builder + age helper (`picker.sh`)

**Files:**
- Create: `scripts/picker.sh`
- Test: `scripts/selftest.sh`

- [ ] **Step 1: Write the failing test**

Add to `scripts/selftest.sh` in the unit section (still under `unset TMUX`, after the Task 1 asserts):

```bash
source "$SCRIPT_DIR/picker.sh"
assert_eq "age seconds" "5s" "$(_age_human 1700000000 1700000005)"
assert_eq "age minutes" "3m" "$(_age_human 1700000000 1700000180)"
assert_eq "age hours" "2h" "$(_age_human 1700000000 1700007200)"
assert_eq "age days" "1d" "$(_age_human 1700000000 1700086400)"
assert_eq "age empty epoch" "-" "$(_age_human "" 1700000005)"

state_write "%50" "proj-row" "wait"
printf '%s\t%s\t%s\n' "proj-row" "wait" "1700000000" > "$STATE_DIR/p50"
row=$(picker_rows 1700000005 | awk -F'\t' '$2=="proj-row"')
assert_eq "row rank for wait" "3" "$(printf '%s' "$row" | cut -f1)"
assert_eq "row session" "proj-row" "$(printf '%s' "$row" | cut -f2)"
assert_eq "row age" "5s" "$(printf '%s' "$row" | cut -f5)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/selftest.sh`
Expected: FAIL — `picker.sh` does not exist, `source` errors with "No such file or directory".

- [ ] **Step 3: Write minimal implementation**

Create `scripts/picker.sh`. The row builder and helpers are sourced-safe; the fzf TUI only runs when executed directly. `picker_rows` accepts an optional `now` epoch (for tests); when omitted it uses `date +%s`. Path lookup uses tmux only when available.

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state.sh"

# Humanize an age given an epoch and a reference "now". Empty/invalid -> "-".
_age_human() {
  local epoch="$1" now="$2" diff
  case "$epoch" in ''|*[!0-9]*) printf '%s' "-"; return 0 ;; esac
  diff=$(( now - epoch ))
  [ "$diff" -lt 0 ] && diff=0
  if [ "$diff" -lt 60 ]; then printf '%ds' "$diff"
  elif [ "$diff" -lt 3600 ]; then printf '%dm' "$(( diff / 60 ))"
  elif [ "$diff" -lt 86400 ]; then printf '%dh' "$(( diff / 3600 ))"
  else printf '%dd' "$(( diff / 86400 ))"; fi
}

# Emit one TAB row per session: rank<TAB>session<TAB>icon<TAB>path<TAB>age.
# rank lets the caller float wait>done>busy to the top. Accepts an optional
# `now` epoch so the suite can assert ages deterministically.
picker_rows() {
  local now="${1:-}"
  [ -z "$now" ] && now=$(date +%s)
  local agg sess st rank icon path epoch age
  agg=$(state_aggregate "")
  while IFS=$'\t' read -r sess st; do
    [ -z "$sess" ] && continue
    rank=$(_urgency_rank "$st")
    case "$st" in
      wait) icon="● wait" ;;
      done) icon="● done" ;;
      busy) icon="○ busy" ;;
      *)    icon="○ ----" ;;
    esac
    path=""
    if [ -n "${TMUX:-}" ]; then
      path=$(tmux display-message -p -t "$sess" '#{pane_current_path}' 2>/dev/null)
    fi
    epoch=$(state_latest_epoch_for_session "$sess")
    age=$(_age_human "$epoch" "$now")
    printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$sess" "$icon" "$path" "$age"
  done <<EOF
$agg
EOF
}

# Interactive entry point — only when executed, never when sourced by the suite.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  selection=$(picker_rows | sort -t$'\t' -k1,1nr \
    | fzf --ansi --delimiter='\t' --with-nth=3,4,5 \
          --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload(bash $SCRIPT_DIR/picker.sh --rows)" \
          --header='enter: switch   ctrl-x: kill')
  [ -z "$selection" ] && exit 0
  target=$(printf '%s' "$selection" | cut -f2)
  [ -n "$target" ] && tmux switch-client -t "$target"
fi
```

Note: the `reload` binding re-runs the script in a rows-only mode. Support it with a tiny pre-main branch — add this just above the `if [ "${BASH_SOURCE[0]}" = "$0" ]` line:

```bash
if [ "${1:-}" = "--rows" ]; then picker_rows | sort -t$'\t' -k1,1nr; exit 0; fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/selftest.sh`
Expected: PASS on all `age *` and `row *` asserts; `Results: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/picker.sh scripts/selftest.sh
git commit -m "Add fzf picker row builder and age helper"
```

---

### Task 3: Popup launcher with fzf guard (`popup.sh`)

**Files:**
- Create: `scripts/popup.sh`
- Test: `scripts/selftest.sh`

- [ ] **Step 1: Write the failing test**

Add to `scripts/selftest.sh` in the unit section:

```bash
assert_file_exists "popup.sh exists" "$SCRIPT_DIR/popup.sh"
assert_eq "popup.sh executable" "yes" "$([ -x "$SCRIPT_DIR/popup.sh" ] && echo yes || echo no)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/selftest.sh`
Expected: FAIL — `popup.sh exists (missing .../popup.sh)`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/popup.sh`:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-popup -E "printf '%s\n\n%s\n' 'fzf not found.' 'Install fzf to use the popup picker (e.g. brew install fzf).'; printf 'Press any key to close...'; read -rsn1"
  exit 0
fi

W=$(tmux show-option -gqv "@ai_popup_width");  W="${W:-80%}"
H=$(tmux show-option -gqv "@ai_popup_height"); H="${H:-80%}"

tmux display-popup -w "$W" -h "$H" -E "$SCRIPT_DIR/picker.sh"
```

Then make both new scripts executable:

```bash
chmod +x scripts/popup.sh scripts/picker.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/selftest.sh`
Expected: PASS on `popup.sh exists` and `popup.sh executable`.

- [ ] **Step 5: Commit**

```bash
git add scripts/popup.sh scripts/picker.sh scripts/selftest.sh
git commit -m "Add popup launcher with fzf-missing install hint"
```

---

### Task 4: Sidebar far-left position fix

**Files:**
- Modify: `scripts/toggle-sidebar.sh:12` (the `split-window` line)
- Modify: `scripts/jump.sh` (the `NEW_PANE=$(tmux split-window ...)` line)
- Test: `scripts/selftest.sh`

- [ ] **Step 1: Write the failing tests**

Add a flag-regression guard in the unit section of `scripts/selftest.sh`:

```bash
if grep -q 'split-window -fhb' "$SCRIPT_DIR/toggle-sidebar.sh"; then echo "PASS: toggle-sidebar spawns full-height (-f)"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL: toggle-sidebar missing -f flag"; FAIL_COUNT=$((FAIL_COUNT+1)); fi
if grep -q 'split-window -fhb' "$SCRIPT_DIR/jump.sh"; then echo "PASS: jump spawns full-height (-f)"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL: jump missing -f flag"; FAIL_COUNT=$((FAIL_COUNT+1)); fi
```

Add a geometry integration test inside the `else` branch of the integration section (after `PANE_A=...`, using the `aiws-a` session `$SA` which has a single pane). This proves a full-size left split lands at column 0 even when the active pane is on the right:

```bash
  command tmux -L "$SOCKET" split-window -h -t "$SA"
  command tmux -L "$SOCKET" select-pane -t "$SA".+
  LEFTCOL=$(command tmux -L "$SOCKET" split-window -fhb -d -t "$SA" -P -F '#{pane_left}')
  assert_eq "full-size left split pins to column 0" "0" "$LEFTCOL"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/selftest.sh`
Expected: FAIL on `toggle-sidebar missing -f flag` and `jump missing -f flag` (scripts still use `-hb`). The geometry assert passes (it tests tmux directly), but keep it — it documents intent.

- [ ] **Step 3: Apply the fix**

In `scripts/toggle-sidebar.sh`, change:

```bash
  tmux split-window -hb -l "$SIDEBAR_WIDTH" "$SCRIPT_DIR/sidebar.sh"
```
to:
```bash
  tmux split-window -fhb -l "$SIDEBAR_WIDTH" "$SCRIPT_DIR/sidebar.sh"
```

In `scripts/jump.sh`, change:

```bash
NEW_PANE=$(tmux split-window -hb -d -l "$WIDTH" -t "$TARGET_SESSION" -P -F '#{pane_id}' "$SCRIPT_DIR/sidebar.sh")
```
to:
```bash
NEW_PANE=$(tmux split-window -fhb -d -l "$WIDTH" -t "$TARGET_SESSION" -P -F '#{pane_id}' "$SCRIPT_DIR/sidebar.sh")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/selftest.sh`
Expected: PASS on both flag guards and the geometry assert; `Results: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/toggle-sidebar.sh scripts/jump.sh scripts/selftest.sh
git commit -m "Pin sidebar to far-left edge with full-size split (-f)"
```

---

### Task 5: Wire popup keybinding and options

**Files:**
- Modify: `ai-workspaces.tmux`
- Test: `scripts/selftest.sh`

- [ ] **Step 1: Write the failing test**

Add to `scripts/selftest.sh` unit section:

```bash
if grep -q '@ai_popup_key' "$SCRIPT_DIR/../ai-workspaces.tmux"; then echo "PASS: popup key wired in tmux entry"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL: popup key not wired"; FAIL_COUNT=$((FAIL_COUNT+1)); fi
if grep -q 'scripts/popup.sh' "$SCRIPT_DIR/../ai-workspaces.tmux"; then echo "PASS: popup.sh bound in tmux entry"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL: popup.sh not bound"; FAIL_COUNT=$((FAIL_COUNT+1)); fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/selftest.sh`
Expected: FAIL — `popup key not wired`.

- [ ] **Step 3: Write minimal implementation**

In `ai-workspaces.tmux`, after the existing `sidebar_width` option read (around line 5), add:

```bash
popup_key=$(tmux show-option -gqv "@ai_popup_key"); popup_key="${popup_key:-S}"
# popup width/height are read at runtime by popup.sh; nothing to set here.
```

After the existing `tmux bind-key "$sidebar_key" ...` line, add:

```bash
tmux bind-key "$popup_key" run-shell "$CURRENT_DIR/scripts/popup.sh"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/selftest.sh`
Expected: PASS on `popup key wired in tmux entry` and `popup.sh bound in tmux entry`.

- [ ] **Step 5: Commit**

```bash
git add ai-workspaces.tmux scripts/selftest.sh
git commit -m "Bind @ai_popup_key (default S) to popup picker"
```

---

### Task 6: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current README options/keybindings section**

Run: `bash -c 'grep -n "@ai_sidebar_key\|## \|Options\|Keybind" README.md'`
Expected: locate the options table and keybindings section to match their format.

- [ ] **Step 2: Add the popup section and options**

Add a "Popup picker" subsection near the sidebar docs, in the README's existing prose/table style:

```markdown
### Popup picker (fzf)

Press `prefix + S` to open a fuzzy picker of all AI sessions in a centered
popup. Sessions needing attention (`wait`) float to the top. In the picker:

- `enter` — switch to the selected session
- `ctrl-x` — kill the selected session and refresh the list

The popup requires [`fzf`](https://github.com/junegunn/fzf) on your `PATH`. If
fzf is missing, pressing the key shows a short install hint instead. The
sidebar (`prefix + Tab`) and popup are independent views over the same state —
use whichever you prefer.
```

Add these rows to the options table (matching its existing columns):

```markdown
| `@ai_popup_key`    | `S`   | prefix key that opens the fzf popup picker |
| `@ai_popup_width`  | `80%` | popup width (any tmux `display-popup -w` value)  |
| `@ai_popup_height` | `80%` | popup height (any tmux `display-popup -h` value) |
```

- [ ] **Step 3: Verify docs render and links are correct**

Run: `bash -c 'grep -n "@ai_popup_key\|Popup picker\|fzf" README.md'`
Expected: the new section and all three option rows are present.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document fzf popup picker and its options"
```

---

## Final verification

- [ ] Run the full suite: `bash scripts/selftest.sh` → `Results: N passed, 0 failed`.
- [ ] Manual (inside tmux, fzf installed): from a right-hand pane press `prefix + Tab` → sidebar appears full-height at the far left.
- [ ] Manual: press `prefix + S` → popup lists sessions, `wait` on top; `enter` switches client; `ctrl-x` kills + reloads.
- [ ] Manual (fzf absent, e.g. `PATH= command`): `prefix + S` shows the install hint and closes cleanly.

## Self-review notes

- **Spec coverage:** position fix (Task 4), fzf popup (Tasks 2–3), separate key per UI (Task 5), fzf-missing hint (Task 3), no state-write changes — only an additive read helper (Task 1), docs + selftest (Tasks 5–6). All spec sections mapped.
- **Type/name consistency:** `state_latest_epoch_for_session`, `_age_human`, `picker_rows`, `@ai_popup_key`, `@ai_popup_width`, `@ai_popup_height` used identically across tasks.
- **bash 3.2:** no associative arrays, no fractional `read -t`; integer math and `case` guards only.
