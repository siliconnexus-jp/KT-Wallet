import 'dart:io';

import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';

void main() {
  final live = Platform.environment['KT_LIVE_EVM_HISTORY'] == '1';

  test(
    'Routescan Avalanche Fuji direct history matches the strict schema',
    () async {
      // Public test address only. The test performs three read-only explorer
      // requests and never loads a private key or broadcasts a transaction.
      const owner = '0xb787f3c2f96403b5a73dc66de68e4a6395d4e632';
      final service = HistoryService(
        timeout: const Duration(seconds: 20),
        endpoints: (_) => 'https://api.avax-test.network/ext/bc/C/rpc',
      );
      addTearDown(service.close);

      final history = await service.fetch(Coin.avalanche, owner, limit: 3);
      expect(history.status, HistoryStatus.ok);
      expect(history.records, isNotEmpty);
      for (final record in history.records) {
        expect(record.hash, matches(RegExp(r'^0x[0-9a-fA-F]{64}$')));
        expect(record.amountText, isNotNull);
        expect(
          record.fromAddress?.toLowerCase() == owner ||
              record.toAddress?.toLowerCase() == owner,
          isTrue,
        );
      }

      // This is a previously confirmed public BSC Testnet transaction from
      // the same public test address. Reading it here proves that a real node
      // transaction object remains compatible with the strict hash/from/nonce
      // parser. No key is loaded and no transaction is broadcast.
      const bscHash =
          '0x0122368527979e6c9d41aa18ff72bb86bc67889b7ad010998902272fc384abca';
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      addTearDown(transport.close);
      final rpc = EvmRpc(
        url: 'https://bsc-testnet-dataseed.bnbchain.org',
        transport: transport,
      );
      final evidence = await rpc.getPendingTransactionEvidence(
        bscHash,
        expectedFrom: owner,
      );
      expect(evidence, isNotNull);
      expect(evidence!.transactionHash.toLowerCase(), bscHash);
      expect(evidence.from.toLowerCase(), owner);
      expect(evidence.nonce, BigInt.from(5));
    },
    skip: live ? false : 'set KT_LIVE_EVM_HISTORY=1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
