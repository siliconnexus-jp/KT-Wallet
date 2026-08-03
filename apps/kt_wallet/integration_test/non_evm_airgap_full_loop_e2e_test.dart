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
    show usdcSolanaDevnetToken;
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/state/networks.dart' show solanaDevnet, tronNile;
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'non-evm-airgap-full-loop-v1';
const _gatewayUrl = 'https://gateway.kt-wallet.com';
const _tronRpcUrl = 'https://nile.trongrid.io';
const _solanaRpcUrl = 'https://api.devnet.solana.com';
const _testUsdt = 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf';
const _tronRecipient = 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR';
const _solanaRecipient = 'PKWh66GhWw5HQW2dDo9LvbuNd6b4EbJ49NmCi1Dsu3A';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TRON + Solana AccountExport -> air-gap -> verify -> broadcast -> history',
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
        'NON_EVM_AIRGAP_CHAINS',
        defaultValue: 'tron,solana',
      );
      final selected = selection
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      expect(
        selected.intersection(const {'tron', 'solana'}),
        isNotEmpty,
        reason: 'NON_EVM_AIRGAP_CHAINS must contain tron or solana',
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
      final scannedExport = _roundTrip(
        _accountExport(addresses, publicKeys),
        _requestId(0x51),
      );
      expect(scannedExport, isA<AccountExport>());
      final paired = watchWalletFromAccountExport(
        scannedExport as AccountExport,
        id: 'watch-non-evm-airgap-full-loop',
        avatarColor: 0xFF0C1220,
        sortOrder: 0,
      );
      expect(paired.canSignLocally, isFalse);
      expect(paired.coldWalletId, _walletId);

      final jsonTransport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 30),
      );
      final restTransport = HttpRestTransport(
        timeout: const Duration(seconds: 30),
      );
      String endpoint(Coin coin) => switch (coin) {
        Coin.tron => _tronRpcUrl,
        Coin.solana => _solanaRpcUrl,
        _ => throw ArgumentError('unexpected non-EVM coin: $coin'),
      };
      String network(Coin coin) => switch (coin) {
        Coin.tron => 'tron-nile',
        Coin.solana => 'sol-devnet',
        _ => throw ArgumentError('unexpected non-EVM coin: $coin'),
      };
      final broadcaster = BroadcastService(
        jsonRpcTransport: jsonTransport,
        restTransport: restTransport,
        endpoints: endpoint,
      );
      final transfers = LocalTransferService(
        broadcaster: broadcaster,
        endpoints: endpoint,
        jsonRpcTransport: jsonTransport,
        restTransport: restTransport,
      );
      final gateway = GatewayClient(
        baseUrl: _gatewayUrl,
        networks: network,
        timeout: const Duration(seconds: 30),
      );
      final history = HistoryService(
        gateway: () => gateway,
        endpoints: endpoint,
        timeout: const Duration(seconds: 30),
      );

      try {
        if (selected.contains('tron')) {
          await _runTron(
            crypto: crypto,
            paired: paired,
            transfers: transfers,
            broadcaster: broadcaster,
            rest: restTransport,
            history: history,
          );
        }
        if (selected.contains('solana')) {
          await _runSolana(
            crypto: crypto,
            paired: paired,
            transfers: transfers,
            broadcaster: broadcaster,
            json: jsonTransport,
            history: history,
          );
        }
      } finally {
        history.close();
        gateway.close();
        jsonTransport.close();
        restTransport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _runTron({
  required CoreCrypto crypto,
  required WatchWallet paired,
  required LocalTransferService transfers,
  required BroadcastService broadcaster,
  required HttpRestTransport rest,
  required HistoryService history,
}) async {
  final signer = paired.addresses.tron;
  final rpc = TronRpc(baseUrl: _tronRpcUrl, transport: rest);
  final balances = await rpc.getAccountBalances(
    signer,
    tokenContract: _testUsdt,
  );
  expect(
    balances.trx,
    greaterThan(BigInt.from(3000000)),
    reason: 'Nile account needs TRX for native and TRC-20 fees',
  );
  expect(
    balances.token ?? BigInt.zero,
    greaterThanOrEqualTo(BigInt.from(1000000)),
    reason: 'Nile account needs 1 test USDT',
  );

  final nativeDraft = TransferDraft(
    symbol: 'TRX',
    networkLabel: 'TRON Nile',
    chain: Chain.tron,
    recipient: _tronRecipient,
    amount: Amount.parse('0.1', 6, symbol: 'TRX'),
    feeTier: 1,
  );
  final tokenDraft = TransferDraft(
    symbol: 'USDT',
    networkLabel: 'TRON Nile',
    chain: Chain.tron,
    recipient: _tronRecipient,
    amount: Amount.parse('1', 6, symbol: 'USDT'),
    feeTier: 1,
    tokenContract: _testUsdt,
  );
  final native = await _sendTron(
    crypto: crypto,
    transfers: transfers,
    broadcaster: broadcaster,
    rest: rest,
    signer: signer,
    draft: nativeDraft,
  );
  final token = await _sendTron(
    crypto: crypto,
    transfers: transfers,
    broadcaster: broadcaster,
    rest: rest,
    signer: signer,
    draft: tokenDraft,
  );
  final records = await _waitForHistory(
    history,
    Coin.tron,
    signer,
    hashes: {native.toLowerCase(), token.toLowerCase()},
    label: 'TRON Nile',
  );
  expect(
    records.where(
      (record) => record.hash.toLowerCase() == native.toLowerCase(),
    ),
    isNotEmpty,
  );
  final tokenRecord = records.where(
    (record) =>
        record.hash.toLowerCase() == token.toLowerCase() &&
        record.assetContract == _testUsdt,
  );
  expect(tokenRecord, isNotEmpty);
  expect(tokenRecord.first.status, ChainTxStatus.confirmed);
  // ignore: avoid_print
  print('TRON_AIRGAP_ACCOUNT=$signer');
  // ignore: avoid_print
  print('TRON_AIRGAP_NATIVE_TX=$native');
  // ignore: avoid_print
  print('TRON_AIRGAP_USDT_TX=$token');
  // ignore: avoid_print
  print('TRON_AIRGAP_HISTORY=confirmed');
}

Future<String> _sendTron({
  required CoreCrypto crypto,
  required LocalTransferService transfers,
  required BroadcastService broadcaster,
  required HttpRestTransport rest,
  required String signer,
  required TransferDraft draft,
}) async {
  final prepared = await transfers.prepareTron(
    draft: draft,
    from: signer,
    expectedNetworkIdentity: tronNile.networkIdentity,
  );
  final request = buildSignRequest(
    draft: draft,
    walletId: _walletId,
    fromAddress: signer,
    networkLabel: 'TRON Nile',
    preparedRawTx: prepared.rawTx,
  );
  expect(request.rawTx, orderedEquals(prepared.rawTx));
  final decoded = _roundTrip(request, request.reqId) as SignRequest;
  final parsed = parseUnsignedTransfer(Chain.tron, decoded.rawTx);
  expect(parsed.to, draft.recipient);
  expect(parsed.amountRaw, draft.amount.raw);
  expect(parsed.tokenContract, draft.tokenContract);

  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.tron,
    signingInput: decoded.rawTx,
  );
  final result = SignResult(
    reqId: decoded.reqId,
    walletId: decoded.walletId,
    coin: decoded.coin,
    signedTx: signed.signedTx,
    signer: signer,
    txHash: signed.txHash,
  );
  final verifiedPayload = _roundTrip(result, decoded.reqId);
  final verified = await verifySignResultCryptographically(
    verifiedPayload.encode(),
    expected: decoded,
    expectedSigner: signer,
  );
  final outcome = await broadcaster.broadcast(
    Chain.tron,
    verified.signedTx,
    expectedTxHash: verified.txHash,
  );
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  final hash = outcome.txHash!;
  expect(hash, verified.txHash);
  await _waitForTronConfirmation(rest, hash);
  return hash;
}

