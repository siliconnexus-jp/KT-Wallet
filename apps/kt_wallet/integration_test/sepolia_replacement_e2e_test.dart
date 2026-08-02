import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

const _walletId = 'sepolia-replacement-e2e-v3';
const _rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
const _chainId = 11155111;

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sepolia queued transaction supports real speed-up and cancellation',
    (tester) async {
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(
        mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json via '
            '--dart-define-from-file',
      );

      final crypto = MethodChannelCoreCrypto();
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      final gateway = GatewayClient(
        baseUrl: 'https://gateway.kt-wallet.com',
        networks: (coin) => coin == Coin.eth ? 'eth-sepolia' : null,
      );
      final rpc = EvmRpc(url: _rpcUrl, transport: transport);
      final broadcaster = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
        gateway: () => gateway,
      );
      final params = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
        gateway: () => gateway,
      );
      final transfers = LocalTransferService(
        params: params,
        broadcaster: broadcaster,
      );

      _stage('START');
      await crypto
          .storeWallet(
            walletId: _walletId,
            mnemonic: mnemonic,
            requireAuth: false,
          )
          .timeout(const Duration(seconds: 30));
      registerE2eWalletCleanup(crypto, _walletId);
      _stage('WALLET_STORED');
      try {
        final addresses = await crypto
            .deriveAddresses(_walletId)
            .timeout(const Duration(seconds: 30));
        _stage('ADDRESS_DERIVED');
        final sender = addresses.eth;
        expect(
          await _readChainId(transport).timeout(const Duration(seconds: 30)),
          _chainId,
        );
        _stage('CHAIN_VERIFIED');

        final initial = await params
            .fetchEvmParams(Chain.ethereum, sender)
            .timeout(const Duration(seconds: 30));
        final balance = await rpc
            .getBalance(sender)
            .timeout(const Duration(seconds: 30));
        _stage('PARAMS_READY');
        final originalFee = initial.fees.standard;
        final conservativeBudget =
            originalFee.maxFeePerGas * BigInt.from(21000 * 8);
        expect(
          balance,
          greaterThan(conservativeBudget),
          reason: 'the local Sepolia test account needs enough ETH for gas',
        );

        await _runReplacementScenario(
          label: 'SPEEDUP',
          cancel: false,
          sender: sender,
          crypto: crypto,
          transport: transport,
          broadcaster: broadcaster,
          params: params,
          transfers: transfers,
        );
        await _runReplacementScenario(
          label: 'CANCEL',
          cancel: true,
          sender: sender,
          crypto: crypto,
          transport: transport,
          broadcaster: broadcaster,
          params: params,
          transfers: transfers,
        );
      } finally {
        gateway.close();
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _runReplacementScenario({
  required String label,
  required bool cancel,
  required String sender,
  required CoreCrypto crypto,
  required JsonRpcTransport transport,
  required BroadcastService broadcaster,
  required ChainParamsService params,
  required LocalTransferService transfers,
}) async {
  _stage('${label}_START');
  final initial = await params
      .fetchEvmParams(Chain.ethereum, sender)
      .timeout(const Duration(seconds: 30));
  final originalFee = initial.fees.standard;

  // Queue nonce N+1 first. The deliberate one-nonce gap keeps this
  // transaction pending reliably even when Sepolia blocks are fast.
  final fillerNonce = BigInt.from(initial.nonce);
  final replacementNonce = fillerNonce + BigInt.one;
  final originalValue = BigInt.one;
  final originalHash = await _signAndBroadcast(
    crypto: crypto,
    broadcaster: broadcaster,
    unsigned: _selfTransfer(
      sender: sender,
      nonce: replacementNonce,
      priorityFee: originalFee.maxPriorityFeePerGas,
      maxFee: originalFee.maxFeePerGas,
      value: originalValue,
    ),
  ).timeout(const Duration(seconds: 30));
  // Transaction hashes are public testnet evidence; no signed bytes or wallet
  // secrets are logged.
  // ignore: avoid_print
  print('SEPOLIA_${label}_ORIGINAL_TX=$originalHash');

  PreparedEvmTransfer? replacement;
  String? winnerHash;
  String? fillerHash;
  try {
    replacement = await transfers
        .prepareEvmReplacement(
          chain: Chain.ethereum,
          evmChainId: _chainId,
          from: sender,
          recipient: sender,
          amountRaw: originalValue,
          tokenContract: null,
          nonce: replacementNonce,
          previousMaxPriorityFeePerGas: originalFee.maxPriorityFeePerGas,
          previousMaxFeePerGas: originalFee.maxFeePerGas,
          previousGasLimit: BigInt.from(21000),
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
      unsigned: replacement.unsignedTx,
    ).timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('SEPOLIA_${label}_WINNER_TX=$winnerHash');
  } finally {
    // Fill nonce N even when replacement preparation/broadcast fails, so this
    // test never intentionally leaves a queued transaction in the account.
    final live = await params
        .fetchEvmParams(Chain.ethereum, sender)
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
      unsigned: _selfTransfer(
        sender: sender,
        nonce: fillerNonce,
        priorityFee: priority,
        maxFee: maxFee,
      ),
    ).timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('SEPOLIA_${label}_FILLER_TX=$fillerHash');
  }

  expect(winnerHash, isNotNull);
  expect(winnerHash, isNot(originalHash));
  final fillerReceipt = await _waitForReceipt(
    transport,
    fillerHash,
  ).timeout(const Duration(seconds: 100));
  final winnerReceipt = await _waitForReceipt(
    transport,
    winnerHash,
  ).timeout(const Duration(seconds: 100));
  expect(fillerReceipt['status'], '0x1');
  expect(winnerReceipt['status'], '0x1');
  expect(
    await _getReceiptOrNull(transport, originalHash),
    isNull,
    reason: 'the lower-fee same-nonce candidate must not also be mined',
  );

  final winnerOnChain = await _getTransaction(transport, winnerHash);
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
  _stage('${label}_CONFIRMED');
}

