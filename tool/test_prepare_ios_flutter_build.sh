#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREPARE_SCRIPT="$SCRIPT_DIR/prepare_ios_flutter_build.sh"
KT_TEST_TMP_DIR="$(mktemp -d)"
trap 'rm -r "$KT_TEST_TMP_DIR"' EXIT

fail() {
  echo "iOS Flutter build preparation test failed: $*" >&2
  exit 1
}

run_fixture() {
  local config_path="$1"
  local target="$2"
  local configuration="$3"
  local action="$4"

  KT_FLUTTER_GENERATED_XCCONFIG="$config_path" \
    FLUTTER_TARGET="$target" \
    DART_DEFINES="test-only-secret" \
    CONFIGURATION="$configuration" \
    ACTION="$action" \
    PREPARE_SCRIPT="$PREPARE_SCRIPT" \
    /bin/sh -c \
      '. "$PREPARE_SCRIPT"; printf "%s|%s" "$FLUTTER_TARGET" "${DART_DEFINES+present}"'
}

missing_listener="$KT_TEST_TMP_DIR/missing/flutter_test_listener.dead/listener.dart"
missing_config="$KT_TEST_TMP_DIR/missing.xcconfig"
printf 'FLUTTER_TARGET=%s\n' "$missing_listener" >"$missing_config"
[[ "$(run_fixture "$missing_config" "$missing_listener" Debug test)" == "lib/main.dart|" ]] ||
  fail "a missing test listener did not restore the production target"

live_listener="$KT_TEST_TMP_DIR/live/flutter_test_listener.live/listener.dart"
mkdir -p "$(dirname -- "$live_listener")"
: >"$live_listener"
live_config="$KT_TEST_TMP_DIR/live.xcconfig"
printf 'FLUTTER_TARGET=%s\n' "$live_listener" >"$live_config"
[[ "$(run_fixture "$live_config" "$live_listener" Debug test)" == "$live_listener|present" ]] ||
  fail "a live Debug integration-test target was modified"

[[ "$(run_fixture "$live_config" "$live_listener" Release install)" == "lib/main.dart|" ]] ||
  fail "an archive preserved a test listener or test-only Dart defines"

production_config="$KT_TEST_TMP_DIR/production.xcconfig"
printf 'FLUTTER_TARGET=lib/main.dart\n' >"$production_config"
[[ "$(run_fixture "$production_config" lib/main.dart Debug build)" == "lib/main.dart|present" ]] ||
  fail "a normal production build lost legitimate Dart defines"

echo "iOS Flutter build preparation vectors passed: 4/4"
