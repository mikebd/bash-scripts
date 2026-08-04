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
Usage: new-worktree-launcher.sh --generator-marker <marker> --runner-relative-path <path> [options]

Options:
  --worktree-dir <path>     New worktree path. Required.
  --branch <name>           New branch name; defaults to the worktree basename.
  --from <ref>              Starting ref; defaults to the primary worktree HEAD.
  --launcher <path>         Launcher path; defaults to ~/.local/bin/codex-<basename>.
  --prepare <executable>    Optional local worktree preparation helper.
  --generator-marker <text> Required generated-launcher marker.
  --runner-relative-path <path>
                            Repository-relative runner path. Required.
  -h, --help                Show this help.
EOF
}

worktree_arg=""
branch=""
from_ref=""
launcher=""
prepare=""
marker=""
runner_relative_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --worktree-dir) [ "$#" -ge 2 ] || { echo "error: missing value for --worktree-dir" >&2; exit 2; }; worktree_arg="$2"; shift 2 ;;
    --branch) [ "$#" -ge 2 ] || { echo "error: missing value for --branch" >&2; exit 2; }; branch="$2"; shift 2 ;;
    --from) [ "$#" -ge 2 ] || { echo "error: missing value for --from" >&2; exit 2; }; from_ref="$2"; shift 2 ;;
    --launcher) [ "$#" -ge 2 ] || { echo "error: missing value for --launcher" >&2; exit 2; }; launcher="$2"; shift 2 ;;
    --prepare) [ "$#" -ge 2 ] || { echo "error: missing value for --prepare" >&2; exit 2; }; prepare="$2"; shift 2 ;;
    --generator-marker) [ "$#" -ge 2 ] || { echo "error: missing value for --generator-marker" >&2; exit 2; }; marker="$2"; shift 2 ;;
    --runner-relative-path) [ "$#" -ge 2 ] || { echo "error: missing value for --runner-relative-path" >&2; exit 2; }; runner_relative_path="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$worktree_arg" ] || { echo "error: --worktree-dir is required" >&2; exit 2; }
[ -n "$marker" ] || { echo "error: --generator-marker is required" >&2; exit 2; }
mikebd_launcher_validate_runner_relative_path "$runner_relative_path"
[ -z "$prepare" ] || [ -x "$prepare" ] || {
  echo "error: missing executable worktree preparation helper: $prepare" >&2
  exit 1
}

worktree_listing="$(mktemp "${TMPDIR:-/tmp}/mikebd-worktree-list.XXXXXX")"
cleanup_worktree_listing() {
  rm -f "$worktree_listing"
}
trap cleanup_worktree_listing EXIT
if ! git worktree list --porcelain >"$worktree_listing"; then
  echo "error: unable to list Git worktrees" >&2
  exit 1
fi
primary_worktree="$(awk '/^worktree / {print substr($0, 10); exit}' "$worktree_listing")"
[ -n "$primary_worktree" ] || { echo "error: unable to determine primary worktree" >&2; exit 1; }
primary_worktree="$(cd "$primary_worktree" && pwd -P)"

if [ -e "$worktree_arg" ]; then
  echo "error: worktree path already exists: $worktree_arg" >&2
  exit 1
fi
worktree_parent="$(cd "$(dirname "$worktree_arg")" && pwd -P)"
worktree_dir="$worktree_parent/$(basename "$worktree_arg")"
worktree_name="$(basename "$worktree_dir")"
branch="${branch:-$worktree_name}"
launcher="${launcher:-$HOME/.local/bin/codex-$worktree_name}"

[ ! -e "$launcher" ] || { echo "error: launcher path already exists: $launcher" >&2; exit 1; }
from_ref="${from_ref:-$(git -C "$primary_worktree" rev-parse HEAD)}"

git -C "$primary_worktree" worktree add -b "$branch" "$worktree_dir" "$from_ref"
if [ -n "$prepare" ]; then
  "$prepare" --target "$worktree_dir"
fi
mikebd_launcher_render "$launcher" "$worktree_dir" "" "$runner_relative_path" "$marker"

echo "created worktree: $worktree_dir"
echo "created launcher: $launcher"
echo "default session: none; run the launcher once, then use launcher-session.sh pin"
