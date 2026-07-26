import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/state/networks.dart';

const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mobile balance pipeline shows funded Sepolia ETH and Test USDT',
    () async {
      expect(
        _mnemonic,
        isNotEmpty,
        reason:
            'run with --dart-define-from-file=integration_test/.sepolia-e2e.json',
      );

      final crypto = MethodChannelCoreCrypto();
      const walletId = 'sepolia-mobile-balance';
      await crypto.storeWallet(
        walletId: walletId,
        mnemonic: _mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(walletId);
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final endpoints = effectiveRpcEndpoints(null, networks);

      final native = await BalanceService(
        endpoints: endpoints,
      ).fetchAll(addresses);
      final tokens = TokenBalanceService(
        endpoints: endpoints,
        registry: networkTokenRegistry(networks),
      );
      final tokenBalances = await tokens.fetchAll(addresses);
      final eth = native[Coin.eth]!;
      final usdt = tokenBalances[usdtSepoliaToken.id]!;

      expect(eth.status, BalanceStatus.ok);
      expect(eth.amount!.raw, greaterThan(BigInt.zero));
      expect(usdt.status, BalanceStatus.ok);
      expect(usdt.amount!.raw, greaterThan(BigInt.zero));

      // Public evidence only; no mnemonic or private key is logged.
      // ignore: avoid_print
    print('MOBILE_BALANCE_ADDRESS=${addresses.eth}');
    // ignore: avoid_print
    print('MOBILE_TRON_ADDRESS=${addresses.tron}');
    // ignore: avoid_print
    print('MOBILE_SOLANA_ADDRESS=${addresses.solana}');
      // ignore: avoid_print
      print('MOBILE_BALANCE_ETH=${eth.amount!.format(maxFraction: 8)}');
      // ignore: avoid_print
      print('MOBILE_BALANCE_USDT=${usdt.amount!.format(maxFraction: 6)}');
    },
  );
}
