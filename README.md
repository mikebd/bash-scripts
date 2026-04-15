# mikebd's Bash Scripts

A small collection of Bash scripts for tasks where shell is still the simplest and most direct tool.

This repo is intentionally separate from [`mikebd/py-scripts`](https://github.com/mikebd/py-scripts):

- use this repo for lightweight shell-first utilities
- use the Python repo for more structured tools with richer UX, tests, and packaging
- some scripts may start here and later be promoted into the Python repo when the logic outgrows Bash

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

## Layout

- `postgres/`: backup, restore, and inspection scripts for PostgreSQL dumps
  - includes `psql-ro-wrapper.sh`, a generic read-only SQL runner that uses
    local `psql` when available and falls back to Docker `postgres:17`

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

## Related Repo

If you want tools that are more polished, typed, or likely to be reused as maintained CLIs, check:

- [`mikebd/py-scripts`](https://github.com/mikebd/py-scripts)

The rough heuristic is:

- Bash first when the script is mostly shelling out to existing tools
- Python when the workflow needs more validation, parsing, test coverage, or long-term maintenance
