#!/usr/bin/env bash
SIDEBAR_PANE="${1:-}"; TARGET_SESSION="${2:-}"
[ -z "$TARGET_SESSION" ] && exit 1
[ -n "$SIDEBAR_PANE" ] && tmux kill-pane -t "$SIDEBAR_PANE" 2>/dev/null || true
tmux switch-client -t "$TARGET_SESSION"
