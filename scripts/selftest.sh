#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/state.sh"
PASS_COUNT=0; FAIL_COUNT=0
assert_eq() { if [ "$2" = "$3" ]; then echo "PASS: $1"; ((PASS_COUNT++)); else echo "FAIL: $1"; echo "  expected: $2"; echo "  actual:   $3"; ((FAIL_COUNT++)); fi; }
assert_file_exists() { if [ -f "$2" ]; then echo "PASS: $1"; ((PASS_COUNT++)); else echo "FAIL: $1 (missing $2)"; ((FAIL_COUNT++)); fi; }
assert_file_absent() { if [ ! -f "$2" ]; then echo "PASS: $1"; ((PASS_COUNT++)); else echo "FAIL: $1 (present $2)"; ((FAIL_COUNT++)); fi; }

TEST_STATE_DIR=$(mktemp -d); STATE_DIR="$TEST_STATE_DIR"
trap 'rm -rf "$TEST_STATE_DIR"' EXIT

assert_eq "rank wait=3" "3" "$(_urgency_rank wait)"
assert_eq "rank done=2" "2" "$(_urgency_rank done)"
assert_eq "rank busy=1" "1" "$(_urgency_rank busy)"
assert_eq "rank unknown=0" "0" "$(_urgency_rank "")"

state_write "%10" "proj-a" "busy"
assert_file_exists "write creates file" "$STATE_DIR/p10"
IFS=$'\t' read -r s st ep < "$STATE_DIR/p10"
assert_eq "write session" "proj-a" "$s"
assert_eq "write state" "busy" "$st"

state_write "%11" "proj-b" "done"; state_remove "%11"
assert_file_absent "remove deletes file" "$STATE_DIR/p11"

state_write "%20" "proj-c" "busy"; state_write "%21" "proj-c" "done"; state_write "%22" "proj-c" "wait"
assert_eq "wait beats done beats busy" "wait" "$(state_for_session proj-c)"

state_write "%30" "proj-d" "done"; state_write "%31" "proj-e" "wait"
out=$(state_aggregate "proj-d")
assert_eq "aggregate excludes session keeps other" "proj-e	wait" "$(echo "$out" | grep proj-e)"
if echo "$out" | grep -q proj-d; then echo "FAIL: aggregate should exclude proj-d"; ((FAIL_COUNT++)); else echo "PASS: aggregate excludes proj-d"; ((PASS_COUNT++)); fi

# NOTE: state_prune relies on `tmux list-panes -a` (ambient socket). When not inside tmux it returns empty,
# which would prune everything — so prune correctness is only asserted in the integration section.
if [ -z "$TMUX" ]; then
  echo "NOTE: integration tests skipped (not inside tmux)."
else
  SOCKET="aiws_test_$$"; SA="aiws-a-$$"; SB="aiws-b-$$"; INT_DIR=$(mktemp -d)
  trap 'tmux -L "$SOCKET" kill-server 2>/dev/null; rm -rf "$TEST_STATE_DIR" "$INT_DIR"' EXIT INT TERM
  tmux -L "$SOCKET" new-session -d -s "$SA"; tmux -L "$SOCKET" new-session -d -s "$SB"
  PANE_A=$(tmux -L "$SOCKET" list-panes -t "$SA" -F '#{pane_id}' | head -1)
  # prune must KEEP a live pane and DROP a dead one — but state_prune queries the AMBIENT tmux, not -L socket.
  # So this is a best-effort note rather than a hard assertion in v1.
  echo "NOTE: live-server present; prune uses ambient socket (documented limitation)."

  # Regression: a sidebar spawned (un-focused, -d) into ANOTHER session must
  # identify its OWN pane via $TMUX_PANE — NOT the active workspace pane that
  # `display-message` would return. This is the bug that made jumps kill a
  # workspace pane and collapse sessions.
  ID_FILE="$INT_DIR/id"
  RECORD="$INT_DIR/record.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "$TMUX_PANE" > "%s"\nsleep 5\n' "$ID_FILE" > "$RECORD"; chmod +x "$RECORD"
  REAL_NEW=$(tmux -L "$SOCKET" split-window -hb -d -t "$SB" -P -F '#{pane_id}' "$RECORD")
  sleep 1
  assert_eq "sidebar self-identifies via TMUX_PANE" "$REAL_NEW" "$(cat "$ID_FILE" 2>/dev/null)"
  WRONG=$(tmux -L "$SOCKET" display-message -t "$SB" -p '#{pane_id}')
  if [ "$WRONG" != "$REAL_NEW" ]; then echo "PASS: display-message mis-identifies the pane (original bug reproduced)"; ((PASS_COUNT++)); else echo "NOTE: display-message coincidentally matched this run"; fi

  # safe_kill_sidebar_pane guards: route the helper's bare `tmux` calls at the
  # test server, then restore the global wrapper.
  tmux() { command tmux -L "$SOCKET" "$@"; }
  KP=$(command tmux -L "$SOCKET" list-panes -t "$SA" -F '#{pane_id}' | head -1)
  if safe_kill_sidebar_pane "$KP"; then echo "FAIL: killed an unmarked sole pane"; ((FAIL_COUNT++)); else echo "PASS: refuses unmarked pane"; ((PASS_COUNT++)); fi
  command tmux -L "$SOCKET" set-option -p -t "$KP" "@ai_sidebar" "1"
  if safe_kill_sidebar_pane "$KP"; then echo "FAIL: killed a sole marked pane (would collapse window/session)"; ((FAIL_COUNT++)); else echo "PASS: refuses sole pane even when marked"; ((PASS_COUNT++)); fi
  SIDE=$(command tmux -L "$SOCKET" split-window -d -t "$KP" -P -F '#{pane_id}')
  command tmux -L "$SOCKET" set-option -p -t "$SIDE" "@ai_sidebar" "1"
  if safe_kill_sidebar_pane "$SIDE"; then echo "PASS: kills a marked, non-sole sidebar"; ((PASS_COUNT++)); else echo "FAIL: refused a valid sidebar kill"; ((FAIL_COUNT++)); fi
  assert_eq "workspace pane survives sidebar kill" "1" "$(command tmux -L "$SOCKET" list-panes -t "$KP" -F x 2>/dev/null | grep -c x)"
  unset -f tmux

  tmux -L "$SOCKET" kill-server 2>/dev/null
fi

echo "---"; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
