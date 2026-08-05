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

add_writable_directory() {
  local path="$1"

  case "$path" in
    /*) ;;
    *)
      echo "error: launcher writable directory must be absolute: $path" >&2
      return 1
      ;;
  esac
  mkdir -p "$path" || {
    echo "error: unable to create launcher writable directory: $path" >&2
    return 1
  }
  add_dir_if_unique "$path"
}

add_go_cache_directories() {
  local go_cache_dir go_mod_cache_dir

  command -v go >/dev/null 2>&1 || return 0
  go_cache_dir="$(go env GOCACHE)" || {
    echo "error: unable to determine Go build cache directory" >&2
    return 1
  }
  go_mod_cache_dir="$(go env GOMODCACHE)" || {
    echo "error: unable to determine Go module cache directory" >&2
    return 1
  }
  if [ "$go_cache_dir" != "off" ]; then
    add_writable_directory "$go_cache_dir" || return 1
  fi
  add_writable_directory "$go_mod_cache_dir" || return 1
}

add_golangci_cache_directory() {
  local golangci_cache_dir

  command -v golangci-lint >/dev/null 2>&1 || return 0
  golangci_cache_dir="${GOLANGCI_LINT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/golangci-lint}"
  add_writable_directory "$golangci_cache_dir"
}

if [ "${#CODEX_LAUNCHER_ADD_DIRS[@]}" -gt 0 ]; then
  for configured_dir in "${CODEX_LAUNCHER_ADD_DIRS[@]}"; do
    add_dir_if_unique "$configured_dir"
  done
fi
add_dir_if_unique "$worktree_dir/.context"
add_dir_if_unique "$worktree_git_dir"
add_go_cache_directories || exit 1
add_golangci_cache_directory || exit 1

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
  RUST_LOG="${RUST_LOG:-warn}"
)
exec "${codex_environment[@]}" "${CODEX_BIN:-codex}" "${codex_command[@]}"
