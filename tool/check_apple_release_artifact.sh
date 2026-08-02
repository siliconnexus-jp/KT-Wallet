#!/usr/bin/env bash
set -euo pipefail

apple_app="${1:-apps/kt_wallet/build/ios/iphoneos/Runner.app}"
expected_bundle_id="${2:-}"

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
failed=0

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
  'github_pat_[A-Za-z0-9_]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|alch_[A-Za-z0-9_-]{12,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk_(live|test)_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|(api[_-]?key|access[_-]?token|bearer[_-]?token)[=:][A-Za-z0-9_+./=-]{20,}' \
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

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Apple release artifact guard passed: $apple_app"
