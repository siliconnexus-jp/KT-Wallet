import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Cleanup-only entrypoint for native integration-test slots that were left by
/// an interrupted run.
///
/// The target is build-time data, never a production route. Keep this allowlist
/// closed and review every addition: deletion still crosses the production
/// CoreCrypto authentication boundary and an unknown id must fail before any
/// native call.
const _walletId = String.fromEnvironment('KT_E2E_CLEANUP_WALLET_ID');
const _reviewedResidualSlots = <String>{
  'polygon-amoy-e2e-v2',
  'kt-e2e-polygon-amoy-v3',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'authenticated cleanup removes one reviewed native E2E slot',
    () async {
      expect(
        _reviewedResidualSlots,
        contains(_walletId),
        reason:
            'KT_E2E_CLEANUP_WALLET_ID must name a reviewed residual test slot.',
      );

      final crypto = MethodChannelCoreCrypto();
      try {
        await crypto
            .deleteWallet(_walletId)
            .timeout(const Duration(seconds: 45));
        // Marker contains only a reviewed, non-secret test identifier.
        // ignore: avoid_print
        print('E2E-RESIDUAL-NATIVE-KEY-DELETED walletId=$_walletId');
      } on WalletNotFoundException {
        // Idempotent verification: an already-absent reviewed slot is clean.
        // ignore: avoid_print
        print('E2E-RESIDUAL-NATIVE-KEY-ABSENT walletId=$_walletId');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
