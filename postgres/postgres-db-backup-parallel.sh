#!/usr/bin/env bash
set -euo pipefail

prompt() {
  local var_name="$1"
  local label="$2"
  local default_value="${3-}"
  local input
  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " input
    input="${input:-$default_value}"
  else
    read -r -p "$label: " input
  fi
  printf -v "$var_name" '%s' "$input"
}

docker_host_args_for() {
  local host="$1"
  local resolved_ip
  if [[ "$host" =~ : || "$host" =~ ^[0-9.]+$ ]]; then
    return 0
  fi
  resolved_ip="$(getent ahosts "$host" | awk 'NR == 1 { print $1 }')"
  if [[ -n "$resolved_ip" ]]; then
    printf -- '--add-host=%s:%s\n' "$host" "$resolved_ip"
  else
    echo "Warning: could not resolve $host on the host machine; Docker will use container DNS." >&2
  fi
}

sanitize_name() {
  local name="$1"
  # Replace unsafe filename characters with underscore.
  name="${name//[^A-Za-z0-9._-]/_}"
  printf '%s' "$name"
}

prompt host "Host"
prompt port "Port" "5432"
prompt username "Username" "${USER:-}"
prompt dbname "Database"

read -r -p "Schema (optional, blank for all): " schema
read -r -p "SSL mode (optional, e.g. require, verify-full): " sslmode
prompt jobs "Parallel jobs" "4"

read -r -s -p "Password (will not echo): " password
printf '\n'

separator="__"
safe_dbname="$(sanitize_name "$dbname")"
if [[ -n "$schema" ]]; then
  safe_schema="$(sanitize_name "$schema")"
  output_dir_name="${safe_dbname}${separator}${safe_schema}"
else
  output_dir_name="${safe_dbname}"
fi

output_dir_host="$PWD/$output_dir_name"
output_dir_container="/backup/$output_dir_name"

if [[ -e "$output_dir_host" ]]; then
  read -r -p "$output_dir_name exists. Overwrite? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
  rm -rf "$output_dir_host"
fi

env_args=(-e "PGPASSWORD=$password")
env_args+=(-e "PGKEEPALIVES=1" -e "PGKEEPALIVES_IDLE=30" -e "PGKEEPALIVES_INTERVAL=10" -e "PGKEEPALIVES_COUNT=5")
if [[ -n "$sslmode" ]]; then
  env_args+=(-e "PGSSLMODE=$sslmode")
fi

pg_args=(pg_dump --verbose --lock-wait-timeout=60 -F d -j "$jobs" --compress=gzip:level=9 -h "$host" -p "$port" -U "$username" -d "$dbname" -f "$output_dir_container")
if [[ -n "$schema" ]]; then
  pg_args+=(-n "$schema")
fi

mapfile -t docker_host_args < <(docker_host_args_for "$host")
time docker run --rm "${docker_host_args[@]}" "${env_args[@]}" -v "$PWD:/backup" -w /backup postgres:17 "${pg_args[@]}"

echo "Backup written to $output_dir_host"
