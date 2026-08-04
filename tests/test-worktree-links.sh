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
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/.context"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/Procfile.local"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/service/.env.local"
mikebd_bash_scripts_test_assert_symlink "$mikebd_bash_scripts_test_target/service/.air.toml"
[ ! -e "$mikebd_bash_scripts_test_target/.env.root" ] || mikebd_bash_scripts_test_fail "root env file was linked"
[ ! -e "$mikebd_bash_scripts_test_target/service/deep/.env.deep" ] || mikebd_bash_scripts_test_fail "deep env file was linked"

mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --target "$mikebd_bash_scripts_test_target" >"$mikebd_bash_scripts_test_tmp_root/link-output-second"
mikebd_bash_scripts_test_assert_file_contains "$mikebd_bash_scripts_test_tmp_root/link-output-second" "skipped_existing=4"

dry_target="$mikebd_bash_scripts_test_tmp_root/dry-run-worktree"
git -C "$mikebd_bash_scripts_test_primary" worktree add -q -b feature/dry-run "$dry_target" HEAD
mikebd_worktree_links_main mikebd_bash_scripts_test_link_rules --dry-run --target "$dry_target" >"$mikebd_bash_scripts_test_tmp_root/dry-run-output"
mikebd_bash_scripts_test_assert_file_contains "$mikebd_bash_scripts_test_tmp_root/dry-run-output" "DRY-RUN link:"
[ ! -e "$dry_target/.context" ] || mikebd_bash_scripts_test_fail "dry run created a link"

echo "PASS: generic worktree-link tests"
