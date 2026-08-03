import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdtSepoliaToken;
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';

const _walletId = 'sepolia-signing-e2e-v2';
const _rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
const _testUsdt = '0xc4DCC311c028e341fd8602D8eB89c5de94625927';
const _sink = '0x000000000000000000000000000000000000dEaD';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sepolia native transfer + Test USDT mint + ERC-20 transfer',
    (tester) async {
      final crypto = MethodChannelCoreCrypto();
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(
        mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json via '
            '--dart-define-from-file',
      );
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
      final rpc = EvmRpc(url: _rpcUrl, transport: transport);
      final paramsService = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
      );
      final broadcaster = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
      );

      try {
        final initialEth = await rpc.getBalance(addresses.eth);
        expect(initialEth, greaterThan(BigInt.from(1000000000000000)));
        expect(
          await _erc20Decimals(transport, _testUsdt),
          usdtSepoliaToken.decimals,
          reason: 'test transfer amounts must use the deployed token scale',
        );
        final tokenUnit = BigInt.from(10).pow(usdtSepoliaToken.decimals);

        final nativeParams = await paramsService.fetchEvmParams(
          Chain.ethereum,
          addresses.eth,
        );
        final nativeTx = Eip1559Tx(
          chainId: BigInt.from(11155111),
          nonce: BigInt.from(nativeParams.nonce),
          maxPriorityFeePerGas: nativeParams.fees.standard.maxPriorityFeePerGas,
          maxFeePerGas: nativeParams.fees.standard.maxFeePerGas,
          gasLimit: BigInt.from(21000),
          to: Eip1559Tx.addressBytes(_sink),
          value: BigInt.from(1000000000000), // 0.000001 ETH
          data: Uint8List(0),
        ).encodeUnsigned();
        final nativeHash = await _signBroadcastAndConfirm(
          crypto,
          broadcaster,
          transport,
          nativeTx,
        );
        final nativeOnChain = await _getTransaction(transport, nativeHash);
        expect(
          '${nativeOnChain['from']}'.toLowerCase(),
          addresses.eth.toLowerCase(),
        );
        expect('${nativeOnChain['to']}'.toLowerCase(), _sink.toLowerCase());
        expect(nativeOnChain['value'], '0xe8d4a51000');

        final mintParams = await paramsService.fetchEvmParams(
          Chain.ethereum,
          addresses.eth,
        );
        final mintAmount = BigInt.from(100) * tokenUnit;
        final mintTx = Eip1559Tx(
          chainId: BigInt.from(11155111),
          nonce: BigInt.from(mintParams.nonce),
          maxPriorityFeePerGas: mintParams.fees.standard.maxPriorityFeePerGas,
          maxFeePerGas: mintParams.fees.standard.maxFeePerGas,
          gasLimit: BigInt.from(100000),
          to: Eip1559Tx.addressBytes(_testUsdt),
          value: BigInt.zero,
          data: _mintCalldata(addresses.eth, mintAmount),
        ).encodeUnsigned();
        final mintHash = await _signBroadcastAndConfirm(
          crypto,
          broadcaster,
          transport,
          mintTx,
        );
        final tokenAfterMint = await rpc.erc20Balance(_testUsdt, addresses.eth);
        expect(tokenAfterMint, greaterThanOrEqualTo(mintAmount));

        final tokenParams = await paramsService.fetchEvmParams(
          Chain.ethereum,
          addresses.eth,
        );
        final transferAmount = tokenUnit;
        final tokenTx = Eip1559Tx(
          chainId: BigInt.from(11155111),
          nonce: BigInt.from(tokenParams.nonce),
          maxPriorityFeePerGas: tokenParams.fees.standard.maxPriorityFeePerGas,
          maxFeePerGas: tokenParams.fees.standard.maxFeePerGas,
          gasLimit: BigInt.from(65000),
          to: Eip1559Tx.addressBytes(_testUsdt),
          value: BigInt.zero,
          data: Erc20.transferCalldata(to: _sink, amount: transferAmount),
        ).encodeUnsigned();
        final tokenHash = await _signBroadcastAndConfirm(
          crypto,
          broadcaster,
          transport,
          tokenTx,
        );
        expect(
          await rpc.erc20Balance(_testUsdt, addresses.eth),
          tokenAfterMint - transferAmount,
        );

        // Public evidence only; no mnemonic or private key leaves the device.
        // ignore: avoid_print
        print('SEPOLIA_E2E_NATIVE_TX=$nativeHash');
        // ignore: avoid_print
        print('SEPOLIA_E2E_MINT_TX=$mintHash');
        // ignore: avoid_print
        print('SEPOLIA_E2E_USDT_TX=$tokenHash');
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<int> _erc20Decimals(JsonRpcTransport transport, String contract) async {
  final response = await transport.post(_rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_call',
    'params': [
      {'to': contract, 'data': '0x313ce567'},
      'latest',
    ],
  });
  final result = response is Map ? response['result'] : null;
  if (result is! String || !result.startsWith('0x')) {
    throw StateError('token decimals unavailable');
  }
  return int.parse(result.substring(2), radix: 16);
}

Future<String> _signBroadcastAndConfirm(
  CoreCrypto crypto,
  BroadcastService broadcaster,
  JsonRpcTransport transport,
  Uint8List unsigned,
) async {
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.eth,
    signingInput: unsigned,
  );
  final outcome = await broadcaster.broadcast(
    Chain.ethereum,
    signed.signedTx,
    expectedTxHash: signed.txHash,
  );
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  final hash = outcome.txHash!;
  final receipt = await _waitForReceipt(transport, hash);
  expect(receipt['status'], '0x1', reason: '$receipt');
  return hash;
}

Future<Map<Object?, Object?>> _waitForReceipt(
  JsonRpcTransport transport,
  String hash,
) async {
  for (var attempt = 0; attempt < 40; attempt++) {
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

Uint8List _mintCalldata(String recipient, BigInt amount) {
  final selector = keccak256(
    Uint8List.fromList(utf8.encode('mint(address,uint256)')),
  ).sublist(0, 4);
  final address = Eip1559Tx.addressBytes(recipient);
  final amountBytes = _uint256(amount);
  return Uint8List.fromList([
    ...selector,
    ...List<int>.filled(12, 0),
    ...address,
    ...amountBytes,
  ]);
}

Uint8List _uint256(BigInt value) {
  if (value < BigInt.zero || value.bitLength > 256) {
    throw ArgumentError.value(value, 'value', 'not uint256');
  }
  final out = Uint8List(32);
  var remaining = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return out;
}
