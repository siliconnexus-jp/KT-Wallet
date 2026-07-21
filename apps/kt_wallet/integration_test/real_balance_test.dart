import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';

/// On-device proof of the live-balance pipeline with REAL crypto: a freshly
/// derived (real) address is queried against the real public RPC endpoints.
/// A brand-new wallet must report ZERO balances with `ok` status — reaching
/// `ok` at all proves address formats and RPC plumbing are genuine (the demo
/// Mock addresses can only ever produce `error`).
///
/// Network-dependent by nature: public endpoints may rate-limit. The test
/// requires at least one chain to answer `ok`, and every `ok` answer to be
/// exactly zero.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('real derived addresses fetch real zero balances over public RPC', () async {
    final crypto = MethodChannelCoreCrypto();
    const id = 'itest-balance';
    await crypto.storeWallet(walletId: id, mnemonic: await crypto.generateMnemonic());
    final addrs = await crypto.deriveAddresses(id);

    final results = await BalanceService().fetchAll(addrs);

    final okChains = <String>[];
    results.forEach((coin, result) {
      // ignore: avoid_print
      print('BALANCE $coin → ${result.status} ${result.amount?.raw}');
      if (result.status == BalanceStatus.ok) {
        okChains.add('$coin');
        expect(result.amount!.raw, BigInt.zero,
            reason: 'a freshly generated wallet cannot hold funds');
      }
    });

    expect(okChains, isNotEmpty,
        reason: 'at least one public endpoint should accept the real address');
  });
}