Future<void> _runSolana({
  required CoreCrypto crypto,
  required WatchWallet paired,
  required LocalTransferService transfers,
  required BroadcastService broadcaster,
  required HttpJsonRpcTransport json,
  required HistoryService history,
}) async {
  final signer = paired.addresses.solana;
  final rpc = SolanaRpc(url: _solanaRpcUrl, transport: json);
  final balances = await Future.wait<BigInt>([
    rpc.getBalance(signer),
    rpc.getTokenBalance(signer, usdcSolanaDevnetToken.contract),
  ]);
  expect(
    balances[0],
    greaterThan(BigInt.from(3000000)),
    reason: 'Devnet account needs SOL for fees and possible ATA rent',
  );
  expect(
    balances[1],
    greaterThanOrEqualTo(BigInt.from(1000000)),
    reason: 'Devnet account needs 1 Circle USDC',
  );

  final nativeDraft = TransferDraft(
    symbol: 'SOL',
    networkLabel: 'Solana Devnet',
    chain: Chain.solana,
    recipient: _solanaRecipient,
    amount: Amount.parse('0.00001', 9, symbol: 'SOL'),
    feeTier: 1,
  );
  final tokenDraft = TransferDraft(
    symbol: 'USDC',
    networkLabel: 'Solana Devnet',
    chain: Chain.solana,
    recipient: _solanaRecipient,
    amount: Amount.parse('1', 6, symbol: 'USDC'),
    feeTier: 1,
    tokenContract: usdcSolanaDevnetToken.contract,
  );
  final native = await _sendSolana(
    crypto: crypto,
    transfers: transfers,
    broadcaster: broadcaster,
    rpc: rpc,
    signer: signer,
    draft: nativeDraft,
  );
  final token = await _sendSolana(
    crypto: crypto,
    transfers: transfers,
    broadcaster: broadcaster,
    rpc: rpc,
    signer: signer,
    draft: tokenDraft,
  );
  final records = await _waitForHistory(
    history,
    Coin.solana,
    signer,
    hashes: {native, token},
    label: 'Solana Devnet',
  );
  expect(records.where((record) => record.hash == native), isNotEmpty);
  final tokenRecord = records.where(
    (record) =>
        record.hash == token &&
        record.assetContract == usdcSolanaDevnetToken.contract,
  );
  expect(tokenRecord, isNotEmpty);
  expect(tokenRecord.first.status, ChainTxStatus.confirmed);
  // ignore: avoid_print
  print('SOLANA_AIRGAP_ACCOUNT=$signer');
  // ignore: avoid_print
  print('SOLANA_AIRGAP_NATIVE_TX=$native');
  // ignore: avoid_print
  print('SOLANA_AIRGAP_USDC_TX=$token');
  // ignore: avoid_print
  print('SOLANA_AIRGAP_HISTORY=confirmed');
}

