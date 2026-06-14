#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"

RESET='\033[0m'; BOLD='\033[1m'
FG_YELLOW='\033[38;5;226m'; FG_GREEN='\033[38;5;82m'; FG_GRAY='\033[38;5;244m'
FG_WHITE='\033[38;5;255m'; FG_PEACH='\033[38;5;215m'; FG_OVERLAY='\033[38;5;238m'
HOME_POS='\033[H'      # cursor to top-left (no full-screen wipe)
CLEAR_BELOW='\033[0J'  # clear from cursor to end of screen

# Identify our own pane from $TMUX_PANE (set by tmux for every pane) or the
# explicit arg from jump.sh. Do NOT fall back to `display-message -p` — that
# returns the session's ACTIVE pane, which is the exact bug that made the sidebar
# mark and later kill a workspace pane. If we can't know our pane, refuse to run.
MY_PANE="${1:-${TMUX_PANE:-}}"
if [ -z "$MY_PANE" ]; then
  echo "ai-sidebar: cannot determine own pane id (TMUX_PANE unset); refusing to start" >&2
  exit 1
fi
tmux set-option -p -t "$MY_PANE" "@ai_sidebar" "1"
printf '\033]2;ai-sidebar\007'

# Hide the cursor while the sidebar is up; restore it whenever we leave.
printf '\033[?25l'
restore_cursor() { printf '\033[?25h'; }
trap restore_cursor EXIT

SESSION_LIST=()

# Builds the whole frame into one string and paints it in a single write,
# anchored at home with a clear-below — no full-screen wipe, so no flicker.
render() {
  local current_session sessions agg idx sess st dot color flag buf
  current_session=$(tmux display-message -p -t "$MY_PANE" '#{session_name}')
  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  agg=$(state_aggregate "")
  buf="${BOLD}${FG_PEACH}  AI Sessions${RESET}\n"
  buf="${buf}${FG_OVERLAY}----------------------${RESET}\n"
  idx=1; SESSION_LIST=()
  while IFS= read -r sess; do
    [ -z "$sess" ] && continue
    SESSION_LIST+=("$sess")
    st=$(printf '%s\n' "$agg" | awk -F'\t' -v s="$sess" '$1==s{print $2; exit}')
    case "$st" in
      wait) color="$FG_YELLOW"; dot="●"; flag=" ⚑";;
      done) color="$FG_GREEN"; dot="●"; flag="";;
      busy) color="$FG_GRAY"; dot="○"; flag="";;
      *) color="$FG_OVERLAY"; dot="○"; flag="";;
    esac
    if [ "$sess" = "$current_session" ]; then
      buf="${buf}${BOLD}${FG_WHITE} ${idx} ${color}${dot}${RESET} ${BOLD}${FG_PEACH}${sess}${RESET}${flag}\n"
    else
      buf="${buf}${FG_OVERLAY} ${idx} ${color}${dot}${RESET} ${FG_WHITE}${sess}${RESET}${flag}\n"
    fi
    idx=$((idx+1)); [ "$idx" -gt 9 ] && break
  done <<< "$sessions"
  buf="${buf}\n${FG_OVERLAY}[1-9] jump   [q] close${RESET}\n"
  printf '%b' "${HOME_POS}${buf}${CLEAR_BELOW}"
}

# Cheap signature of everything the frame depends on. We only repaint when it
# changes, so an idle sidebar sits perfectly still (no per-second twitch).
compute_sig() {
  printf '%s|%s|%s' \
    "$(tmux display-message -p -t "$MY_PANE" '#{session_name}' 2>/dev/null)" \
    "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" \
    "$(state_aggregate '')"
}

printf '\033[2J'   # one full clear on startup
prev_sig="__init__"
while true; do
  sig="$(compute_sig)"
  if [ "$sig" != "$prev_sig" ]; then
    render
    prev_sig="$sig"
  fi
  key=""
  # `read -t` only accepts whole seconds on bash 3.2 (macOS system bash), so 1s
  # is the floor — do not "optimize" to a fractional timeout, it breaks there.
  read -t 1 -rsn1 key; rc=$?
  if [ $rc -eq 0 ]; then
    case "$key" in
      q|Q) restore_cursor; safe_kill_sidebar_pane "$MY_PANE"; exit 0 ;;
      # Bare Esc closes. No need to drain the rest of an escape sequence first —
      # we exit and the pane is killed regardless, so draining only added a 1s
      # stall on a lone Esc (bash 3.2 can't time out faster).
      $'\x1b') restore_cursor; safe_kill_sidebar_pane "$MY_PANE"; exit 0 ;;
      [1-9])
        target_idx=$((key-1))
        if [ "$target_idx" -lt "${#SESSION_LIST[@]}" ]; then
          # jump.sh keeps the sidebar alive by re-spawning it in the target
          # session; this instance exits as its pane is replaced.
          "$SCRIPT_DIR/jump.sh" "$MY_PANE" "${SESSION_LIST[$target_idx]}"
          exit 0
        fi ;;
    esac
  fi
done
