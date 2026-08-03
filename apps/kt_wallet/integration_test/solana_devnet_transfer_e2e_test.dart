import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';

const _walletId = 'solana-devnet-e2e-v1';
const _rpcUrl = 'https://api.devnet.solana.com';
const _usdcMint = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
const _sourceUsdcAccount = '4uZFDi2Tr3HgxJhnXtSogzJ7k4KZBnxe7z1qP818ugWK';
const _circleUsdcAccount = '6D2ZmPSpbtqPFuze1GKvhtEwJnrP9FpCvQXvQe9t6HQ8';
const _nativeRecipient = 'PKWh66GhWw5HQW2dDo9LvbuNd6b4EbJ49NmCi1Dsu3A';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Devnet native SOL + Circle USDC SPL transfer',
    (tester) async {
      final crypto = MethodChannelCoreCrypto();
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(mnemonic, isNotEmpty);
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      final rpc = SolanaRpc(url: _rpcUrl, transport: transport);
      final broadcaster = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
      );

      try {
        final solBefore = await rpc.getBalance(addresses.solana);
        final usdcBefore = await rpc.getTokenBalance(
          addresses.solana,
          _usdcMint,
        );
        expect(solBefore, greaterThan(BigInt.from(100000)));
        expect(usdcBefore, greaterThanOrEqualTo(BigInt.from(1000000)));

        final nativeMessage = SolanaMessage.systemTransfer(
          from: addresses.solana,
          to: _nativeRecipient,
          lamports: BigInt.from(10000),
          recentBlockhash: await rpc.getLatestBlockhash(),
        );
        final nativeHash = await _signBroadcastAndConfirm(
          crypto,
          rpc,
          broadcaster,
          nativeMessage,
        );

        final tokenMessage = SolanaMessage.splTransfer(
          source: _sourceUsdcAccount,
          destination: _circleUsdcAccount,
          owner: addresses.solana,
          amount: BigInt.from(1000000),
          recentBlockhash: await rpc.getLatestBlockhash(),
        );
        final tokenHash = await _signBroadcastAndConfirm(
          crypto,
          rpc,
          broadcaster,
          tokenMessage,
        );

        // Public chain evidence is printed before the finalized-balance wait
        // so a node commitment lag can never hide already-broadcast hashes.
        // ignore: avoid_print
        print('SOLANA_DEVNET_NATIVE_TX=$nativeHash');
        // ignore: avoid_print
        print('SOLANA_DEVNET_USDC_TX=$tokenHash');
        await _waitForBalance(
          () => rpc.getBalance(addresses.solana),
          (balance) => balance < solBefore,
          description: 'SOL balance to decrease',
        );
        await _waitForBalance(
          () => rpc.getTokenBalance(addresses.solana, _usdcMint),
          (balance) => balance == usdcBefore - BigInt.from(1000000),
          description: 'USDC balance to decrease by exactly 1 USDC',
        );
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<String> _signBroadcastAndConfirm(
  CoreCrypto crypto,
  SolanaRpc rpc,
  BroadcastService broadcaster,
  SolanaMessage message,
) async {
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.solana,
    signingInput: message.serialize(),
  );
  final result = await broadcaster.broadcast(
    Chain.solana,
    signed.signedTx,
    expectedTxHash: signed.txHash,
  );
  expect(result.status, BroadcastStatus.ok, reason: result.message);
  final signature = result.txHash!;
  for (var attempt = 0; attempt < 30; attempt++) {
    final status = await rpc.signatureResult(signature);
    if (status?.failed == true) {
      fail('Solana transaction was included but failed: $signature');
    }
    if (status?.confirmationStatus == 'confirmed' ||
        status?.confirmationStatus == 'finalized') {
      return signature;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException('Solana transaction not confirmed: $signature');
}

Future<void> _waitForBalance(
  Future<BigInt> Function() read,
  bool Function(BigInt) matches, {
  required String description,
}) async {
  BigInt? last;
  for (var attempt = 0; attempt < 30; attempt++) {
    last = await read();
    if (matches(last)) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  fail('Timed out waiting for $description; last value: $last');
}
