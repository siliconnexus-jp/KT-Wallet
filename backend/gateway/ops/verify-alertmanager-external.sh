#!/bin/sh
set -eu

config=${1:-}
secret_file=${2:-}

fail() {
  echo "external alertmanager guard: $1" >&2
  exit 1
}

[ -n "$config" ] || fail "missing rendered config path"
[ -n "$secret_file" ] || fail "missing webhook URL file path"
[ -f "$config" ] || fail "missing rendered config"
[ -f "$secret_file" ] || fail "missing webhook URL file"
[ ! -L "$secret_file" ] || fail "webhook URL file must not be a symlink"

case "$secret_file" in
  /*) ;;
  *) fail "webhook URL file path must be absolute" ;;
esac
if ! printf '%s\n' "$secret_file" | LC_ALL=C grep -Eq '^/[A-Za-z0-9._/-]+$'; then
  fail "webhook URL file path contains unsafe YAML characters"
fi
case "$secret_file" in
  *//*|*/../*|*/./*|*/..|*/.)
    fail "webhook URL file path is not canonical"
    ;;
esac

mode=$(stat -f '%Lp' "$secret_file" 2>/dev/null || stat -c '%a' "$secret_file" 2>/dev/null || true)
case "$mode" in
  400|440|600|640) ;;
  *) fail "webhook URL file mode must be 0400, 0440, 0600 or 0640" ;;
esac

line_count=$(awk 'END { print NR }' "$secret_file")
[ "$line_count" -eq 1 ] || fail "webhook URL file must contain exactly one line"
byte_count=$(wc -c < "$secret_file" | tr -d '[:space:]')
[ "$byte_count" -ge 10 ] && [ "$byte_count" -le 2048 ] || fail "webhook URL is empty or oversized"
if ! LC_ALL=C grep -Eq '^https://[^/?#[:space:]]+([/?][^#[:space:]]*)?$' "$secret_file"; then
  fail "webhook URL must be one fragment-free HTTPS URL"
fi
if LC_ALL=C grep -Eq '^https://[^/?#[:space:]]*@' "$secret_file"; then
  fail "webhook URL authority must not contain user information"
fi

webhook_url=$(sed -n '1p' "$secret_file")
if grep -Fq -- "$webhook_url" "$config"; then
  fail "rendered config contains the webhook URL instead of url_file"
fi
if grep -Eq '^[[:space:]]*url:[[:space:]]' "$config"; then
  fail "rendered config contains an inline webhook URL"
fi
if grep -Eqi '^[[:space:]]+(password|credentials|api[_-]?key|token|secret):' "$config"; then
  fail "rendered config contains an inline credential field"
fi

require_line_count() {
  expected=$1
  literal=$2
  actual=$(grep -Fxc -- "$literal" "$config" || true)
  [ "$actual" -eq "$expected" ] || fail "expected $expected occurrence(s) of: $literal"
}

require_line_count 1 "  receiver: local-observation-default"
require_line_count 1 "    - receiver: local-observation-untrusted"
require_line_count 1 "    - receiver: external-critical"
require_line_count 1 "    - receiver: external-warning"
require_line_count 1 "  - name: local-observation-default"
require_line_count 1 "  - name: local-observation-untrusted"
require_line_count 1 "  - name: external-critical"
require_line_count 1 "  - name: external-warning"
require_line_count 2 "    webhook_configs:"
require_line_count 2 "        url_file: $secret_file"
require_line_count 2 "      - send_resolved: true"
require_line_count 2 "        max_alerts: 20"
require_line_count 2 "        timeout: 10s"
require_line_count 2 "          follow_redirects: false"

receiver_count=$(grep -Ec '^  - name: ' "$config")
[ "$receiver_count" -eq 4 ] || fail "expected exactly four receivers"
url_file_count=$(grep -Ec '^[[:space:]]+url_file:' "$config")
[ "$url_file_count" -eq 2 ] || fail "unexpected webhook URL file reference"

if command -v amtool >/dev/null 2>&1; then
  amtool check-config "$config" >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" --verify.receivers=external-critical \
    severity=critical service=kt-wallet-gateway environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" --verify.receivers=external-warning \
    severity=warning service=kt-wallet-gateway environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" --verify.receivers=local-observation-untrusted \
    severity=info trust=untrusted-client-report \
    service=kt-wallet-client environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" --verify.receivers=local-observation-untrusted \
    severity=critical trust=untrusted-client-report \
    service=kt-wallet-client environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" --verify.receivers=local-observation-default \
    severity=info service=kt-wallet-gateway environment=production >/dev/null
fi

echo "external alertmanager guard: OK"
