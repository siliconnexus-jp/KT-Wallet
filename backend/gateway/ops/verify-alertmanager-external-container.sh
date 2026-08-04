#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=${1:-prom/alertmanager@sha256:51a825c2a40acc3e338fdd00d622e01ec090f72be2b3ea46be0839cd47a4d286}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

secret="$scratch/external-webhook-url"
config="$scratch/alertmanager.external.yml"
printf '%s\n' 'https://alerts.example.test/v1/notify?key=fixture-not-a-secret' > "$secret"
chmod 600 "$secret"
sh "$root/ops/render-alertmanager-external.sh" "$secret" "$config" >/dev/null

run_amtool() {
  docker run --rm --entrypoint /bin/amtool \
    --user "$(id -u):$(id -g)" \
    -v "$scratch:$scratch:ro" \
    "$image" "$@" >/dev/null
}

run_amtool check-config "$config"
run_amtool config routes test --enable-feature=utf8-strict-mode \
  --config.file="$config" --verify.receivers=external-critical \
  severity=critical service=kt-wallet-gateway environment=production
run_amtool config routes test --enable-feature=utf8-strict-mode \
  --config.file="$config" --verify.receivers=external-warning \
  severity=warning service=kt-wallet-gateway environment=production
run_amtool config routes test --enable-feature=utf8-strict-mode \
  --config.file="$config" --verify.receivers=local-observation-untrusted \
  severity=info trust=untrusted-client-report \
  service=kt-wallet-client environment=production
run_amtool config routes test --enable-feature=utf8-strict-mode \
  --config.file="$config" --verify.receivers=local-observation-untrusted \
  severity=critical trust=untrusted-client-report \
  service=kt-wallet-client environment=production
run_amtool config routes test --enable-feature=utf8-strict-mode \
  --config.file="$config" --verify.receivers=local-observation-default \
  severity=info service=kt-wallet-gateway environment=production

echo "external alertmanager container guard: OK"
