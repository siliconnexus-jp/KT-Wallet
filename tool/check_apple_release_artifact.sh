#!/usr/bin/env bash
set -euo pipefail

require_signed=0
if [[ "${1:-}" == "--require-signed" ]]; then
  require_signed=1
  shift
fi

apple_app="${1:-apps/kt_wallet/build/ios/iphoneos/Runner.app}"
expected_bundle_id="${2:-}"

if [[ "$#" -gt 2 ]]; then
  echo "Usage: $0 [--require-signed] APP_BUNDLE [EXPECTED_BUNDLE_ID]" >&2
  exit 2
fi

if [[ ! -d "$apple_app" || "$apple_app" != *.app ]]; then
  echo "Apple app bundle not found or unsupported: $apple_app" >&2
  exit 2
fi

if [[ -z "$expected_bundle_id" ]]; then
  case "$apple_app" in
    *apps/kt_wallet/*) expected_bundle_id="cc.siliconnexus.ktwallet" ;;
    *apps/cold_signer/*)
      expected_bundle_id="cc.siliconnexus.ktwallet.coldsigner"
      ;;
    *)
      echo "Expected bundle ID is required outside apps/*/build" >&2
      exit 2
      ;;
  esac
fi

case "$expected_bundle_id" in
  cc.siliconnexus.ktwallet | cc.siliconnexus.ktwallet.coldsigner) ;;
  *)
    echo "Unsupported expected bundle ID: $expected_bundle_id" >&2
    exit 2
    ;;
esac

plist="$apple_app/Info.plist"
privacy_manifest="$apple_app/PrivacyInfo.xcprivacy"
sqlite_binary="$apple_app/Frameworks/sqlite3.framework/sqlite3"
embedded_profile="$apple_app/embedded.mobileprovision"
failed=0

signed_entitlement() {
  local key="$1"
  codesign -d --entitlements :- "$apple_app" 2>/dev/null |
    plutil -extract "$key" raw -o - - 2>/dev/null
}

profile_value() {
  local key="$1"
  security cms -D -u 9 -i "$embedded_profile" 2>/dev/null |
    plutil -extract "$key" raw -o - - 2>/dev/null
}

for required_file in \
  "$plist" \
  "$privacy_manifest" \
  "$apple_app/Runner" \
  "$apple_app/Frameworks/App.framework/App" \
  "$apple_app/Frameworks/Flutter.framework/Flutter" \
  "$apple_app/Frameworks/WalletCore.framework/WalletCore" \
  "$apple_app/Frameworks/core_crypto.framework/core_crypto" \
  "$apple_app/Frameworks/core_crypto.framework/core_crypto_privacy.bundle/PrivacyInfo.xcprivacy" \
  "$apple_app/Frameworks/WalletCoreSwiftProtobuf.framework/WalletCoreSwiftProtobuf.bundle/PrivacyInfo.xcprivacy" \
  "$sqlite_binary"; do
  if [[ ! -f "$required_file" ]]; then
    echo "MISSING Apple release file: ${required_file#"$apple_app/"}" >&2
    failed=1
  else
    echo "OK: Apple release file ${required_file#"$apple_app/"}"
  fi
done

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
  echo "FORBIDDEN Apple bundle identity mismatch: $actual_bundle_id" >&2
  failed=1
else
  echo "OK: Apple bundle identity $expected_bundle_id"
fi

if [[ -f "$apple_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ||
  -f "$apple_app/Frameworks/App.framework/flutter_assets/vm_snapshot_data" ||
  -f "$apple_app/Frameworks/App.framework/flutter_assets/isolate_snapshot_data" ]]; then
  echo "FORBIDDEN Apple artifact contains Flutter Debug snapshots" >&2
  failed=1
else
  echo "OK: Apple artifact contains no Flutter Debug snapshots"
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$plist" 2>/dev/null || true)" != "false" ]]; then
  echo "FORBIDDEN Apple export-compliance declaration is missing or not false" >&2
  failed=1
else
  echo "OK: Apple standard-encryption declaration"
fi

for manifest in \
  "$privacy_manifest" \
  "$apple_app/Frameworks/core_crypto.framework/core_crypto_privacy.bundle/PrivacyInfo.xcprivacy" \
  "$apple_app/Frameworks/WalletCoreSwiftProtobuf.framework/WalletCoreSwiftProtobuf.bundle/PrivacyInfo.xcprivacy"; do
  if [[ -f "$manifest" ]] && ! plutil -lint "$manifest" >/dev/null; then
    echo "FORBIDDEN malformed privacy manifest: ${manifest#"$apple_app/"}" >&2
    failed=1
  fi
