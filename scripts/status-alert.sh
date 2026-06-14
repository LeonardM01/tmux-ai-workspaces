#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
# status-right is rendered per client, so the session to exclude is passed in as
# #{client_session}. Avoid the ambiguous no-target display-message except as a
# fallback (empty arg on older installs, or an unexpanded format literal).
CURRENT_SESSION="${1:-}"
case "$CURRENT_SESSION" in
  ''|*'#{'*) CURRENT_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null) ;;
esac
wait_count=0; done_count=0; busy_count=0
while IFS=$'\t' read -r sess st; do
  [ -z "$sess" ] && continue
  # Use $((x+1)) not ((x++)): the latter returns non-zero when the result is 0,
  # which would abort the script the moment anyone enables `set -e`.
  case "$st" in
    wait) wait_count=$((wait_count+1)) ;;
    done) done_count=$((done_count+1)) ;;
    busy) busy_count=$((busy_count+1)) ;;
  esac
done < <(state_aggregate "$CURRENT_SESSION")
out=""
[ "$wait_count" -gt 0 ] && out="${out}#[fg=colour226]⚑${wait_count} "
[ "$done_count" -gt 0 ] && out="${out}#[fg=colour82]●${done_count} "
[ "$busy_count" -gt 0 ] && out="${out}#[fg=colour244]○${busy_count} "
printf '%s' "${out% }"
