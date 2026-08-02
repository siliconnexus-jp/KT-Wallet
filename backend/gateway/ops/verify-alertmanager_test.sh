#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
guard="$root/ops/verify-alertmanager.sh"
source_config="$root/ops/alertmanager/alertmanager.yml"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

sh "$guard" "$source_config" >/dev/null

cp "$source_config" "$scratch/credential.yml"
printf '\nwebhook_configs:\n' >> "$scratch/credential.yml"
if sh "$guard" "$scratch/credential.yml" >/dev/null 2>&1; then
  echo "alertmanager guard test: committed webhook destination was accepted" >&2
  exit 1
fi

sed '/trust="untrusted-client-report"/d' "$source_config" > "$scratch/no-untrusted.yml"
if sh "$guard" "$scratch/no-untrusted.yml" >/dev/null 2>&1; then
  echo "alertmanager guard test: missing untrusted route was accepted" >&2
  exit 1
fi

echo "alertmanager guard tests: OK"
