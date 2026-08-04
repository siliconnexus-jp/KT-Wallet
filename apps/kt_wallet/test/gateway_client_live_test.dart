import 'dart:io';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/price_service.dart';

void main() {
  final enabled = Platform.environment['KT_LIVE_GATEWAY_CLIENT'] == '1';
  final baseUrl =
      Platform.environment['KT_GATEWAY_URL'] ?? 'https://gateway.kt-wallet.com';

  test(
    'production Gateway health survives the strict response boundary',
    () async {
      final client = GatewayClient(baseUrl: baseUrl);

      expect(await client.health(), isTrue);
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );

  test(
    'production Sepolia preflight results bind network and public probe owner',
    () async {
      const publicProbe = '0x000000000000000000000000000000000000dEaD';
      final client = GatewayClient(
        baseUrl: baseUrl,
        networks: (_) => 'eth-sepolia',
      );

      final params = await client.getChainParams(
        chain: Coin.eth,
        address: publicProbe,
      );
      final balances = await client.getEvmSpendableBalances(
        chain: Coin.eth,
        address: publicProbe,
      );

      expect(params.nonce, greaterThanOrEqualTo(0));
      expect(params.fees.slow.maxFeePerGas, greaterThan(BigInt.zero));
      expect(balances.native, greaterThanOrEqualTo(BigInt.zero));
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );

  test(
    'production Sepolia balances bind the exact public probe owner',
    () async {
      const publicProbe = '0x000000000000000000000000000000000000dEaD';
      final client = GatewayClient(
        baseUrl: baseUrl,
        networks: (_) => 'eth-sepolia',
      );

      final balances = await client.getBalances(
        chain: Coin.eth,
        address: publicProbe,
      );

      expect(balances.native.raw, greaterThanOrEqualTo(BigInt.zero));
      expect(balances.native.decimals, 18);
      expect(balances.native.symbol, 'ETH');
      expect(balances.tokens, isEmpty);
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );

  test(
    'production Sepolia status binds the exact public probe hash',
    () async {
      const probeHash =
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final client = GatewayClient(
        baseUrl: baseUrl,
        networks: (_) => 'eth-sepolia',
      );

      expect(
        await client.getTransactionStatus(chain: Coin.eth, hash: probeHash),
        GatewayTransactionStatus.unknown,
      );
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );

  test(
    'production BNB history binds every row to the exact public owner',
    () async {
      const publicOwner = '0xb787f3c2f96403b5a73dc66de68e4a6395d4e632';
      final client = GatewayClient(
        baseUrl: baseUrl,
        networks: (_) => 'bnb-mainnet',
      );

      final history = await client.getHistory(
        chain: Coin.bnb,
        address: publicOwner,
        limit: 2,
      );

      expect(history.unsupported, isFalse);
      expect(history.records, isNotEmpty);
      for (final record in history.records) {
        expect(record.id, isNotEmpty);
        expect(record.hash, isNotEmpty);
        expect(record.amountRaw, isNotNull);
        expect(record.decimals, isNotNull);
        expect(record.symbol, isNotNull);
      }
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );

  test(
    'production prices survive exact schema, freshness and request binding',
    () async {
      final client = GatewayClient(baseUrl: baseUrl);
      final requestedSymbols = {
        for (final coin in Coin.values) BalanceService.symbolFor[coin]!,
        ...PriceService.coinGeckoTokenIds.keys,
      };

      final prices = await client.getPrices(requestedSymbols.toList());

      expect(prices.usdBySymbol.keys.toSet(), requestedSymbols);
      expect(prices.usdBySymbol.values, everyElement(greaterThan(0)));
      expect(prices.fiatPerUsd.keys, containsAll(const ['USD', 'CNY', 'JPY']));
      expect(
        DateTime.now().millisecondsSinceEpoch - prices.cachedAtMs,
        inInclusiveRange(0, const Duration(minutes: 15).inMilliseconds),
      );
      client.close();
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );
}
