#!/usr/bin/env bash

set -euo pipefail

# Namespaced fixture state and helpers are intentionally exposed to sourced test
# scripts. They are not exported to child processes unless explicitly required.
mikebd_bash_scripts_test_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../codex/launcher/requirements.sh disable=SC1091
source "$mikebd_bash_scripts_test_root/codex/launcher/requirements.sh"
# shellcheck source=../codex/launcher/launcher-lib.sh disable=SC1091
source "$mikebd_bash_scripts_test_root/codex/launcher/launcher-lib.sh"
# shellcheck source=../git/worktree-links.sh disable=SC1091
source "$mikebd_bash_scripts_test_root/git/worktree-links.sh"
mikebd_launcher_require_git
mikebd_launcher_require_jq

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
  [ -L "$1" ] || mikebd_bash_scripts_test_fail "expected symlink: $1"
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
  mkdir -p "$mikebd_bash_scripts_test_primary/service/deep" "$mikebd_bash_scripts_test_primary/scripts/dx"
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
  cat >"$mikebd_bash_scripts_test_primary/scripts/dx/codex" <<EOF
#!/usr/bin/env bash
exec "$mikebd_bash_scripts_test_root/codex/launcher/run.sh" "\$@"
EOF
  chmod 755 "$mikebd_bash_scripts_test_primary/scripts/dx/codex"
  git -C "$mikebd_bash_scripts_test_primary" add .gitignore README.md scripts
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

mikebd_bash_scripts_test_setup_fake_codex() {
  mikebd_bash_scripts_test_add_dir="$mikebd_bash_scripts_test_tmp_root/add-dir"
  mkdir -p "$mikebd_bash_scripts_test_add_dir"
  mikebd_bash_scripts_test_config="$mikebd_bash_scripts_test_tmp_root/launcher.env"
  cat >"$mikebd_bash_scripts_test_config" <<EOF
CODEX_LAUNCHER_ADD_DIRS=("$mikebd_bash_scripts_test_add_dir")
CODEX_LAUNCHER_MODEL="test-model"
CODEX_LAUNCHER_REASONING_EFFORT="low"
CODEX_LAUNCHER_USE_RTK="1"
EOF

  mikebd_bash_scripts_test_fake="$mikebd_bash_scripts_test_tmp_root/fake-codex"
  # shellcheck disable=SC2034
  mikebd_bash_scripts_test_fake_output="$mikebd_bash_scripts_test_tmp_root/fake-output"
  cat >"$mikebd_bash_scripts_test_fake" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "fork" ]; then
  mkdir -p "$CODEX_HOME/sessions/2026/01/01"
  printf '{"type":"session_meta","payload":{"id":"child-123","forked_from_id":"session-123","cwd":"%s"}}\n' "$PWD" >"$CODEX_HOME/sessions/2026/01/01/child.jsonl"
fi
{
  printf 'USE_RTK=%s\n' "$USE_RTK"
  printf 'CODEX_HOME=%s\n' "$CODEX_HOME"
  printf 'PWD=%s\n' "$PWD"
  printf 'ARGS:'
  printf ' <%s>' "$@"
  printf '\n'
} >"$MIKEBD_BASH_SCRIPTS_TEST_FAKE_OUTPUT"
EOF
  chmod 755 "$mikebd_bash_scripts_test_fake"
}
