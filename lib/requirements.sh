#!/usr/bin/env bash

# Sourceable command checks for portable shared shell workflows.
# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

mikebd_require_command() {
  local command_name="$1"
  local hint="${2:-}"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  echo "error: required command is unavailable: $command_name" >&2
  [ -n "$hint" ] && echo "hint: $hint" >&2
  return 1
}

mikebd_require_git() {
  mikebd_require_command git
}
