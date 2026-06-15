#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-popup -E "bash -c \"printf '%s\n\n%s\n' 'fzf not found.' 'Install fzf to use the popup picker (e.g. brew install fzf).'; printf 'Press any key to close...'; read -rsn1\""
  exit 0
fi

W=$(tmux show-option -gqv "@ai_popup_width");  W="${W:-80%}"
H=$(tmux show-option -gqv "@ai_popup_height"); H="${H:-80%}"

tmux display-popup -w "$W" -h "$H" -E "$SCRIPT_DIR/picker.sh"
