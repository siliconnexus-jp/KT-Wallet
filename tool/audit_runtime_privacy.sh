#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

failed=0

reject_literal() {
  local file="$1"
  local literal="$2"
  local label="$3"
  if LC_ALL=C grep -Fq -- "$literal" "$REPO_ROOT/$file"; then
    echo "FORBIDDEN runtime privacy pattern: $label" >&2
    failed=1
  else
    echo "OK: $label absent"
  fi
}

# CoreCrypto is the highest-value boundary. Native library exceptions can
# contain wallet ids, paths or serialized transaction context. Dart accepts
# only stable error codes and the single allowlisted cooldown integer.
reject_literal \
  "packages/core_crypto/lib/src/method_channel.dart" \
  "message: e.message" \
  "raw CoreCrypto PlatformException message"
reject_literal \
  "packages/core_crypto/lib/src/method_channel.dart" \
  "details: e.details" \
  "unfiltered CoreCrypto PlatformException details"
reject_literal \
  "packages/core_crypto/ios/core_crypto/Sources/core_crypto/CoreCryptoPlugin.swift" \
  'message: "\(error)"' \
  "raw iOS CoreCrypto exception message"
reject_literal \
  "packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/CoreCryptoPlugin.kt" \
  "e.message" \
  "raw Android CoreCrypto exception message"
reject_literal \
  "packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/CoreCryptoPlugin.kt" \
  "msg.toString()" \
  "raw Android authentication provider message"
reject_literal \
  "packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/CoreCryptoPlugin.kt" \
  "android.util.Log" \
  "CoreCrypto operation logging"

# File/media provider errors routinely include sandbox paths and content URIs.
reject_literal \
  "apps/kt_wallet/ios/Runner/AppDelegate.swift" \
  "localizedDescription" \
  "raw iOS file/media provider description"
reject_literal \
  "apps/kt_wallet/android/app/src/main/kotlin/cc/siliconnexus/ktwallet/MainActivity.kt" \
  "e.message" \
  "raw Android file/media provider description"

# A custom RPC/Gateway URL can carry a provider key in its path or query.
reject_literal \
  "apps/kt_wallet/lib/src/transfer/broadcast_service.dart" \
  "BroadcastOutcome.unknown('\$error')" \
  "raw broadcast exception interpolation"
reject_literal \
  "apps/kt_wallet/lib/src/market/airdrop_service.dart" \
  "throw AirdropException('\$e')" \
  "raw faucet transport exception interpolation"
reject_literal \
  "apps/kt_wallet/lib/src/screens/assets_screens.dart" \
  "l10n.airdropFailed(e.message)" \
  "raw faucet provider message in UI"
reject_literal \
  "apps/kt_wallet/lib/src/screens/transfer_screens.dart" \
  "_error = '\$error'" \
  "raw air-gap persistence error in UI"
reject_literal \
  "apps/kt_wallet/lib/src/screens/transfer_screens.dart" \
  "_showMessage('\$error')" \
  "raw replacement error in UI"
reject_literal \
  "apps/kt_wallet/lib/src/screens/transfer_screens.dart" \
  "_showTransferError(context, '\$e')" \
  "raw hot-transfer error in UI"
reject_literal \
  "apps/kt_wallet/lib/src/screens/transfer_screens.dart" \
  "_showTransferError(context, error.message)" \
  "unlocalized transfer rejection in UI"
reject_literal \
  "apps/kt_wallet/lib/src/screens/approval_screen.dart" \
  "_message(error.message)" \
  "unlocalized approval rejection in UI"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "runtime privacy audit: OK"
