#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render="$root/ops/render-alertmanager-external.sh"
guard="$root/ops/verify-alertmanager-external.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

secret="$scratch/external-webhook-url"
config="$scratch/alertmanager.external.yml"
printf '%s\n' 'https://alerts.example.test/v1/notify?key=fixture-not-a-secret' > "$secret"
chmod 600 "$secret"

sh "$render" "$secret" "$config"
sh "$guard" "$config" "$secret" >/dev/null

group_read_secret="$scratch/group-read-webhook-url"
group_read_config="$scratch/group-read.yml"
printf '%s\n' 'https://alerts.example.test/group-readable' > "$group_read_secret"
chmod 640 "$group_read_secret"
sh "$render" "$group_read_secret" "$group_read_config" >/dev/null
sh "$guard" "$group_read_config" "$group_read_secret" >/dev/null

if grep -Fq 'fixture-not-a-secret' "$config"; then
  echo "external alertmanager guard test: rendered config leaked webhook URL" >&2
  exit 1
fi
if [ "$(grep -Fc "url_file: $secret" "$config")" -ne 2 ]; then
  echo "external alertmanager guard test: webhook URL file is not referenced exactly twice" >&2
  exit 1
fi

sed 's/receiver: external-critical/receiver: local-observation-critical/' \
  "$config" > "$scratch/wrong-critical-route.yml"
if sh "$guard" "$scratch/wrong-critical-route.yml" "$secret" >/dev/null 2>&1; then
  echo "external alertmanager guard test: critical route drift was accepted" >&2
  exit 1
fi

cp "$config" "$scratch/inline-url.yml"
printf '\nurl: https://alerts.example.test/leaked\n' >> "$scratch/inline-url.yml"
if sh "$guard" "$scratch/inline-url.yml" "$secret" >/dev/null 2>&1; then
  echo "external alertmanager guard test: inline webhook URL was accepted" >&2
  exit 1
fi

bad_http="$scratch/http-webhook-url"
printf '%s\n' 'http://alerts.example.test/notify' > "$bad_http"
chmod 600 "$bad_http"
if sh "$render" "$bad_http" "$scratch/http.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: plaintext webhook URL was accepted" >&2
  exit 1
fi

bad_mode="$scratch/world-readable-webhook-url"
printf '%s\n' 'https://alerts.example.test/notify' > "$bad_mode"
chmod 644 "$bad_mode"
if sh "$render" "$bad_mode" "$scratch/world-readable.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: world-readable webhook URL was accepted" >&2
  exit 1
fi

bad_multiline="$scratch/multiline-webhook-url"
printf '%s\n%s\n' 'https://alerts.example.test/notify' 'second-line' > "$bad_multiline"
chmod 600 "$bad_multiline"
if sh "$render" "$bad_multiline" "$scratch/multiline.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: multiline webhook URL was accepted" >&2
  exit 1
fi

bad_authority="$scratch/userinfo-webhook-url"
printf '%s\n' 'https://user:password@alerts.example.test/notify' > "$bad_authority"
chmod 600 "$bad_authority"
if sh "$render" "$bad_authority" "$scratch/userinfo.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: webhook URL user information was accepted" >&2
  exit 1
fi

bad_host="$scratch/hostless-webhook-url"
printf '%s\n' 'https:///notify' > "$bad_host"
chmod 600 "$bad_host"
if sh "$render" "$bad_host" "$scratch/hostless.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: hostless webhook URL was accepted" >&2
  exit 1
fi

bad_fragment="$scratch/fragment-webhook-url"
printf '%s\n' 'https://alerts.example.test/notify#credential' > "$bad_fragment"
chmod 600 "$bad_fragment"
if sh "$render" "$bad_fragment" "$scratch/fragment.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: webhook URL fragment was accepted" >&2
  exit 1
fi

bad_oversized="$scratch/oversized-webhook-url"
awk 'BEGIN { printf "https://alerts.example.test/"; for (i = 0; i < 2050; i++) printf "a"; printf "\n" }' \
  > "$bad_oversized"
chmod 600 "$bad_oversized"
if sh "$render" "$bad_oversized" "$scratch/oversized.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: oversized webhook URL was accepted" >&2
  exit 1
fi

if sh "$render" "$scratch/missing-webhook-url" "$scratch/missing.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: missing webhook URL file was accepted" >&2
  exit 1
fi

symlink_secret="$scratch/symlink-webhook-url"
ln -s "$secret" "$symlink_secret"
if sh "$render" "$symlink_secret" "$scratch/symlink.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: symlink webhook URL file was accepted" >&2
  exit 1
fi

bad_path="$scratch/path with spaces"
printf '%s\n' 'https://alerts.example.test/notify' > "$bad_path"
chmod 600 "$bad_path"
if sh "$render" "$bad_path" "$scratch/path.yml" >/dev/null 2>&1; then
  echo "external alertmanager guard test: unsafe YAML file path was accepted" >&2
  exit 1
fi

existing="$scratch/existing.yml"
printf '%s\n' 'operator-owned-content' > "$existing"
if sh "$render" "$secret" "$existing" >/dev/null 2>&1; then
  echo "external alertmanager guard test: existing output was overwritten" >&2
  exit 1
fi
if [ "$(sed -n '1p' "$existing")" != 'operator-owned-content' ]; then
  echo "external alertmanager guard test: failed render modified existing output" >&2
  exit 1
fi

dangling="$scratch/dangling-output.yml"
ln -s "$scratch/nonexistent-output-target" "$dangling"
if sh "$render" "$secret" "$dangling" >/dev/null 2>&1; then
  echo "external alertmanager guard test: dangling output symlink was overwritten" >&2
  exit 1
fi
[ -L "$dangling" ] || {
  echo "external alertmanager guard test: failed render removed dangling output symlink" >&2
  exit 1
}

echo "external alertmanager guard tests: OK"