Future<String> _sendSolana({
  required CoreCrypto crypto,
  required LocalTransferService transfers,
  required BroadcastService broadcaster,
  required SolanaRpc rpc,
  required String signer,
  required TransferDraft draft,
}) async {
  final prepared = await transfers.prepareSolana(
    draft: draft,
    from: signer,
    expectedNetworkIdentity: solanaDevnet.networkIdentity,
  );
  final request = buildSignRequest(
    draft: draft,
    walletId: _walletId,
    fromAddress: signer,
    networkLabel: 'Solana Devnet',
    preparedRawTx: prepared.message,
  );
  expect(request.rawTx, orderedEquals(prepared.message));
  final decoded = _roundTrip(request, request.reqId) as SignRequest;
  final parsed = parseUnsignedTransfer(Chain.solana, decoded.rawTx);
  expect(parsed.to, draft.recipient);
  expect(parsed.amountRaw, draft.amount.raw);
  expect(parsed.tokenContract, draft.tokenContract);

  final signed = await crypto.signTransaction(
    walletId: _walletId,
    coin: Coin.solana,
    signingInput: decoded.rawTx,
  );
  final result = SignResult(
    reqId: decoded.reqId,
    walletId: decoded.walletId,
    coin: decoded.coin,
    signedTx: signed.signedTx,
    signer: signer,
    txHash: signed.txHash,
  );
  final verifiedPayload = _roundTrip(result, decoded.reqId);
  final verified = await verifySignResultCryptographically(
    verifiedPayload.encode(),
    expected: decoded,
    expectedSigner: signer,
  );
  final outcome = await broadcaster.broadcast(
    Chain.solana,
    verified.signedTx,
    expectedTxHash: verified.txHash,
  );
  expect(outcome.status, BroadcastStatus.ok, reason: outcome.message);
  final hash = outcome.txHash!;
  expect(hash, verified.txHash);
  await _waitForSolanaConfirmation(rpc, hash);
  return hash;
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

Future<void> _waitForTronConfirmation(
  HttpRestTransport rest,
  String hash,
) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    final result = await rest.postJson(
      '$_tronRpcUrl/wallet/gettransactioninfobyid',
      {'value': hash},
    );
    if (result is Map && result['id'] == hash) {
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

Future<void> _waitForSolanaConfirmation(SolanaRpc rpc, String hash) async {
  for (var attempt = 0; attempt < 45; attempt++) {
    final status = await rpc.signatureResult(hash);
    if (status?.failed == true) {
      fail('Solana transaction was included but failed: $hash');
    }
    if (status?.confirmationStatus == 'confirmed' ||
        status?.confirmationStatus == 'finalized') {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException('Solana transaction not confirmed: $hash');
}

Future<List<ChainTxRecord>> _waitForHistory(
  HistoryService history,
  Coin coin,
  String address, {
  required Set<String> hashes,
  required String label,
}) async {
  for (var attempt = 0; attempt < 72; attempt++) {
    final result = await history.fetch(coin, address, limit: 100);
    if (result.status == HistoryStatus.ok) {
      final seen = result.records.map((record) => record.hash).toSet();
      if (seen.containsAll(hashes)) return result.records;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  throw TimeoutException('$label history did not index both air-gap hashes');
}
