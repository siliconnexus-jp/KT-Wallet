#!/usr/bin/env bash
set -euo pipefail

release_artifact="${1:-apps/kt_wallet/build/app/outputs/flutter-apk/app-release.apk}"
expected_package="${2:-}"

if [[ ! -f "$release_artifact" ]]; then
  echo "Release artifact not found: $release_artifact" >&2
  exit 2
fi

case "$release_artifact" in
  *.apk) artifact_kind="apk" ;;
  *.aab) artifact_kind="aab" ;;
  *)
    echo "Unsupported release artifact: $release_artifact" >&2
    exit 2
    ;;
esac

if [[ -z "$expected_package" ]]; then
  case "$release_artifact" in
    *apps/kt_wallet/*) expected_package="cc.siliconnexus.ktwallet" ;;
    *apps/cold_signer/*)
      expected_package="cc.siliconnexus.ktwallet.coldsigner"
      ;;
    *)
      echo "Expected package is required for an artifact outside apps/*/build" >&2
      exit 2
      ;;
  esac
fi

case "$expected_package" in
  cc.siliconnexus.ktwallet | cc.siliconnexus.ktwallet.coldsigner) ;;
  *)
    echo "Unsupported expected package: $expected_package" >&2
    exit 2
    ;;
esac

release_guard_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kt-wallet-release.XXXXXX")"
cleanup_release_guard() {
  case "${release_guard_tmp##*/}" in
    kt-wallet-release.*) rm -rf -- "$release_guard_tmp" ;;
    *) echo "Refusing to clean unexpected temporary path" >&2 ;;
  esac
}
trap cleanup_release_guard EXIT

unpacked_dir="$release_guard_tmp/unpacked"
manifest_file="$release_guard_tmp/AndroidManifest.xml"
certificate_log="$release_guard_tmp/certificates.txt"
mkdir -p "$unpacked_dir"

# Validate every archive path before extraction. Release artifacts may be
# supplied by CI or another workstation; a malicious ZIP entry must never
# escape the isolated temporary directory or create a symlink there.
archive_entries="$release_guard_tmp/archive-entries.txt"
unzip -Z1 "$release_artifact" >"$archive_entries"
read -r archive_uncompressed_bytes archive_entry_count <<<"$(
  unzip -l "$release_artifact" | awk 'END { print $1, $2 }'
)"
if [[ ! "$archive_uncompressed_bytes" =~ ^[0-9]+$ ||
  ! "$archive_entry_count" =~ ^[0-9]+$ ||
  "$archive_uncompressed_bytes" -gt 1073741824 ||
  "$archive_entry_count" -gt 10000 ]]; then
  echo "FORBIDDEN release archive: invalid or excessive expansion" >&2
  exit 1
