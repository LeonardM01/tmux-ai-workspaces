# tmux-ai-workspaces — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorming complete, pending spec review)

## Summary

A tpm-installable tmux plugin with two capabilities:

1. **Toggle-able left sidebar** — a keybind opens a narrow live pane on the left of the
   current window listing all running tmux sessions, with one-key jumping between them.
2. **Always-visible Claude Code status indicators** — driven by Claude Code hooks, so you
   can tell at a glance which session is *working*, *done*, or *waiting for your input*
   without opening the sidebar.

The plugin targets the user's existing setup: tpm + catppuccin (mocha), tmux-sessionx
(`prefix + o`), resurrect/continuum, vim-tmux-navigator, on tmux 3.6b (macOS).

## Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Navigator form factor | **Toggle-able left sidebar** | Matches "activate a sidebar"; non-invasive; coexists with resurrect/continuum. |
| State detection | **Claude Code hooks** | Semantic & accurate — distinguishes done vs needs-input vs busy. |
| Sidebar list scope | **Open sessions only** | Simplest; new projects still come from existing `tmux-sessionizer` (`prefix + f`). |
| Implementation technique | **Pure shell + tpm plugin** | Zero new dependencies; fits tmux-plugin conventions; the live board wants a custom render loop. |
| Indicator surfaces | **Status bar (always) + sidebar (detail)** | The point is knowing *without* opening the sidebar. |

**Not fzf-driven.** fzf was considered and rejected for the live board — it is built for
one-shot picking, not a living dashboard. The sidebar uses a `read -t 1` loop (live refresh
+ key capture in one). fzf remains an optional *future* fuzzy-jump mode only.

## Architecture & components

Built into the existing `tmux-AI-workspaces-plugin/` directory, tpm-compatible:

```
ai-workspaces.tmux          # entry point tpm runs: bindings, status segment, tmux hooks, options
scripts/
  toggle-sidebar.sh         # open/close the left split in current window
  sidebar.sh                # the live render+input loop (the board)
  jump.sh                   # switch-client to a session, then close sidebar
  state.sh                  # shared lib: read/write/clear/prune state, urgency ranking
  status-alert.sh           # compact segment string for status-right
  claude-hook.sh            # called BY claude hooks: writes per-pane state
  clear-state.sh            # called by tmux client-session-changed: clears focused session
  install-hooks.sh          # jq-merges hook entries into ~/.claude/settings.json (backs up first)
  selftest.sh               # plain-shell assertions + headless tmux integration smoke test
hooks/settings-snippet.json # the exact hook entries, for manual install / reference
README.md
FUTURE.md                   # compiled-TUI path, fzf fuzzy-jump, sessions+dirs, per-window tree, notifications
```

### Configuration (tmux user-options, with defaults)

| Option | Default | Meaning |
|--------|---------|---------|
| `@ai_sidebar_key` | `Tab` | Toggle key (used as `prefix + <key>`) |
| `@ai_sidebar_width` | `24` | Sidebar width in columns |
| `@ai_state_dir` | `$TMPDIR/tmux-ai` | Where per-pane state files live |

## State protocol (contract between hooks and UI)

- State dir: `${TMPDIR:-/tmp}/tmux-ai/`.
- **One file per Claude pane.** Filename = sanitized `$TMUX_PANE` (e.g. `%12`).
  Contents = `session_name<TAB>state<TAB>epoch`.
- States: `busy` (working) · `done` (finished a turn) · `wait` (needs permission/input).
- The UI **aggregates panes → session**, choosing the most urgent state:
  **`wait` > `done` > `busy`**.
- Keying by pane (not session) means multiple Claude instances in one session work
  correctly, and stale panes can be pruned.
- **Pruning:** on each render, any state file whose pane no longer exists
  (`tmux list-panes -a -F '#{pane_id}'`) is deleted. `SessionEnd` also removes the file.

## Sidebar (the board)

- `prefix + Tab` toggles it (`@ai_sidebar_key`).
- `toggle-sidebar.sh` checks for a marked sidebar pane in the current window:
  present → kill it; absent → `split-window -hb -l <width>` on the left running `sidebar.sh`.
  Idempotent via the pane marker, so rapid toggling is safe.
