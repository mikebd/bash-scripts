# mikebd's Bash Scripts

A small collection of Bash scripts for tasks where shell is still the simplest and most direct tool.

This repo is intentionally separate from [`mikebd/py-scripts`](https://github.com/mikebd/py-scripts):

- use this repo for lightweight shell-first utilities
- use the Python repo for more structured tools with richer UX, tests, and packaging
- some scripts may start here and later be promoted into the Python repo when the logic outgrows Bash

## Layout

- `postgres/`: backup, restore, and inspection scripts for PostgreSQL dumps

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

## Related Repo

If you want tools that are more polished, typed, or likely to be reused as maintained CLIs, check:

- [`mikebd/py-scripts`](https://github.com/mikebd/py-scripts)

The rough heuristic is:

- Bash first when the script is mostly shelling out to existing tools
- Python when the workflow needs more validation, parsing, test coverage, or long-term maintenance
