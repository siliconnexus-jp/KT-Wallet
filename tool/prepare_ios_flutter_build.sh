#!/bin/sh

# Flutter integration tests temporarily rewrite Generated.xcconfig so Xcode
# compiles an ephemeral flutter_test_listener.dart and injects test-only Dart
# defines. If the Flutter tool exits, that ignored file can outlive the listener
# and poison the next build or archive. This script is sourced by both iOS App
# build phases so it can repair the current shell environment without weakening
# a live Flutter integration-test build.

kt_generated_config="${KT_FLUTTER_GENERATED_XCCONFIG:-${SRCROOT:-}/Flutter/Generated.xcconfig}"
kt_generated_target=""

if [ -f "$kt_generated_config" ]; then
  kt_generated_target="$({
    awk -F= '$1 == "FLUTTER_TARGET" { print substr($0, index($0, "=") + 1); exit }' \
      "$kt_generated_config"
  } 2>/dev/null || true)"
fi

case "$kt_generated_target" in
  */flutter_test_listener.*/listener.dart)
    kt_should_restore_production=0
    case "${CONFIGURATION:-}" in
      *Release* | *Profile*) kt_should_restore_production=1 ;;
    esac
    if [ "${ACTION:-}" = "install" ] || [ ! -f "$kt_generated_target" ]; then
      kt_should_restore_production=1
    fi

    if [ "$kt_should_restore_production" -eq 1 ]; then
      export FLUTTER_TARGET=lib/main.dart
      unset DART_DEFINES
      printf '%s\n' \
        'warning: restored lib/main.dart after a stale Flutter test listener; test-only Dart defines were discarded' \
        >&2
    fi
    unset kt_should_restore_production
    ;;
esac

unset kt_generated_config kt_generated_target