- `sidebar.sh` loop:
  1. Render header + numbered session rows. Each row: colored dot per state
     (`busy`=dim `○`, `done`=green `●`, `wait`=yellow `●` + `⚑`), zoom/current-session
     highlighting, catppuccin-styled.
  2. `read -t 1 -rsn1 key` — 1-second timeout gives **live refresh + key capture in one loop**.
- Keys: `1`–`9` jump to that session · `q`/`Esc` close. (j/k cursor highlight deferred.)
- `jump.sh <session>`: kill the sidebar pane, then `switch-client -t <session>`.

## Status-bar alert (always visible)

- `status-alert.sh` scans the state dir for sessions **other than the current** and emits a
  compact catppuccin-styled segment, e.g. `⚑2 ●1` (yellow waits, green dones), empty when clear.
- `ai-workspaces.tmux` prepends it into `status-right` (before battery) via `set -ga`, and
  lowers `status-interval` to `2` for prompt refresh.
- This is the signal that lets you "know to go" without opening the sidebar.

## Claude Code hooks (additive — never replaces lean-ctx)

`claude-hook.sh <state>` resolves the session from `$TMUX_PANE`
(`tmux display-message -p -t "$TMUX_PANE" '#{session_name}'`), no-op if not inside tmux,
and writes the state file.

| Claude hook | State written |
|-------------|---------------|
| `UserPromptSubmit` | `busy` |
| `Notification` | `wait` |
| `Stop` | `done` |
| `SessionEnd` | removes the pane's file |

`install-hooks.sh` uses `jq` to **append** our command to the existing `Stop` and
`UserPromptSubmit` arrays and **add** `Notification` + `SessionEnd` entries, backing up
`~/.claude/settings.json` first. Existing `lean-ctx hook observe` entries remain intact.
If `jq` is absent (not the case here), the installer prints `hooks/settings-snippet.json`
for manual merge.

### Clearing on focus

A tmux `client-session-changed` hook runs `clear-state.sh` to clear the flag for the session
just switched to (you've seen it). Claude rewrites `done`/`wait` on its next event.

## Error handling & edge cases

- Not in tmux → hooks no-op (guard on `$TMUX_PANE`).
- Missing state dir → created on first write/render.
- Stale panes → pruned each render and on `SessionEnd`.
- `jq` missing → installer falls back to printing the manual snippet.
- Sidebar double-toggle → idempotent via pane marker.

## Testing

- **Pure-function tests** (`state.sh`: urgency ranking, session aggregation, pruning) via
  plain-shell assertions in `selftest.sh` — no `bats` dependency.
- **Headless integration smoke test**: spin a throwaway server on a private socket
  (`tmux -L aitest`), create fake sessions, write fake state files, assert `status-alert.sh`
  output and that `jump.sh` switches the client. Runs without touching the user's live server.

## Build sequence

1. `state.sh` + selftest (the contract first).
2. `claude-hook.sh` + `install-hooks.sh` (begin emitting real state).
3. `status-alert.sh` + wire into `.tmux` (first visible payoff).
4. `sidebar.sh` + `toggle-sidebar.sh` + `jump.sh`.
5. `clear-state.sh` + tmux `client-session-changed` hook wiring.
6. `README.md`, `FUTURE.md`, polish.

## Future directions (out of scope for v1 — see FUTURE.md)

- **Compiled TUI** (Go/Rust) sidebar for richer rendering and interaction.
- **fzf fuzzy-jump** mode as an alternative selection UX.
- **Sessions + project dirs** listing (fold in sessionizer) and **per-window tree** view.
- **Desktop / audible notifications** (e.g. `terminal-notifier`) on `wait`.

## Environment facts (verified 2026-06-14)

- tmux 3.6b (full popup/menu/format support).
- `fzf` present, `jq` present, `bats` absent, `terminal-notifier` absent.
- `~/.claude/settings.json` exists with hooks for `Stop`, `UserPromptSubmit`,
  `SessionStart`, `SessionEnd`, etc. (all `lean-ctx hook observe`); **no** `Notification` hook yet.
- `tmux-sessionizer` at `~/scripts/tmux-sessionizer`.
- Workspace is **not** a git repository.
