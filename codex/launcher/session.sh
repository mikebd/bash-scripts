#!/usr/bin/env bash

set -euo pipefail

# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=requirements.sh disable=SC1091
source "$script_dir/requirements.sh"
# shellcheck source=launcher-lib.sh disable=SC1091
source "$script_dir/launcher-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  session.sh --generator-marker <marker> [--runner-relative-path <path>] pin --launcher <path> --session-id <id>
  session.sh --generator-marker <marker> [--runner-relative-path <path>] fork --launcher <source> --target-launcher <path>
EOF
}

meta_value() {
  local file="$1"
  local field="$2"

  jq -r --arg field "$field" '(.payload // .) as $metadata | ($metadata[$field] // empty)' \
    <<<"$(sed -n '1p' "$file")"
}

capture_session_files() {
  local sessions_dir="$1"
  local manifest="$2"

  : >"$manifest"
  [ -d "$sessions_dir" ] || return 0
  find "$sessions_dir" -type f -name '*.jsonl' -print >"$manifest"
}

session_file_previously_seen() {
  local file="$1"
  local manifest="$2"

  grep -Fqx -- "$file" "$manifest"
}

marker=""
fallback_runner_relative_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --generator-marker)
      [ "$#" -ge 2 ] || { echo "error: missing value for --generator-marker" >&2; exit 2; }
      marker="$2"
      shift 2
      ;;
    --runner-relative-path)
      [ "$#" -ge 2 ] || { echo "error: missing value for --runner-relative-path" >&2; exit 2; }
      fallback_runner_relative_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

[ -n "$marker" ] || { echo "error: --generator-marker is required" >&2; exit 2; }
if [ -n "$fallback_runner_relative_path" ]; then
  mikebd_launcher_validate_runner_relative_path "$fallback_runner_relative_path"
fi

subcommand="${1:-}"
[ -n "$subcommand" ] || { usage >&2; exit 2; }
shift

launcher=""
target_launcher=""
session_id=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --launcher) [ "$#" -ge 2 ] || { echo "error: missing value for --launcher" >&2; exit 2; }; launcher="$2"; shift 2 ;;
    --target-launcher) [ "$#" -ge 2 ] || { echo "error: missing value for --target-launcher" >&2; exit 2; }; target_launcher="$2"; shift 2 ;;
    --session-id) [ "$#" -ge 2 ] || { echo "error: missing value for --session-id" >&2; exit 2; }; session_id="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$subcommand" in
  pin)
    [ -n "$launcher" ] && [ -n "$session_id" ] || { echo "error: pin requires --launcher and --session-id" >&2; exit 2; }
    mikebd_launcher_update_session "$launcher" "$session_id" "$marker"
    echo "pinned session $session_id in $launcher"
    ;;
  fork)
    mikebd_launcher_require_git
    mikebd_launcher_require_jq
    [ -n "$launcher" ] && [ -n "$target_launcher" ] || { echo "error: fork requires --launcher and --target-launcher" >&2; exit 2; }
    mikebd_launcher_assert_generated "$launcher" "$marker"
    [ ! -e "$target_launcher" ] || { echo "error: target launcher already exists: $target_launcher" >&2; exit 1; }
    worktree_dir="$(mikebd_launcher_field "$launcher" worktree_dir)"
    parent_session="$(mikebd_launcher_field "$launcher" default_session_id)"
    [ -n "$parent_session" ] || { echo "error: source launcher has no pinned session" >&2; exit 1; }
    if runner_relative_path="$(mikebd_launcher_field_optional "$launcher" runner_relative_path)"; then
      :
    else
      field_status=$?
      [ "$field_status" -eq 1 ] || exit "$field_status"
      runner_relative_path="$fallback_runner_relative_path"
    fi
    mikebd_launcher_validate_runner_relative_path "$runner_relative_path"
    repo_root="$(git -C "$worktree_dir" rev-parse --show-toplevel)"
    runner="$repo_root/$runner_relative_path"
    [ -x "$runner" ] || { echo "error: missing launcher runner: $runner" >&2; exit 1; }
    codex_home="$(mikebd_launcher_config_cache_home "$worktree_dir")"
    sessions_dir="$codex_home/sessions"
    before_sessions="$(mktemp "${TMPDIR:-/tmp}/mikebd-launcher-before.XXXXXX")"
    after_sessions="$(mktemp "${TMPDIR:-/tmp}/mikebd-launcher-after.XXXXXX")"
    cleanup_session_manifests() {
      rm -f "$before_sessions" "$after_sessions"
    }
    trap cleanup_session_manifests EXIT
    capture_session_files "$sessions_dir" "$before_sessions"

    "$runner" --worktree-dir "$worktree_dir" --fork-session-id "$parent_session"

    candidates=()
    capture_session_files "$sessions_dir" "$after_sessions"
    while IFS= read -r file; do
      session_file_previously_seen "$file" "$before_sessions" && continue
      child_id="$(meta_value "$file" id)"
      forked_from="$(meta_value "$file" forked_from_id)"
      child_cwd="$(meta_value "$file" cwd)"
      if [ -n "$child_id" ] && [ "$forked_from" = "$parent_session" ] && [ "$child_cwd" = "$worktree_dir" ]; then
        candidates+=("$child_id")
      fi
    done <"$after_sessions"

    if [ "${#candidates[@]}" -ne 1 ]; then
      echo "error: expected one forked child session, found ${#candidates[@]}" >&2
      printf 'candidate session IDs: %s\n' "${candidates[*]:-none}" >&2
      exit 1
    fi
    mikebd_launcher_render "$target_launcher" "$worktree_dir" "${candidates[0]}" "$runner_relative_path" "$marker"
    trap - EXIT
    cleanup_session_manifests
    echo "created fork launcher: $target_launcher"
    echo "pinned session: ${candidates[0]}"
    ;;
  *)
    echo "error: unknown subcommand: $subcommand" >&2
    usage >&2
    exit 2
    ;;
esac
