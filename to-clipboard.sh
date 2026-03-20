#!/usr/bin/env bash
set -euo pipefail

# Copy stdin, text args, or a file's contents to the system clipboard.
# A symlink from ~/.local/bin/cb to this script is expected to exist so other
# scripts can call `cb` as a stable clipboard command.
if [ "$#" -eq 1 ] && [ -f "$1" ]; then
  data="$(cat -- "$1")"
elif [ "$#" -gt 0 ]; then
  data="$*"
else
  data="$(cat)"
fi

if [ -n "${TMUX:-}" ]; then
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$data" | wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$data" | xclip -selection clipboard
  else
    printf '%s\n' "cb: install wl-clipboard or xclip for tmux clipboard" >&2
    exit 1
  fi
else
  printf '%s' "$data" | kitty +kitten clipboard
fi
