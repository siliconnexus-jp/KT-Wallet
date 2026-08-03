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
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'evm-airgap-matrix-v1';
const _gatewayUrl = 'https://gateway.kt-wallet.com';
const _recipient = '0x000000000000000000000000000000000000dEaD';

class _NetworkCase {
  const _NetworkCase({
    required this.key,
    required this.chain,
    required this.coin,
    required this.networkId,
    required this.networkLabel,
    required this.rpcUrl,
    required this.chainId,
    required this.nativeSymbol,
    required this.tokenSymbol,
    required this.tokenContract,
    required this.tokenDecimals,
  });

  final String key;
  final Chain chain;
  final Coin coin;
  final String networkId;
  final String networkLabel;
  final String rpcUrl;
  final int chainId;
  final String nativeSymbol;
  final String tokenSymbol;
  final String tokenContract;
  final int tokenDecimals;
}

const _networkCases = <_NetworkCase>[
  _NetworkCase(
    key: 'base',
    chain: Chain.base,
    coin: Coin.base,
    networkId: 'base-sepolia',
    networkLabel: 'Base Sepolia',
    rpcUrl: 'https://sepolia.base.org',
    chainId: 84532,
    nativeSymbol: 'ETH',
    tokenSymbol: 'USDC',
    tokenContract: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
    tokenDecimals: 6,
  ),
  _NetworkCase(
    key: 'arbitrum',
    chain: Chain.arbitrum,
    coin: Coin.arbitrum,
    networkId: 'arbitrum-sepolia',
    networkLabel: 'Arbitrum Sepolia',
    rpcUrl: 'https://sepolia-rollup.arbitrum.io/rpc',
    chainId: 421614,
    nativeSymbol: 'ETH',
    tokenSymbol: 'USDC',
    tokenContract: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
    tokenDecimals: 6,
  ),
  _NetworkCase(
    key: 'avalanche',
    chain: Chain.avalanche,
    coin: Coin.avalanche,
    networkId: 'avalanche-fuji',
    networkLabel: 'Avalanche Fuji',
    rpcUrl: 'https://api.avax-test.network/ext/bc/C/rpc',
    chainId: 43113,
    nativeSymbol: 'AVAX',
    tokenSymbol: 'USDC',
    tokenContract: '0x5425890298aed601595a70AB815c96711a31Bc65',
    tokenDecimals: 6,
  ),
  _NetworkCase(
    key: 'bnb',
    chain: Chain.bnb,
    coin: Coin.bnb,
    networkId: 'bnb-testnet',
    networkLabel: 'BNB Smart Chain Testnet',
    rpcUrl: 'https://bsc-testnet-dataseed.bnbchain.org',
    chainId: 97,
    nativeSymbol: 'BNB',
    tokenSymbol: 'BUSD',
    tokenContract: '0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee',
    tokenDecimals: 18,
  ),
];

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'EVM matrix AccountExport -> air-gap sign -> verify -> broadcast -> history',
    (tester) async {
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(
        mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json using '
            '--dart-define-from-file',
      );
      const selection = String.fromEnvironment(
        'EVM_AIRGAP_CHAINS',
        defaultValue: 'base,arbitrum,avalanche,bnb',
      );
      final selected = selection
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      final cases = _networkCases
          .where((network) => selected.contains(network.key))
          .toList(growable: false);
      expect(cases, isNotEmpty, reason: 'no EVM_AIRGAP_CHAINS matched');

      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final publicKeys = await crypto.derivePublicKeys(_walletId);

      final exported = _accountExport(addresses, publicKeys);
      final scannedExport = _roundTrip(exported, _requestId(0x31));
      expect(scannedExport, isA<AccountExport>());
      final paired = watchWalletFromAccountExport(
        scannedExport as AccountExport,
        id: 'watch-evm-airgap-matrix',
        avatarColor: 0xFF0C1220,
        sortOrder: 0,
      );
      expect(paired, isA<WatchWallet>());
      expect(paired.canSignLocally, isFalse);
      expect(paired.coldWalletId, _walletId);

      for (final network in cases) {
        await _runNetwork(
          network,
          crypto: crypto,
          paired: paired,
          addresses: addresses,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}

Future<void> _runNetwork(
  _NetworkCase network, {
  required CoreCrypto crypto,
  required WatchWallet paired,
  required ChainAddresses addresses,
}) async {
  final signer = addressForChain(addresses, network.chain);
  expect(
    addressForChain(paired.addresses, network.chain).toLowerCase(),
    signer.toLowerCase(),
  );
  final transport = HttpJsonRpcTransport(timeout: const Duration(seconds: 30));
  final rpc = EvmRpc(url: network.rpcUrl, transport: transport);
  final paramsService = ChainParamsService(
    jsonRpcTransport: transport,
    endpoints: (_) => network.rpcUrl,
  );
  final broadcaster = BroadcastService(
    jsonRpcTransport: transport,
    endpoints: (_) => network.rpcUrl,
  );
  final transfers = LocalTransferService(
    params: paramsService,
    broadcaster: broadcaster,
    endpoints: (_) => network.rpcUrl,
    jsonRpcTransport: transport,
  );
  final gateway = GatewayClient(
    baseUrl: _gatewayUrl,
    networks: (_) => network.networkId,
    timeout: const Duration(seconds: 30),
  );
  final history = HistoryService(
    gateway: () => gateway,
    endpoints: (_) => network.rpcUrl,
    timeout: const Duration(seconds: 30),
  );

  try {
    final tokenUnit = BigInt.from(10).pow(network.tokenDecimals);
    final balances = await Future.wait<BigInt>([
      rpc.getBalance(signer),
      rpc.erc20Balance(network.tokenContract, signer),
    ]);
    expect(
      balances[0],
      greaterThan(BigInt.from(100000000000000)),
      reason: '${network.networkLabel} needs native gas for two transactions',
    );
    expect(
      balances[1],
      greaterThanOrEqualTo(tokenUnit),
      reason: '${network.networkLabel} needs 1 ${network.tokenSymbol}',
    );

    final native = await _sendThroughAirGap(
      network,
      crypto: crypto,
      transfers: transfers,
      broadcaster: broadcaster,
      transport: transport,
      signer: signer,
      draft: TransferDraft(
        symbol: network.nativeSymbol,
        networkLabel: network.networkLabel,
        chain: network.chain,
        recipient: _recipient,
        amount: Amount.parse('0.000001', 18, symbol: network.nativeSymbol),
        feeTier: 1,
      ),
    );
    final token = await _sendThroughAirGap(
      network,
      crypto: crypto,
      transfers: transfers,
      broadcaster: broadcaster,
      transport: transport,
      signer: signer,
      draft: TransferDraft(
        symbol: network.tokenSymbol,
        networkLabel: network.networkLabel,
        chain: network.chain,
        recipient: _recipient,
        amount: Amount.parse(
          '1',
          network.tokenDecimals,
          symbol: network.tokenSymbol,
        ),
        feeTier: 1,
        tokenContract: network.tokenContract,
      ),
    );

    final records = await _waitForHistory(
      history,
      network,
      signer,
      hashes: {native.hash.toLowerCase(), token.hash.toLowerCase()},
    );
    final nativeRecord = records.where(
      (record) => record.hash.toLowerCase() == native.hash.toLowerCase(),
    );
    final tokenRecord = records.where(
      (record) =>
          record.hash.toLowerCase() == token.hash.toLowerCase() &&
          record.assetContract?.toLowerCase() ==
              network.tokenContract.toLowerCase(),
    );
    expect(nativeRecord, isNotEmpty);
    expect(tokenRecord, isNotEmpty);
    expect(nativeRecord.first.status, ChainTxStatus.confirmed);
    expect(tokenRecord.first.status, ChainTxStatus.confirmed);

    final tag = network.key.toUpperCase();
    // Public evidence only. No mnemonic/private key is printed or reported.
    // ignore: avoid_print
    print('${tag}_AIRGAP_ACCOUNT=$signer');
    // ignore: avoid_print
    print('${tag}_AIRGAP_NATIVE_TX=${native.hash}');
    // ignore: avoid_print
    print('${tag}_AIRGAP_${network.tokenSymbol}_TX=${token.hash}');
    // ignore: avoid_print
    print('${tag}_AIRGAP_HISTORY=confirmed');
  } finally {
    history.close();
    gateway.close();
    transport.close();
  }
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

Future<({String hash, Map<Object?, Object?> receipt})> _sendThroughAirGap(
  _NetworkCase network, {
  required CoreCrypto crypto,
  required LocalTransferService transfers,
  required BroadcastService broadcaster,
  required JsonRpcTransport transport,
  required String signer,
  required TransferDraft draft,
}) async {
  final prepared = await transfers.prepareEvm(
    draft: draft,
    from: signer,
    evmChainId: network.chainId,
  );
  final request = buildSignRequest(
    draft: draft,
    walletId: _walletId,
    fromAddress: signer,
    nonce: prepared.nonce,
    maxPriorityFeePerGas: prepared.maxPriorityFeePerGas,
    maxFeePerGas: prepared.maxFeePerGas,
    gasLimit: prepared.gasLimit,
    evmChainId: prepared.evmChainId,
    networkLabel: network.networkLabel,
  );
  expect(request.rawTx, orderedEquals(prepared.unsignedTx));

  final decodedRequest = _roundTrip(request, request.reqId) as SignRequest;
  final parsed = parseUnsignedTransfer(network.chain, decodedRequest.rawTx);
  expect(parsed.networkId, BigInt.from(network.chainId));
  expect(parsed.to.toLowerCase(), draft.recipient.toLowerCase());
  expect(parsed.amountRaw, draft.amount.raw);
  expect(
    parsed.tokenContract?.toLowerCase(),
    draft.tokenContract?.toLowerCase(),
  );

  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: network.coin,
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
    network.chain,
    verified.signedTx,
    expectedTxHash: verified.txHash,
  );
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  final hash = outcome.txHash!;
  expect(hash.toLowerCase(), verified.txHash.toLowerCase());
  final receipt = await _waitForReceipt(network, transport, hash);
  expect(receipt['status'], '0x1', reason: '$receipt');
  final onChain = await _getTransaction(network, transport, hash);
  final txTo = draft.tokenContract ?? draft.recipient;
  expect('${onChain['from']}'.toLowerCase(), signer.toLowerCase());
  expect('${onChain['to']}'.toLowerCase(), txTo.toLowerCase());
  return (hash: hash, receipt: receipt);
}

Future<Map<Object?, Object?>> _waitForReceipt(
  _NetworkCase network,
  JsonRpcTransport transport,
  String hash,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final response = await transport.post(network.rpcUrl, {
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
  throw TimeoutException('${network.networkLabel} receipt not mined: $hash');
}

Future<Map<Object?, Object?>> _getTransaction(
  _NetworkCase network,
  JsonRpcTransport transport,
  String hash,
) async {
  final response = await transport.post(network.rpcUrl, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_getTransactionByHash',
    'params': [hash],
  });
  if (response is! Map || response['result'] is! Map) {
    throw StateError('${network.networkLabel} transaction not found: $hash');
  }
  return (response['result'] as Map).cast<Object?, Object?>();
}

Future<List<ChainTxRecord>> _waitForHistory(
  HistoryService history,
  _NetworkCase network,
  String address, {
  required Set<String> hashes,
}) async {
  for (var attempt = 0; attempt < 72; attempt++) {
    final result = await history.fetch(network.coin, address, limit: 100);
    if (result.status == HistoryStatus.ok) {
      final seen = result.records
          .map((record) => record.hash.toLowerCase())
          .toSet();
      if (seen.containsAll(hashes)) return result.records;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  throw TimeoutException(
    '${network.networkLabel} history did not index both air-gap hashes',
  );
}
