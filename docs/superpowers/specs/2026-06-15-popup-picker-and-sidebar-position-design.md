# Popup Picker + Sidebar Position — Design

Date: 2026-06-15

## Background

This plugin shows the status of Claude Code sessions across a tmux server. Claude
Code hooks call `claude-hook.sh`, which writes a per-pane TAB record
(`session\tstate\tepoch`) under `$STATE_DIR` (default `/tmp/tmux-ai`). `state.sh`
aggregates those files per session by urgency (`wait > done > busy`). Today the only
view is a persistent left-split **sidebar** (`sidebar.sh`), opened by
`toggle-sidebar.sh` and bound to `@ai_sidebar_key` (default `Tab`).

Reference project [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager)
solves the same problem with an **fzf picker inside a `display-popup`**. Its state
model is simpler than ours (per-session tmux options vs. our per-pane files +
urgency rollup), so we adopt its *presentation* without changing our state layer.

## Goals

1. Sidebar always opens pinned to the far-left edge of the window, independent of
   which pane is currently active.
2. Add an alternative **popup picker** UI (fzf), as a second view over the same
   state, reachable by its own key. Sidebar and popup are both always available.
3. No changes to the hook/state layer — both views read the same `$STATE_DIR` files.

## Non-goals

- Replacing the sidebar. It stays as-is (other than the position fix).
- A live "switch between sidebar and popup" key. Each UI has its own key; the user
  picks by pressing the key they want.
- A fallback renderer when fzf is absent. Popup mode requires fzf (see Decisions).

## Decisions (from brainstorming)

- **Popup interaction model:** fzf picker (fuzzy search, columns, kill binding),
  matching the reference project.
- **Keys:** separate key per UI. `@ai_sidebar_key` opens the sidebar,
  `@ai_popup_key` opens the popup. Both bound at load; no global "mode" option.
- **fzf missing:** show an install hint in the popup and exit. No fallback renderer.

## Design

### 1. Sidebar position fix

In `scripts/toggle-sidebar.sh`, change the spawn line:

```sh
# before
tmux split-window -hb -l "$SIDEBAR_WIDTH" "$SCRIPT_DIR/sidebar.sh"
# after
tmux split-window -fhb -l "$SIDEBAR_WIDTH" "$SCRIPT_DIR/sidebar.sh"
```

`-f` (full size) makes the new pane span the full window height and pins it to the
left edge of the **window** rather than splitting relative to the active pane. The
existing `@ai_sidebar` per-pane marking, `safe_kill_sidebar_pane`, the one-sidebar-
per-session invariant, and `jump.sh` re-spawn behavior are unchanged.

### 2. Popup launcher — `scripts/popup.sh`

- Resolve `SCRIPT_DIR`; do not require `$TMUX_PANE` (popup runs in caller context).
- If `command -v fzf` fails:
  `tmux display-popup -E "printf '%s\n' 'fzf not found — install fzf to use the popup picker'; read -rsn1"`
  (or equivalent that keeps the message visible briefly), then exit 0.
- Otherwise read dimensions:
  - `@ai_popup_width`  (default `80%`)
  - `@ai_popup_height` (default `80%`)
  - and run: `tmux display-popup -w "$W" -h "$H" -E "$SCRIPT_DIR/picker.sh"`.

### 3. Picker body — `scripts/picker.sh`

- `source "$SCRIPT_DIR/state.sh"`.
- Build rows from `state_aggregate ""` (the per-session highest-urgency rollup we
  already compute). For each session also gather:
  - urgency icon + color: `wait` → yellow `●`, `done` → green `●`, `busy` → gray `○`,
    unknown → dim `○` (same palette as `sidebar.sh`).
  - `pane_current_path` of the session (via `tmux display-message -p -t "$sess"`).
  - age, derived from the stored epoch (reuse/extend a `state.sh` helper rather than
    re-reading files ad hoc).
- Emit `rank<TAB>session<TAB>icon<TAB>path<TAB>age`, sorted by rank descending so
  attention-needed (`wait`) floats to the top.
- Pipe into fzf with `--with-nth` hiding the rank/session columns (show icon, path,
  age), `--delimiter=\t`.
- Bindings:
  - `enter` → selection resolves to the session field; popup closes and
    `tmux switch-client -t "$session"`.
  - `ctrl-x` → `tmux kill-session -t "$session"` then reload the fzf list.

### 4. Keybindings & options — `ai-workspaces.tmux`

- Keep: `@ai_sidebar_key` (default `Tab`) → `toggle-sidebar.sh`.
- Add: `@ai_popup_key` (default `S`) → `popup.sh`.
- Add option reads/defaults for `@ai_popup_width` / `@ai_popup_height` (consumed at
  runtime by `popup.sh`; nothing to set in the entry file beyond documenting).
- Both binds registered idempotently alongside the existing wiring.

### 5. State layer

Untouched. `claude-hook.sh`, `state.sh` write/aggregation, pruning, and
`safe_kill_sidebar_pane` are unchanged. Popup and sidebar are two readers of the
same `$STATE_DIR`.

### 6. Docs & selftest

- `README.md`: new "Popup picker" section, options table rows for `@ai_popup_key`,
  `@ai_popup_width`, `@ai_popup_height`, and a note that the popup requires `fzf`.
- `scripts/selftest.sh`: assert `popup.sh` and `picker.sh` exist and are executable;
  optionally warn (not fail) if `fzf` is absent.

## Data flow

```
Claude Code hook → claude-hook.sh → state.sh (per-pane file in $STATE_DIR)
                                          │
                state_aggregate ("wait>done>busy" per session)
                        ├── sidebar.sh  (persistent left split, 1s poll)
                        └── picker.sh   (fzf rows inside display-popup)
```

## Testing

- `selftest.sh` passes with the new scripts present/executable.
- Manual: sidebar opens far-left when invoked from a right-hand pane.
- Manual: popup key with fzf installed lists sessions, `wait` sorted on top, Enter
  switches client, ctrl-x kills + reloads.
- Manual: popup key with fzf absent shows the install hint and exits cleanly.

## Risk / blast radius

- `toggle-sidebar.sh`: single-flag change; low risk, isolated to spawn geometry.
- New scripts are additive; they only read state, except the `ctrl-x` kill path
  (guarded by fzf selection, same `kill-session` the reference project uses).
- No changes to hooks or state writes, so existing behavior cannot regress.
