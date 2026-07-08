#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  cat >&2 <<'EOF'
usage: psql-ro-wrapper.sh <sql-file|- for stdin> [psql-args...]

required env:
  PGHOST
  PGPORT
  PGUSER
  PGPASSWORD
  PGDATABASE

optional env:
  PGSSLMODE (default: require)
  PG_STATEMENT_TIMEOUT_MS (default: 25000)
EOF
  exit 2
fi

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"

sql_input="$1"
shift || true
sql_input_dir=""

if [[ "${sql_input}" != "-" ]]; then
  sql_input_dir="$(cd -- "$(dirname -- "${sql_input}")" && pwd)"
fi

# Enforce read-only sessions and bounded runtime by default.
readonly_opts="-c default_transaction_read_only=on -c statement_timeout=${PG_STATEMENT_TIMEOUT_MS:-25000}"
if [[ -n "${PGOPTIONS:-}" ]]; then
  export PGOPTIONS="${PGOPTIONS} ${readonly_opts}"
else
  export PGOPTIONS="${readonly_opts}"
fi

sslmode="${PGSSLMODE:-require}"
conn="host=${PGHOST} port=${PGPORT} user=${PGUSER} dbname=${PGDATABASE} sslmode=${sslmode}"

# Prefer host psql when available to avoid Docker startup overhead.
run_local_psql() {
  if [[ "${sql_input}" == "-" ]]; then
    psql "${conn}" -v ON_ERROR_STOP=1 -P pager=off "$@"
  else
    psql "${conn}" -v ON_ERROR_STOP=1 -P pager=off -f "${sql_input}" "$@"
  fi
}

# Docker fallback keeps this wrapper usable on systems without local psql.
run_docker_psql() {
  if [[ "${sql_input}" == "-" ]]; then
    docker run --rm --network host -i \
      -e PGPASSWORD="${PGPASSWORD}" \
      -e PGOPTIONS="${PGOPTIONS}" \
      postgres:17 psql "${conn}" -v ON_ERROR_STOP=1 -P pager=off "$@"
  else
    # Mount the SQL file directory so psql can read the same absolute file path
    # inside the container. This avoids docker -i stdin hangs for reusable
    # file-based query workflows while keeping stdin mode available for "-".
    docker run --rm --network host \
      -v "${sql_input_dir}:${sql_input_dir}:ro" \
      -e PGPASSWORD="${PGPASSWORD}" \
      -e PGOPTIONS="${PGOPTIONS}" \
      postgres:17 psql "${conn}" -v ON_ERROR_STOP=1 -P pager=off -f "${sql_input}" "$@"
  fi
}

if command -v psql >/dev/null 2>&1; then
  export PGPASSWORD
  run_local_psql "$@"
else
  run_docker_psql "$@"
fi
