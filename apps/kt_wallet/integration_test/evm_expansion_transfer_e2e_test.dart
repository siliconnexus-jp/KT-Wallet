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

const _walletId = 'evm-expansion-e2e-v1';
const _sink = '0x000000000000000000000000000000000000dEaD';

const _cases = [
  (
    name: 'BASE_SEPOLIA',
    chain: Chain.base,
    coin: Coin.base,
    rpc: 'https://sepolia.base.org',
    chainId: 84532,
    usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  ),
  (
    name: 'ARBITRUM_SEPOLIA',
    chain: Chain.arbitrum,
    coin: Coin.arbitrum,
    rpc: 'https://sepolia-rollup.arbitrum.io/rpc',
    chainId: 421614,
    usdc: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
  ),
  (
    name: 'AVALANCHE_FUJI',
    chain: Chain.avalanche,
    coin: Coin.avalanche,
    rpc: 'https://api.avax-test.network/ext/bc/C/rpc',
    chainId: 43113,
    usdc: '0x5425890298aed601595a70AB815c96711a31Bc65',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Base + Arbitrum + Avalanche native and USDC transfers',
    (tester) async {
      final crypto = MethodChannelCoreCrypto();
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      const selected = String.fromEnvironment(
        'EVM_E2E_CHAINS',
        defaultValue: 'BASE_SEPOLIA,ARBITRUM_SEPOLIA,AVALANCHE_FUJI',
      );
      expect(mnemonic, isNotEmpty);
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(_walletId);
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 25),
      );

      try {
        for (final item in _cases) {
          if (!selected.split(',').contains(item.name)) continue;
          final address = addresses.forCoin(item.coin);
          final rpc = EvmRpc(url: item.rpc, transport: transport);
          final params = ChainParamsService(
            jsonRpcTransport: transport,
            endpoints: (_) => item.rpc,
          );
          final broadcaster = BroadcastService(
            jsonRpcTransport: transport,
            endpoints: (_) => item.rpc,
          );
          final nativeBefore = await rpc.getBalance(address);
          final usdcBefore = await rpc.erc20Balance(item.usdc, address);
          expect(nativeBefore, greaterThan(BigInt.from(100000000000000)));
          expect(usdcBefore, greaterThanOrEqualTo(BigInt.from(1000000)));

          final nativeHash = await _transfer(
            crypto,
            transport,
            params,
            broadcaster,
            chain: item.chain,
            coin: item.coin,
            rpcUrl: item.rpc,
            chainId: item.chainId,
            from: address,
            to: _sink,
            value: BigInt.from(1000000000000),
            data: Uint8List(0),
            gasLimit: item.chain == Chain.arbitrum ? 100000 : 21000,
          );
          final usdcHash = await _transfer(
            crypto,
            transport,
            params,
            broadcaster,
            chain: item.chain,
            coin: item.coin,
            rpcUrl: item.rpc,
            chainId: item.chainId,
            from: address,
            to: item.usdc,
            value: BigInt.zero,
            data: Erc20.transferCalldata(
              to: _sink,
              amount: BigInt.from(1000000),
            ),
            gasLimit: item.chain == Chain.arbitrum ? 150000 : 90000,
          );

          expect(await rpc.getBalance(address), lessThan(nativeBefore));
          await _waitForTokenBalance(
            rpc,
            item.usdc,
            address,
            usdcBefore - BigInt.from(1000000),
          );
          // ignore: avoid_print
          print('${item.name}_NATIVE_TX=$nativeHash');
          // ignore: avoid_print
          print('${item.name}_USDC_TX=$usdcHash');
        }
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _waitForTokenBalance(
  EvmRpc rpc,
  String contract,
  String address,
  BigInt expected,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (await rpc.erc20Balance(contract, address) == expected) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  expect(await rpc.erc20Balance(contract, address), expected);
}

Future<String> _transfer(
  CoreCrypto crypto,
  JsonRpcTransport transport,
  ChainParamsService params,
  BroadcastService broadcaster, {
  required Chain chain,
  required Coin coin,
  required String rpcUrl,
  required int chainId,
  required String from,
  required String to,
  required BigInt value,
  required Uint8List data,
  required int gasLimit,
}) async {
  final state = await params.fetchEvmParams(chain, from);
  final tx = Eip1559Tx(
    chainId: BigInt.from(chainId),
    nonce: BigInt.from(state.nonce),
    maxPriorityFeePerGas: state.fees.standard.maxPriorityFeePerGas,
    maxFeePerGas: state.fees.standard.maxFeePerGas,
    gasLimit: BigInt.from(gasLimit),
    to: Eip1559Tx.addressBytes(to),
    value: value,
    data: data,
  ).encodeUnsigned();
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: coin,
    signingInput: tx,
  );
  final result = await broadcaster.broadcast(chain, signed.signedTx);
  expect(result.status, BroadcastStatus.ok, reason: result.message);
  await _waitForReceipt(transport, rpcUrl, result.txHash!);
  return result.txHash!;
}

Future<void> _waitForReceipt(
  JsonRpcTransport transport,
  String rpcUrl,
  String hash,
) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    final response = await transport.post(rpcUrl, {
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
  throw TimeoutException('receipt not mined: $hash');
}
