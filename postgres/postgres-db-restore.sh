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

prompt backup_file "Backup file (.backup.gz)"
backup_file="$(expand_path "$backup_file")"

if [[ ! -f "$backup_file" ]]; then
  echo "Backup file not found: $backup_file" >&2
  exit 1
fi

prompt host "Host"
prompt port "Port" "5432"
prompt username "Username" "${USER:-}"
prompt dbname "Database"

read -r -p "SSL mode (optional, e.g. require, verify-full): " sslmode

read -r -s -p "Password (will not echo): " password
printf '\n'

read -r -p "Rewrite database name in dump? Source name (optional): " rewrite_from
rewrite_to=""
if [[ -n "$rewrite_from" ]]; then
  read -r -p "Rewrite to (target name): " rewrite_to
  if [[ -z "$rewrite_to" ]]; then
    echo "Target name required when rewriting." >&2
    exit 1
  fi
fi

read -r -p "Restore into $dbname on $host:$port as $username? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

env_args=(-e "PGPASSWORD=$password")
env_args+=(-e "PGKEEPALIVES=1" -e "PGKEEPALIVES_IDLE=30" -e "PGKEEPALIVES_INTERVAL=10" -e "PGKEEPALIVES_COUNT=5")
if [[ -n "$sslmode" ]]; then
  env_args+=(-e "PGSSLMODE=$sslmode")
fi

pg_args=(psql -v ON_ERROR_STOP=1 -h "$host" -p "$port" -U "$username" -d "$dbname")
mapfile -t docker_host_args < <(docker_host_args_for "$host")

if [[ -n "$rewrite_from" ]]; then
  sed_escape() {
    printf '%s' "$1" | sed -e 's/[\/&|\\]/\\&/g'
  }
  from_esc="$(sed_escape "$rewrite_from")"
  to_esc="$(sed_escape "$rewrite_to")"
  gunzip -c "$backup_file" \
    | sed -E \
        -e "s|(CREATE DATABASE )(\\\"?)${from_esc}(\\\"?)|\\1\\2${to_esc}\\3|g" \
        -e "s|(COMMENT ON DATABASE )(\\\"?)${from_esc}(\\\"?)|\\1\\2${to_esc}\\3|g" \
        -e "s|(ALTER DATABASE )(\\\"?)${from_esc}(\\\"?)|\\1\\2${to_esc}\\3|g" \
        -e "s|^\\\\connect ${from_esc}$|\\\\connect ${to_esc}|g" \
    | docker run --rm -i "${docker_host_args[@]}" "${env_args[@]}" postgres:17 "${pg_args[@]}"
else
  gunzip -c "$backup_file" | docker run --rm -i "${docker_host_args[@]}" "${env_args[@]}" postgres:17 "${pg_args[@]}"
fi

echo "Restore completed from $backup_file"
