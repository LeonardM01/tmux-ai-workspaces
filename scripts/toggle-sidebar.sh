#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
SIDEBAR_WIDTH=$(tmux show-option -gqv "@ai_sidebar_width"); SIDEBAR_WIDTH="${SIDEBAR_WIDTH:-24}"
SIDEBAR_PANE=$(tmux list-panes -F '#{pane_id} #{@ai_sidebar}' | awk '$2 == "1" {print $1; exit}')
if [ -n "$SIDEBAR_PANE" ]; then
  safe_kill_sidebar_pane "$SIDEBAR_PANE"
else
  tmux split-window -hb -l "$SIDEBAR_WIDTH" "$SCRIPT_DIR/sidebar.sh"
fi
