#!/usr/bin/env bash
cat > /dev/null   # consume stdin (Claude hook JSON) BEFORE any exit
STATE_ARG="${1:-}"
[ -z "$TMUX_PANE" ] && exit 0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
SESSION=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
[ -z "$SESSION" ] && exit 0
case "$STATE_ARG" in
  busy|done|wait) state_write "$TMUX_PANE" "$SESSION" "$STATE_ARG" ;;
  remove) state_remove "$TMUX_PANE" ;;
  *) exit 0 ;;
esac
exit 0
