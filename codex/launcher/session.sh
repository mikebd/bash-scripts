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
  session.sh --generator-marker <marker> [--runner-relative-path <path>] fork --launcher <source> --target-launcher <path> [--add-dir <path>]...
  session.sh --generator-marker <marker> [--runner-relative-path <path>] adopt --launcher <source> --target-launcher <path> --session-id <id> [--add-dir <path>]...
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

session_add_dir_if_unique() {
  local candidate="$1"
  local existing

  if [ "${#session_add_dirs[@]}" -gt 0 ]; then
    for existing in "${session_add_dirs[@]}"; do
      [ "$existing" = "$candidate" ] && return 0
    done
  fi
  session_add_dirs+=("$candidate")
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
additional_add_dirs=()
session_add_dirs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --launcher) [ "$#" -ge 2 ] || { echo "error: missing value for --launcher" >&2; exit 2; }; launcher="$2"; shift 2 ;;
    --target-launcher) [ "$#" -ge 2 ] || { echo "error: missing value for --target-launcher" >&2; exit 2; }; target_launcher="$2"; shift 2 ;;
    --session-id) [ "$#" -ge 2 ] || { echo "error: missing value for --session-id" >&2; exit 2; }; session_id="$2"; shift 2 ;;
    --add-dir) [ "$#" -ge 2 ] || { echo "error: missing value for --add-dir" >&2; exit 2; }; additional_add_dirs+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$subcommand" in
  pin)
    [ -n "$launcher" ] && [ -n "$session_id" ] || { echo "error: pin requires --launcher and --session-id" >&2; exit 2; }
    [ "${#additional_add_dirs[@]}" -eq 0 ] || { echo "error: pin does not accept --add-dir" >&2; exit 2; }
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
    codex_home="$(mikebd_launcher_config_codex_home)"
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
      if [ "${#candidates[@]}" -eq 0 ]; then
        printf 'candidate session IDs: none\n' >&2
      else
        # The length check keeps this expansion safe under Bash 3.2 + set -u.
        printf 'candidate session IDs: %s\n' "${candidates[*]}" >&2
      fi
      exit 1
    fi
    session_add_dirs=()
    while IFS= read -r extra_add_dir; do
      [ -n "$extra_add_dir" ] || continue
      session_add_dir_if_unique "$extra_add_dir"
    done <<<"$(mikebd_launcher_extra_add_dirs "$launcher")"
    if [ "${#additional_add_dirs[@]}" -gt 0 ]; then
      for extra_add_dir in "${additional_add_dirs[@]}"; do
        session_add_dir_if_unique "$extra_add_dir"
      done
    fi
    if [ "${#session_add_dirs[@]}" -gt 0 ]; then
      mikebd_launcher_render "$target_launcher" "$worktree_dir" "${candidates[0]}" "$runner_relative_path" "$marker" "${session_add_dirs[@]}"
    else
      mikebd_launcher_render "$target_launcher" "$worktree_dir" "${candidates[0]}" "$runner_relative_path" "$marker"
    fi
    trap - EXIT
    cleanup_session_manifests
    echo "created fork launcher: $target_launcher"
    echo "pinned session: ${candidates[0]}"
    ;;
  adopt)
    mikebd_launcher_require_git
    mikebd_launcher_require_jq
    [ -n "$launcher" ] && [ -n "$target_launcher" ] && [ -n "$session_id" ] || {
      echo "error: adopt requires --launcher, --target-launcher, and --session-id" >&2
      exit 2
    }
    case "$session_id" in
      *[!A-Za-z0-9_-]*) echo "error: invalid session ID: $session_id" >&2; exit 2 ;;
    esac
    mikebd_launcher_assert_generated "$launcher" "$marker"
    [ ! -e "$target_launcher" ] || { echo "error: target launcher already exists: $target_launcher" >&2; exit 1; }
    worktree_dir="$(mikebd_launcher_field "$launcher" worktree_dir)"
    parent_session="$(mikebd_launcher_field "$launcher" default_session_id)"
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
    codex_home="$(mikebd_launcher_config_codex_home)"
    sessions_dir="$codex_home/sessions"
    session_manifest="$(mktemp "${TMPDIR:-/tmp}/mikebd-launcher-adopt.XXXXXX")"
    cleanup_adopt_manifest() {
      rm -f "$session_manifest"
    }
    trap cleanup_adopt_manifest EXIT
    capture_session_files "$sessions_dir" "$session_manifest"
    session_files=()
    while IFS= read -r file; do
      [ "$(meta_value "$file" id)" = "$session_id" ] || continue
      session_files+=("$file")
    done <"$session_manifest"
    if [ "${#session_files[@]}" -ne 1 ]; then
      echo "error: expected one session metadata file for $session_id, found ${#session_files[@]}" >&2
      exit 1
    fi
    session_cwd="$(meta_value "${session_files[0]}" cwd)"
    [ "$session_cwd" = "$worktree_dir" ] || {
      echo "error: session $session_id belongs to $session_cwd, not launcher worktree $worktree_dir" >&2
      exit 1
    }
    forked_from="$(meta_value "${session_files[0]}" forked_from_id)"
    if [ -n "$parent_session" ] && [ "$forked_from" != "$parent_session" ]; then
      if [ -n "$forked_from" ]; then
        echo "info: adopted session $session_id forked from $forked_from, not source launcher session $parent_session" >&2
      else
        echo "info: adopted session $session_id has no forked_from_id; source launcher session is $parent_session" >&2
      fi
    fi
    session_add_dirs=()
    while IFS= read -r inherited_add_dir; do
      [ -n "$inherited_add_dir" ] || continue
      session_add_dir_if_unique "$inherited_add_dir"
    done <<<"$(mikebd_launcher_extra_add_dirs "$launcher")"
    if [ "${#additional_add_dirs[@]}" -gt 0 ]; then
      for inherited_add_dir in "${additional_add_dirs[@]}"; do
        session_add_dir_if_unique "$inherited_add_dir"
      done
    fi
    if [ "${#session_add_dirs[@]}" -gt 0 ]; then
      mikebd_launcher_render "$target_launcher" "$worktree_dir" "$session_id" "$runner_relative_path" "$marker" "${session_add_dirs[@]}"
    else
      mikebd_launcher_render "$target_launcher" "$worktree_dir" "$session_id" "$runner_relative_path" "$marker"
    fi
    trap - EXIT
    cleanup_adopt_manifest
    echo "created adopted session launcher: $target_launcher"
    echo "pinned session: $session_id"
    ;;
  *)
    echo "error: unknown subcommand: $subcommand" >&2
    usage >&2
    exit 2
    ;;
esac
