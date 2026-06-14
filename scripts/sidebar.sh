#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"

RESET='\033[0m'; BOLD='\033[1m'
FG_YELLOW='\033[38;5;226m'; FG_GREEN='\033[38;5;82m'; FG_GRAY='\033[38;5;244m'
FG_WHITE='\033[38;5;255m'; FG_PEACH='\033[38;5;215m'; FG_OVERLAY='\033[38;5;238m'
CLEAR_SCREEN='\033[2J\033[H'

MY_PANE=$(tmux display-message -p '#{pane_id}')
tmux set-option -p -t "$MY_PANE" "@ai_sidebar" "1"
printf '\033]2;ai-sidebar\007'

SESSION_LIST=()
render() {
  local current_session sessions agg
  current_session=$(tmux display-message -p '#{session_name}')
  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  # "session<TAB>state" lines; looked up per row via awk (bash 3.2 safe).
  agg=$(state_aggregate "")
  printf '%b' "$CLEAR_SCREEN"
  printf '%b  AI Sessions%b\n' "${BOLD}${FG_PEACH}" "$RESET"
  printf '%b----------------------%b\n' "$FG_OVERLAY" "$RESET"
  local idx=1; SESSION_LIST=()
  while IFS= read -r sess; do
    [ -z "$sess" ] && continue
    SESSION_LIST+=("$sess")
    local st dot color flag=""
    st=$(printf '%s\n' "$agg" | awk -F'\t' -v s="$sess" '$1==s{print $2; exit}')
    case "$st" in
      wait) color="$FG_YELLOW"; dot="●"; flag=" ⚑";;
      done) color="$FG_GREEN"; dot="●"; flag="";;
      busy) color="$FG_GRAY"; dot="○"; flag="";;
      *) color="$FG_OVERLAY"; dot="○"; flag="";;
    esac
    if [ "$sess" = "$current_session" ]; then
      printf '%b %d %b%s%b %b%s%b%s\n' "${BOLD}${FG_WHITE}" "$idx" "$color" "$dot" "$RESET" "${BOLD}${FG_PEACH}" "$sess" "$RESET" "$flag"
    else
      printf '%b %d %b%s%b %b%s%b%s\n' "$FG_OVERLAY" "$idx" "$color" "$dot" "$RESET" "$FG_WHITE" "$sess" "$RESET" "$flag"
    fi
    idx=$((idx+1)); [ "$idx" -gt 9 ] && break
  done <<< "$sessions"
  printf '\n%b[q] close  [1-9] jump%b\n' "$FG_OVERLAY" "$RESET"
}

while true; do
  render
  key=""
  read -t 1 -rsn1 key; rc=$?
  if [ $rc -eq 0 ]; then
    case "$key" in
      q|Q) tmux kill-pane -t "$MY_PANE"; exit 0 ;;
      $'\x1b') read -t 1 -rsn10 _ 2>/dev/null; tmux kill-pane -t "$MY_PANE"; exit 0 ;;
      [1-9])
        target_idx=$((key-1))
        if [ "$target_idx" -lt "${#SESSION_LIST[@]}" ]; then
          "$SCRIPT_DIR/jump.sh" "$MY_PANE" "${SESSION_LIST[$target_idx]}"; exit 0
        fi ;;
    esac
  fi
done
