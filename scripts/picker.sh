#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state.sh"

# Humanize an age given an epoch and a reference "now". Empty/invalid -> "-".
_age_human() {
  local epoch="$1" now="$2" diff
  case "$epoch" in ''|*[!0-9]*) printf '%s' "-"; return 0 ;; esac
  diff=$(( now - epoch ))
  [ "$diff" -lt 0 ] && diff=0
  if [ "$diff" -lt 60 ]; then printf '%ds' "$diff"
  elif [ "$diff" -lt 3600 ]; then printf '%dm' "$(( diff / 60 ))"
  elif [ "$diff" -lt 86400 ]; then printf '%dh' "$(( diff / 3600 ))"
  else printf '%dd' "$(( diff / 86400 ))"; fi
}

# Emit one TAB row per session: rank<TAB>session<TAB>icon<TAB>path<TAB>age.
# rank lets the caller float wait>done>busy to the top. Accepts an optional
# `now` epoch so the suite can assert ages deterministically.
picker_rows() {
  local now="${1:-}"
  [ -z "$now" ] && now=$(date +%s)
  local agg sess st rank icon path epoch age
  agg=$(state_aggregate "")
  while IFS=$'\t' read -r sess st; do
    [ -z "$sess" ] && continue
    rank=$(_urgency_rank "$st")
    case "$st" in
      wait) icon="● wait" ;;
      done) icon="● done" ;;
      busy) icon="○ busy" ;;
      *)    icon="○ ----" ;;
    esac
    path=""
    if [ -n "${TMUX:-}" ]; then
      path=$(tmux display-message -p -t "$sess" '#{pane_current_path}' 2>/dev/null)
    fi
    epoch=$(state_latest_epoch_for_session "$sess")
    age=$(_age_human "$epoch" "$now")
    printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$sess" "$icon" "$path" "$age"
  done <<EOF
$agg
EOF
}

if [ "${1:-}" = "--rows" ]; then picker_rows | sort -t$'\t' -k1,1nr; exit 0; fi

# Interactive entry point — only when executed, never when sourced by the suite.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  selection=$(picker_rows | sort -t$'\t' -k1,1nr \
    | fzf --ansi --delimiter='\t' --with-nth=3,4,5 \
          --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload(bash $SCRIPT_DIR/picker.sh --rows)" \
          --header='enter: switch   ctrl-x: kill')
  [ -z "$selection" ] && exit 0
  target=$(printf '%s' "$selection" | cut -f2)
  [ -n "$target" ] && tmux switch-client -t "$target"
fi
