#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# CocoaPods is not a first-class OSV lockfile ecosystem. Keep the small set of
# remote native dependencies independently reviewable instead of treating a
# successful `pod install --deployment` as vulnerability evidence.
TRUST_WALLET_CORE_VERSION="4.7.0"
TRUST_WALLET_CORE_SPEC_SHA1="2585d49bc854da68a61bd1576dc7cdd928ac1e1c"
TRUST_WALLET_CORE_SOURCE="https://github.com/trustwallet/wallet-core/releases/download/4.7.0/TrustWalletCore-4.7.0.tar.xz"
TRUST_WALLET_CORE_ARCHIVE_SHA256="24cd2707cdec0c856234f350ca62cd0b80c0ffce5776ea067e526469d25957a4"
TRUST_WALLET_CORE_REPO="https://github.com/trustwallet/wallet-core.git"
TRUST_WALLET_CORE_TAG="4.7.0"
TRUST_WALLET_CORE_COMMIT="e231585e2850443009e33f68b49486a5a6ea6337"

SWIFT_PROTOBUF_VERSION="1.29.0"
SWIFT_PROTOBUF_SPEC_SHA1="a4798576a2d309511fc45f81843d348732ec571d"
SWIFT_PROTOBUF_REPO="https://github.com/apple/swift-protobuf.git"
SWIFT_PROTOBUF_TAG="1.29.0"
SWIFT_PROTOBUF_COMMIT="d72aed98f8253ec1aa9ea1141e28150f408cf17f"

SQLITE_DART_VERSION="3.5.0"
SQLITE_UPSTREAM_VERSION="3.53.3"
SQLITE_REPO="https://github.com/sqlite/sqlite.git"
SQLITE_TAG="version-3.53.3"
SQLITE_COMMIT="92a6c5c3636faa021ecc3be5403a00f50f65eda7"
SQLITE_RELEASE_TAG="sqlite3-3.5.0"

fail() {
  echo "Apple native dependency audit failed: $*" >&2
  exit 1
}

for command_name in curl dart git jq pod shasum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done

verify_lock() {
  local lock_file="$1"

  grep -Fqx "  - TrustWalletCore ($TRUST_WALLET_CORE_VERSION):" "$lock_file" ||
    fail "$lock_file does not lock TrustWalletCore $TRUST_WALLET_CORE_VERSION"
  grep -Fqx "  - WalletCoreSwiftProtobuf ($SWIFT_PROTOBUF_VERSION)" "$lock_file" ||
    fail "$lock_file does not lock WalletCoreSwiftProtobuf $SWIFT_PROTOBUF_VERSION"
  grep -Fqx "  TrustWalletCore: $TRUST_WALLET_CORE_SPEC_SHA1" "$lock_file" ||
    fail "$lock_file has an unexpected TrustWalletCore spec checksum"
  grep -Fqx "  WalletCoreSwiftProtobuf: $SWIFT_PROTOBUF_SPEC_SHA1" "$lock_file" ||
    fail "$lock_file has an unexpected WalletCoreSwiftProtobuf spec checksum"

  if grep -Eq '^  - (sqlite3|sqlite3_flutter_libs)([ /]| \()' "$lock_file"; then
    fail "$lock_file still packages the retired CocoaPods SQLite 3.52.0 path"
  fi
}

verify_lock "$REPO_ROOT/apps/kt_wallet/ios/Podfile.lock"
verify_lock "$REPO_ROOT/apps/cold_signer/ios/Podfile.lock"

verify_profile_config() {
  local ios_root="$1"
  local profile_config="$ios_root/Flutter/Profile.xcconfig"
  local project_file="$ios_root/Runner.xcodeproj/project.pbxproj"

  grep -Fqx '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"' \
    "$profile_config" || fail "$profile_config does not include the Profile Pod settings"
  grep -Fqx '#include "Generated.xcconfig"' "$profile_config" ||
    fail "$profile_config does not include Flutter generated settings"
  grep -Fqx 'FLUTTER_TARGET=lib/main.dart' "$profile_config" ||
    fail "$profile_config can package a temporary Flutter test listener"
  grep -Fq 'baseConfigurationReference = C0DE00012EC6000000000001 /* Profile.xcconfig */;' \
    "$project_file" || fail "$project_file does not use Profile.xcconfig for Runner Profile"
}

verify_profile_config "$REPO_ROOT/apps/kt_wallet/ios"
verify_profile_config "$REPO_ROOT/apps/cold_signer/ios"

trust_spec="$(pod spec which TrustWalletCore --version="$TRUST_WALLET_CORE_VERSION")"
swift_protobuf_spec="$(pod spec which WalletCoreSwiftProtobuf --version="$SWIFT_PROTOBUF_VERSION")"

jq -e --arg source "$TRUST_WALLET_CORE_SOURCE" \
  '.source.http == $source' "$trust_spec" >/dev/null ||
  fail "TrustWalletCore PodSpec source changed"
jq -e --arg repo "${SWIFT_PROTOBUF_REPO%.git}" --arg tag "$SWIFT_PROTOBUF_TAG" \
  '(.source.git | rtrimstr(".git")) == $repo and .source.tag == $tag' \
  "$swift_protobuf_spec" >/dev/null ||
  fail "WalletCoreSwiftProtobuf PodSpec source changed"

