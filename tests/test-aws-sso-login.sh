#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2129
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/aws-sso-login-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: expected output to contain: %s\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

mkdir -p "$test_root/home/.aws/sso/cache" "$test_root/home/.aws/cli/cache" "$test_root/bin"
printf '%s\n' '#!/usr/bin/env bash' > "$test_root/bin/aws"
printf '%s\n' 'set -euo pipefail' >> "$test_root/bin/aws"
printf '%s\n' 'case "${1:-}" in' >> "$test_root/bin/aws"
printf '%s\n' '  sts)' >> "$test_root/bin/aws"
printf '%s\n' '    if [ "${MOCK_AWS_MODE:-current}" = expired ]; then printf "Error loading SSO Token: Token has expired and refresh failed\\n" >&2; exit 255; fi' >> "$test_root/bin/aws"
printf '%s\n' '    exit 0' >> "$test_root/bin/aws"
printf '%s\n' '    ;;' >> "$test_root/bin/aws"
printf '%s\n' '  configure)' >> "$test_root/bin/aws"
printf '%s\n' '    case "${5:-}" in' >> "$test_root/bin/aws"
printf '%s\n' '      test)' >> "$test_root/bin/aws"
printf '%s\n' '        case "${3:-}" in' >> "$test_root/bin/aws"
printf '%s\n' '          sso_session) printf "test-session\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_account_id) printf "123456789012\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_role_name) printf "ReadOnly\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_start_url) printf "\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          *) exit 1 ;;' >> "$test_root/bin/aws"
printf '%s\n' '        esac' >> "$test_root/bin/aws"
printf '%s\n' '        ;;' >> "$test_root/bin/aws"
printf '%s\n' '      legacy)' >> "$test_root/bin/aws"
printf '%s\n' '        case "${3:-}" in' >> "$test_root/bin/aws"
printf '%s\n' '          sso_session) printf "\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_account_id) printf "210987654321\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_role_name) printf "PowerUser\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          sso_start_url) printf "https://legacy.awsapps.com/start\\n" ;;' >> "$test_root/bin/aws"
printf '%s\n' '          *) exit 1 ;;' >> "$test_root/bin/aws"
printf '%s\n' '        esac' >> "$test_root/bin/aws"
printf '%s\n' '        ;;' >> "$test_root/bin/aws"
printf '%s\n' '      *) exit 1 ;;' >> "$test_root/bin/aws"
printf '%s\n' '    esac' >> "$test_root/bin/aws"
printf '%s\n' '    ;;' >> "$test_root/bin/aws"
printf '%s\n' '  sso)' >> "$test_root/bin/aws"
printf '%s\n' '    printf "invoked: %s\\n" "$*"' >> "$test_root/bin/aws"
printf '%s\n' '    ;;' >> "$test_root/bin/aws"
printf '%s\n' '  *) exit 2 ;;' >> "$test_root/bin/aws"
printf '%s\n' 'esac' >> "$test_root/bin/aws"
chmod 755 "$test_root/bin/aws"

printf '%s\n' '[sso-session test-session]' > "$test_root/config"
printf '%s\n' 'sso_start_url = https://example.awsapps.com/start' >> "$test_root/config"
printf '%s\n' 'sso_region = ca-central-1' >> "$test_root/config"
printf '%s\n' '[profile test]' >> "$test_root/config"
printf '%s\n' 'sso_session = test-session' >> "$test_root/config"
printf '%s\n' '[profile legacy]' >> "$test_root/config"
printf '%s\n' 'sso_start_url = https://legacy.awsapps.com/start' >> "$test_root/config"

write_cache() {
  local cache_file="$1"
  local contents="$2"
  printf '%s\n' "$contents" > "$cache_file"
}

modern_token_key="$(printf '%s' test-session | sha1sum | cut -d' ' -f1)"
write_cache "$test_root/home/.aws/sso/cache/$modern_token_key.json" '{"expiresAt":"2099-01-02T03:04:05Z"}'
modern_role_json="$(jq -cnS --arg accountId 123456789012 --arg roleName ReadOnly --arg sessionName test-session '{accountId:$accountId,roleName:$roleName,sessionName:$sessionName}')"
modern_role_key="$(printf '%s' "$modern_role_json" | sha1sum | cut -d' ' -f1)"
write_cache "$test_root/home/.aws/cli/cache/$modern_role_key.json" '{"Credentials":{"Expiration":"2099-01-02T04:05:06Z"}}'

legacy_start_url='https://legacy.awsapps.com/start'
legacy_token_key="$(printf '%s' "$legacy_start_url" | sha1sum | cut -d' ' -f1)"
write_cache "$test_root/home/.aws/sso/cache/$legacy_token_key.json" '{"expiresAt":"2099-02-02T03:04:05Z"}'
legacy_role_json="$(jq -cnS --arg accountId 210987654321 --arg roleName PowerUser --arg startUrl "$legacy_start_url" '{accountId:$accountId,roleName:$roleName,startUrl:$startUrl}')"
legacy_role_key="$(printf '%s' "$legacy_role_json" | sha1sum | cut -d' ' -f1)"
write_cache "$test_root/home/.aws/cli/cache/$legacy_role_key.json" '{"Credentials":{"Expiration":"2099-02-02T04:04:06Z"}}'

base_env=(HOME="$test_root/home" AWS_CONFIG_FILE="$test_root/config" PATH="$test_root/bin:$PATH")
modern_output="$(env "${base_env[@]}" "$script_dir/aws/aws-sso-login.sh" --profile=test)"
assert_contains "$modern_output" 'SSO token expires in'
assert_contains "$modern_output" 'Role credentials expires in'

profile_output="$(env "${base_env[@]}" AWS_PROFILE=test "$script_dir/aws/aws-sso-login.sh")"
assert_contains "$profile_output" 'SSO token expires in'
assert_contains "$profile_output" 'Role credentials expires in'

write_cache "$test_root/home/.aws/sso/cache/$modern_token_key.json" '{"expiresAt":"not-a-timestamp"}'
malformed_output="$(env "${base_env[@]}" "$script_dir/aws/aws-sso-login.sh" --profile test)"
assert_contains "$malformed_output" 'SSO token expiry unavailable'
assert_contains "$malformed_output" 'Role credentials expires in'

write_cache "$test_root/home/.aws/sso/cache/$modern_token_key.json" '{"expiresAt":"2000-01-02T03:04:05Z"}'
expired_output="$(env "${base_env[@]}" "$script_dir/aws/aws-sso-login.sh" --profile test)"
assert_contains "$expired_output" 'SSO token expired'
assert_contains "$expired_output" 'Role credentials expires in'

missing_output="$(env "${base_env[@]}" "$script_dir/aws/aws-sso-login.sh" --profile missing)"
assert_contains "$missing_output" 'SSO token expiry unavailable'
assert_contains "$missing_output" 'Role credentials expiry unavailable'

legacy_output="$(env "${base_env[@]}" "$script_dir/aws/aws-sso-login.sh" --profile legacy)"
assert_contains "$legacy_output" 'SSO token expires in'
assert_contains "$legacy_output" 'Role credentials expires in'

login_output="$(env "${base_env[@]}" MOCK_AWS_MODE=expired "$script_dir/aws/aws-sso-login.sh" --profile test --no-browser)"
assert_contains "$login_output" 'invoked: sso login --profile test --no-browser'

printf 'PASS: aws-sso-login cache and login-path tests\n'
