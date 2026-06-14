#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
CURRENT_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null)
[ -z "$CURRENT_SESSION" ] && exit 0
[ -d "$STATE_DIR" ] || exit 0
for fpath in "$STATE_DIR"/p*; do
  [ -f "$fpath" ] || continue
  IFS=$'\t' read -r sess st epoch < "$fpath"
  [ "$sess" = "$CURRENT_SESSION" ] && rm -f "$fpath"
done
exit 0