fi
unsafe_archive_path=0
while IFS= read -r archive_entry; do
  case "$archive_entry" in
    "" | /* | .. | ../* | */../* | *\\*)
      unsafe_archive_path=1
      ;;
  esac
done <"$archive_entries"
if [[ "$unsafe_archive_path" -ne 0 ]] ||
  zipinfo -l "$release_artifact" | awk 'NR > 2 && $1 ~ /^l/ { found=1 } END { exit !found }'; then
  echo "FORBIDDEN release archive: unsafe path or symbolic link" >&2
  exit 1
fi
unzip -qo "$release_artifact" -d "$unpacked_dir"

failed=0

if [[ "$artifact_kind" == "aab" ]]; then
  required_bundle_entries=(
    BundleConfig.pb
    base/manifest/AndroidManifest.xml
    base/dex/classes.dex
  )
  for bundle_entry in "${required_bundle_entries[@]}"; do
    if [[ ! -f "$unpacked_dir/$bundle_entry" ]]; then
      echo "MISSING required App Bundle entry: $bundle_entry" >&2
      failed=1
    else
      echo "OK: App Bundle entry $bundle_entry"
    fi
  done
  native_library_root="$unpacked_dir/base/lib"
else
  native_library_root="$unpacked_dir/lib"
fi

# Scan the whole uncompressed APK, including DEX where the fail-closed Wallet
# Core bridge leaves its exact diagnostic marker, not only one native ABI. A
# future Gradle regression must not pass merely because it packaged
# libTrustWalletCore.so while compiling the Kotlin stub bridge. The old
# pipeline used
# `strings | grep -q` under pipefail; a real match could terminate `strings`
# with SIGPIPE (141) and incorrectly report the marker as absent.
forbidden_markers=(
  "KT_ALLOW_MOCK_CRYPTO"
  "MockCoreCrypto"
  "demoSignResult"
  "SIGNED-V1:"
  "KT Wallet — 屏幕库"
  "TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa"
  "Trust Wallet Core is not linked in this build (walletCore=false)"
)
for marker in "${forbidden_markers[@]}"; do
  if LC_ALL=C grep -aR -Fq -- "$marker" "$unpacked_dir"; then
    echo "FORBIDDEN release marker detected" >&2
    failed=1
  else
    echo "OK: forbidden release marker absent"
  fi
done

# Provider and repository tokens must never be compiled into a client binary.
# Report only the category, never the matching credential.
if LC_ALL=C grep -aR -Eq \
  'github_pat_[A-Za-z0-9_]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|alch_[A-Za-z0-9_-]{12,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk_(live|test)_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|(api[_-]?key|access[_-]?token|bearer[_-]?token)[=:][A-Za-z0-9_+./=-]{20,}' \
  "$unpacked_dir"; then
  echo "FORBIDDEN release credential pattern detected" >&2
  failed=1
else
  echo "OK: no provider/repository credential pattern"
fi

# If a funded local E2E phrase exists, use its exact value as a private canary.
# The phrase is never printed, even when a leak is found.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
local_e2e_file="$repo_root/apps/kt_wallet/integration_test/.sepolia-e2e.json"
if [[ -f "$local_e2e_file" ]]; then
  local_mnemonic="$({
    sed -n 's/.*"SEPOLIA_E2E_MNEMONIC"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$local_e2e_file"
  } | head -n 1)"
  if [[ -n "$local_mnemonic" ]] &&
    LC_ALL=C grep -aR -Fq -- "$local_mnemonic" "$unpacked_dir"; then
    echo "FORBIDDEN local E2E mnemonic canary detected" >&2
    failed=1
  else
    echo "OK: local E2E mnemonic canary absent"
  fi
fi

# A universal APK or base AAB module is accepted only when every advertised
# ABI contains the Dart release image, real Wallet Core and pinned SQLite.
for abi in arm64-v8a armeabi-v7a x86_64; do
  for library in libapp.so libTrustWalletCore.so libsqlite3.so; do
    if [[ ! -f "$native_library_root/$abi/$library" ]]; then
      echo "MISSING release native library: $abi/$library" >&2
      failed=1
    else
      echo "OK: native library $abi/$library"
    fi
  done

  sqlite_library="$native_library_root/$abi/libsqlite3.so"
  if [[ -f "$sqlite_library" ]]; then
    if ! LC_ALL=C grep -aFq -- '3.53.3' "$sqlite_library"; then
      echo "FORBIDDEN SQLite runtime version: $abi is not 3.53.3" >&2
      failed=1
    elif LC_ALL=C grep -aFq -- '3.52.0' "$sqlite_library"; then
      echo "FORBIDDEN vulnerable SQLite 3.52.0 marker: $abi" >&2
      failed=1
    else
      echo "OK: SQLite 3.53.3 runtime $abi"
    fi
  fi
done

# Source manifests are not proof of what ships: Android libraries can add
# permissions and components during manifest merge. Inspect the final APK or
# protobuf manifest from the base module of the final App Bundle.
apkanalyzer_bin="$(command -v apkanalyzer || true)"
if [[ -z "$apkanalyzer_bin" ]]; then
  android_sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "$android_sdk_dir" &&
    -x "$android_sdk_dir/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    apkanalyzer_bin="$android_sdk_dir/cmdline-tools/latest/bin/apkanalyzer"
  elif [[ -x "$HOME/Library/Android/sdk/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    apkanalyzer_bin="$HOME/Library/Android/sdk/cmdline-tools/latest/bin/apkanalyzer"
  fi
fi
if [[ "$artifact_kind" == "apk" && -z "$apkanalyzer_bin" ]]; then
  echo "apkanalyzer is required to verify the merged release manifest" >&2
  exit 2
fi

if [[ "$artifact_kind" == "apk" ]]; then
  "$apkanalyzer_bin" manifest print "$release_artifact" >"$manifest_file"
else
  # Bind validation to the producer version embedded in BundleConfig.pb and a
  # separately reviewed toolchain lock. Never pick the newest unrelated JAR
  # from a developer's cache.
  if ! command -v xmllint >/dev/null 2>&1; then
    echo "xmllint is required to verify the Android release toolchain" >&2
    exit 2
  fi
  bundletool_version_reader="$repo_root/tool/read_bundletool_version.dart"
  toolchain_lock="$repo_root/tool/android-release-toolchain.lock"
  if [[ ! -f "$bundletool_version_reader" || ! -f "$toolchain_lock" ]]; then
    echo "Android release toolchain verifier or lock is unavailable" >&2
    exit 2
  fi
  lock_version_count="$(grep -Ec \
    '^bundletool\.version=[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' \
    "$toolchain_lock" || true)"
  lock_sha_count="$(grep -Ec '^bundletool\.sha256=[0-9a-f]{64}$' \
    "$toolchain_lock" || true)"
  locked_bundletool_version="$(
    sed -n 's/^bundletool\.version=\([0-9][0-9A-Za-z.+-]*\)$/\1/p' \
      "$toolchain_lock"
  )"
  locked_bundletool_sha="$(
    sed -n 's/^bundletool\.sha256=\([0-9a-f]\{64\}\)$/\1/p' \
      "$toolchain_lock"
  )"
  if [[ "$lock_version_count" != "1" || "$lock_sha_count" != "1" ||
    -z "$locked_bundletool_version" || -z "$locked_bundletool_sha" ]]; then
    echo "Android release toolchain lock is malformed" >&2
    exit 2
  fi
  bundletool_version="$(
    dart "$bundletool_version_reader" \
      "$unpacked_dir/BundleConfig.pb"
  )"
  if [[ "$bundletool_version" != "$locked_bundletool_version" ]]; then
    echo "FORBIDDEN Android App Bundle: producer toolchain version drift" >&2
    exit 1
  fi

  if [[ "$expected_package" == "cc.siliconnexus.ktwallet" ]]; then
    android_project_root="$repo_root/apps/kt_wallet/android"
  else
    android_project_root="$repo_root/apps/cold_signer/android"
  fi
  verification_metadata="$android_project_root/gradle/verification-metadata.xml"
  android_settings="$android_project_root/settings.gradle.kts"
  if [[ ! -f "$verification_metadata" || ! -f "$android_settings" ]]; then
    echo "Android dependency verification metadata is unavailable" >&2
    exit 2
  fi

  metadata_bundletool_sha="$(xmllint --xpath \
    "string((//*[local-name()='component'][@group='com.android.tools.build' and @name='bundletool' and @version='$bundletool_version']/*[local-name()='artifact'][@name='bundletool-$bundletool_version.jar']/*[local-name()='sha256'])[1]/@value)" \
    "$verification_metadata")"
  if [[ "$metadata_bundletool_sha" != "$locked_bundletool_sha" ]]; then
    echo "Android bundletool lock does not match Gradle verification metadata" >&2
    exit 2
  fi

  gradle_user_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
  gradle_module_cache="$gradle_user_home/caches/modules-2/files-2.1"
  bundletool_jar="${BUNDLETOOL_JAR:-}"
  if [[ -z "$bundletool_jar" ]]; then
    bundletool_jar="$(find \
      "$gradle_module_cache/com.android.tools.build/bundletool/$bundletool_version" \
      -type f -name "bundletool-$bundletool_version.jar" -print -quit 2>/dev/null)"
  fi
  if [[ -z "$bundletool_jar" || ! -f "$bundletool_jar" ]]; then
    echo "bundletool is required to verify an Android App Bundle" >&2
    exit 2
  fi
  actual_bundletool_sha="$(shasum -a 256 "$bundletool_jar" | awk '{print $1}')"
  if [[ "$actual_bundletool_sha" != "$locked_bundletool_sha" ]]; then
    echo "Android bundletool JAR does not match the reviewed SHA-256" >&2
    exit 2
  fi
  echo "OK: BundleConfig producer and reviewed bundletool lock match $bundletool_version"

  bundletool_dependency_names="$(
    unzip -p "$bundletool_jar" META-INF/MANIFEST.MF | tr -d '\r' |
      awk 'BEGIN { active=0 }
        /^Class-Path:/ {
          active=1
          sub(/^Class-Path: /, "")
          printf "%s", $0
          next
        }
        active && /^ / {
          sub(/^ /, "")
          printf "%s", $0
          next
        }
        active { exit }
        END { print "" }'
  )"
  agp_version="$(
    sed -n 's/.*id("com\.android\.application") version "\([^"]*\)".*/\1/p' \
      "$android_settings" | head -n 1
  )"
  if [[ -z "$agp_version" ]]; then
    echo "Android Gradle Plugin version is unavailable" >&2
    exit 2
  fi
  aapt2_dependency_name="$(xmllint --xpath \
    "string((//*[local-name()='component'][@group='com.android.tools.build' and @name='aapt2-proto' and starts-with(@version, '$agp_version-')]/*[local-name()='artifact'][contains(@name, '.jar')])[1]/@name)" \
    "$verification_metadata")"
  if [[ -z "$aapt2_dependency_name" ]]; then
    echo "AGP-matched aapt2-proto is absent from verification metadata" >&2
    exit 2
  fi

  bundletool_classpath="$bundletool_jar"
  verified_dependency_count=0
  for dependency_name in $bundletool_dependency_names; do
    resolved_dependency_name="$dependency_name"
    # bundletool's manifest retains an old aapt2-proto filename. Use the
    # exact aapt2 schema resolved by the current AGP, never a cache maximum.
    if [[ "$dependency_name" == aapt2-proto-*.jar ]]; then
      resolved_dependency_name="$aapt2_dependency_name"
    fi
    dependency_jar="$(find "$gradle_module_cache" -type f \
      -name "$resolved_dependency_name" -print -quit 2>/dev/null)"
    if [[ -z "$dependency_jar" ]]; then
      echo "bundletool runtime dependency is unavailable: $resolved_dependency_name" >&2
      exit 2
    fi
    expected_dependency_sha="$(xmllint --xpath \
      "string((//*[local-name()='artifact'][@name='$resolved_dependency_name']/*[local-name()='sha256'])[1]/@value)" \
      "$verification_metadata")"
    actual_dependency_sha="$(shasum -a 256 "$dependency_jar" | awk '{print $1}')"
    if [[ -z "$expected_dependency_sha" ||
      "$actual_dependency_sha" != "$expected_dependency_sha" ]]; then
      echo "bundletool runtime dependency failed integrity verification" >&2
      exit 2
    fi
    bundletool_classpath="$bundletool_classpath:$dependency_jar"
    verified_dependency_count=$((verified_dependency_count + 1))
  done
  echo "OK: bundletool runtime dependency hashes verified ($verified_dependency_count)"

  bundletool_main="com.android.tools.build.bundletool.BundleToolMain"
  if ! java -cp "$bundletool_classpath" "$bundletool_main" validate \
    --bundle="$release_artifact" >/dev/null; then
    echo "FORBIDDEN Android App Bundle: bundletool validation failed" >&2
    exit 1
  fi
  echo "OK: bundletool validates the Android App Bundle"
  java -cp "$bundletool_classpath" "$bundletool_main" dump manifest \
    --bundle="$release_artifact" --module=base >"$manifest_file"
fi
if ! grep -Fq "package=\"$expected_package\"" "$manifest_file"; then
  echo "FORBIDDEN release package identity mismatch" >&2
  failed=1
else
  echo "OK: package identity $expected_package"
fi
if ! grep -Eq 'android:allowBackup="false"' "$manifest_file"; then
  echo "FORBIDDEN release manifest: backup is not explicitly disabled" >&2
  failed=1
else
  echo "OK: Android backup disabled"
fi
if ! grep -Fq 'android:fullBackupContent=' "$manifest_file" ||
  ! grep -Fq 'android:dataExtractionRules=' "$manifest_file"; then
  echo "FORBIDDEN release manifest: extraction rules are incomplete" >&2
  failed=1
else
  echo "OK: both Android extraction-rule generations are present"
fi
if ! grep -Eq 'android:usesCleartextTraffic="false"' "$manifest_file"; then
  echo "FORBIDDEN release manifest: cleartext traffic is not explicitly disabled" >&2
  failed=1
else
  echo "OK: cleartext traffic disabled"
fi
if grep -Eq 'android:(debuggable|testOnly)="true"' "$manifest_file"; then
  echo "FORBIDDEN release manifest: debug/test mode enabled" >&2
  failed=1
else
  echo "OK: release is not debuggable or test-only"
fi

if ! command -v xmllint >/dev/null 2>&1; then
  echo "xmllint is required to verify the merged Android manifest" >&2
  exit 2
fi
permissions="$({
  xmllint --xpath \
    '//*[local-name()="uses-permission"]/@*[local-name()="name"]' \
    "$manifest_file" 2>/dev/null || true
} | sed 's/[[:space:]]*android:name=/\nandroid:name=/g' |
  sed -n 's/.*android:name="\([^"]*\)".*/\1/p')"
