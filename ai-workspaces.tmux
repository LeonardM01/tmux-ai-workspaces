#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

sidebar_key=$(tmux show-option -gqv "@ai_sidebar_key"); sidebar_key="${sidebar_key:-Tab}"
sidebar_width=$(tmux show-option -gqv "@ai_sidebar_width"); sidebar_width="${sidebar_width:-24}"
# state_dir option is read by scripts at runtime; nothing to set here.

tmux bind-key "$sidebar_key" run-shell "$CURRENT_DIR/scripts/toggle-sidebar.sh"

existing_right=$(tmux show-option -gv "status-right" 2>/dev/null)
new_right="#($CURRENT_DIR/scripts/status-alert.sh)${existing_right:+#[bg=#{@thm_bg},fg=#{@thm_overlay_0}]│}${existing_right}"
tmux set-option -g status-right "$new_right"

current_interval=$(tmux show-option -gqv "status-interval")
if [ -z "$current_interval" ] || [ "$current_interval" -gt 2 ] 2>/dev/null; then
  tmux set-option -g status-interval 2
fi

tmux set-hook -ga client-session-changed "run-shell '$CURRENT_DIR/scripts/clear-state.sh'"
