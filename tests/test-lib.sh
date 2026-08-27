#!/usr/bin/env bash

set -euo pipefail

# Namespaced fixture state and helpers are intentionally exposed to sourced test
# scripts. They are not exported to child processes unless explicitly required.
# shellcheck disable=SC2034
mikebd_bash_scripts_test_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

mikebd_bash_scripts_test_tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mikebd-bash-scripts.XXXXXX")"

mikebd_bash_scripts_test_cleanup() {
  rm -rf "$mikebd_bash_scripts_test_tmp_root"
}

mikebd_bash_scripts_test_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mikebd_bash_scripts_test_assert_file_contains() {
  local file="$1"
  local text="$2"

  grep -Fq "$text" "$file" || mikebd_bash_scripts_test_fail "expected $text in $file"
}

mikebd_bash_scripts_test_assert_symlink() {
  local link_path="$1"
  local expected_source="$2"
  local actual_source

  [ -L "$link_path" ] || mikebd_bash_scripts_test_fail "expected symlink: $link_path"
  actual_source="$(readlink "$link_path")"
  [ "$actual_source" = "$expected_source" ] || {
    mikebd_bash_scripts_test_fail "symlink source = $actual_source, want $expected_source"
  }
}

mikebd_bash_scripts_test_setup_fixture() {
  local branch="${1:-feature/test}"
  local target_name="${2:-secondary-worktree}"

  mikebd_bash_scripts_test_primary="$mikebd_bash_scripts_test_tmp_root/primary"
  mkdir -p "$mikebd_bash_scripts_test_primary"
  git -C "$mikebd_bash_scripts_test_primary" init -q
  git -C "$mikebd_bash_scripts_test_primary" symbolic-ref HEAD refs/heads/main
  git -C "$mikebd_bash_scripts_test_primary" config user.email test@example.invalid
  git -C "$mikebd_bash_scripts_test_primary" config user.name "Bash Scripts Test"
  mkdir -p "$mikebd_bash_scripts_test_primary/service/deep"
  printf 'local context\n' >"$mikebd_bash_scripts_test_primary/.context"
  printf 'procfile\n' >"$mikebd_bash_scripts_test_primary/Procfile.local"
  printf 'service env\n' >"$mikebd_bash_scripts_test_primary/service/.env.local"
  printf 'air config\n' >"$mikebd_bash_scripts_test_primary/service/.air.toml"
  printf 'deep env\n' >"$mikebd_bash_scripts_test_primary/service/deep/.env.deep"
  printf 'tracked\n' >"$mikebd_bash_scripts_test_primary/README.md"
  cat >"$mikebd_bash_scripts_test_primary/.gitignore" <<'EOF'
.context
Procfile*
service/.env*
service/.air*
service/deep/
EOF
  git -C "$mikebd_bash_scripts_test_primary" add .gitignore README.md
  git -C "$mikebd_bash_scripts_test_primary" commit -q -m initial

  mikebd_bash_scripts_test_target="$mikebd_bash_scripts_test_tmp_root/$target_name"
  git -C "$mikebd_bash_scripts_test_primary" worktree add -q -b "$branch" "$mikebd_bash_scripts_test_target" HEAD
}

mikebd_bash_scripts_test_link_rules() {
  mikebd_worktree_links_add_relative .context
  mikebd_worktree_links_add_root_glob 'Procfile*'
  mikebd_worktree_links_add_child_glob '.env*'
  mikebd_worktree_links_add_child_glob '.air*'
}
