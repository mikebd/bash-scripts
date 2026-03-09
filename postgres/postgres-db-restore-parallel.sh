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

expand_path() {
  local path="$1"
  # shellcheck disable=SC2088
  if [[ "$path" == "~" || "${path:0:2}" == "~/" ]]; then
    printf '%s\n' "${path/#\~/$HOME}"
  else
    printf '%s\n' "$path"
  fi
}

prompt backup_dir "Backup directory"
backup_dir="$(expand_path "$backup_dir")"

if [[ ! -d "$backup_dir" ]]; then
  echo "Backup directory not found: $backup_dir" >&2
  exit 1
fi

prompt host "Host"
prompt port "Port" "5432"
prompt username "Username" "${USER:-}"
prompt dbname "Database"
read -r -p "SSL mode (optional, e.g. require, verify-full): " sslmode
prompt jobs "Parallel jobs" "4"

read -r -s -p "Password (will not echo): " password
printf '\n'

read -r -p "Drop existing objects before restore? [y/N]: " clean_confirm
clean_flag=""
if [[ "$clean_confirm" =~ ^[Yy]$ ]]; then
  clean_flag="--clean"
fi

read -r -p "Skip restoring object ownerships (--no-owner)? [y/N]: " no_owner_confirm
no_owner_flag=""
if [[ "$no_owner_confirm" =~ ^[Yy]$ ]]; then
  no_owner_flag="--no-owner"
fi

read -r -p "Skip restoring privileges (--no-privileges)? [y/N]: " no_privileges_confirm
no_privileges_flag=""
if [[ "$no_privileges_confirm" =~ ^[Yy]$ ]]; then
  no_privileges_flag="--no-privileges"
fi

# shellcheck disable=SC2154
read -r -p "Restore $backup_dir into $dbname on $host:$port as $username? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

backup_dir_parent="$(cd "$(dirname "$backup_dir")" && pwd)"
backup_dir_name="$(basename "$backup_dir")"
backup_dir_container="/backup/$backup_dir_name"

env_args=(-e "PGPASSWORD=$password")
env_args+=(-e "PGKEEPALIVES=1" -e "PGKEEPALIVES_IDLE=30" -e "PGKEEPALIVES_INTERVAL=10" -e "PGKEEPALIVES_COUNT=5")
if [[ -n "$sslmode" ]]; then
  env_args+=(-e "PGSSLMODE=$sslmode")
fi

# shellcheck disable=SC2154
pg_args=(pg_restore --verbose -j "$jobs" -h "$host" -p "$port" -U "$username" -d "$dbname")
if [[ -n "$clean_flag" ]]; then
  pg_args+=("$clean_flag")
fi
if [[ -n "$no_owner_flag" ]]; then
  pg_args+=("$no_owner_flag")
fi
if [[ -n "$no_privileges_flag" ]]; then
  pg_args+=("$no_privileges_flag")
fi
pg_args+=("$backup_dir_container")

mapfile -t docker_host_args < <(docker_host_args_for "$host")
docker run --rm "${docker_host_args[@]}" "${env_args[@]}" -v "$backup_dir_parent:/backup" postgres:17 "${pg_args[@]}"

echo "Restore completed from $backup_dir"
