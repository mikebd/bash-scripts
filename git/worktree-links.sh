#!/usr/bin/env bash

# Sourceable Git-worktree link engine. Consumers provide a rule function that
# calls the mikebd_worktree_links_add_* helpers below. Its intentional
# MIKEBD_WORKTREE_LINKS_* callback state is reset by each main invocation.
# Portability contract: Bash 3.2 on macOS and common GNU/Linux environments.

mikebd_worktree_links_usage() {
  cat <<'EOF'
Usage: worktree-links [--target <worktree-path>] [--dry-run]

Creates only missing links from the primary Git worktree into a secondary
worktree. The caller supplies the link rules.
EOF
}

mikebd_worktree_links_add_path() {
  local source_path="$1"
  local target_path="$2"

  if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
    MIKEBD_WORKTREE_LINKS_SKIPPED_MISSING_SOURCE=$((MIKEBD_WORKTREE_LINKS_SKIPPED_MISSING_SOURCE + 1))
    return 0
  fi

  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    MIKEBD_WORKTREE_LINKS_SKIPPED_EXISTING=$((MIKEBD_WORKTREE_LINKS_SKIPPED_EXISTING + 1))
    return 0
  fi

  if [ "$MIKEBD_WORKTREE_LINKS_DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN link: $target_path -> $source_path"
    MIKEBD_WORKTREE_LINKS_CREATED=$((MIKEBD_WORKTREE_LINKS_CREATED + 1))
    return 0
  fi

  mkdir -p "$(dirname "$target_path")"
  ln -s "$source_path" "$target_path"
  echo "linked: $target_path -> $source_path"
  MIKEBD_WORKTREE_LINKS_CREATED=$((MIKEBD_WORKTREE_LINKS_CREATED + 1))
}

mikebd_worktree_links_add_relative() {
  local relative_path="$1"

  mikebd_worktree_links_add_path \
    "$MIKEBD_WORKTREE_LINKS_PRIMARY/$relative_path" \
    "$MIKEBD_WORKTREE_LINKS_TARGET/$relative_path"
}

mikebd_worktree_links_add_root_glob() {
  local pattern="$1"
  local source_path

  for source_path in "$MIKEBD_WORKTREE_LINKS_PRIMARY"/$pattern; do
    [ -e "$source_path" ] || [ -L "$source_path" ] || continue
    mikebd_worktree_links_add_path \
      "$source_path" \
      "$MIKEBD_WORKTREE_LINKS_TARGET/$(basename "$source_path")"
  done
}

mikebd_worktree_links_add_child_glob() {
  local pattern="$1"
  local child_dir source_path child_name

  for child_dir in "$MIKEBD_WORKTREE_LINKS_PRIMARY"/*; do
    [ -d "$child_dir" ] || continue
    child_name="$(basename "$child_dir")"
    for source_path in "$child_dir"/$pattern; do
      [ -e "$source_path" ] || [ -L "$source_path" ] || continue
      mikebd_worktree_links_add_path \
        "$source_path" \
        "$MIKEBD_WORKTREE_LINKS_TARGET/$child_name/$(basename "$source_path")"
    done
  done
}

mikebd_worktree_links_main() {
  local rules_function="$1"
  local target_arg=""
  local git_context="."
  local repo_root worktree_listing primary_worktree target_worktree

  shift
  MIKEBD_WORKTREE_LINKS_DRY_RUN=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -t|--target)
        [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; return 2; }
        target_arg="$2"
        shift 2
        ;;
      -n|--dry-run)
        MIKEBD_WORKTREE_LINKS_DRY_RUN=1
        shift
        ;;
      -h|--help)
        mikebd_worktree_links_usage
        return 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        mikebd_worktree_links_usage >&2
        return 2
        ;;
    esac
  done

  if [ -n "$target_arg" ]; then
    [ -d "$target_arg" ] || { echo "error: target is not a directory: $target_arg" >&2; return 1; }
    git_context="$target_arg"
  fi
  repo_root="$(git -C "$git_context" rev-parse --show-toplevel)" || return 1

  worktree_listing="$(mktemp "${TMPDIR:-/tmp}/mikebd-worktree-list.XXXXXX")" || return 1
  if ! git -C "$repo_root" worktree list --porcelain >"$worktree_listing"; then
    rm -f "$worktree_listing"
    echo "error: unable to list Git worktrees" >&2
    return 1
  fi
  primary_worktree="$(awk '/^worktree / {print substr($0, 10); exit}' "$worktree_listing")"
  rm -f "$worktree_listing"
  [ -n "$primary_worktree" ] || { echo "error: unable to determine primary worktree" >&2; return 1; }
  primary_worktree="$(cd "$primary_worktree" && pwd -P)" || return 1

  if [ -n "$target_arg" ]; then
    target_worktree="$(cd "$target_arg" && pwd -P)" || return 1
  else
    target_worktree="$repo_root"
  fi

  if [ "$target_worktree" = "$primary_worktree" ]; then
    echo "summary: target=$target_worktree created=0 skipped_existing=0 skipped_missing_source=0 dry_run=$MIKEBD_WORKTREE_LINKS_DRY_RUN noop_primary_target=1"
    return 0
  fi

  MIKEBD_WORKTREE_LINKS_PRIMARY="$primary_worktree"
  MIKEBD_WORKTREE_LINKS_TARGET="$target_worktree"
  MIKEBD_WORKTREE_LINKS_CREATED=0
  MIKEBD_WORKTREE_LINKS_SKIPPED_EXISTING=0
  MIKEBD_WORKTREE_LINKS_SKIPPED_MISSING_SOURCE=0

  "$rules_function"
  echo "summary: target=$target_worktree created=$MIKEBD_WORKTREE_LINKS_CREATED skipped_existing=$MIKEBD_WORKTREE_LINKS_SKIPPED_EXISTING skipped_missing_source=$MIKEBD_WORKTREE_LINKS_SKIPPED_MISSING_SOURCE dry_run=$MIKEBD_WORKTREE_LINKS_DRY_RUN"
}