if [[ "$expected_package" == "cc.siliconnexus.ktwallet" ]]; then
  required_permissions=(
    android.permission.ACCESS_NETWORK_STATE
    android.permission.CAMERA
    android.permission.DETECT_SCREEN_CAPTURE
    android.permission.INTERNET
    android.permission.USE_BIOMETRIC
  )
else
  required_permissions=(
    android.permission.ACCESS_NETWORK_STATE
    android.permission.CAMERA
    android.permission.DETECT_SCREEN_CAPTURE
    android.permission.USE_BIOMETRIC
  )
fi
for permission in "${required_permissions[@]}"; do
  if ! grep -Fxq "$permission" <<<"$permissions"; then
    echo "MISSING required release permission: $permission" >&2
    failed=1
  fi
done
while IFS= read -r permission; do
  [[ -z "$permission" ]] && continue
  case "$permission" in
    android.permission.ACCESS_NETWORK_STATE | \
      android.permission.CAMERA | \
      android.permission.DETECT_SCREEN_CAPTURE | \
      android.permission.USE_BIOMETRIC | \
      android.permission.USE_FINGERPRINT | \
      "$expected_package.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION") ;;
    android.permission.INTERNET)
      if [[ "$expected_package" != "cc.siliconnexus.ktwallet" ]]; then
        echo "FORBIDDEN Cold Signer permission: android.permission.INTERNET" >&2
        failed=1
      fi
      ;;
    *)
      echo "UNREVIEWED release permission: $permission" >&2
      failed=1
      ;;
  esac
