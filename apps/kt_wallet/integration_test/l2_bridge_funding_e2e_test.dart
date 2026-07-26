import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';

const _walletId = 'l2-bridge-funding-e2e-v1';
const _sepoliaRpc = 'https://ethereum-sepolia-rpc.publicnode.com';
const _baseRpc = 'https://sepolia.base.org';
const _arbitrumRpc = 'https://sepolia-rollup.arbitrum.io/rpc';
const _basePortal = '0x49f53e41452C74589E85cA1677426Ba426459e85';
const _arbitrumInbox = '0xaAe29B0366299461418F5324a79Afc425BE5ae21';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bridge Sepolia ETH to Base and Arbitrum Sepolia',
    (tester) async {
      final crypto = MethodChannelCoreCrypto();
      // ignore: avoid_print
      print('BRIDGE_STAGE=store');
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(mnemonic, isNotEmpty);
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(_walletId);
      // ignore: avoid_print
      print('BRIDGE_STAGE=balances');
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 25),
      );
      final params = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => _sepoliaRpc,
      );
      final broadcaster = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: (_) => _sepoliaRpc,
      );
      final amount = BigInt.from(10).pow(16); // 0.01 ETH on each L2.

      try {
        final baseBefore = await EvmRpc(
          url: _baseRpc,
          transport: transport,
        ).getBalance(addresses.base);
        final arbitrumBefore = await EvmRpc(
          url: _arbitrumRpc,
          transport: transport,
        ).getBalance(addresses.arbitrum);

        // ignore: avoid_print
        print('BRIDGE_STAGE=base-sign');
        final baseHash = await _sendL1(
          crypto,
          transport,
          params,
          broadcaster,
          from: addresses.eth,
          to: _basePortal,
          value: amount,
          data: _baseDepositCalldata(addresses.base, amount),
        );
        // ignore: avoid_print
        print('BRIDGE_STAGE=arbitrum-sign');
        final arbitrumHash = await _sendL1(
          crypto,
          transport,
          params,
          broadcaster,
          from: addresses.eth,
          to: _arbitrumInbox,
          value: amount,
          data: _selector('depositEth()'),
        );

        // ignore: avoid_print
        print('BRIDGE_STAGE=wait-l2');
        await _waitForBalance(
          EvmRpc(url: _baseRpc, transport: transport),
          addresses.base,
          baseBefore,
        );
        await _waitForBalance(
          EvmRpc(url: _arbitrumRpc, transport: transport),
          addresses.arbitrum,
          arbitrumBefore,
        );

        // ignore: avoid_print
        print('BASE_SEPOLIA_BRIDGE_L1_TX=$baseHash');
        // ignore: avoid_print
        print('ARBITRUM_SEPOLIA_BRIDGE_L1_TX=$arbitrumHash');
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<String> _sendL1(
  CoreCrypto crypto,
  JsonRpcTransport transport,
  ChainParamsService params,
  BroadcastService broadcaster, {
  required String from,
  required String to,
  required BigInt value,
  required Uint8List data,
}) async {
  final state = await params.fetchEvmParams(Chain.ethereum, from);
  final unsigned = Eip1559Tx(
    chainId: BigInt.from(11155111),
    nonce: BigInt.from(state.nonce),
    maxPriorityFeePerGas: state.fees.standard.maxPriorityFeePerGas,
    maxFeePerGas: state.fees.standard.maxFeePerGas,
    gasLimit: BigInt.from(300000),
    to: Eip1559Tx.addressBytes(to),
    value: value,
    data: data,
  ).encodeUnsigned();
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.eth,
    signingInput: unsigned,
  );
  final result = await broadcaster.broadcast(Chain.ethereum, signed.signedTx);
  expect(result.status, BroadcastStatus.ok, reason: result.message);
  await _waitForReceipt(transport, result.txHash!);
  return result.txHash!;
}

Uint8List _baseDepositCalldata(String recipient, BigInt value) =>
    Uint8List.fromList([
      ..._selector('depositTransaction(address,uint256,uint64,bool,bytes)'),
      ...List<int>.filled(12, 0),
      ...Eip1559Tx.addressBytes(recipient),
      ..._uint256(value),
      ..._uint256(BigInt.from(100000)),
      ..._uint256(BigInt.zero),
      ..._uint256(BigInt.from(160)),
      ..._uint256(BigInt.zero),
    ]);

Uint8List _selector(String signature) => Uint8List.fromList(
  keccak256(Uint8List.fromList(utf8.encode(signature))).sublist(0, 4),
);

Uint8List _uint256(BigInt value) {
  final out = Uint8List(32);
  var remaining = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return out;
}

Future<void> _waitForReceipt(JsonRpcTransport transport, String hash) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    final response = await transport.post(_sepoliaRpc, {
      'jsonrpc': '2.0',
      'id': attempt + 1,
      'method': 'eth_getTransactionReceipt',
      'params': [hash],
    });
    if (response is Map && response['result'] is Map) {
      expect((response['result'] as Map)['status'], '0x1');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw TimeoutException('L1 receipt not mined: $hash');
}

Future<void> _waitForBalance(EvmRpc rpc, String address, BigInt before) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (await rpc.getBalance(address) > before) return;
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  throw TimeoutException('L2 bridge deposit not credited');
}
