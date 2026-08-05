#!/usr/bin/env bash

# Sourceable command checks for portable Codex launcher workflows.
# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

mikebd_launcher_require_command() {
  local command_name="$1"
  local hint="${2:-}"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  echo "error: required command is unavailable: $command_name" >&2
  [ -n "$hint" ] && echo "hint: $hint" >&2
  return 1
}

mikebd_launcher_require_git() {
  mikebd_launcher_require_command git
}

mikebd_launcher_require_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi

  echo "error: jq is required for reliable fork-session metadata parsing" >&2
  if command -v brew >/dev/null 2>&1; then
    echo "hint: install it with: brew install jq" >&2
  else
    echo "hint: install jq using your platform's package manager" >&2
  fi
  return 1
}

mikebd_launcher_require_codex() {
  mikebd_launcher_require_command "${CODEX_BIN:-codex}"
}
