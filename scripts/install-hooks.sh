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

EPOCH=$(date +%s)
cp "$SETTINGS" "${SETTINGS}.bak.${EPOCH}"
echo "Backed up to ${SETTINGS}.bak.${EPOCH}"

already_present() {
  local hook_type="$1" command="$2"
  jq -e --arg ht "$hook_type" --arg cmd "$command" \
    '[.hooks[$ht] // [] | .[] | .hooks // [] | .[] | select(.command == $cmd)] | length > 0' \
    "$SETTINGS" 2>/dev/null | grep -q true
}
add_hook_entry() {
  local hook_type="$1" command="$2" new_entry tmp
  new_entry=$(jq -n --arg cmd "$command" '{"matcher":".*","hooks":[{"type":"command","command":$cmd}]}')
  tmp=$(mktemp)
  jq --arg ht "$hook_type" --argjson entry "$new_entry" '.hooks[$ht] = ((.hooks[$ht] // []) + [$entry])' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

declare -a PAIRS=( "UserPromptSubmit|$HOOK_SCRIPT busy" "Stop|$HOOK_SCRIPT done" "Notification|$HOOK_SCRIPT wait" "SessionEnd|$HOOK_SCRIPT remove" )
for pair in "${PAIRS[@]}"; do
  ht="${pair%%|*}"; cmd="${pair#*|}"
  if already_present "$ht" "$cmd"; then
    echo "Already present: $ht"
  else
    add_hook_entry "$ht" "$cmd"; echo "Added $ht -> $cmd"
  fi
done
echo "Install complete. Restart Claude Code to activate hooks."
