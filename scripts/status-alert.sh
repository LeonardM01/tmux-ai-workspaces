#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
CURRENT_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null)
wait_count=0; done_count=0; busy_count=0
while IFS=$'\t' read -r sess st; do
  [ -z "$sess" ] && continue
  case "$st" in wait) ((wait_count++));; done) ((done_count++));; busy) ((busy_count++));; esac
done < <(state_aggregate "$CURRENT_SESSION")
out=""
[ "$wait_count" -gt 0 ] && out="${out}#[fg=colour226]⚑${wait_count} "
[ "$done_count" -gt 0 ] && out="${out}#[fg=colour82]●${done_count} "
[ "$busy_count" -gt 0 ] && out="${out}#[fg=colour244]○${busy_count} "
printf '%s' "$out"
