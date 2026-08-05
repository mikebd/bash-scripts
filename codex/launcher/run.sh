#!/usr/bin/env bash

set -euo pipefail

# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=requirements.sh disable=SC1091
source "$script_dir/requirements.sh"
# shellcheck source=launcher-lib.sh disable=SC1091
source "$script_dir/launcher-lib.sh"
mikebd_launcher_require_git

usage() {
  cat <<'EOF'
Usage: run.sh [--prepare <executable>] [--worktree-dir <path>] [--session-id <id>] [--fork-session-id <id>] [--] [codex args...]

Runs Codex with local developer-workflow configuration for a Git worktree.
EOF
}

prepare=""
worktree_arg=""
session_id=""
fork_session_id=""
codex_passthrough=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prepare)
      [ "$#" -ge 2 ] || { echo "error: missing value for --prepare" >&2; exit 2; }
      prepare="$2"
      shift 2
      ;;
    --worktree-dir)
      [ "$#" -ge 2 ] || { echo "error: missing value for --worktree-dir" >&2; exit 2; }
      worktree_arg="$2"
      shift 2
      ;;
    --session-id)
      [ "$#" -ge 2 ] || { echo "error: missing value for --session-id" >&2; exit 2; }
      session_id="$2"
      shift 2
      ;;
    --fork-session-id)
      [ "$#" -ge 2 ] || { echo "error: missing value for --fork-session-id" >&2; exit 2; }
      fork_session_id="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      codex_passthrough=("$@")
      break
      ;;
    *)
      codex_passthrough=("$@")
      break
      ;;
  esac
done

if [ -n "$worktree_arg" ]; then
  [ -d "$worktree_arg" ] || { echo "error: worktree is not a directory: $worktree_arg" >&2; exit 1; }
  worktree_dir="$(cd "$worktree_arg" && pwd -P)"
else
  worktree_dir="$(git rev-parse --show-toplevel)"
fi

worktree_git_dir="$(git -C "$worktree_dir" rev-parse --git-dir)"
case "$worktree_git_dir" in
  /*) ;;
  *) worktree_git_dir="$(cd "$worktree_dir/$worktree_git_dir" && pwd -P)" ;;
esac

if [ -n "$prepare" ]; then
  [ -x "$prepare" ] || { echo "error: missing executable worktree preparation helper: $prepare" >&2; exit 1; }
  "$prepare" --target "$worktree_dir" >/dev/null
fi
cd "$worktree_dir"

mikebd_launcher_load_config
cache_home="$(mikebd_launcher_prepare_cache_home "$worktree_dir")" || exit 1
go_tmp_root="$cache_home"
go_cache_dir="$go_tmp_root/go-cache"
go_mod_cache_dir="$go_tmp_root/go-mod"
go_tmp_dir="$go_tmp_root/go-tmp"
golangci_cache_dir="$go_tmp_root/golangci-cache"
tmp_dir="$go_tmp_root/tmp"
for cache_dir in "$go_cache_dir" "$go_mod_cache_dir" "$go_tmp_dir" "$golangci_cache_dir" "$tmp_dir"; do
  (umask 077; mkdir -p "$cache_dir") || exit 1
  chmod 700 "$cache_dir" || exit 1
done

canonical_dir() {
  local path="$1"

  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
  else
    return 1
  fi
}

add_dirs=()
add_dir_if_unique() {
  local path="$1"
  local canonical existing

  canonical="$(canonical_dir "$path" 2>/dev/null)" || return 0
  if [ "${#add_dirs[@]}" -gt 0 ]; then
    for existing in "${add_dirs[@]}"; do
      [ "$existing" = "$canonical" ] && return 0
    done
  fi
  add_dirs+=("$canonical")
}

if [ "${#CODEX_LAUNCHER_ADD_DIRS[@]}" -gt 0 ]; then
  for configured_dir in "${CODEX_LAUNCHER_ADD_DIRS[@]}"; do
    add_dir_if_unique "$configured_dir"
  done
fi
add_dir_if_unique "$worktree_dir/.context"
add_dir_if_unique "$worktree_git_dir"

codex_args=(--sandbox "$CODEX_LAUNCHER_SANDBOX")
if [ -n "$CODEX_LAUNCHER_MODEL" ]; then
  codex_args+=(--model "$CODEX_LAUNCHER_MODEL")
fi
if [ -n "$CODEX_LAUNCHER_REASONING_EFFORT" ]; then
  codex_args+=(--config "model_reasoning_effort=$CODEX_LAUNCHER_REASONING_EFFORT")
fi
if [ "${#add_dirs[@]}" -gt 0 ]; then
  for add_dir in "${add_dirs[@]}"; do
    codex_args+=(--add-dir "$add_dir")
  done
fi

if [ -n "$fork_session_id" ] && [ -n "$session_id" ]; then
  echo "error: --session-id and --fork-session-id are mutually exclusive" >&2
  exit 2
fi

mikebd_launcher_require_codex

if [ -n "$fork_session_id" ]; then
  codex_command=(fork "${codex_args[@]}" "$fork_session_id")
elif [ -n "$session_id" ]; then
  codex_command=(resume "${codex_args[@]}" "$session_id")
else
  codex_command=("${codex_args[@]}")
fi
if [ "${#codex_passthrough[@]}" -gt 0 ]; then
  codex_command+=("${codex_passthrough[@]}")
fi

codex_environment=(env)
if [ -n "${CODEX_HOME:-}" ]; then
  codex_environment+=("CODEX_HOME=$CODEX_HOME")
fi
codex_environment+=(
  USE_RTK="${USE_RTK:-$CODEX_LAUNCHER_USE_RTK}" \
  GOCACHE="${GOCACHE:-$go_cache_dir}" \
  GOMODCACHE="${GOMODCACHE:-$go_mod_cache_dir}" \
  GOTMPDIR="${GOTMPDIR:-$go_tmp_dir}" \
  GOLANGCI_LINT_CACHE="${GOLANGCI_LINT_CACHE:-$golangci_cache_dir}" \
  TMPDIR="${TMPDIR:-$tmp_dir}" \
  RUST_LOG="${RUST_LOG:-warn}"
)
exec "${codex_environment[@]}" "${CODEX_BIN:-codex}" "${codex_command[@]}"
