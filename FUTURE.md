# Future directions

Ideas intentionally left **out of scope for v1** to keep the first release small, pure-shell,
and dependency-free. Captured here so the design rationale isn't lost.

## Compiled TUI sidebar (Go / Rust)

The v1 sidebar is a `read -t 1` shell render loop. A compiled TUI (e.g. Bubble Tea in Go, or
ratatui in Rust) would give:

- Smooth, flicker-free rendering and a real cursor/highlight model.
- Richer interaction: fuzzy filtering, multi-level trees, mouse support.
- A single distributable binary.

**Cost:** a build toolchain, a binary to ship per platform, and far more code. Only worth it
if the shell sidebar hits real limits. The state protocol (`$TMPDIR/tmux-ai/<pane>` files)
stays identical, so a TUI is a drop-in replacement for `sidebar.sh` without touching hooks.

## fzf fuzzy-jump mode

An optional alternate selection UX: pipe the session list through `fzf` for fuzzy filtering
when the list grows long. Kept out of v1 because fzf owns the pane and fights the live-refresh
board; better as a separate `prefix`-bound popup picker that complements the sidebar.

## List unopened project dirs (sessionizer fold-in)

Show a second section in the sidebar: project directories under `~/coding` that aren't open
yet, so you can spin one up without leaving the sidebar (folding in `tmux-sessionizer`'s job).
Deferred because it lengthens the list and overlaps an existing tool.

## Per-window / per-pane tree view

Expand each session to its windows (and the specific window running Claude), for people who
run multiple Claude instances per project. Deferred in favor of the simpler session-level board.

## Desktop & audible notifications

On a `wait` transition, optionally fire `terminal-notifier` (macOS) / `notify-send` (Linux)
or ring the bell, so you get pinged even when tmux isn't focused. Deferred — needs per-OS
detection and opt-in config to avoid being noisy.

## Hybrid bell fallback

Layer tmux's native `monitor-bell` as a backup signal alongside the semantic hook states, for
non-Claude programs. Deferred as overkill for v1.
