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

const _walletId = 'polygon-amoy-e2e-v1';
const _rpcUrl = 'https://polygon-amoy-bor-rpc.publicnode.com';
const _usdc = '0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582';
const _sink = '0x000000000000000000000000000000000000dEaD';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Amoy native POL + Circle USDC transfer',
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
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 20),
      );
      final rpc = EvmRpc(url: _rpcUrl, transport: transport);
      final params = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
      );
      final broadcaster = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: (_) => _rpcUrl,
      );

      try {
        final polBefore = await rpc.getBalance(addresses.polygon);
        final usdcBefore = await rpc.erc20Balance(_usdc, addresses.polygon);
        expect(polBefore, greaterThan(BigInt.from(1000000000000000)));
        expect(usdcBefore, greaterThanOrEqualTo(BigInt.from(1000000)));

        final nativeParams = await params.fetchEvmParams(
          Chain.polygon,
          addresses.polygon,
        );
        final nativeTx = Eip1559Tx(
          chainId: BigInt.from(80002),
          nonce: BigInt.from(nativeParams.nonce),
          maxPriorityFeePerGas: nativeParams.fees.standard.maxPriorityFeePerGas,
          maxFeePerGas: nativeParams.fees.standard.maxFeePerGas,
          gasLimit: BigInt.from(21000),
          to: Eip1559Tx.addressBytes(_sink),
          value: BigInt.from(1000000000000),
          data: Uint8List(0),
        ).encodeUnsigned();
        final nativeHash = await _signBroadcastAndConfirm(
          crypto,
          broadcaster,
          transport,
          nativeTx,
        );

        final tokenParams = await params.fetchEvmParams(
          Chain.polygon,
          addresses.polygon,
        );
        final tokenTx = Eip1559Tx(
          chainId: BigInt.from(80002),
          nonce: BigInt.from(tokenParams.nonce),
          maxPriorityFeePerGas: tokenParams.fees.standard.maxPriorityFeePerGas,
          maxFeePerGas: tokenParams.fees.standard.maxFeePerGas,
          gasLimit: BigInt.from(75000),
          to: Eip1559Tx.addressBytes(_usdc),
          value: BigInt.zero,
          data: Erc20.transferCalldata(to: _sink, amount: BigInt.from(1000000)),
        ).encodeUnsigned();
        final tokenHash = await _signBroadcastAndConfirm(
          crypto,
          broadcaster,
          transport,
          tokenTx,
        );

        expect(await rpc.getBalance(addresses.polygon), lessThan(polBefore));
        expect(
          await rpc.erc20Balance(_usdc, addresses.polygon),
          usdcBefore - BigInt.from(1000000),
        );
        // ignore: avoid_print
        print('POLYGON_AMOY_NATIVE_TX=$nativeHash');
        // ignore: avoid_print
        print('POLYGON_AMOY_USDC_TX=$tokenHash');
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<String> _signBroadcastAndConfirm(
  CoreCrypto crypto,
  BroadcastService broadcaster,
  JsonRpcTransport transport,
  Uint8List unsigned,
) async {
  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.polygon,
    signingInput: unsigned,
  );
  final result = await broadcaster.broadcast(Chain.polygon, signed.signedTx);
  expect(result.status, BroadcastStatus.ok, reason: result.message);
  final hash = result.txHash!;
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
  throw TimeoutException('Polygon receipt not mined: $hash');
}
