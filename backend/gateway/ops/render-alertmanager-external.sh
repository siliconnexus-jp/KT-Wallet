#!/bin/sh
set -eu
umask 077

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_config="$root/ops/alertmanager/alertmanager.yml"
guard="$root/ops/verify-alertmanager-external.sh"
secret_file=${1:-}
output=${2:-}

fail() {
  echo "external alertmanager renderer: $1" >&2
  exit 1
}

[ -n "$secret_file" ] || fail "usage: render-alertmanager-external.sh WEBHOOK_URL_FILE OUTPUT"
[ -n "$output" ] || fail "usage: render-alertmanager-external.sh WEBHOOK_URL_FILE OUTPUT"
case "$secret_file" in /*) ;; *) fail "webhook URL file path must be absolute" ;; esac
case "$output" in /*) ;; *) fail "output path must be absolute" ;; esac
for path in "$secret_file" "$output"
do
  if ! printf '%s\n' "$path" | LC_ALL=C grep -Eq '^/[A-Za-z0-9._/-]+$'; then
    fail "paths must be absolute and contain only safe YAML path characters"
  fi
  case "$path" in *//*|*/../*|*/./*|*/..|*/.) fail "paths must be canonical" ;; esac
done
[ "$secret_file" != "$output" ] || fail "output must not replace the webhook URL file"
[ "$output" != "$source_config" ] || fail "output must not replace the repository baseline"
[ ! -e "$output" ] && [ ! -L "$output" ] || \
  fail "output already exists; render to a new candidate path"
output_dir=$(dirname -- "$output")
[ -d "$output_dir" ] || fail "output directory does not exist"

sh "$root/ops/verify-alertmanager.sh" "$source_config" >/dev/null
for literal in \
  '    - receiver: local-observation-critical' \
  '    - receiver: local-observation-warning' \
  '  - name: local-observation-critical' \
  '  - name: local-observation-warning'
do
  [ "$(grep -Fc -- "$literal" "$source_config")" -eq 1 ] || \
    fail "repository baseline no longer has the expected unique insertion point"
done

candidate=$(mktemp "$output_dir/.alertmanager.external.XXXXXX")
trap 'rm -f "$candidate"' EXIT HUP INT TERM
awk -v secret="$secret_file" '
  $0 == "    - receiver: local-observation-critical" {
    print "    - receiver: external-critical"
    next
  }
  $0 == "    - receiver: local-observation-warning" {
    print "    - receiver: external-warning"
    next
  }
  $0 == "  - name: local-observation-critical" {
    print "  - name: external-critical"
    print "    webhook_configs:"
    print "      - send_resolved: true"
    print "        url_file: " secret
    print "        max_alerts: 20"
    print "        timeout: 10s"
    print "        http_config:"
    print "          follow_redirects: false"
    next
  }
  $0 == "  - name: local-observation-warning" {
    print "  - name: external-warning"
    print "    webhook_configs:"
    print "      - send_resolved: true"
    print "        url_file: " secret
    print "        max_alerts: 20"
    print "        timeout: 10s"
    print "        http_config:"
    print "          follow_redirects: false"
    next
  }
  { print }
' "$source_config" > "$candidate"

chmod 600 "$candidate"
sh "$guard" "$candidate" "$secret_file" >/dev/null
mv "$candidate" "$output"
trap - EXIT HUP INT TERM
echo "external alertmanager renderer: candidate created and verified"