done <<<"$permissions"
if [[ "$failed" -eq 0 ]]; then
  echo "OK: merged permission set is allowlisted"
fi

exported_names="$({
  xmllint --xpath \
    '//*[@*[local-name()="exported"]="true"]/@*[local-name()="name"]' \
    "$manifest_file" 2>/dev/null || true
} | sed 's/[[:space:]]*android:name=/\nandroid:name=/g' |
  sed -n 's/.*android:name="\([^"]*\)".*/\1/p')"
main_activity="$expected_package.MainActivity"
if ! grep -Fxq "$main_activity" <<<"$exported_names"; then
  echo "MISSING exported launcher activity" >&2
  failed=1
fi
while IFS= read -r component; do
  [[ -z "$component" ]] && continue
  case "$component" in
    "$main_activity") ;;
    androidx.profileinstaller.ProfileInstallReceiver)
      protected_receiver_count="$(xmllint --xpath \
        'count(//*[@*[local-name()="name"]="androidx.profileinstaller.ProfileInstallReceiver" and @*[local-name()="exported"]="true" and @*[local-name()="permission"]="android.permission.DUMP"])' \
        "$manifest_file")"
      if [[ "$protected_receiver_count" != "1" ]]; then
        echo "FORBIDDEN unprotected ProfileInstaller receiver" >&2
        failed=1
      fi
      ;;
    *)
      echo "UNREVIEWED exported Android component: $component" >&2
      failed=1
      ;;
  esac
