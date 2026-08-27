# mikebd's Bash Scripts

A small collection of Bash scripts for tasks where shell is still the simplest and most direct tool.

This repo is the lightweight shell-first companion to
[`mikebd/py-scripts`](https://github.com/mikebd/py-scripts).

## Table of Contents

- [Portability](#portability)
- [Layout](#layout)
- [Local Usage](#local-usage)
- [Branch Context](#branch-context)
- [Bash or Python?](#bash-or-python)

## Portability

This repo optimizes for simplicity, directness, and local usefulness, not for
maximum shell portability.

It is currently used only on Pop!_OS, which is Ubuntu-based. Users on other
operating systems may need to adapt these scripts before they are safe and
correct to run, and should treat them as inspiration rather than as
drop-in-compatible tools.

Examples of intentionally non-prioritized portability concerns include:

- GNU vs BSD differences in common tools such as `xargs`, `sed`, `date`, and
  `awk`
- availability and behavior of Linux-oriented tools such as `getent`
- Bash version differences, including features that may not exist in older
  platform-default Bash installs
- local assumptions about Docker, `psql`, clipboard tools, and other machine
  setup details
- environment- or distro-specific defaults that may differ on macOS, other
  Linux distributions, or CI runners

This default does not prevent a directory or script from declaring and meeting
a stricter compatibility contract. Such exceptions must be explicit; they do
not change the portability expectations of unrelated utilities.

Currently, `git/worktree-links.sh` and `lib/requirements.sh` support the Bash 3.2
included with macOS and common GNU/Linux environments. They use portable shell
forms, account for GNU/BSD command differences where needed, and document
their required external commands. This contract does not apply to other
directories, including `codex/logs/`.

## Layout

- `codex/logs/`: Codex SQLite log database helpers, including a trigger manager
  for suppressing noisy low-level log rows
- `lib/requirements.sh`: portable, sourceable command-requirement helpers for
  shared shell workflows
- `git/worktree-links.sh`: portable, sourceable worktree-link engine with
  repository-defined link rules
- `postgres/`: backup, restore, and inspection scripts for PostgreSQL dumps
  - includes `psql-ro-wrapper.sh`, a generic read-only SQL runner that uses
    local `psql` when available and falls back to Docker `postgres:17`
  - file-mode Docker fallback mounts host SQL paths and runs `psql -f` instead
    of stdin piping because `docker run -i` can hang unpredictably in local
    wrapper usage
- `tests/`: self-contained portable-DX tests for the requirement and
  worktree-link primitives; run `tests/run-portable-dx.sh` locally

## Local Usage

The scripts in this repo are symlinked into `~/.local/bin` on my machine so they can still be run directly by name.

Examples:

```bash
postgres-db-backup.sh
postgres-db-backup-parallel.sh
postgres-db-restore.sh
postgres-db-restore-parallel.sh
postgres-db-scan-parallel-backup.sh
```

For environment-specific access, keep thin shims in `~/.local/bin` that export
PG env vars from your local `DB_*` env file format and then `exec`:

```bash
~/src/mikebd/bash/scripts/postgres/psql-ro-wrapper.sh <sql-file|- for stdin>
```

Use this template as a starting point for those shims:

- `postgres/psql-ro-shim.example.sh`

It demonstrates translating `DB_*` source variables into the PG-native
variables expected by `psql-ro-wrapper.sh`.

## Branch Context

This repository's optional Branch Context is maintained on the
[`bash-scripts-context` branch](https://github.com/mikebd/public-branch-context/tree/bash-scripts-context)
of the public Branch Context repository. It provides branch-scoped working
context for coding-agent workflows, including resumability, decision
traceability, handoffs, and reproducible investigations.

See the [Branch Context guidance](https://github.com/mikebd/ai-agent-skills/tree/main/shared/references/branch-context)
for the overall model and conventions.

## Bash or Python?

If you want tools that are more polished, typed, or likely to be reused as maintained CLIs, check:

- [`mikebd/py-scripts`](https://github.com/mikebd/py-scripts)

The rough heuristic is:

- Bash first when the script is mostly shelling out to existing tools
- Python when the workflow needs more validation, parsing, test coverage, or long-term maintenance
