#!/usr/bin/env bash

set -euo pipefail

mikebd_bash_scripts_test_primary=""
mikebd_bash_scripts_test_target=""
mikebd_bash_scripts_test_tmp_root=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-lib.sh disable=SC1091
source "$script_dir/test-lib.sh"
trap 'mikebd_bash_scripts_test_cleanup' EXIT

mikebd_bash_scripts_test_setup_fixture
mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --target "$mikebd_bash_scripts_test_target" >"$mikebd_bash_scripts_test_tmp_root/link-output"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/.context" "$mikebd_bash_scripts_test_primary/.context"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/Procfile.local" "$mikebd_bash_scripts_test_primary/Procfile.local"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/service/.env.local" "$mikebd_bash_scripts_test_primary/service/.env.local"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/service/.air.toml" "$mikebd_bash_scripts_test_primary/service/.air.toml"
[ ! -e "$mikebd_bash_scripts_test_target/.env.root" ] || mikebd_bash_scripts_test_fail "root env file was linked"
[ ! -e "$mikebd_bash_scripts_test_target/service/deep/.env.deep" ] || mikebd_bash_scripts_test_fail "deep env file was linked"

mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --target "$mikebd_bash_scripts_test_target" >"$mikebd_bash_scripts_test_tmp_root/link-output-second"
mikebd_bash_scripts_test_assert_file_contains "$mikebd_bash_scripts_test_tmp_root/link-output-second" "skipped_existing=4"

dry_target="$mikebd_bash_scripts_test_tmp_root/dry-run-worktree"
git -C "$mikebd_bash_scripts_test_primary" worktree add -q -b feature/dry-run "$dry_target" HEAD
mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --dry-run --target "$dry_target" >"$mikebd_bash_scripts_test_tmp_root/dry-run-output"
mikebd_bash_scripts_test_assert_file_contains "$mikebd_bash_scripts_test_tmp_root/dry-run-output" "DRY-RUN link:"
[ ! -e "$dry_target/.context" ] || mikebd_bash_scripts_test_fail "dry run created a link"

mkdir -p "$mikebd_bash_scripts_test_target/service"
if mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --target "$mikebd_bash_scripts_test_target/service" >"$mikebd_bash_scripts_test_tmp_root/subdirectory-target-output" 2>&1; then
  mikebd_bash_scripts_test_fail "worktree-link setup accepted a target subdirectory"
fi
mikebd_bash_scripts_test_assert_file_contains "$mikebd_bash_scripts_test_tmp_root/subdirectory-target-output" "target must be a Git worktree root"

mkdir -p "$mikebd_bash_scripts_test_primary/blocked"
printf 'blocked source\n' >"$mikebd_bash_scripts_test_primary/blocked/source"
printf 'blocked target\n' >"$mikebd_bash_scripts_test_target/blocked"
mikebd_bash_scripts_test_failure_rules() {
  mikebd_worktree_links_add_relative blocked/source || true
  mikebd_worktree_links_add_relative .context
}
if mikebd_worktree_links_main mikebd_bash_scripts_test_failure_rules --target "$mikebd_bash_scripts_test_target" >"$mikebd_bash_scripts_test_tmp_root/link-failure-output" 2>&1; then
  mikebd_bash_scripts_test_fail "worktree-link setup succeeded after a link failure"
fi
if grep -Fq "summary:" "$mikebd_bash_scripts_test_tmp_root/link-failure-output"; then
  mikebd_bash_scripts_test_fail "worktree-link setup printed a success summary after a link failure"
fi

echo "PASS: generic worktree-link tests"
