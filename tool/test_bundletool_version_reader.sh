#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
reader="$script_dir/read_bundletool_version.dart"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kt-bundle-reader.XXXXXX")"
cleanup_bundle_reader_test() {
  case "${test_tmp##*/}" in
    kt-bundle-reader.*) rm -rf -- "$test_tmp" ;;
    *) echo "Refusing to clean unexpected temporary path" >&2 ;;
  esac
}
trap cleanup_bundle_reader_test EXIT

expect_invalid() {
  local fixture="$1"
  local log="$test_tmp/invalid.log"
  if dart "$reader" "$fixture" >"$log" 2>&1; then
    echo "BundleConfig negative vector was accepted" >&2
    exit 1
  fi
  if [[ "$(cat "$log")" != "Invalid BundleConfig.pb" ]]; then
    echo "BundleConfig negative vector leaked an unstable error" >&2
    exit 1
  fi
}

# BundleConfig.bundletool.version = "1.18.3".
printf '\x0a\x08\x12\x06\x31\x2e\x31\x38\x2e\x33' \
  >"$test_tmp/valid.pb"
if [[ "$(dart "$reader" "$test_tmp/valid.pb")" != "1.18.3" ]]; then
  echo "BundleConfig positive vector failed" >&2
  exit 1
fi

printf '\x0a\x08\x12' >"$test_tmp/truncated.pb"
expect_invalid "$test_tmp/truncated.pb"

printf '\x0a\x08\x12\x06\x31\x2e\x31\x38\x2e\x33\x0a\x08\x12\x06\x31\x2e\x31\x38\x2e\x33' \
  >"$test_tmp/duplicate.pb"
expect_invalid "$test_tmp/duplicate.pb"

printf '\x0a\x04\x12\x02\xc3\x28' >"$test_tmp/invalid-utf8.pb"
expect_invalid "$test_tmp/invalid-utf8.pb"

printf '\x0a\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02' \
  >"$test_tmp/overflow.pb"
expect_invalid "$test_tmp/overflow.pb"

printf '\x13' >"$test_tmp/unsupported-wire.pb"
expect_invalid "$test_tmp/unsupported-wire.pb"

echo "bundletool version reader: 1 positive + 5 negative vectors passed"
