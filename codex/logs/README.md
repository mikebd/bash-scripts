# Codex Log Database Helpers

Utilities in this directory manage local Codex SQLite log retention.

Motivation: [Codex SQLite feedback logs can write ~640 TB/year and rapidly consume SSD endurance](https://github.com/openai/codex/issues/28224)

Codex currently stores structured logs in:

```text
$HOME/.codex/logs_2.sqlite
```

`codex-log-trigger.sh` installs and audits a local SQLite trigger named
`block_low_level_logs`. The trigger retains `INFO`, `WARN`, and `ERROR` rows
while ignoring `TRACE`, `DEBUG`, and any other non-listed levels before they are
inserted.

This is a local workaround for Codex versions where `log_level = "warn"` and
`RUST_LOG=warn` do not prevent low-level rows from being written to the SQLite
log database.

## Usage

Check the table schema:

```bash
codex/logs/codex-log-trigger.sh schema
```

Confirm whether the expected trigger is installed:

```bash
codex/logs/codex-log-trigger.sh status
```

Install the trigger if it is absent:

```bash
codex/logs/codex-log-trigger.sh install
```

Replace the trigger with the current expected definition:

```bash
codex/logs/codex-log-trigger.sh reinstall
```

Capture a marker before launching a fresh Codex process:

```bash
marker="$(codex/logs/codex-log-trigger.sh marker)"
```

Audit rows inserted after that marker:

```bash
codex/logs/codex-log-trigger.sh audit --since-id "$marker"
```

Group the same marker window by Codex process:

```bash
codex/logs/codex-log-trigger.sh audit --since-id "$marker" --by-process
```

Audit the last 10 minutes:

```bash
codex/logs/codex-log-trigger.sh audit
```

Audit a different recent window:

```bash
codex/logs/codex-log-trigger.sh audit --minutes 30
```

Use a non-default database path:

```bash
codex/logs/codex-log-trigger.sh --db "$HOME/.codex/logs_2.sqlite" status
```

or:

```bash
CODEX_LOG_DB="$HOME/.codex/logs_2.sqlite" codex/logs/codex-log-trigger.sh status
```

## Verification Workflow

After installing or reinstalling the trigger:

1. Capture a marker.
2. Launch a fresh Codex process briefly.
3. Exit that process after startup completes.
4. Run `audit --since-id "$marker"`.

Expected result: `TRACE` and `DEBUG` counts remain `0`. `INFO`, `WARN`, and
`ERROR` may appear.

## Upgrade Hygiene

The trigger lives inside the SQLite database, not in Codex config. A Codex
upgrade can drop or bypass it if the upgrade replaces the database, recreates
the `logs` table, changes the database path, changes the schema, or removes
unknown triggers during migration.

After upgrading Codex, run:

```bash
codex/logs/codex-log-trigger.sh status
codex/logs/codex-log-trigger.sh audit
```

If the trigger is missing or `TRACE` / `DEBUG` rows reappear, run:

```bash
codex/logs/codex-log-trigger.sh reinstall
```

## Rollback

Rollback is intentionally manual:

```bash
sqlite3 "$HOME/.codex/logs_2.sqlite" "DROP TRIGGER IF EXISTS block_low_level_logs;"
```
