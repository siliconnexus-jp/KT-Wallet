#!/bin/sh
set -eu

config=${1:-ops/alertmanager/alertmanager.yml}

if [ ! -f "$config" ]; then
  echo "alertmanager guard: missing config: $config" >&2
  exit 1
fi

require_literal() {
  literal=$1
  if ! grep -Fq -- "$literal" "$config"; then
    echo "alertmanager guard: missing required policy: $literal" >&2
    exit 1
  fi
}

require_literal "receiver: local-observation-default"
require_literal 'severity="critical"'
require_literal 'severity="warning"'
require_literal 'trust="untrusted-client-report"'
require_literal "receiver: local-observation-critical"
require_literal "receiver: local-observation-warning"
require_literal "receiver: local-observation-untrusted"
require_literal "source_matchers:"
require_literal "target_matchers:"
require_literal "equal: [environment, service]"

# Repository configuration is deliberately receiver-neutral. Notification
# credentials and destinations belong in an operator-owned overlay and must
# never be committed alongside the wallet source.
if grep -Eqi '(api[_-]?key|password|token|secret|webhook_configs:|email_configs:|slack_configs:|telegram_configs:|pagerduty_configs:|opsgenie_configs:)' "$config"; then
  echo "alertmanager guard: committed config contains a destination or credential field" >&2
  exit 1
fi

receiver_count=$(grep -Ec '^  - name: local-observation-' "$config")
if [ "$receiver_count" -ne 4 ]; then
  echo "alertmanager guard: expected exactly four receiver-neutral local routes" >&2
  exit 1
fi

if command -v amtool >/dev/null 2>&1; then
  amtool check-config "$config"
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" \
    --verify.receivers=local-observation-critical \
    severity=critical service=kt-wallet-gateway environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" \
    --verify.receivers=local-observation-warning \
    severity=warning service=kt-wallet-gateway environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" \
    --verify.receivers=local-observation-untrusted \
    severity=info trust=untrusted-client-report \
    service=kt-wallet-client environment=production >/dev/null
  amtool config routes test --enable-feature=utf8-strict-mode \
    --config.file="$config" \
    --verify.receivers=local-observation-default \
    severity=info service=kt-wallet-gateway environment=production >/dev/null
fi

echo "alertmanager guard: OK"
