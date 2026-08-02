import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

const _walletId = 'evm-replacement-matrix-e2e-v1';

const _cases = [
  (
    name: 'BASE_SEPOLIA',
    chain: Chain.base,
    coin: Coin.base,
    rpc: 'https://sepolia.base.org',
    chainId: 84532,
    gasLimit: 21000,
    nonceGap: true,
  ),
  (
    name: 'ARBITRUM_SEPOLIA',
    chain: Chain.arbitrum,
    coin: Coin.arbitrum,
    rpc: 'https://sepolia-rollup.arbitrum.io/rpc',
    chainId: 421614,
    gasLimit: 100000,
    nonceGap: false,
  ),
  (
    name: 'AVALANCHE_FUJI',
    chain: Chain.avalanche,
    coin: Coin.avalanche,
    rpc: 'https://api.avax-test.network/ext/bc/C/rpc',
    chainId: 43113,
    gasLimit: 21000,
    nonceGap: false,
  ),
  (
    name: 'BNB_TESTNET',
    chain: Chain.bnb,
    coin: Coin.bnb,
    rpc: 'https://bsc-testnet-rpc.publicnode.com',
    chainId: 97,
    gasLimit: 21000,
    nonceGap: true,
  ),
];

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'EVM testnet matrix supports real speed-up and cancellation',
    (tester) async {
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      const selected = String.fromEnvironment(
        'EVM_REPLACEMENT_CHAINS',
        defaultValue:
            'BASE_SEPOLIA,ARBITRUM_SEPOLIA,AVALANCHE_FUJI,BNB_TESTNET',
      );
      expect(
        mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json via '
            '--dart-define-from-file',
      );
      final enabled = selected
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      expect(enabled, isNotEmpty);

      final crypto = MethodChannelCoreCrypto();
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 25),
      );
      await crypto
          .storeWallet(
            walletId: _walletId,
            mnemonic: mnemonic,
            requireAuth: false,
          )
          .timeout(const Duration(seconds: 30));
      registerE2eWalletCleanup(crypto, _walletId);
      try {
        final addresses = await crypto
            .deriveAddresses(_walletId)
            .timeout(const Duration(seconds: 30));
        for (final item in _cases) {
          if (!enabled.contains(item.name)) continue;
          final sender = addresses.forCoin(item.coin);
          expect(
            await _readChainId(transport, item.rpc),
            item.chainId,
            reason: '${item.name} RPC returned the wrong chainId',
          );
          final rpc = EvmRpc(url: item.rpc, transport: transport);
          final params = ChainParamsService(
            jsonRpcTransport: transport,
            endpoints: (_) => item.rpc,
          );
          final broadcaster = BroadcastService(
            jsonRpcTransport: transport,
            endpoints: (_) => item.rpc,
          );
          final transfers = LocalTransferService(
            params: params,
            broadcaster: broadcaster,
          );
          final initial = await params
              .fetchEvmParams(item.chain, sender)
              .timeout(const Duration(seconds: 30));
          final balance = await rpc
              .getBalance(sender)
              .timeout(const Duration(seconds: 30));
          final conservativeBudget =
              initial.fees.standard.maxFeePerGas *
              BigInt.from(item.gasLimit * 8);
          expect(
            balance,
            greaterThan(conservativeBudget),
            reason:
                '${item.name} account needs enough native gas for both '
                'replacement scenarios before the first broadcast',
          );
          _stage(item.name, 'READY');

          await _runScenario(
            item: item,
            label: 'SPEEDUP',
            cancel: false,
            sender: sender,
            crypto: crypto,
            transport: transport,
            broadcaster: broadcaster,
            params: params,
            transfers: transfers,
          );
          await _runScenario(
            item: item,
            label: 'CANCEL',
            cancel: true,
            sender: sender,
            crypto: crypto,
            transport: transport,
            broadcaster: broadcaster,
            params: params,
            transfers: transfers,
          );
        }
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _runScenario({
  required ({
    String name,
    Chain chain,
    Coin coin,
    String rpc,
    int chainId,
    int gasLimit,
    bool nonceGap,
  })
  item,
  required String label,
  required bool cancel,
  required String sender,
  required CoreCrypto crypto,
  required JsonRpcTransport transport,
  required BroadcastService broadcaster,
  required ChainParamsService params,
  required LocalTransferService transfers,
}) async {
  if (!item.nonceGap) {
    return _runRapidScenario(
      item: item,
      label: label,
      cancel: cancel,
      sender: sender,
      crypto: crypto,
      transport: transport,
      broadcaster: broadcaster,
      params: params,
      transfers: transfers,
    );
  }
  _stage(item.name, '${label}_START');
  final initial = await params
      .fetchEvmParams(item.chain, sender)
      .timeout(const Duration(seconds: 30));
  final originalFee = initial.fees.standard;
  final fillerNonce = BigInt.from(initial.nonce);
  final replacementNonce = fillerNonce + BigInt.one;
  final originalValue = BigInt.one;
  final originalHash = await _signAndBroadcast(
    crypto: crypto,
    broadcaster: broadcaster,
    chain: item.chain,
    coin: item.coin,
    unsigned: _selfTransfer(
      sender: sender,
      chainId: item.chainId,
      nonce: replacementNonce,
      priorityFee: originalFee.maxPriorityFeePerGas,
      maxFee: originalFee.maxFeePerGas,
      gasLimit: item.gasLimit,
      value: originalValue,
    ),
  ).timeout(const Duration(seconds: 30));
  // Public testnet hashes are evidence; no address, signed bytes or secret is
  // printed by this test.
  // ignore: avoid_print
  print('${item.name}_${label}_ORIGINAL_TX=$originalHash');

  PreparedEvmTransfer? replacement;
  String? winnerHash;
  String? fillerHash;
  try {
    replacement = await transfers
        .prepareEvmReplacement(
          chain: item.chain,
          evmChainId: item.chainId,
          from: sender,
          recipient: sender,
          amountRaw: originalValue,
          tokenContract: null,
          nonce: replacementNonce,
          previousMaxPriorityFeePerGas: originalFee.maxPriorityFeePerGas,
          previousMaxFeePerGas: originalFee.maxFeePerGas,
          previousGasLimit: BigInt.from(item.gasLimit),
          cancel: cancel,
        )
        .timeout(const Duration(seconds: 30));
    expect(
      replacement.maxPriorityFeePerGas,
      greaterThan(originalFee.maxPriorityFeePerGas),
    );
    expect(replacement.maxFeePerGas, greaterThan(originalFee.maxFeePerGas));
    expect(replacement.recipient.toLowerCase(), sender.toLowerCase());
    expect(replacement.amountRaw, cancel ? BigInt.zero : originalValue);
    winnerHash = await _signAndBroadcast(
      crypto: crypto,
      broadcaster: broadcaster,
      chain: item.chain,
      coin: item.coin,
      unsigned: replacement.unsignedTx,
    ).timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('${item.name}_${label}_WINNER_TX=$winnerHash');
  } finally {
    final live = await params
        .fetchEvmParams(item.chain, sender)
        .timeout(const Duration(seconds: 30));
    final fast = live.fees.fast;
    final priority = _max(
      replacement?.maxPriorityFeePerGas ?? BigInt.zero,
      fast.maxPriorityFeePerGas,
    );
    final maxFee = _max(
      replacement?.maxFeePerGas ?? BigInt.zero,
      fast.maxFeePerGas,
    );
    fillerHash = await _signAndBroadcast(
      crypto: crypto,
      broadcaster: broadcaster,
      chain: item.chain,
      coin: item.coin,
      unsigned: _selfTransfer(
        sender: sender,
        chainId: item.chainId,
        nonce: fillerNonce,
        priorityFee: priority,
        maxFee: maxFee,
        gasLimit: item.gasLimit,
      ),
    ).timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('${item.name}_${label}_FILLER_TX=$fillerHash');
  }

  expect(winnerHash, isNotNull);
  expect(winnerHash, isNot(originalHash));
  final fillerReceipt = await _waitForReceipt(
    transport,
    item.rpc,
    fillerHash,
  ).timeout(const Duration(seconds: 120));
  final winnerReceipt = await _waitForReceipt(
    transport,
    item.rpc,
    winnerHash,
  ).timeout(const Duration(seconds: 120));
  expect(fillerReceipt['status'], '0x1');
  expect(winnerReceipt['status'], '0x1');
  expect(
    await _getReceiptOrNull(transport, item.rpc, originalHash),
    isNull,
    reason: '${item.name} lower-fee same-nonce candidate must not be mined',
  );

  final winnerOnChain = await _getTransaction(transport, item.rpc, winnerHash);
  expect('${winnerOnChain['from']}'.toLowerCase(), sender.toLowerCase());
  expect('${winnerOnChain['to']}'.toLowerCase(), sender.toLowerCase());
  expect(_hexQuantity(winnerOnChain['nonce']), replacementNonce);
  expect(
    _hexQuantity(winnerOnChain['value']),
    cancel ? BigInt.zero : originalValue,
  );
  expect(
    _hexQuantity(winnerOnChain['maxPriorityFeePerGas']),
    replacement.maxPriorityFeePerGas,
  );
  expect(_hexQuantity(winnerOnChain['maxFeePerGas']), replacement.maxFeePerGas);
  _stage(item.name, '${label}_CONFIRMED');
}

Future<void> _runRapidScenario({
  required ({
    String name,
    Chain chain,
    Coin coin,
    String rpc,
    int chainId,
    int gasLimit,
    bool nonceGap,
  })
  item,
  required String label,
  required bool cancel,
  required String sender,
  required CoreCrypto crypto,
  required JsonRpcTransport transport,
  required BroadcastService broadcaster,
  required ChainParamsService params,
  required LocalTransferService transfers,
}) async {
  _stage(item.name, '${label}_RAPID_START');
  final initial = await params
      .fetchEvmParams(item.chain, sender)
      .timeout(const Duration(seconds: 30));
  final nonce = BigInt.from(initial.nonce);
  // Use the live slow tier for the original and let replacement preparation
  // select at least the fast tier. This creates a meaningful fee delta on
  // chains whose sequencers finalize within a few hundred milliseconds.
  final originalFee = initial.fees.slow;
  final originalValue = BigInt.one;
  final originalUnsigned = _selfTransfer(
    sender: sender,
    chainId: item.chainId,
    nonce: nonce,
    priorityFee: originalFee.maxPriorityFeePerGas,
    maxFee: originalFee.maxFeePerGas,
    gasLimit: item.gasLimit,
    value: originalValue,
  );
  final replacement = await transfers
      .prepareEvmReplacement(
        chain: item.chain,
        evmChainId: item.chainId,
        from: sender,
        recipient: sender,
        amountRaw: originalValue,
        tokenContract: null,
        nonce: nonce,
        previousMaxPriorityFeePerGas: originalFee.maxPriorityFeePerGas,
        previousMaxFeePerGas: originalFee.maxFeePerGas,
        previousGasLimit: BigInt.from(item.gasLimit),
        cancel: cancel,
      )
      .timeout(const Duration(seconds: 30));
  expect(
    replacement.maxPriorityFeePerGas,
    greaterThan(originalFee.maxPriorityFeePerGas),
  );
  expect(replacement.maxFeePerGas, greaterThan(originalFee.maxFeePerGas));
  expect(replacement.amountRaw, cancel ? BigInt.zero : originalValue);

  // Fast L2 sequencers reject nonce gaps and can mine within a biometric
  // round-trip. Sign both candidates first, then submit the lower-fee original
  // slightly ahead of the winner. Both node acknowledgements plus the single
  // winner receipt prove real same-nonce replacement without a fake delay.
  final originalSigned = await _sign(
    crypto: crypto,
    coin: item.coin,
    unsigned: originalUnsigned,
  );
  final winnerSigned = await _sign(
    crypto: crypto,
    coin: item.coin,
    unsigned: replacement.unsignedTx,
  );
  final originalFuture = broadcaster.broadcast(item.chain, originalSigned);
  await Future<void>.delayed(const Duration(milliseconds: 1));
  final winnerFuture = broadcaster.broadcast(item.chain, winnerSigned);
  final outcomes = await Future.wait([originalFuture, winnerFuture]);
  expect(outcomes[0].status, BroadcastStatus.ok, reason: outcomes[0].message);
  expect(outcomes[1].status, BroadcastStatus.ok, reason: outcomes[1].message);
  final originalHash = outcomes[0].txHash!;
  final winnerHash = outcomes[1].txHash!;
  expect(winnerHash, isNot(originalHash));
  // ignore: avoid_print
  print('${item.name}_${label}_ORIGINAL_TX=$originalHash');
  // ignore: avoid_print
  print('${item.name}_${label}_WINNER_TX=$winnerHash');

  final winnerReceipt = await _waitForReceipt(
    transport,
    item.rpc,
    winnerHash,
  ).timeout(const Duration(seconds: 120));
  expect(winnerReceipt['status'], '0x1');
  expect(
    await _getReceiptOrNull(transport, item.rpc, originalHash),
    isNull,
    reason: '${item.name} lower-fee same-nonce candidate must not be mined',
  );
  final winnerOnChain = await _getTransaction(transport, item.rpc, winnerHash);
  expect('${winnerOnChain['from']}'.toLowerCase(), sender.toLowerCase());
  expect('${winnerOnChain['to']}'.toLowerCase(), sender.toLowerCase());
  expect(_hexQuantity(winnerOnChain['nonce']), nonce);
  expect(
    _hexQuantity(winnerOnChain['value']),
    cancel ? BigInt.zero : originalValue,
  );
  expect(
    _hexQuantity(winnerOnChain['maxPriorityFeePerGas']),
    replacement.maxPriorityFeePerGas,
  );
  expect(_hexQuantity(winnerOnChain['maxFeePerGas']), replacement.maxFeePerGas);
  _stage(item.name, '${label}_RAPID_CONFIRMED');
}

Uint8List _selfTransfer({
  required String sender,
  required int chainId,
  required BigInt nonce,
  required BigInt priorityFee,
  required BigInt maxFee,
  required int gasLimit,
  BigInt? value,
}) => Eip1559Tx(
  chainId: BigInt.from(chainId),
  nonce: nonce,
  maxPriorityFeePerGas: priorityFee,
  maxFeePerGas: maxFee,
  gasLimit: BigInt.from(gasLimit),
  to: Eip1559Tx.addressBytes(sender),
  value: value ?? BigInt.zero,
  data: Uint8List(0),
).encodeUnsigned();

Future<String> _signAndBroadcast({
  required CoreCrypto crypto,
  required BroadcastService broadcaster,
  required Chain chain,
  required Coin coin,
  required Uint8List unsigned,
}) async {
  final signed = await _sign(crypto: crypto, coin: coin, unsigned: unsigned);
  final outcome = await broadcaster.broadcast(chain, signed);
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  return outcome.txHash!;
}

Future<Uint8List> _sign({
  required CoreCrypto crypto,
  required Coin coin,
  required Uint8List unsigned,
}) async {
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: coin,
    signingInput: unsigned,
  );
  return signed.signedTx;
}

