import 'dart:async';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';

const _walletId = 'tron-nile-e2e-v1';
const _rpcUrl = 'https://nile.trongrid.io';
const _testUsdt = 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Nile native TRX + test USDT transfer',
    (tester) async {
      final crypto = MethodChannelCoreCrypto();
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(mnemonic, isNotEmpty);
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(_walletId);
      final rest = HttpRestTransport(timeout: const Duration(seconds: 20));
      final rpc = TronRpc(baseUrl: _rpcUrl, transport: rest);
      final broadcaster = BroadcastService(
        restTransport: rest,
        endpoints: (_) => _rpcUrl,
      );

      try {
        final trxBefore = await rpc.getTrxBalance(addresses.tron);
        final usdtBefore = await _trc20Balance(rest, addresses.tron);
        expect(trxBefore, greaterThan(BigInt.from(10 * 1000000)));
        expect(usdtBefore, greaterThanOrEqualTo(BigInt.from(10 * 1000000)));

        final nativeHash = await _signBroadcastAndConfirm(
          crypto: crypto,
          rpc: rpc,
          rest: rest,
          broadcaster: broadcaster,
          intent: TransferIntent(
            chain: Chain.tron,
            operation: TxOperation.nativeTransfer,
            from: addresses.tron,
            to: _testUsdt,
            amount: Amount.parse('1', 6, symbol: 'TRX'),
          ),
        );
        expect(await rpc.getTrxBalance(addresses.tron), lessThan(trxBefore));

        final tokenHash = await _signBroadcastAndConfirm(
          crypto: crypto,
          rpc: rpc,
          rest: rest,
          broadcaster: broadcaster,
          intent: TransferIntent(
            chain: Chain.tron,
            operation: TxOperation.tokenTransfer,
            from: addresses.tron,
            to: _testUsdt,
            tokenContract: _testUsdt,
            amount: Amount.parse('1', 6, symbol: 'USDT'),
          ),
          feeLimit: 100000000,
        );
        expect(
          await _waitForTrc20Balance(
            rest,
            addresses.tron,
            usdtBefore - BigInt.from(1000000),
          ),
          usdtBefore - BigInt.from(1000000),
        );

        // Public chain evidence only.
        // ignore: avoid_print
        print('TRON_NILE_NATIVE_TX=$nativeHash');
        // ignore: avoid_print
        print('TRON_NILE_USDT_TX=$tokenHash');
      } finally {
        rest.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<String> _signBroadcastAndConfirm({
  required CoreCrypto crypto,
  required TronRpc rpc,
  required HttpRestTransport rest,
  required BroadcastService broadcaster,
  required TransferIntent intent,
  int? feeLimit,
}) async {
  final block = await rpc.getNowBlock();
  final number = block.number;
  final blockId = _hexDecode(block.blockId);
  final now = DateTime.now().millisecondsSinceEpoch;
  final raw = TronRawTx.forTransfer(
    intent,
    refBlockBytes: Uint8List.fromList([(number >> 8) & 0xff, number & 0xff]),
    refBlockHash: Uint8List.sublistView(blockId, 8, 16),
    timestamp: now,
    // Hardware-backed signing can wait for the user to authenticate. Keep
    // enough TAPOS validity for two consecutive confirmations in an E2E run.
    expiration: now + 10 * 60 * 1000,
    feeLimit: feeLimit,
  ).encodeRawData();
  // ignore: avoid_print
  print('TRON_NILE_SIGNING_${intent.operation.name}');
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.tron,
    signingInput: raw,
  );
  // ignore: avoid_print
  print('TRON_NILE_SIGNED_${intent.operation.name}');
  final result = await broadcaster.broadcast(Chain.tron, signed.signedTx);
  expect(result.status, BroadcastStatus.ok, reason: result.message);
  final hash = result.txHash!;
  // ignore: avoid_print
  print('TRON_NILE_BROADCAST_ACCEPTED=$hash');
  await _waitForConfirmation(rest, hash);
  return hash;
}

Future<void> _waitForConfirmation(HttpRestTransport rest, String hash) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    final result = await rest.postJson(
      '$_rpcUrl/wallet/gettransactioninfobyid',
      {'value': hash},
    );
    if (result is Map && result['id'] == hash) {
      expect(result['result'], anyOf(isNull, isA<Map<String, Object?>>()));
      final receipt = result['receipt'];
      if (receipt is Map && receipt['result'] != null) {
        expect(receipt['result'], 'SUCCESS', reason: '$result');
      }
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw TimeoutException('TRON transaction not confirmed: $hash');
}

Future<BigInt> _trc20Balance(HttpRestTransport rest, String address) async {
  final response = await rest.getJson('$_rpcUrl/v1/accounts/$address');
  final data = response is Map ? response['data'] : null;
  final account = data is List && data.isNotEmpty ? data.first : null;
  final balances = account is Map ? account['trc20'] : null;
  if (balances is! List) return BigInt.zero;
  for (final item in balances) {
    if (item is Map && item[_testUsdt] != null) {
      return BigInt.parse('${item[_testUsdt]}');
    }
  }
  return BigInt.zero;
}

Future<BigInt> _waitForTrc20Balance(
  HttpRestTransport rest,
  String address,
  BigInt expected,
) async {
  var balance = await _trc20Balance(rest, address);
  for (var attempt = 0; attempt < 10 && balance != expected; attempt++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    balance = await _trc20Balance(rest, address);
  }
  return balance;
}

Uint8List _hexDecode(String input) {
  if (input.length.isOdd) throw FormatException('odd hex length');
  return Uint8List.fromList([
    for (var i = 0; i < input.length; i += 2)
      int.parse(input.substring(i, i + 2), radix: 16),
  ]);
}
