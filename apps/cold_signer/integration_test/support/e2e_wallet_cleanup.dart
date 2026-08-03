import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers fail-closed authenticated deletion for native test key material.
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