done

if [[ -f "$sqlite_binary" ]]; then
  if ! LC_ALL=C grep -aFq -- '3.53.3' "$sqlite_binary"; then
    echo "FORBIDDEN Apple SQLite runtime is not 3.53.3" >&2
    failed=1
  elif LC_ALL=C grep -aFq -- '3.52.0' "$sqlite_binary"; then
    echo "FORBIDDEN vulnerable Apple SQLite 3.52.0 marker" >&2
    failed=1
  else
    echo "OK: Apple SQLite 3.53.3 runtime"
  fi
fi

forbidden_markers=(
  "KT_ALLOW_MOCK_CRYPTO"
  "MockCoreCrypto"
  "demoSignResult"
  "SIGNED-V1:"
  "KT Wallet — 屏幕库"
  "TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa"
)
for marker in "${forbidden_markers[@]}"; do
  if LC_ALL=C grep -aR -Fq -- "$marker" "$apple_app"; then
    echo "FORBIDDEN Apple release marker detected" >&2
    failed=1
  else
    echo "OK: forbidden Apple release marker absent"
  fi
done

if LC_ALL=C grep -aR -Eq \
  'github_pat_[A-Za-z0-9_]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|alch_[A-Za-z0-9_-]{12,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk_(live|test)_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|(api[_-]?key|access[_-]?token|auth[_-]?token|bearer[_-]?token|client[_-]?secret|credential|password|secret|token)["'"'"'[:space:]]*[:=]["'"'"'[:space:]]*[A-Za-z0-9_+./=~-]{20,}' \
  "$apple_app"; then
  echo "FORBIDDEN Apple release credential pattern detected" >&2
  failed=1
else
  echo "OK: no provider/repository credential pattern in Apple bundle"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
local_e2e_file="$repo_root/apps/kt_wallet/integration_test/.sepolia-e2e.json"
if [[ -f "$local_e2e_file" ]]; then
  local_mnemonic="$({
    sed -n 's/.*"SEPOLIA_E2E_MNEMONIC"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$local_e2e_file"
  } | head -n 1)"
  if [[ -n "$local_mnemonic" ]] &&
    LC_ALL=C grep -aR -Fq -- "$local_mnemonic" "$apple_app"; then
    echo "FORBIDDEN local E2E mnemonic canary in Apple bundle" >&2
    failed=1
  else
    echo "OK: local E2E mnemonic canary absent from Apple bundle"
  fi
fi