done <<<"$exported_names"
if [[ "$failed" -eq 0 ]]; then
  echo "OK: exported Android components are allowlisted"
fi

# Unsigned is acceptable while formal signing remains explicitly out of scope;
# a signed APK/AAB must verify and must never use Android's public debug cert.
if [[ "$artifact_kind" == "apk" ]]; then
  apksigner_bin="$(command -v apksigner || true)"
  if [[ -z "$apksigner_bin" ]]; then
    android_sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    if [[ -n "$android_sdk_dir" ]]; then
      apksigner_bin="$(find "$android_sdk_dir/build-tools" -name apksigner -type f | sort | tail -n 1)"
    fi
  fi
  if [[ -n "$apksigner_bin" && -x "$apksigner_bin" ]]; then
    if "$apksigner_bin" verify --verbose --print-certs "$release_artifact" \
      >"$certificate_log" 2>&1; then
      if grep -Fq 'CN=Android Debug' "$certificate_log"; then
        echo "FORBIDDEN release signature: Android Debug certificate" >&2
        failed=1
      else
        echo "OK: signed APK verifies and is not Android Debug"
      fi
    elif grep -Fq 'Missing META-INF/MANIFEST.MF' "$certificate_log"; then
      echo "OK: APK is intentionally unsigned; distribution signing pending"
    else
      echo "FORBIDDEN release APK signature: malformed or unverifiable" >&2
      failed=1
    fi
  else
    echo "apksigner is required to verify an Android APK signature" >&2
    exit 2
  fi
