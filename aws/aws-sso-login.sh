#!/usr/bin/env bash
# Expiry reporting uses jq, sha1sum, and GNU date; login detection does not.
set -euo pipefail

usage() {
  printf 'usage: %s [aws-sso-login-args...]\n' "$0" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

profile_args=()
args=("$@")
effective_profile="${AWS_PROFILE:-default}"
index=0
while ((index < ${#args[@]})); do
  case "${args[index]}" in
    --profile)
      if ((index + 1 < ${#args[@]})); then
        effective_profile="${args[index + 1]}"
        profile_args+=(--profile "${args[index + 1]}")
      fi
      index=$((index + 2))
      ;;
    --profile=*)
      effective_profile="${args[index]#--profile=}"
      profile_args+=(--profile "$effective_profile")
      index=$((index + 1))
      ;;
    *)
      index=$((index + 1))
      ;;
  esac
done

err_file="$(mktemp "${TMPDIR:-/tmp}/aws-sso-login-check.XXXXXX")"
trap 'rm -f "$err_file"' EXIT

if aws sts get-caller-identity "${profile_args[@]}" --output json >/dev/null 2>"$err_file"; then
  printf 'AWS session is current; login not required.\n'

  aws_config_get() {
    local key="$1"
    if [ "$effective_profile" = default ]; then
      aws configure get "$key" 2>/dev/null || true
    else
      aws configure get "$key" --profile "$effective_profile" 2>/dev/null || true
    fi
  }

  format_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$((seconds % 86400 / 3600))
    local minutes=$((seconds % 3600 / 60))

    if ((days > 0)); then
      printf '%sd %sh %sm' "$days" "$hours" "$minutes"
    elif ((hours > 0)); then
      printf '%sh %sm' "$hours" "$minutes"
    elif ((minutes > 0)); then
      printf '%sm' "$minutes"
    else
      printf '%ss' "$seconds"
    fi
  }

  report_expiry() {
    local label="$1"
    local timestamp="$2"
    local expiry_epoch
    local now_epoch
    local remaining

    if [ -z "$timestamp" ]; then
      printf '%s expiry unavailable.\n' "$label"
      return
    fi

    if ! expiry_epoch="$(date -u -d "$timestamp" +%s 2>/dev/null)"; then
      printf '%s expiry unavailable.\n' "$label"
      return
    fi

    now_epoch="$(date -u +%s)"
    remaining=$((expiry_epoch - now_epoch))
    if ((remaining <= 0)); then
      printf '%s expired %s ago (%s).\n' \
        "$label" \
        "$(format_duration "$((-remaining))")" \
        "$(date -d "@$expiry_epoch" '+%Y-%m-%d %H:%M:%S %Z')"
      return
    fi

    printf '%s expires in %s (%s).\n' \
      "$label" \
      "$(format_duration "$remaining")" \
      "$(date -d "@$expiry_epoch" '+%Y-%m-%d %H:%M:%S %Z')"
  }

  read_cache_value() {
    local cache_file="$1"
    local query="$2"

    if [ ! -r "$cache_file" ] || ! command -v jq >/dev/null 2>&1; then
      return 1
    fi
    jq -er "$query // empty" "$cache_file" 2>/dev/null
  }

  sso_session="$(aws_config_get sso_session)"
  account_id="$(aws_config_get sso_account_id)"
  role_name="$(aws_config_get sso_role_name)"
  config_file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  start_url="$(aws_config_get sso_start_url)"

  if [ -n "$sso_session" ] && [ -r "$config_file" ]; then
    start_url="$(awk -v session="$sso_session" '
      $0 == "[sso-session " session "]" { in_session=1; next }
      $0 ~ /^\[/ { in_session=0 }
      in_session && $0 ~ /^[[:space:]]*sso_start_url[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, "")
        print
        exit
      }
    ' "$config_file")"
  fi

  if command -v sha1sum >/dev/null 2>&1 && [ -n "$start_url" ]; then
    if [ -n "$sso_session" ]; then
      token_cache_key="$(printf '%s' "$sso_session" | sha1sum | cut -d' ' -f1)"
    else
      token_cache_key="$(printf '%s' "$start_url" | sha1sum | cut -d' ' -f1)"
    fi
    sso_expiry="$(read_cache_value "$HOME/.aws/sso/cache/$token_cache_key.json" '.expiresAt' || true)"
  else
    sso_expiry=""
  fi
  report_expiry 'SSO token' "$sso_expiry"

  role_expiry=""
  if command -v jq >/dev/null 2>&1 && command -v sha1sum >/dev/null 2>&1 \
    && [ -n "$account_id" ] && [ -n "$role_name" ] && [ -n "$start_url" ]; then
    if [ -n "$sso_session" ]; then
      role_cache_json="$(jq -cnS \
        --arg accountId "$account_id" \
        --arg roleName "$role_name" \
        --arg sessionName "$sso_session" \
        '{accountId:$accountId,roleName:$roleName,sessionName:$sessionName}')"
    else
      role_cache_json="$(jq -cnS \
        --arg accountId "$account_id" \
        --arg roleName "$role_name" \
        --arg startUrl "$start_url" \
        '{accountId:$accountId,roleName:$roleName,startUrl:$startUrl}')"
    fi
    role_cache_key="$(printf '%s' "$role_cache_json" | sha1sum | cut -d' ' -f1)"
    role_expiry="$(read_cache_value "$HOME/.aws/cli/cache/$role_cache_key.json" '.Credentials.Expiration' || true)"
  fi
  report_expiry 'Role credentials' "$role_expiry"
  exit 0
fi

check_status=$?
check_error="$(<"$err_file")"

case "$check_error" in
  *"Your session has expired"*|\
  *"reauthenticate"*|\
  *"Unable to locate credentials"*|\
  *"ExpiredToken"*|\
  *"expired token"*|\
  *"security token included in the request is expired"*|\
  *"Error loading SSO Token"*|\
  *"Token has expired and refresh failed"*|\
  *"SSO session"*|\
  *"The config profile"* )
    exec aws sso login "$@"
    ;;
esac

printf 'AWS session check failed, but not with a recognized auth-expiry or missing-credentials error.\n' >&2
printf "Not running \`aws sso login\` automatically.\n" >&2
printf '%s\n' "$check_error" >&2
exit "$check_status"
