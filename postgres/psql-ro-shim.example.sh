#!/usr/bin/env bash
set -euo pipefail

# Example local shim for ~/.local/bin/<your-name>.
# Copy this file to ~/.local/bin and customize:
# 1) DB_ENV_FILE
# 2) CORE_WRAPPER path if needed

DB_ENV_FILE="${DB_ENV_FILE:-PATH/TO/ENV_FILE}"
CORE_WRAPPER="${CORE_WRAPPER:-/home/you/src/mikebd/bash/scripts/postgres/psql-ro-wrapper.sh}"

if [[ ! -f "${DB_ENV_FILE}" ]]; then
  echo "env file not found: ${DB_ENV_FILE}" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "${DB_ENV_FILE}"
set +a

# Translate DB_* source vars to PG-native vars expected by psql-ro-wrapper.sh.
export PGHOST="${DB_HOST:?DB_HOST is required}"
export PGPORT="${DB_PORT:?DB_PORT is required}"
export PGUSER="${DB_USERNAME:?DB_USERNAME is required}"
export PGPASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
export PGDATABASE="${DB_NAME:?DB_NAME is required}"
export PGSSLMODE="${DB_SSL_MODE:-require}"

exec "${CORE_WRAPPER}" "$@"
