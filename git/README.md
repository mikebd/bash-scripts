# Worktree-link engine

`worktree-links.sh` is a portable, sourceable engine for creating missing
links from a primary Git worktree into a secondary worktree. It does not know
which files a repository needs; the consuming repository supplies a rule
function.

It supports Bash 3.2 on macOS and common GNU/Linux environments. It requires
`git` and common POSIX shell utilities. Existing files and links are never
overwritten.

## Adapter pattern

Source the engine from a repository-local adapter, define its link rules, and
pass the adapter's arguments to `mikebd_worktree_links_main`:

```bash
#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
shared_scripts_root="${MIKEBD_BASH_SCRIPTS_ROOT:-$HOME/src/mikebd/bash/scripts}"
source "$shared_scripts_root/git/worktree-links.sh"

example_worktree_links_rules() {
  mikebd_worktree_links_add_relative ".context"
  mikebd_worktree_links_add_root_glob ".env.*"
}

mikebd_worktree_links_main example_worktree_links_rules "$@"
```

The adapter's rule function may use these helpers:

- `mikebd_worktree_links_add_relative <path>` links the same relative path
  under both worktrees.
- `mikebd_worktree_links_add_root_glob <pattern>` links matching files from
  the primary worktree root.
- `mikebd_worktree_links_add_child_glob <pattern>` links matching files under
  each direct child directory of the primary worktree.

## Arguments

The engine accepts:

```text
worktree-links [--target <worktree-path>] [--dry-run]
```

Without `--target`, the current repository is used. `--dry-run` reports links
that would be created without modifying the target. The primary worktree is
resolved from `git worktree list`; a primary-worktree target is reported as a
no-op.

The engine emits one line for each created or dry-run link, followed by a
summary containing created, existing-target, missing-source, and dry-run
counts. The `MIKEBD_WORKTREE_LINKS_*` variables are intentional callback state
for the rule function and are reset for each `mikebd_worktree_links_main`
invocation.
