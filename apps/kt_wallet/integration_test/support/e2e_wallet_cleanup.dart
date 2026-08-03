import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a native wallet in the reserved integration-test namespace.
///
/// A previous process crash can leave a create-only native slot behind. Such
/// a slot is removed only through the production authentication boundary and
/// only when its identifier begins with `kt-e2e-`; arbitrary or production
/// wallet identifiers are rejected before any native call. Deletion failures
/// propagate and the existing key is never overwritten.
Future<void> storeE2eWallet(
  CoreCrypto crypto, {
  required String walletId,
  required String mnemonic,
  bool requireAuth = false,
  String? kdfPassword,
  Duration timeout = const Duration(seconds: 45),
}) async {
  if (!walletId.startsWith('kt-e2e-')) {
    throw ArgumentError.value(
      walletId,
      'walletId',
      'native integration-test wallet IDs must begin with kt-e2e-',
    );
  }

  try {
    await crypto
        .storeWallet(
          walletId: walletId,
          mnemonic: mnemonic,
          requireAuth: requireAuth,
          kdfPassword: kdfPassword,
        )
        .timeout(timeout);
    registerE2eWalletCleanup(crypto, walletId, timeout: timeout);
    return;
  } on WalletAlreadyExistsException {
    await crypto.deleteWallet(walletId).timeout(timeout);
  }

  await crypto
      .storeWallet(
        walletId: walletId,
        mnemonic: mnemonic,
        requireAuth: requireAuth,
        kdfPassword: kdfPassword,
      )
      .timeout(timeout);
  registerE2eWalletCleanup(crypto, walletId, timeout: timeout);
}

/// Registers an authenticated teardown for a native wallet created by an E2E
/// test.
///
/// Native deletion intentionally uses the same system-auth gate as production.
/// Device runs therefore need an enrolled biometric/passcode and must satisfy
/// the prompt during teardown. A timeout is treated as a test failure: silently
/// leaving key material behind would make the run look cleaner than it is.
void registerE2eWalletCleanup(
  CoreCrypto crypto,
  String walletId, {
  Duration timeout = const Duration(seconds: 45),
}) {
  addTearDown(() async {
    try {
      await crypto.deleteWallet(walletId).timeout(timeout);
    } on WalletNotFoundException {
      // The scenario may deliberately exercise deletion before teardown.
    }
  });
}
