#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
# The session is passed in by the client-session-changed hook (#{client_session}).
# `display-message` with no -t resolves against an ambiguous "current" client and
# can clear the wrong session under multiple attached clients — same class of bug
# the sidebar had. Fall back to it only if the arg is missing or unexpanded.
CURRENT_SESSION="${1:-}"
case "$CURRENT_SESSION" in
  ''|*'#{'*) CURRENT_SESSION=$(tmux display-message -p '#{client_session}' 2>/dev/null) ;;
esac
[ -z "$CURRENT_SESSION" ] && exit 0
[ -d "$STATE_DIR" ] || exit 0
for fpath in "$STATE_DIR"/p*; do
  [ -f "$fpath" ] || continue
  IFS=$'\t' read -r sess st epoch < "$fpath"
  [ "$sess" = "$CURRENT_SESSION" ] && rm -f "$fpath"
done
exit 0
