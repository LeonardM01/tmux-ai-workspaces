#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
SIDEBAR_PANE="${1:-}"; TARGET_SESSION="${2:-}"
[ -z "$TARGET_SESSION" ] && exit 1

WIDTH=$(tmux show-option -gqv "@ai_sidebar_width"); WIDTH="${WIDTH:-24}"

# Remove any sidebar that already exists in the target session (avoid dupes when
# hopping back and forth). safe_kill_sidebar_pane re-checks the @ai_sidebar mark
# and refuses to kill a sole pane, so a mislabeled workspace pane is never taken.
for p in $(tmux list-panes -s -t "$TARGET_SESSION" -F '#{pane_id} #{@ai_sidebar}' 2>/dev/null | awk '$2=="1"{print $1}'); do
  [ "$p" = "$SIDEBAR_PANE" ] && continue
  safe_kill_sidebar_pane "$p"
done

# Spawn a fresh sidebar in the target session WITHOUT focusing it (-d), so the
# user lands in their workspace with the sidebar still visible on the left. The
# new pane identifies itself from $TMUX_PANE; we capture its id here (-P -F) so
# we only retire the old sidebar once the replacement actually exists.
NEW_PANE=$(tmux split-window -fhb -d -l "$WIDTH" -t "$TARGET_SESSION" -P -F '#{pane_id}' "$SCRIPT_DIR/sidebar.sh")

# Move the client to the target session. (No -c client target: single-client use
# is assumed; with multiple clients this switches the ambiguous "current" one.)
# If the target vanished between keypress and now, switch fails — bail without
# touching the old sidebar so the user keeps a working one where they are.
if ! tmux switch-client -t "$TARGET_SESSION" 2>/dev/null; then
  [ -n "$NEW_PANE" ] && safe_kill_sidebar_pane "$NEW_PANE"
  exit 1
fi

# Finally drop the old sidebar pane in the previous session — but only once the
# replacement exists, and only through the guarded kill so we can never take a
# workspace pane or the last pane of a window with it. Done last: this script
# runs inside that pane, so killing it earlier would terminate us mid-flight.
[ -n "$NEW_PANE" ] && [ -n "$SIDEBAR_PANE" ] && safe_kill_sidebar_pane "$SIDEBAR_PANE"
exit 0
