#!/bin/sh
set -eu

config=${1:-ops/haproxy/haproxy.cfg}

if [ ! -f "$config" ]; then
  echo "HAProxy guard: missing config: $config" >&2
  exit 1
fi

retry_count=$(grep -Ec '^[[:space:]]*retries[[:space:]]+0([[:space:]]|$)' "$config" || true)
if [ "$retry_count" -ne 1 ]; then
  echo "HAProxy guard: exactly one 'retries 0' directive is required" >&2
  exit 1
fi

if grep -Eiq '^[[:space:]]*(option[[:space:]]+redispatch|retry-on)([[:space:]]|$)' "$config"; then
  echo "HAProxy guard: redispatch/retry-on can replay kt_broadcast" >&2
  exit 1
fi

echo "HAProxy guard: OK"
