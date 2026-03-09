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

read -r -p "Filter findings to a role name (optional): " role_filter

backup_dir_parent="$(cd "$(dirname "$backup_dir")" && pwd)"
backup_dir_name="$(basename "$backup_dir")"
backup_dir_container="/backup/$backup_dir_name"

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

count_matches() {
  local pattern="$1"
  local file="$2"
  local count
  count="$(rg -c "$pattern" "$file" 2>/dev/null || true)"
  if [[ -z "$count" ]]; then
    count="0"
  fi
  printf '%s\n' "$count"
}

print_grouped_counts() {
  local kind="$1"
  local file="$2"
  local extractor="$3"
  local grouped

  grouped="$(
    perl -ne "$extractor" "$file" \
      | sort \
      | uniq -c \
      | awk '{count=$1; $1=""; sub(/^ /, ""); printf "%s: %s\n", $0, count}'
  )"

  if [[ -n "$grouped" ]]; then
    printf '%s by role:\n' "$kind"
    printf '%s\n' "$grouped"
  else
    printf '%s by role:\n' "$kind"
    echo "none"
  fi
}

summary_file="$tmp_sql"

echo "Rendering archive to SQL for inspection..."
docker run --rm -v "$backup_dir_parent:/backup" postgres:17 \
  pg_restore -f - "$backup_dir_container" > "$tmp_sql"

echo
echo "Ownership statements:"
if [[ -n "$role_filter" ]]; then
  rg -n -F "$role_filter" "$tmp_sql" | rg 'OWNER TO '
else
  rg -n 'OWNER TO ' "$tmp_sql"
fi || true

echo
echo "Privilege statements:"
if [[ -n "$role_filter" ]]; then
  rg -n -F "$role_filter" "$tmp_sql" | rg '^(GRANT|REVOKE) '
else
  rg -n '^(GRANT|REVOKE) ' "$tmp_sql"
fi || true

echo
echo "Summary:"
owner_count=0
priv_count=0
if [[ -n "$role_filter" ]]; then
  filtered_sql="$(mktemp)"
  trap 'rm -f "$tmp_sql" "$filtered_sql"' EXIT
  rg -F "$role_filter" "$tmp_sql" > "$filtered_sql" || true
  summary_file="$filtered_sql"
  owner_count="$(count_matches 'OWNER TO ' "$filtered_sql")"
  priv_count="$(count_matches '^(GRANT|REVOKE) ' "$filtered_sql")"
else
  owner_count="$(count_matches 'OWNER TO ' "$tmp_sql")"
  priv_count="$(count_matches '^(GRANT|REVOKE) ' "$tmp_sql")"
fi

printf 'Ownership statements found: %s\n' "$owner_count"
printf 'Privilege statements found: %s\n' "$priv_count"

echo
# shellcheck disable=SC2016
print_grouped_counts \
  "Ownership statements" \
  "$summary_file" \
  'print "$1\n" if /OWNER TO ([^;]+);/'
echo
# shellcheck disable=SC2016
print_grouped_counts \
  "Privilege statements" \
  "$summary_file" \
  'print "$1\n" if /^GRANT\b.*\bTO ([^;]+);$/; print "$1\n" if /^REVOKE\b.*\bFROM ([^;]+);$/;'

if [[ "$owner_count" == "0" && "$priv_count" == "0" ]]; then
  echo "No ownership or privilege statements found."
fi
