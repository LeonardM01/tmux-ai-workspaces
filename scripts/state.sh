#!/usr/bin/env bash
_resolve_state_dir() {
  if [ -n "$TMUX" ]; then
    local opt; opt=$(tmux show-option -gqv "@ai_state_dir" 2>/dev/null)
    if [ -n "$opt" ]; then echo "$opt"; return; fi
  fi
  echo "${TMPDIR:-/tmp}/tmux-ai"
}
STATE_DIR="$(_resolve_state_dir)"

_sanitize_pane_id() { echo "${1//%/p}"; }

state_write() {
  local pane_id="$1" session="$2" state="$3" epoch
  epoch=$(date +%s)
  mkdir -p "$STATE_DIR"
  local fname="$STATE_DIR/$(_sanitize_pane_id "$pane_id")"
  # Write atomically: a reader (status bar, aggregate) must never observe the
  # truncate-then-write window of a plain `>`. Temp files are dotfiles, so the
  # "$STATE_DIR"/p* globs elsewhere never pick them up.
  local tmp; tmp=$(mktemp "$STATE_DIR/.tmp.XXXXXX") || return 1
  printf '%s\t%s\t%s\n' "$session" "$state" "$epoch" > "$tmp"
  mv -f "$tmp" "$fname"
}

state_remove() { rm -f "$STATE_DIR/$(_sanitize_pane_id "$1")"; }

# Kill a pane ONLY when it is still marked as a sidebar right now AND is not the
# sole pane in its window. A correctly-marked sidebar is always a split beside a
# workspace pane, so a sole-pane match means the id is wrong (the old pane-
# misidentification bug) — refusing the kill then prevents collapsing a window
# or a whole session. Returns 0 if it killed the pane, 1 if it refused.
safe_kill_sidebar_pane() {
  local pane="$1"; [ -n "$pane" ] || return 1
  local marked; marked=$(tmux display-message -p -t "$pane" '#{@ai_sidebar}' 2>/dev/null) || return 1
  [ "$marked" = "1" ] || return 1
  local count; count=$(tmux list-panes -t "$pane" -F '#{pane_id}' 2>/dev/null | grep -c .)
  [ "${count:-0}" -gt 1 ] || return 1
  tmux kill-pane -t "$pane" 2>/dev/null
}

state_prune() {
  [ -d "$STATE_DIR" ] || return 0
  # Without an ambient tmux server we cannot enumerate live panes; pruning then
  # would delete ALL state. Skip pruning entirely when not inside tmux.
  [ -n "$TMUX" ] || return 0
  local live_panes; live_panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  for fpath in "$STATE_DIR"/p*; do
    [ -f "$fpath" ] || continue
    local fname="${fpath##*/}"; local pane_id="%${fname#p}"
    if ! echo "$live_panes" | grep -qxF "$pane_id"; then rm -f "$fpath"; fi
  done
}

_urgency_rank() {
  case "$1" in wait) echo 3;; done) echo 2;; busy) echo 1;; *) echo 0;; esac
}

# Emits one line per session: "session<TAB>highest-urgency-state".
# Urgency order: wait > done > busy. awk owns the per-session map so this stays
# bash 3.2 compatible (no associative arrays).
state_aggregate() {
  local exclude="${1:-}" fpath
  state_prune
  [ -d "$STATE_DIR" ] || return 0
  for fpath in "$STATE_DIR"/p*; do
    [ -f "$fpath" ] || continue
    cat "$fpath"
  done | awk -F'\t' -v exclude="$exclude" '
    function rank(s){ if(s=="wait")return 3; if(s=="done")return 2; if(s=="busy")return 1; return 0 }
    {
      sess=$1; st=$2
      if (sess=="" || sess==exclude) next
      r=rank(st)
      if (!(sess in best) || r>best[sess]) { best[sess]=r; bstate[sess]=st }
    }
    END { for (s in bstate) printf "%s\t%s\n", s, bstate[s] }
  '
}

state_for_session() {
  local target="$1"; state_prune
  [ -d "$STATE_DIR" ] || return 0
  local best_rank=0 best_state=""
  for fpath in "$STATE_DIR"/p*; do
    [ -f "$fpath" ] || continue
    IFS=$'\t' read -r sess st epoch < "$fpath"
    [ "$sess" = "$target" ] || continue
    local rank; rank=$(_urgency_rank "$st")
    if [ "$rank" -gt "$best_rank" ]; then best_rank=$rank; best_state=$st; fi
  done
  echo "$best_state"
}