if [[ "$require_signed" -eq 1 ]]; then
  echo "Checking App Store distribution signature and provisioning profile"

  signature_details="$(codesign -dv --verbose=4 "$apple_app" 2>&1 || true)"
  if ! codesign --verify --deep --strict --verbose=2 "$apple_app" >/dev/null 2>&1; then
    echo "FORBIDDEN Apple distribution artifact has no valid strict signature" >&2
    failed=1
  elif ! grep -Eq '^Authority=(Apple Distribution|iPhone Distribution):' \
    <<<"$signature_details"; then
    echo "FORBIDDEN Apple artifact is not signed by a distribution identity" >&2
    failed=1
  else
    echo "OK: Apple distribution signature verifies"
  fi

  if [[ ! -f "$embedded_profile" ]]; then
    echo "MISSING embedded.mobileprovision in signed Apple artifact" >&2
    failed=1
  else
    if ! security cms -D -u 9 -i "$embedded_profile" >/dev/null 2>&1; then
      echo "FORBIDDEN provisioning profile CMS is not trusted" >&2
      failed=1
    else
      echo "OK: provisioning profile CMS trust verifies"
    fi

    profile_bundle="$(profile_value 'Entitlements.application-identifier' || true)"
    profile_team="$(profile_value 'TeamIdentifier.0' || true)"
    profile_platform="$(profile_value 'Platform.0' || true)"
    profile_expiration="$(profile_value 'ExpirationDate' || true)"
    profile_debug="$(profile_value 'Entitlements.get-task-allow' || true)"
    profile_devices="$(profile_value 'ProvisionedDevices.0' || true)"
    profile_enterprise="$(profile_value 'ProvisionsAllDevices' || true)"
    # `plutil -extract` interprets an unescaped period as a key-path
    # separator. Entitlement names contain literal periods, so escaping them
    # is security-critical: without this, a valid distribution artifact is
    # indistinguishable from one that omitted Complete Data Protection.
    profile_protection="$(
      profile_value \
        'Entitlements.com\.apple\.developer\.default-data-protection' || true
    )"

    if [[ -z "$profile_team" || "$profile_bundle" != "$profile_team.$expected_bundle_id" ]]; then
      echo "FORBIDDEN provisioning profile does not exactly match the bundle ID" >&2
      failed=1
    else
      echo "OK: provisioning profile exactly matches the bundle ID"
    fi
    if [[ "$profile_platform" != "iOS" ]]; then
      echo "FORBIDDEN provisioning profile is not for iOS" >&2
      failed=1
    else
      echo "OK: provisioning profile platform is iOS"
    fi
    if [[ "$profile_debug" != "false" ]]; then
      echo "FORBIDDEN provisioning profile permits debugger attachment" >&2
      failed=1
    else
      echo "OK: provisioning profile disables debugger attachment"
    fi
    if [[ -n "$profile_devices" || "$profile_enterprise" == "true" ]]; then
      echo "FORBIDDEN provisioning profile is development, ad hoc, or enterprise" >&2
      failed=1
    else
      echo "OK: provisioning profile is App Store distribution"
    fi
    if [[ "$profile_protection" != "NSFileProtectionComplete" ]]; then
      echo "FORBIDDEN provisioning profile lacks complete data protection" >&2
      failed=1
    else
      echo "OK: provisioning profile requires complete data protection"
    fi

    profile_signer_match=0
    profile_signer_sha1=""
    for certificate_index in {0..31}; do
      profile_certificate="$(
        profile_value "DeveloperCertificates.$certificate_index" || true
      )"
      if [[ -z "$profile_certificate" ]]; then
        break
      fi
      profile_certificate_sha1="$(
        printf '%s' "$profile_certificate" |
          /usr/bin/base64 -D 2>/dev/null |
          shasum 2>/dev/null |
          awk '{print $1}' || true
      )"
      if [[ "$profile_certificate_sha1" =~ ^[0-9a-f]{40}$ ]] &&
        codesign --verify --deep --strict \
          -R="anchor apple generic and certificate leaf = H\"$profile_certificate_sha1\"" \
          "$apple_app" >/dev/null 2>&1; then
        profile_signer_match=1
        profile_signer_sha1="$profile_certificate_sha1"
        break
      fi
    done
    if [[ "$profile_signer_match" -ne 1 ]]; then
      echo "FORBIDDEN app signer is not trusted by the provisioning profile" >&2
      failed=1
    else
      echo "OK: app signer is Apple-trusted and present in the profile"

      nested_signer_count=0
      while IFS= read -r -d '' nested_code; do
        nested_signer_count=$((nested_signer_count + 1))
        if ! codesign --verify --strict \
          -R="anchor apple generic and certificate leaf = H\"$profile_signer_sha1\"" \
          "$nested_code" >/dev/null 2>&1; then
          echo "FORBIDDEN nested Apple code signer does not match the profile" >&2
          failed=1
        fi
      done < <(
        find "$apple_app" \
          \( -type d \( -name '*.framework' -o -name '*.appex' \) \
          -o -type f -name '*.dylib' \) -print0
      )
      echo "OK: $nested_signer_count nested Apple code objects match the profile signer"
    fi

    expiration_epoch="$(
      date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$profile_expiration" '+%s' 2>/dev/null || true
    )"
    now_epoch="$(date -u '+%s')"
    if [[ -z "$expiration_epoch" || "$expiration_epoch" -le "$now_epoch" ]]; then
      echo "FORBIDDEN provisioning profile is expired or has an invalid expiration" >&2
      failed=1
    else
      echo "OK: provisioning profile has not expired"
    fi

    signed_bundle="$(signed_entitlement 'application-identifier' || true)"
    signed_team="$(
      signed_entitlement 'com\.apple\.developer\.team-identifier' || true
    )"
    signed_debug="$(signed_entitlement 'get-task-allow' || true)"
    signed_protection="$(
      signed_entitlement \
        'com\.apple\.developer\.default-data-protection' || true
    )"
    if [[ "$signed_bundle" != "$profile_bundle" || "$signed_team" != "$profile_team" ]]; then
      echo "FORBIDDEN signed entitlements do not match the provisioning identity" >&2
      failed=1
    else
      echo "OK: signed app identity matches the provisioning profile"
    fi
    if [[ "$signed_debug" == "true" ]]; then
      echo "FORBIDDEN signed app permits debugger attachment" >&2
      failed=1
    else
      echo "OK: signed app does not permit debugger attachment"
    fi
    if [[ "$signed_protection" != "NSFileProtectionComplete" ]]; then
      echo "FORBIDDEN signed app lacks complete data protection" >&2
      failed=1
    else
      echo "OK: signed app requires complete data protection"
    fi
  fi
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Apple release artifact guard passed: $apple_app"
