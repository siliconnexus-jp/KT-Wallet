import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

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
