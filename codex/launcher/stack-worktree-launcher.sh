#!/usr/bin/env bash

set -euo pipefail

# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=requirements.sh disable=SC1091
source "$script_dir/requirements.sh"
mikebd_launcher_require_git

usage() {
  cat <<'EOF'
Usage: stack-worktree-launcher.sh --suffix <suffix> --generator-marker <marker> --runner-relative-path <path> [options]

Create a sibling worktree, stacked branch, and unpinned Codex launcher from
the current worktree's committed HEAD.

Options:
  --suffix <suffix>          Opaque suffix appended to the source worktree basename and branch. Required.
  --prepare <executable>     Optional local worktree preparation helper.
  --session-command <path>   Command shown for pinning the first session.
  --add-dir <path>           Extra writable directory for this launcher; repeatable.
  --generator-marker <text>  Required generated-launcher marker.
  --runner-relative-path <path>
                            Repository-relative runner path. Required.
  -h, --help                Show this help.
EOF
}

suffix=""
prepare=""
marker=""
runner_relative_path=""
session_command="$script_dir/session.sh"
extra_add_dirs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --suffix) [ "$#" -ge 2 ] || { echo "error: missing value for --suffix" >&2; exit 2; }; suffix="$2"; shift 2 ;;
    --prepare) [ "$#" -ge 2 ] || { echo "error: missing value for --prepare" >&2; exit 2; }; prepare="$2"; shift 2 ;;
    --session-command) [ "$#" -ge 2 ] || { echo "error: missing value for --session-command" >&2; exit 2; }; session_command="$2"; shift 2 ;;
    --add-dir) [ "$#" -ge 2 ] || { echo "error: missing value for --add-dir" >&2; exit 2; }; extra_add_dirs+=("$2"); shift 2 ;;
    --generator-marker) [ "$#" -ge 2 ] || { echo "error: missing value for --generator-marker" >&2; exit 2; }; marker="$2"; shift 2 ;;
    --runner-relative-path) [ "$#" -ge 2 ] || { echo "error: missing value for --runner-relative-path" >&2; exit 2; }; runner_relative_path="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$suffix" ] || { echo "error: --suffix is required" >&2; exit 2; }
[ -n "$marker" ] || { echo "error: --generator-marker is required" >&2; exit 2; }
[ -n "$runner_relative_path" ] || { echo "error: --runner-relative-path is required" >&2; exit 2; }
case "$suffix" in
  */*|*\\*|*$'\n'*|*$'\r'*)
    echo "error: suffix must be a single path-name fragment: $suffix" >&2
    exit 2
    ;;
esac

source_worktree="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: stack creation must run inside a Git worktree" >&2
  exit 1
}
source_worktree="$(cd "$source_worktree" && pwd -P)"
source_branch="$(git -C "$source_worktree" branch --show-current)"
[ -n "$source_branch" ] || {
  echo "error: stack creation requires an attached source branch" >&2
  exit 1
}
source_head="$(git -C "$source_worktree" rev-parse --verify HEAD)" || {
  echo "error: unable to resolve the source worktree HEAD" >&2
  exit 1
}
source_name="$(basename "$source_worktree")"
target_name="${source_name}${suffix}"
target_worktree="$(dirname "$source_worktree")/$target_name"
target_branch="${source_branch}${suffix}"
target_launcher="$HOME/.local/bin/codex-$target_name"

git check-ref-format --branch "$target_branch" >/dev/null 2>&1 || {
  echo "error: suffix produces an unsafe branch name: $target_branch" >&2
  exit 2
}
if [ -e "$target_worktree" ] || [ -L "$target_worktree" ]; then
  echo "error: target worktree path already exists: $target_worktree" >&2
  exit 1
fi
if [ -e "$target_launcher" ] || [ -L "$target_launcher" ]; then
  echo "error: target launcher already exists: $target_launcher" >&2
  exit 1
fi
if git -C "$source_worktree" show-ref --verify --quiet "refs/heads/$target_branch"; then
  echo "error: target branch already exists: $target_branch" >&2
  exit 1
fi

stack_args=(
  --worktree-dir "$target_worktree"
  --branch "$target_branch"
  --from "$source_head"
  --launcher "$target_launcher"
  --prepare "$prepare"
  --generator-marker "$marker"
  --runner-relative-path "$runner_relative_path"
  --session-command "$session_command"
)
if [ "${#extra_add_dirs[@]}" -gt 0 ]; then
  for extra_add_dir in "${extra_add_dirs[@]}"; do
    stack_args+=(--add-dir "$extra_add_dir")
  done
fi
exec "$script_dir/new-worktree-launcher.sh" "${stack_args[@]}"
