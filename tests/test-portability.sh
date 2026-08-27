#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for portable_script in \
  "$script_dir/../git/worktree-links.sh" \
  "$script_dir/../lib/requirements.sh"; do
  if grep -E 'declare[[:space:]]+-A|mapfile|readarray' "$portable_script" >/dev/null; then
    echo "FAIL: $(basename "$portable_script") contains a Bash-4-only construct" >&2
    exit 1
  fi
  if grep -F '< <(' "$portable_script" >/dev/null; then
    echo "FAIL: $(basename "$portable_script") contains process substitution" >&2
    exit 1
  fi
done

echo "PASS: portable shared-script syntax tests"
