import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdtSepoliaToken;
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'sepolia-airgap-full-loop-v1';
const _rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
const _gatewayUrl = 'https://gateway.kt-wallet.com';
const _recipient = '0x000000000000000000000000000000000000dEaD';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sepolia AccountExport -> air-gap sign -> verify -> broadcast -> history',
    (tester) async {
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(
        mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json using '
            '--dart-define-from-file',
      );

      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final publicKeys = await crypto.derivePublicKeys(_walletId);

      // Cold Signer export -> animated QR frames -> online scanner -> strict
      // public-key/address/path validation -> non-signing watch wallet.
      final exported = _accountExport(addresses, publicKeys);
      final scannedExport = _roundTrip(exported, _requestId(0x11));
      expect(scannedExport, isA<AccountExport>());
      final paired = watchWalletFromAccountExport(
        scannedExport as AccountExport,
        id: 'watch-sepolia-full-loop',
        avatarColor: 0xFF0C1220,
        sortOrder: 0,
      );
      expect(paired, isA<WatchWallet>());
      expect(paired.canSignLocally, isFalse);
      expect(paired.coldWalletId, _walletId);
      expect(paired.addresses.eth.toLowerCase(), addresses.eth.toLowerCase());

      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 25),
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
      final gateway = GatewayClient(
        baseUrl: _gatewayUrl,
        networks: (_) => 'eth-sepolia',
        timeout: const Duration(seconds: 30),
      );
      final history = HistoryService(
        gateway: () => gateway,
        endpoints: (_) => _rpcUrl,
        timeout: const Duration(seconds: 30),
      );

      try {
        final tokenUnit = BigInt.from(10).pow(usdtSepoliaToken.decimals);
        final balances = await Future.wait<BigInt>([
          rpc.getBalance(addresses.eth),
          rpc.erc20Balance(usdtSepoliaToken.contract, addresses.eth),
        ]);
        expect(
          balances[0],
          greaterThan(BigInt.from(500000000000000)),
          reason: 'the air-gap test account needs Sepolia ETH for two fees',
        );
        expect(
          balances[1],
          greaterThanOrEqualTo(tokenUnit),
          reason: 'the air-gap test account needs at least 1 test USDT',
        );

        final native = await _sendThroughAirGap(
          crypto: crypto,
          paramsService: paramsService,
          broadcaster: broadcaster,
          transport: transport,
          signer: paired.addresses.eth,
          draft: TransferDraft(
            symbol: 'ETH',
            networkLabel: 'Sepolia',
            chain: Chain.ethereum,
            recipient: _recipient,
            amount: Amount.parse('0.000001', 18, symbol: 'ETH'),
            feeTier: 1,
          ),
        );
        final token = await _sendThroughAirGap(
          crypto: crypto,
          paramsService: paramsService,
          broadcaster: broadcaster,
          transport: transport,
          signer: paired.addresses.eth,
          draft: TransferDraft(
            symbol: 'USDT',
            networkLabel: 'Sepolia',
            chain: Chain.ethereum,
            recipient: _recipient,
            amount: Amount.parse('1', 6, symbol: 'USDT'),
            feeTier: 1,
            tokenContract: usdtSepoliaToken.contract,
          ),
        );

        final records = await _waitForHistory(
          history,
          addresses.eth,
          hashes: {native.hash.toLowerCase(), token.hash.toLowerCase()},
        );
        final nativeRecord = records.where(
          (record) => record.hash.toLowerCase() == native.hash.toLowerCase(),
        );
        final tokenRecord = records.where(
          (record) =>
              record.hash.toLowerCase() == token.hash.toLowerCase() &&
              record.assetContract?.toLowerCase() ==
                  usdtSepoliaToken.contract.toLowerCase(),
        );
        expect(nativeRecord, isNotEmpty);
        expect(tokenRecord, isNotEmpty);
        expect(nativeRecord.first.status, ChainTxStatus.confirmed);
        expect(tokenRecord.first.status, ChainTxStatus.confirmed);

        // Public evidence only. No mnemonic/private key is printed or placed
        // in the HTML report.
        // ignore: avoid_print
        print('SEPOLIA_AIRGAP_ACCOUNT=${addresses.eth}');
        // ignore: avoid_print
        print('SEPOLIA_AIRGAP_NATIVE_TX=${native.hash}');
        // ignore: avoid_print
        print('SEPOLIA_AIRGAP_USDT_TX=${token.hash}');
        // ignore: avoid_print
        print('SEPOLIA_AIRGAP_HISTORY=confirmed');
      } finally {
        history.close();
        gateway.close();
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

AccountExport _accountExport(
  ChainAddresses addresses,
  ChainPublicKeys publicKeys,
) {
  AccountRecord account(int slip44, Chain chain, Coin coin) => AccountRecord(
    coin: slip44,
    address: addressForChain(addresses, chain),
    path: accountExportDerivationPaths[slip44]!,
    index: 0,
    publicKey: publicKeys.forCoin(coin),
  );
  return AccountExport(
    walletId: _walletId,
    walletName: 'KT Air-gap E2E',
    accounts: [
      account(60, Chain.ethereum, Coin.eth),
      account(966, Chain.polygon, Coin.polygon),
      account(8453, Chain.base, Coin.base),
      account(42161, Chain.arbitrum, Coin.arbitrum),
      account(9000, Chain.avalanche, Coin.avalanche),
      account(714, Chain.bnb, Coin.bnb),
      account(195, Chain.tron, Coin.tron),
      account(501, Chain.solana, Coin.solana),
    ],
  );
}

AirgapPayload _roundTrip(AirgapPayload payload, Uint8List reqId) {
  final aggregator = FrameAggregator();
  final frames = encodeQrFrames(payload, reqId: reqId);
  expect(frames.length, greaterThan(1));
  for (final qr in frames) {
    aggregator.addFrame(AirgapFrame.decode(base64Url.decode(qr)));
  }
  expect(aggregator.state, AggregatorState.done);
  return AirgapPayload.decode(aggregator.payload!);
}

Uint8List _requestId(int seed) => Uint8List.fromList([
  for (var i = 0; i < AirgapLimits.reqIdLength; i++) (seed + i) & 0xff,
]);

Future<({String hash, Map<Object?, Object?> receipt})> _sendThroughAirGap({
  required CoreCrypto crypto,
  required ChainParamsService paramsService,
  required BroadcastService broadcaster,
  required JsonRpcTransport transport,
  required String signer,
  required TransferDraft draft,
}) async {
  final params = await paramsService.fetchEvmParams(Chain.ethereum, signer);
  final tier = params.tierFor(draft.feeTier);
  final token = draft.tokenContract != null;
  final to = token ? draft.tokenContract! : draft.recipient;
  final value = token ? BigInt.zero : draft.amount.raw;
  final calldata = token
      ? Erc20.transferCalldata(to: draft.recipient, amount: draft.amount.raw)
      : Uint8List(0);
  final data = '0x${hexEncode(calldata)}';
  await paramsService.simulateEvmTransfer(
    Chain.ethereum,
    from: signer,
    to: to,
    value: value,
    data: data,
    tokenTransfer: token,
  );
  final gas = await paramsService.estimateEvmGas(
    Chain.ethereum,
    from: signer,
    to: to,
    value: value,
    data: data,
  );
  final request = buildSignRequest(
    draft: draft,
    walletId: _walletId,
    fromAddress: signer,
    nonce: BigInt.from(params.nonce),
    maxPriorityFeePerGas: tier.maxPriorityFeePerGas,
    maxFeePerGas: tier.maxFeePerGas,
    gasLimit: gas,
    evmChainId: 11155111,
    networkLabel: 'Sepolia',
  );

  final decodedRequest = _roundTrip(request, request.reqId) as SignRequest;
  final parsed = parseUnsignedTransfer(Chain.ethereum, decodedRequest.rawTx);
  expect(parsed.networkId, BigInt.from(11155111));
  expect(parsed.to.toLowerCase(), draft.recipient.toLowerCase());
  expect(parsed.amountRaw, draft.amount.raw);
  expect(
    parsed.tokenContract?.toLowerCase(),
    draft.tokenContract?.toLowerCase(),
  );

  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.eth,
    signingInput: decodedRequest.rawTx,
  );
  final response = SignResult(
    reqId: decodedRequest.reqId,
    walletId: decodedRequest.walletId,
    coin: decodedRequest.coin,
    signedTx: signed.signedTx,
    signer: signer,
    txHash: signed.txHash,
  );
  final decodedResponse = _roundTrip(response, decodedRequest.reqId);
  final verified = await verifySignResultCryptographically(
    decodedResponse.encode(),
    expected: decodedRequest,
    expectedSigner: signer,
  );
  expect(verified.txHash.toLowerCase(), signed.txHash.toLowerCase());

  final outcome = await broadcaster.broadcast(
    Chain.ethereum,
    verified.signedTx,
    expectedTxHash: verified.txHash,
  );
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  final hash = outcome.txHash!;
  expect(hash.toLowerCase(), verified.txHash.toLowerCase());
  final receipt = await _waitForReceipt(transport, hash);
  expect(receipt['status'], '0x1', reason: '$receipt');
  final onChain = await _getTransaction(transport, hash);
  expect('${onChain['from']}'.toLowerCase(), signer.toLowerCase());
  expect('${onChain['to']}'.toLowerCase(), to.toLowerCase());
  return (hash: hash, receipt: receipt);
}

Future<Map<Object?, Object?>> _waitForReceipt(
  JsonRpcTransport transport,
  String hash,
) async {
  for (var attempt = 0; attempt < 60; attempt++) {
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

Future<List<ChainTxRecord>> _waitForHistory(
  HistoryService history,
  String address, {
  required Set<String> hashes,
}) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    final result = await history.fetch(Coin.eth, address, limit: 100);
    if (result.status == HistoryStatus.ok) {
      final seen = result.records
          .map((record) => record.hash.toLowerCase())
          .toSet();
      if (seen.containsAll(hashes)) return result.records;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  throw TimeoutException('Sepolia history did not index both air-gap hashes');
}
