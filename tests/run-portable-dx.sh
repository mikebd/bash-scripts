#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for test_script in \
  test-requirements.sh \
  test-source-isolation.sh \
  test-worktree-links.sh \
  test-portability.sh; do
  bash "$script_dir/$test_script"
done

echo "PASS: all portable DX tests"