else
  aab_signature_file="$(grep -Ei '^META-INF/[^/]+\.SF$' \
    "$archive_entries" | head -n 1 || true)"
  aab_signature_block="$(grep -Ei '^META-INF/[^/]+\.(RSA|DSA|EC)$' \
    "$archive_entries" | head -n 1 || true)"
  if [[ -z "$aab_signature_file" && -z "$aab_signature_block" ]]; then
    echo "OK: AAB is intentionally unsigned; upload signing pending"
  elif [[ -z "$aab_signature_file" || -z "$aab_signature_block" ]]; then
    echo "FORBIDDEN release AAB signature: incomplete signature metadata" >&2
    failed=1
  elif ! command -v jarsigner >/dev/null 2>&1; then
    echo "jarsigner is required to verify an Android App Bundle signature" >&2
    exit 2
  elif jarsigner -J-Duser.language=en -J-Duser.country=US \
    -verify -verbose -certs "$release_artifact" \
    >"$certificate_log" 2>&1 &&
    grep -Fq 'jar verified.' "$certificate_log"; then
    if grep -Fq 'CN=Android Debug' "$certificate_log"; then
      echo "FORBIDDEN App Bundle signature: Android Debug certificate" >&2
      failed=1
    else
      echo "OK: signed AAB verifies and is not Android Debug"
    fi
  else
    echo "FORBIDDEN release AAB signature: malformed or unverifiable" >&2
    failed=1
  fi
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Release artifact guard passed: $release_artifact"
