import 'dart:io';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';

void main() {
  final live = Platform.environment['KT_LIVE_SOLANA_PREFLIGHT'] == '1';

  test(
    'official Solana Devnet blockhash fee and simulation match strict schema',
    () async {
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      addTearDown(transport.close);
      final rpc = SolanaRpc(
        url: 'https://api.devnet.solana.com',
        transport: transport,
      );

      final latest = await rpc.getLatestBlockhashInfo();
      expect(latest.lastValidBlockHeight, greaterThan(0));

      // Public account used only to build a read-only, unsigned simulation.
      // No private key is loaded and sendTransaction is never called.
      const payer = '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut';
      const recipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
      final message = SolanaMessage.systemTransfer(
        from: payer,
        to: recipient,
        lamports: BigInt.zero,
        recentBlockhash: latest.blockhash,
      ).serialize();

      final fee = await rpc.getFeeForMessage(message);
      expect(fee, greaterThan(BigInt.zero));
      final simulated = await rpc.simulateMessage(
        message,
        accountAddresses: const [payer],
      );
      expect(simulated.accountLamports[payer], greaterThan(BigInt.zero));
      expect(simulated.feeLamports, fee);
      expect(simulated.unitsConsumed, isNotNull);

      // Previously confirmed, public Devnet transaction from the repository's
      // test report. This is a read-only compatibility check for the official
      // getSignatureStatuses shape; it never loads a key or broadcasts.
      const knownSignature =
          '23J1Vn2WniBbsdmGYVgoViGhZmrgErjUKbaQ1eikWEhiW4KjTAVjNL6ZwmuYtWro8L1oXxyPBGAJwAUCEgXvzzbX';
      final status = await rpc.signatureResult(knownSignature);
      expect(status, isNotNull);
      expect(status!.slot, greaterThan(0));
      expect(status.confirmationStatus, 'finalized');
      expect(status.failed, isFalse);
    },
    skip: live ? false : 'set KT_LIVE_SOLANA_PREFLIGHT=1',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'official Solana Devnet balance and SPL accounts match strict schema',
    () async {
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      addTearDown(transport.close);
      final rpc = SolanaRpc(
        url: 'https://api.devnet.solana.com',
        transport: transport,
      );

      const owner = '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut';
      const devnetUsdcMint = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
      expect(await rpc.getBalance(owner), greaterThan(BigInt.zero));
      expect(
        await rpc.getTokenBalance(owner, devnetUsdcMint, expectedDecimals: 6),
        greaterThanOrEqualTo(BigInt.zero),
      );
    },
    skip: live ? false : 'set KT_LIVE_SOLANA_PREFLIGHT=1',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'official Solana Devnet direct history matches strict schema',
    () async {
      const owner = '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut';
      final service = HistoryService(
        timeout: const Duration(seconds: 20),
        endpoints: (_) => 'https://api.devnet.solana.com',
      );
      addTearDown(service.close);

      final history = await service.fetch(Coin.solana, owner, limit: 3);
      expect(history.status, HistoryStatus.ok);
      expect(history.records, isNotEmpty);
      for (final record in history.records) {
        expect(record.hash, isNotEmpty);
        expect(record.amountText, isNotNull);
      }
    },
    skip: live ? false : 'set KT_LIVE_SOLANA_PREFLIGHT=1',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
