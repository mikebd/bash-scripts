#!/usr/bin/env bash
set -euo pipefail

default_db="${HOME}/.codex/logs_2.sqlite"
db="${CODEX_LOG_DB:-${default_db}}"
trigger_name="block_low_level_logs"
expected_trigger_sql="CREATE TRIGGER ${trigger_name} BEFORE INSERT ON logs WHEN NEW.level NOT IN ('INFO','WARN','ERROR') BEGIN SELECT RAISE(IGNORE); END"

usage() {
  cat >&2 <<'USAGE'
usage:
  codex-log-trigger.sh [--db <sqlite-db>] <command> [args...]

commands:
  schema                         show the logs table schema
  status                         confirm whether the expected trigger is installed
  install                        install the trigger if absent; fail if mismatched
  reinstall                      drop and recreate the trigger with the expected SQL
  marker                         print the current max logs.id marker
  audit [--minutes <n>]          count rows by level for the recent time window
  audit --since-id <id>          count rows by level after an id marker
  audit --since-id <id> --by-process
                                 count rows by process_uuid and level after a marker

The trigger retains INFO, WARN, and ERROR rows while ignoring TRACE, DEBUG, and
other non-listed levels before insertion.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required"
}

require_db() {
  [[ -f "$db" ]] || die "database not found: $db"
}

quote_sql_literal() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

trigger_sql() {
  sqlite3 "$db" "select sql from sqlite_master where type = 'trigger' and name = $(quote_sql_literal "$trigger_name");"
}

print_status() {
  local actual_sql
  actual_sql="$(trigger_sql)"

  if [[ -z "$actual_sql" ]]; then
    printf 'missing trigger: %s\n' "$trigger_name"
    return 1
  fi

  if [[ "$actual_sql" != "$expected_trigger_sql" ]]; then
    printf 'trigger installed but differs from expected SQL.\n'
    printf '\nexpected:\n%s\n' "$expected_trigger_sql"
    printf '\nactual:\n%s\n' "$actual_sql"
    return 1
  fi

  printf 'trigger installed and matches expected SQL: %s\n' "$trigger_name"
}

install_trigger() {
  local actual_sql
  actual_sql="$(trigger_sql)"

  if [[ -n "$actual_sql" && "$actual_sql" != "$expected_trigger_sql" ]]; then
    printf 'trigger already exists with different SQL; use reinstall to replace it.\n' >&2
    printf '\nactual:\n%s\n' "$actual_sql" >&2
    exit 1
  fi

  sqlite3 "$db" "${expected_trigger_sql/CREATE TRIGGER/CREATE TRIGGER IF NOT EXISTS};"
  print_status
}

reinstall_trigger() {
  sqlite3 "$db" "
DROP TRIGGER IF EXISTS ${trigger_name};
${expected_trigger_sql};
"
  print_status
}

print_marker() {
  sqlite3 "$db" "select coalesce(max(id),0) from logs;"
}

audit_counts() {
  local minutes="10"
  local since_id=""
  local by_process="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --minutes)
        [[ $# -ge 2 ]] || die "--minutes requires a value"
        minutes="$2"
        shift 2
        ;;
      --since-id)
        [[ $# -ge 2 ]] || die "--since-id requires a value"
        since_id="$2"
        shift 2
        ;;
      --by-process)
        by_process="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown audit argument: $1"
        ;;
    esac
  done

  [[ "$minutes" =~ ^[0-9]+$ ]] || die "--minutes must be a non-negative integer"
  [[ -z "$since_id" || "$since_id" =~ ^[0-9]+$ ]] || die "--since-id must be a non-negative integer"

  if [[ "$by_process" == "true" ]]; then
    [[ -n "$since_id" ]] || die "--by-process requires --since-id"
    sqlite3 -header -column "$db" "
select process_uuid, level, count(*) as count, min(id) as min_id, max(id) as max_id
from logs
where id > ${since_id}
group by process_uuid, level
order by min_id, level;
"
    return
  fi

  if [[ -n "$since_id" ]]; then
    sqlite3 -header -column "$db" "
with levels(level, sort_order) as (
  values ('TRACE', 1), ('DEBUG', 2), ('INFO', 3), ('WARN', 4), ('ERROR', 5)
)
select levels.level,
       coalesce(count(logs.id), 0) as count,
       min(logs.id) as min_id,
       max(logs.id) as max_id,
       min(datetime(logs.ts, 'unixepoch')) as min_utc,
       max(datetime(logs.ts, 'unixepoch')) as max_utc
from levels
left join logs on logs.level = levels.level
              and logs.id > ${since_id}
group by levels.level, levels.sort_order
order by levels.sort_order;
"
    return
  fi

  sqlite3 -header -column "$db" "
with levels(level, sort_order) as (
  values ('TRACE', 1), ('DEBUG', 2), ('INFO', 3), ('WARN', 4), ('ERROR', 5)
)
select levels.level,
       coalesce(count(logs.id), 0) as count
from levels
left join logs on logs.level = levels.level
              and logs.ts >= strftime('%s','now','-${minutes} minutes')
group by levels.level, levels.sort_order
order by levels.sort_order;
"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db)
        [[ $# -ge 2 ]] || die "--db requires a path"
        db="$2"
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

  [[ $# -ge 1 ]] || {
    usage
    exit 2
  }

  require_sqlite
  require_db

  local command="$1"
  shift

  case "$command" in
    schema)
      sqlite3 "$db" ".schema logs"
      ;;
    status)
      print_status
      ;;
    install)
      install_trigger
      ;;
    reinstall)
      reinstall_trigger
      ;;
    marker)
      print_marker
      ;;
    audit)
      audit_counts "$@"
      ;;
    *)
      die "unknown command: $command"
      ;;
  esac
}

main "$@"
