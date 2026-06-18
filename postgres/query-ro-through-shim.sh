#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  query-ro-through-shim.sh <psql-shim> [--out <output-file>] --sql '<read-only sql>' [psql args...]
  query-ro-through-shim.sh <psql-shim> [--out <output-file>] --file <sql-file> [psql args...]
  query-ro-through-shim.sh <psql-shim> [--out <output-file>] - [psql args...]

Runs SQL through the given read-only psql shim. Use --out for host-side output
capture, especially when the underlying shim may fall back to Docker.
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

psql_shim="$1"
shift

if [[ ! -x "${psql_shim}" ]]; then
  echo "missing executable psql shim: ${psql_shim}" >&2
  exit 2
fi

out_file=""
if [[ "${1:-}" == "--out" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "--out requires an output file path" >&2
    exit 2
  fi
  out_file="$2"
  shift 2
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

run_query() {
  if [[ -n "${out_file}" ]]; then
    mkdir -p "$(dirname "${out_file}")"
    "${psql_shim}" "$@" > "${out_file}"
  else
    exec "${psql_shim}" "$@"
  fi
}

mode="$1"
shift

case "${mode}" in
  --sql)
    if [[ $# -lt 1 ]]; then
      echo "--sql requires a SQL string" >&2
      exit 2
    fi
    sql="$1"
    shift
    tmp_sql="$(mktemp)"
    cleanup() {
      rm -f "${tmp_sql}"
    }
    trap cleanup EXIT
    printf '%s\n' "${sql}" > "${tmp_sql}"
    run_query "${tmp_sql}" "$@"
    ;;
  --file)
    if [[ $# -lt 1 ]]; then
      echo "--file requires a SQL file path" >&2
      exit 2
    fi
    sql_file="$1"
    shift
    run_query "${sql_file}" "$@"
    ;;
  -)
    run_query - "$@"
    ;;
  --help|-h)
    usage
    ;;
  *)
    echo "unknown mode: ${mode}" >&2
    usage
    exit 2
    ;;
esac