resolve_tag() {
  local repo="$1"
  local tag="$2"
  local refs
  local resolved

  refs="$(git ls-remote "$repo" "refs/tags/$tag" "refs/tags/$tag^{}")" ||
    fail "cannot resolve $repo tag $tag"
  resolved="$(printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ {print $1; exit}')"
  if [[ -z "$resolved" ]]; then
    resolved="$(printf '%s\n' "$refs" | awk -v ref="refs/tags/$tag" '$2 == ref {print $1; exit}')"
  fi
  [[ -n "$resolved" ]] || fail "empty commit for $repo tag $tag"
  printf '%s' "$resolved"
}

[[ "$(resolve_tag "$TRUST_WALLET_CORE_REPO" "$TRUST_WALLET_CORE_TAG")" == "$TRUST_WALLET_CORE_COMMIT" ]] ||
  fail "TrustWalletCore tag moved"
[[ "$(resolve_tag "$SWIFT_PROTOBUF_REPO" "$SWIFT_PROTOBUF_TAG")" == "$SWIFT_PROTOBUF_COMMIT" ]] ||
  fail "WalletCoreSwiftProtobuf tag moved"
[[ "$(resolve_tag "$SQLITE_REPO" "$SQLITE_TAG")" == "$SQLITE_COMMIT" ]] ||
  fail "SQLite tag moved"

# The TrustWalletCore pod is a prebuilt HTTP archive and its PodSpec does not
# publish a digest. Verify the release bytes directly on every audit run.
trust_archive_sha256="$(
  curl -fsSL --retry 2 --proto '=https' "$TRUST_WALLET_CORE_SOURCE" |
    shasum -a 256 |
    awk '{print $1}'
)" || fail "cannot download or hash TrustWalletCore archive"
[[ "$trust_archive_sha256" == "$TRUST_WALLET_CORE_ARCHIVE_SHA256" ]] ||
  fail "TrustWalletCore archive checksum changed"

pub_deps="$(cd "$REPO_ROOT" && dart pub deps --json)"
sqlite_dart_version="$(
  jq -r '.packages[] | select(.name == "sqlite3") | .version' <<<"$pub_deps"
)"
[[ "$sqlite_dart_version" == "$SQLITE_DART_VERSION" ]] ||
  fail "expected sqlite3 Dart $SQLITE_DART_VERSION, got $sqlite_dart_version"
if jq -e '.packages[] | select(.name == "sqlite3_flutter_libs")' \
  <<<"$pub_deps" >/dev/null; then
  fail "sqlite3_flutter_libs must remain removed"
fi

sqlite_package_root="$(
  dart pub cache list |
    jq -r --arg version "$SQLITE_DART_VERSION" '.packages.sqlite3[$version].location'
)"
[[ -d "$sqlite_package_root" ]] || fail "sqlite3 package cache is unavailable"
sqlite_hashes="$sqlite_package_root/lib/src/hook/asset_hashes.dart"
sqlite_changelog="$sqlite_package_root/CHANGELOG.md"

grep -Fq "releaseTag = '$SQLITE_RELEASE_TAG'" "$sqlite_hashes" ||
  fail "sqlite3 native asset release tag is not pinned"
grep -Fq "Update SQLite to $SQLITE_UPSTREAM_VERSION" "$sqlite_changelog" ||
  fail "sqlite3 package does not document SQLite $SQLITE_UPSTREAM_VERSION"
for required_asset in \
  libsqlite3.arm.android.so \
  libsqlite3.arm64.android.so \
  libsqlite3.x64.android.so \
  libsqlite3.arm64.ios.dylib \
  libsqlite3.arm64.ios_sim.dylib \
  libsqlite3.x64.ios_sim.dylib; do
  grep -Eq "'$required_asset': '[0-9a-f]{64}'" "$sqlite_hashes" ||
    fail "sqlite3 package does not hash $required_asset"
done

# OSV has no CocoaPods package matcher, but it does support exact source
# commits. Query all three upstream commits and fail closed on API errors,
# pagination or any advisory. Only public commit hashes leave this machine.
osv_payload="$(jq -n \
  --arg wallet_core "$TRUST_WALLET_CORE_COMMIT" \
  --arg swift_protobuf "$SWIFT_PROTOBUF_COMMIT" \
  --arg sqlite "$SQLITE_COMMIT" \
  '{queries: [
    {commit: $wallet_core},
    {commit: $swift_protobuf},
    {commit: $sqlite}
  ]}')"
osv_response="$(
  curl -fsS --retry 2 --proto '=https' \
    -H 'content-type: application/json' \
    -d "$osv_payload" \
    https://api.osv.dev/v1/querybatch
)" || fail "OSV commit query failed"

jq -e '.results | length == 3' <<<"$osv_response" >/dev/null ||
  fail "OSV returned an incomplete result set"
if jq -e '.results[] | select(has("next_page_token"))' \
  <<<"$osv_response" >/dev/null; then
  fail "OSV response was paginated; refusing an incomplete audit"
fi
if jq -e '.results[] | (.vulns // []) | length > 0' \
  <<<"$osv_response" >/dev/null; then
  jq -r '.results[] | (.vulns // [])[] | .id' <<<"$osv_response" >&2
  fail "OSV found a known vulnerability in an Apple native dependency"
fi

echo "Apple native dependency audit passed: 2 remote Pods + SQLite $SQLITE_UPSTREAM_VERSION"
