#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# A patched Go toolchain is part of the evidence. Do not let the scanner or
# Gateway silently fall back to an older globally installed patch release.
export GOTOOLCHAIN=go1.26.5+auto

"$REPO_ROOT/tool/audit_runtime_privacy.sh"
"$REPO_ROOT/tool/test_bundletool_version_reader.sh"
"$REPO_ROOT/tool/test_prepare_ios_flutter_build.sh"

GRADLE_WRAPPER_SHA256="76805e32c009c0cf0dd5d206bddc9fb22ea42e84db904b764f3047de095493f3"
GRADLE_DISTRIBUTION_SHA256="b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85"

verify_gradle_wrapper() {
  local android_root="$1"
  local wrapper_jar="$android_root/gradle/wrapper/gradle-wrapper.jar"
  local wrapper_properties="$android_root/gradle/wrapper/gradle-wrapper.properties"
  local actual_sha256

  actual_sha256="$(shasum -a 256 "$wrapper_jar" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$GRADLE_WRAPPER_SHA256" ]]; then
    echo "Unexpected Gradle wrapper JAR checksum: $wrapper_jar" >&2
    exit 1
  fi
  if ! grep -Fq "distributionSha256Sum=$GRADLE_DISTRIBUTION_SHA256" "$wrapper_properties"; then
    echo "Missing or unexpected Gradle distribution checksum: $wrapper_properties" >&2
    exit 1
  fi
  if ! grep -Fq 'validateDistributionUrl=true' "$wrapper_properties"; then
    echo "Gradle distribution URL validation is not enabled: $wrapper_properties" >&2
    exit 1
  fi
}

verify_gradle_wrapper "$REPO_ROOT/apps/kt_wallet/android"
verify_gradle_wrapper "$REPO_ROOT/apps/cold_signer/android"
verify_gradle_wrapper "$REPO_ROOT/packages/core_crypto/example/android"

# Resolve the exact production runtime graphs without --write-locks. Any
# coordinate added, removed or changed from the reviewed lock state fails.
(
  cd "$REPO_ROOT/apps/kt_wallet/android"
  ./gradlew verifyReleaseRuntimeDependencies --console=plain >/dev/null
)
(
  cd "$REPO_ROOT/apps/cold_signer/android"
  ./gradlew verifyReleaseRuntimeDependencies --console=plain >/dev/null
)

# CocoaPods has no native OSV lockfile extractor. `--deployment` enforces the
# committed versions/spec checksums; the dedicated audit below also pins remote
# source bytes/tags and queries their exact upstream commits through OSV.
(
  cd "$REPO_ROOT/apps/kt_wallet/ios"
  pod install --deployment --silent
)
(
  cd "$REPO_ROOT/apps/cold_signer/ios"
  pod install --deployment --silent
)

"$REPO_ROOT/tool/audit_apple_native_dependencies.sh"
"$REPO_ROOT/tool/test_portable_backup_swift.sh"

(
  cd "$REPO_ROOT/backend/gateway"
  make audit
)

# Scan only deployable/runtime lock states as a blocking gate. Gradle's
# verification metadata deliberately contains build-tool classpaths too; those
# are integrity-pinned but must be triaged separately from code packaged in the
# APK. It sends public dependency coordinates/versions to OSV, never wallet
# addresses, provider credentials, recovery phrases or source files.
go run github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.2.4 \
  scan source \
  --lockfile "$REPO_ROOT/pubspec.lock" \
  --lockfile "$REPO_ROOT/website/package-lock.json" \
  --lockfile "$REPO_ROOT/backend/gateway/go.mod" \
  --lockfile "$REPO_ROOT/apps/kt_wallet/android/app/gradle.lockfile" \
  --lockfile "$REPO_ROOT/apps/cold_signer/android/app/gradle.lockfile" \
  --no-resolve \
  --format=vertical
