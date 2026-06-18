#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [aws-login-args...]\n' "$0" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

err_file="$(mktemp "${TMPDIR:-/tmp}/aws-login-check.XXXXXX")"
trap 'rm -f "$err_file"' EXIT

if aws sts get-caller-identity --output json >/dev/null 2>"$err_file"; then
  printf 'AWS session is current; login not required.\n'
  exit 0
fi

check_status=$?
check_error="$(cat "$err_file")"

case "$check_error" in
  *"Your session has expired"*|\
  *"reauthenticate"*|\
  *"Unable to locate credentials"*|\
  *"ExpiredToken"*|\
  *"expired token"*|\
  *"security token included in the request is expired"*|\
  *"SSO session"*|\
  *"The config profile"* )
    exec aws login "$@"
    ;;
esac

printf 'AWS session check failed, but not with a recognized auth-expiry or missing-credentials error.\n' >&2
printf "Not running \`aws login\` automatically.\n" >&2
printf '%s\n' "$check_error" >&2
exit "$check_status"
