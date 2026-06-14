#!/usr/bin/env bash
SIDEBAR_PANE="${1:-}"; TARGET_SESSION="${2:-}"
[ -z "$TARGET_SESSION" ] && exit 1
# Switch FIRST. This script runs inside the sidebar pane, so killing that pane
# before switching would terminate this process before switch-client executes
# (the original bug: sidebar closed but the client never moved). switch-client
# only changes the client's view, leaving this process alive to clean up.
tmux switch-client -t "$TARGET_SESSION"
[ -n "$SIDEBAR_PANE" ] && tmux kill-pane -t "$SIDEBAR_PANE" 2>/dev/null || true
