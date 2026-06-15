#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

sidebar_key=$(tmux show-option -gqv "@ai_sidebar_key"); sidebar_key="${sidebar_key:-Tab}"
sidebar_width=$(tmux show-option -gqv "@ai_sidebar_width"); sidebar_width="${sidebar_width:-24}"
popup_key=$(tmux show-option -gqv "@ai_popup_key"); popup_key="${popup_key:-S}"
# popup width/height are read at runtime by popup.sh; nothing to set here.
# state_dir option is read by scripts at runtime; nothing to set here.

tmux bind-key "$sidebar_key" run-shell "$CURRENT_DIR/scripts/toggle-sidebar.sh"
tmux bind-key "$popup_key" run-shell "$CURRENT_DIR/scripts/popup.sh"

existing_right=$(tmux show-option -gv "status-right" 2>/dev/null)
# Idempotent: only prepend our segment if it isn't already present (this file
# re-runs on every `source-file` / config reload).
case "$existing_right" in
  *status-alert.sh*) : ;;
  *)
    new_right="#($CURRENT_DIR/scripts/status-alert.sh #{client_session})${existing_right:+#[bg=#{@thm_bg},fg=#{@thm_overlay_0}]│}${existing_right}"
    tmux set-option -g status-right "$new_right"
    ;;
esac

# Ensure the status bar refreshes at least every 2s. Validate the existing value
# is numeric first — a non-numeric value would make `[ -gt ]` error, and the
# 2>/dev/null would then silently swallow it and skip the set.
current_interval=$(tmux show-option -gqv "status-interval")
case "$current_interval" in
  ''|*[!0-9]*) tmux set-option -g status-interval 2 ;;
  *) [ "$current_interval" -gt 2 ] && tmux set-option -g status-interval 2 ;;
esac

# Idempotent: only register the focus-clear hook if it isn't already there.
if ! tmux show-hooks -g 2>/dev/null | grep -q "clear-state.sh"; then
  tmux set-hook -ga client-session-changed "run-shell '$CURRENT_DIR/scripts/clear-state.sh #{client_session}'"
fi
