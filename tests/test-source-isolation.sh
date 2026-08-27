#!/usr/bin/env bash

set -euo pipefail

test_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mikebd_bash_scripts_source_isolation_assert() {
  local name="$1"
  local actual="$2"
  local expected="$3"

  [ "$actual" = "$expected" ] || {
    echo "FAIL: $name changed from $expected to $actual" >&2
    exit 1
  }
}

(
  script_dir="caller-script-dir"
  scripts_root="caller-scripts-root"
  repo_root="caller-repo-root"
  tmp_root="caller-tmp-root"
  trap ':' EXIT
  expected_exit_trap="$(trap -p EXIT)"
  expected_shell_options="$(set -o)"
  # shellcheck source=../lib/requirements.sh disable=SC1091
  source "$test_script_dir/../lib/requirements.sh"
  mikebd_bash_scripts_source_isolation_assert script_dir "$script_dir" caller-script-dir
  mikebd_bash_scripts_source_isolation_assert scripts_root "$scripts_root" caller-scripts-root
  mikebd_bash_scripts_source_isolation_assert repo_root "$repo_root" caller-repo-root
  mikebd_bash_scripts_source_isolation_assert tmp_root "$tmp_root" caller-tmp-root
  mikebd_bash_scripts_source_isolation_assert exit_trap "$(trap -p EXIT)" "$expected_exit_trap"
  mikebd_bash_scripts_source_isolation_assert shell_options "$(set -o)" "$expected_shell_options"

  # shellcheck source=../git/worktree-links.sh disable=SC1091
  source "$test_script_dir/../git/worktree-links.sh"
  mikebd_bash_scripts_source_isolation_assert script_dir "$script_dir" caller-script-dir
  mikebd_bash_scripts_source_isolation_assert scripts_root "$scripts_root" caller-scripts-root
  mikebd_bash_scripts_source_isolation_assert repo_root "$repo_root" caller-repo-root
  mikebd_bash_scripts_source_isolation_assert tmp_root "$tmp_root" caller-tmp-root
  mikebd_bash_scripts_source_isolation_assert exit_trap "$(trap -p EXIT)" "$expected_exit_trap"
  mikebd_bash_scripts_source_isolation_assert shell_options "$(set -o)" "$expected_shell_options"
)

echo "PASS: source-isolation tests"
