#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage:
  psql-ro-env-file.sh <db-env-file> <sql-file|- for stdin> [psql args...]

Sources a DB-only env file, translates DB_* variables to PG* variables, and
execs psql-ro-wrapper.sh with read-only session enforcement.

required env-file keys:
  DB_HOST
  DB_PORT
  DB_USER or DB_USERNAME
  DB_PASSWORD
  DB_NAME

optional env-file keys:
  DB_SSL_MODE (default: require)
  DB_SCHEMA
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

db_env_file="$1"
shift

if [[ ! -f "${db_env_file}" ]]; then
  echo "env file not found: ${db_env_file}" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "${db_env_file}"
set +a

export PGHOST="${DB_HOST:?DB_HOST is required}"
export PGPORT="${DB_PORT:?DB_PORT is required}"
export PGUSER="${DB_USER:-${DB_USERNAME:-}}"
: "${PGUSER:?DB_USER or DB_USERNAME is required}"
export PGPASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
export PGDATABASE="${DB_NAME:?DB_NAME is required}"
export PGSSLMODE="${DB_SSL_MODE:-require}"

exec "${script_dir}/psql-ro-wrapper.sh" "$@"