Future<int> _readChainId(JsonRpcTransport transport, String rpcUrl) async {
  final response = await transport.post(rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_chainId',
    'params': const <Object?>[],
  });
  if (response is! Map || response['result'] is! String) {
    throw StateError('chainId unavailable');
  }
  return _hexQuantity(response['result']).toInt();
}

Future<Map<Object?, Object?>> _waitForReceipt(
  JsonRpcTransport transport,
  String rpcUrl,
  String hash,
) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    final receipt = await _getReceiptOrNull(transport, rpcUrl, hash);
    if (receipt != null) return receipt;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw TimeoutException('receipt not mined: $hash');
}

Future<Map<Object?, Object?>?> _getReceiptOrNull(
  JsonRpcTransport transport,
  String rpcUrl,
  String hash,
) async {
  final response = await transport.post(rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_getTransactionReceipt',
    'params': [hash],
  });
  if (response is! Map || response['result'] == null) return null;
  if (response['result'] is! Map) {
    throw StateError('invalid transaction receipt: $hash');
  }
  return (response['result'] as Map).cast<Object?, Object?>();
}

Future<Map<Object?, Object?>> _getTransaction(
  JsonRpcTransport transport,
  String rpcUrl,
  String hash,
) async {
  final response = await transport.post(rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_getTransactionByHash',
    'params': [hash],
  });
  if (response is! Map || response['result'] is! Map) {
    throw StateError('transaction not found: $hash');
  }
  return (response['result'] as Map).cast<Object?, Object?>();
}

BigInt _hexQuantity(Object? value) {
  final text = '$value';
  if (!text.startsWith('0x')) throw StateError('invalid hex quantity: $text');
  final digits = text.substring(2);
  return digits.isEmpty ? BigInt.zero : BigInt.parse(digits, radix: 16);
}

BigInt _max(BigInt a, BigInt b) => a > b ? a : b;

void _stage(String network, String value) {
  // This marker contains no address, mnemonic, private key or signed bytes.
  // ignore: avoid_print
  print('${network}_REPLACEMENT_STAGE=$value');
}
