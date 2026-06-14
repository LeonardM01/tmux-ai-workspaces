#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK_SCRIPT="$PLUGIN_DIR/scripts/claude-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Add these entries manually to ~/.claude/settings.json:"
  cat "$PLUGIN_DIR/hooks/settings-snippet.json"
  exit 1
fi
if [ ! -f "$SETTINGS" ]; then
  echo "No settings file at $SETTINGS"; exit 1
fi
# Refuse to touch a file that isn't valid JSON — appending to it would either
# fail silently or corrupt it further.
if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "Error: $SETTINGS is not valid JSON. Aborting; no changes made."; exit 1
fi

EPOCH=$(date +%s)
cp "$SETTINGS" "${SETTINGS}.bak.${EPOCH}"
echo "Backed up to ${SETTINGS}.bak.${EPOCH}"

# Match on a stable substring (script name + state), not the full absolute path:
# a path spelled differently (symlink vs realpath, or the manual-snippet form)
# must still count as present, otherwise re-running adds a duplicate hook.
already_present() {
  local hook_type="$1" match="$2"
  jq -e --arg ht "$hook_type" --arg m "$match" \
    '[.hooks[$ht] // [] | .[] | .hooks // [] | .[] | select((.command // "") | contains($m))] | length > 0' \
    "$SETTINGS" 2>/dev/null | grep -q true
}
add_hook_entry() {
  local hook_type="$1" command="$2" new_entry tmp
  new_entry=$(jq -n --arg cmd "$command" '{"matcher":".*","hooks":[{"type":"command","command":$cmd}]}') || return 1
  tmp=$(mktemp) || return 1
  if jq --arg ht "$hook_type" --argjson entry "$new_entry" \
      '.hooks[$ht] = ((.hooks[$ht] // []) + [$entry])' "$SETTINGS" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$SETTINGS" || { rm -f "$tmp"; return 1; }
  else
    rm -f "$tmp"; return 1
  fi
}

declare -a PAIRS=( "UserPromptSubmit|$HOOK_SCRIPT busy" "Stop|$HOOK_SCRIPT done" "Notification|$HOOK_SCRIPT wait" "SessionEnd|$HOOK_SCRIPT remove" )
FAILED=0
for pair in "${PAIRS[@]}"; do
  ht="${pair%%|*}"; cmd="${pair#*|}"
  match="claude-hook.sh ${cmd##* }"   # e.g. "claude-hook.sh busy"
  if already_present "$ht" "$match"; then
    echo "Already present: $ht"
  elif add_hook_entry "$ht" "$cmd"; then
    echo "Added $ht -> $cmd"
  else
    echo "FAILED to add $ht (jq/write error)"; FAILED=1
  fi
done
if [ "$FAILED" -eq 0 ]; then
  echo "Install complete. Restart Claude Code to activate hooks."
else
  echo "Install finished WITH ERRORS — some hooks were not added. Restore from ${SETTINGS}.bak.${EPOCH} if needed."
  exit 1
fi
