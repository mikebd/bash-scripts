#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/requirements.sh disable=SC1091
source "$script_dir/../lib/requirements.sh"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mikebd-requirements-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

missing_command="mikebd-requirements-command-that-does-not-exist"
hint="install the test command"

mikebd_require_command git
mikebd_require_git

if mikebd_require_command "$missing_command" >"$tmp_root/missing-output" 2>&1; then
  echo "FAIL: missing command succeeded" >&2
  exit 1
fi
grep -Fqx "error: required command is unavailable: $missing_command" "$tmp_root/missing-output" || {
  echo "FAIL: missing-command diagnostic changed" >&2
  exit 1
}

if mikebd_require_command "$missing_command" "$hint" >"$tmp_root/hint-output" 2>&1; then
  echo "FAIL: missing command with hint succeeded" >&2
  exit 1
fi
grep -Fqx "error: required command is unavailable: $missing_command" "$tmp_root/hint-output" || {
  echo "FAIL: hinted missing-command diagnostic changed" >&2
  exit 1
}
grep -Fqx "hint: $hint" "$tmp_root/hint-output" || {
  echo "FAIL: missing-command hint changed" >&2
  exit 1
}

echo "PASS: generic requirement tests"
