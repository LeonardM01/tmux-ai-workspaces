#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIDEBAR_PANE="${1:-}"; TARGET_SESSION="${2:-}"
[ -z "$TARGET_SESSION" ] && exit 1

WIDTH=$(tmux show-option -gqv "@ai_sidebar_width"); WIDTH="${WIDTH:-24}"

# Remove any sidebar that already exists in the target session (avoid dupes
# when hopping back and forth).
for p in $(tmux list-panes -s -t "$TARGET_SESSION" -F '#{pane_id} #{@ai_sidebar}' 2>/dev/null | awk '$2=="1"{print $1}'); do
  [ "$p" = "$SIDEBAR_PANE" ] && continue
  tmux kill-pane -t "$p" 2>/dev/null
done

# Spawn a fresh sidebar in the target session WITHOUT focusing it (-d), so the
# user lands in their workspace with the sidebar still visible on the left.
tmux split-window -hb -d -l "$WIDTH" -t "$TARGET_SESSION" "$SCRIPT_DIR/sidebar.sh"

# Move the client to the target session.
tmux switch-client -t "$TARGET_SESSION"

# Finally drop the old sidebar pane in the previous session. Done last: this
# script runs inside that pane, so killing it earlier would terminate us before
# the commands above could run.
[ -n "$SIDEBAR_PANE" ] && tmux kill-pane -t "$SIDEBAR_PANE" 2>/dev/null || true
