import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/airdrop_service.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/state/networks.dart';

/// The testnet money shot: REAL test funds land in the app's service layer.
///
/// Real wallet-core derives a real Solana address; a REAL devnet airdrop is
/// requested against the built-in Devnet network; the app's own
/// BalanceService (pointed at Devnet by the same resolver the UI uses)
/// observes the balance becoming non-zero. Network-dependent by nature —
/// devnet faucets rate-limit, so an airdrop rejection is reported as a skip
/// rather than a failure, but any observed balance must be real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('devnet airdrop → real SOL visible through BalanceService', () async {
    const requestedLamports = lamportsPerSol ~/ 10;
    final crypto = MethodChannelCoreCrypto();
    const id = 'itest-devnet';
    await crypto.storeWallet(
      walletId: id,
      mnemonic: await crypto.generateMnemonic(),
      requireAuth: false,
    );
    final addrs = await crypto.deriveAddresses(id);
    // ignore: avoid_print
    print('DEVNET addr=${addrs.solana}');

    final airdrop = AirdropService();
    String? signature;
    try {
      signature = await airdrop.requestAirdrop(
        rpcUrl: solanaDevnet.rpcUrl,
        address: addrs.solana,
        lamports: requestedLamports,
      );
      // ignore: avoid_print
      print('AIRDROP sig=$signature');
    } on AirdropException catch (e) {
      // Devnet faucet rate limits are outside our control; the pipeline is
      // still proven by the request being ACCEPTED-shaped or rejected by the
      // real node. Mark and bail without failing the suite.
      // ignore: avoid_print
      print('AIRDROP-RATE-LIMITED: ${e.message}');
      markTestSkipped(
        'Solana public Devnet faucet rejected the request: ${e.message}',
      );
      return;
    }

    // Poll the app's own balance path (network-resolved to Devnet) until the
    // funds are visible — devnet finalizes in a few seconds.
    final balances = BalanceService(endpoints: (coin) => solanaDevnet.rpcUrl);
    BigInt seen = BigInt.zero;
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final result = (await balances.fetchAll(addrs))[Coin.solana]!;
      if (result.status == BalanceStatus.ok &&
          result.amount!.raw > BigInt.zero) {
        seen = result.amount!.raw;
        break;
      }
    }
    // ignore: avoid_print
    print('DEVNET balance raw=$seen');
    expect(
      seen,
      BigInt.from(requestedLamports),
      reason: 'the airdropped 0.1 SOL must be visible through the app service',
    );
  });
}