Uint8List _selfTransfer({
  required String sender,
  required BigInt nonce,
  required BigInt priorityFee,
  required BigInt maxFee,
  BigInt? value,
}) => Eip1559Tx(
  chainId: BigInt.from(_chainId),
  nonce: nonce,
  maxPriorityFeePerGas: priorityFee,
  maxFeePerGas: maxFee,
  gasLimit: BigInt.from(21000),
  to: Eip1559Tx.addressBytes(sender),
  value: value ?? BigInt.zero,
  data: Uint8List(0),
).encodeUnsigned();

Future<String> _signAndBroadcast({
  required CoreCrypto crypto,
  required BroadcastService broadcaster,
  required Uint8List unsigned,
}) async {
  _stage('SIGN_START');
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.eth,
    signingInput: unsigned,
  );
  _stage('SIGN_DONE');
  _stage('BROADCAST_START');
  final outcome = await broadcaster.broadcast(Chain.ethereum, signed.signedTx);
  _stage('BROADCAST_DONE');
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  return outcome.txHash!;
}

Future<int> _readChainId(JsonRpcTransport transport) async {
  final response = await transport.post(_rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_chainId',
    'params': const <Object?>[],
  });
  if (response is! Map || response['result'] is! String) {
    throw StateError('Sepolia chainId unavailable');
  }
  return _hexQuantity(response['result']).toInt();
}

Future<Map<Object?, Object?>> _waitForReceipt(
  JsonRpcTransport transport,
  String hash,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final response = await transport.post(_rpcUrl, {
      'jsonrpc': '2.0',
      'id': attempt + 1,
      'method': 'eth_getTransactionReceipt',
      'params': [hash],
    });
    if (response is Map && response['result'] is Map) {
      return (response['result'] as Map).cast<Object?, Object?>();
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw TimeoutException('receipt not mined: $hash');
}

Future<Map<Object?, Object?>?> _getReceiptOrNull(
  JsonRpcTransport transport,
  String hash,
) async {
  final response = await transport.post(_rpcUrl, {
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
  String hash,
) async {
  final response = await transport.post(_rpcUrl, {
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

void _stage(String value) {
  // This marker contains no address, mnemonic, private key, or signed bytes.
  // ignore: avoid_print
  print('SEPOLIA_REPLACEMENT_STAGE=$value');
}
