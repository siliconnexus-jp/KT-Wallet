import 'dart:io';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';

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
}
