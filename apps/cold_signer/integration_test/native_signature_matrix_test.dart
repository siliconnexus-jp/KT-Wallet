import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _walletId = 'standalone-signer-matrix-v1';
const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
const _evmRecipient = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _evmToken = '0x1111111111111111111111111111111111111111';
const _tronRecipient = 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR';
const _tronUsdt = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _solanaRecipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _solanaSource = 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5';
const _solanaMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _solanaBlockhash = 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb';

const _evmNetworks =
    <({Chain chain, Coin coin, int slip44, int chainId, String symbol})>[
      (
        chain: Chain.ethereum,
        coin: Coin.eth,
        slip44: 60,
        chainId: 11155111,
        symbol: 'ETH',
      ),
      (
        chain: Chain.polygon,
        coin: Coin.polygon,
        slip44: 966,
        chainId: 80002,
        symbol: 'POL',
      ),
      (
        chain: Chain.base,
        coin: Coin.base,
        slip44: 8453,
        chainId: 84532,
        symbol: 'ETH',
      ),
      (
        chain: Chain.arbitrum,
        coin: Coin.arbitrum,
        slip44: 42161,
        chainId: 421614,
        symbol: 'ETH',
      ),
      (
        chain: Chain.avalanche,
        coin: Coin.avalanche,
        slip44: 9000,
        chainId: 43113,
        symbol: 'AVAX',
      ),
      (
        chain: Chain.bnb,
        coin: Coin.bnb,
        slip44: 714,
        chainId: 97,
        symbol: 'BNB',
      ),
    ];

String _addressFor(ChainAddresses addresses, Chain chain) => switch (chain) {
  Chain.ethereum => addresses.eth,
  Chain.polygon => addresses.polygon,
  Chain.base => addresses.base,
  Chain.arbitrum => addresses.arbitrum,
  Chain.avalanche => addresses.avalanche,
  Chain.bnb => addresses.bnb,
  Chain.tron => addresses.tron,
  Chain.solana => addresses.solana,
};

Uint8List _requestId(int operation) => Uint8List.fromList([
  0x4b,
  0x54,
  0x43,
  0x53,
  0x00,
  0x00,
  operation >> 8,
  operation & 0xff,
]);

SignRequest _request({
  required int operation,
  required int coin,
  required Uint8List rawTx,
  int? chainId,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return SignRequest(
    reqId: _requestId(operation),
    walletId: _walletId,
    coin: coin,
    chainId: chainId,
    rawTx: rawTx,
    summary: const {0: 'untrusted-test-display-hint'},
    createdAt: now,
    expiresAt: now + 600,
  );
}

Uint8List _frameRoundTrip(AirgapPayload payload) {
  final aggregator = FrameAggregator();
  final frames = Fragmenter(chunkSize: 120).fragment(
    payload.encode(),
    reqId: switch (payload) {
      SignRequest(:final reqId) => reqId,
      SignResult(:final reqId) => reqId,
      _ => throw StateError('matrix only accepts transaction payloads'),
    },
  );
  for (final frame in frames) {
    final qr = base64Url.encode(frame.encode());
    aggregator.addFrame(AirgapFrame.decode(base64Url.decode(qr)));
  }
  expect(aggregator.state, AggregatorState.done);
  return aggregator.payload!;
}

SignRequest _decodeRequest(SignRequest request) {
  final decoded = AirgapPayload.decode(_frameRoundTrip(request));
  expect(decoded, isA<SignRequest>());
  return decoded as SignRequest;
}

Future<Map<String, String>> _signAndVerify({
  required MethodChannelCoreCrypto crypto,
  required SignRequest request,
  required Coin coin,
  required Chain chain,
  required String expectedSigner,
}) async {
  final decoded = _decodeRequest(request);
  final parsed = parseUnsignedTransfer(chain, decoded.rawTx);
  if (parsed.networkId == null) {
    expect(decoded.chainId, isNull);
  } else {
    expect(parsed.networkId, BigInt.from(decoded.chainId!));
  }

  final native = await crypto.signTransaction(
    walletId: _walletId,
    coin: coin,
    signingInput: decoded.rawTx,
  );
  final result = SignResult(
    reqId: decoded.reqId,
    walletId: decoded.walletId,
    coin: decoded.coin,
    signedTx: native.signedTx,
    signer: expectedSigner,
    txHash: native.txHash,
  );
  final returned = AirgapPayload.decode(_frameRoundTrip(result));
  expect(returned, isA<SignResult>());
  final signed = returned as SignResult;
  expect(signed.reqIdHex, decoded.reqIdHex);
  expect(signed.walletId, decoded.walletId);
  expect(signed.coin, decoded.coin);

  final verified = await verifySignedTransaction(
    chain: chain,
    unsignedTx: decoded.rawTx,
    signedTx: signed.signedTx,
    claimedSigner: signed.signer,
  );
  expect(Addresses.equal(chain, verified.signer, expectedSigner), isTrue);
  expect(verified.txHash, native.txHash);
  expect(signed.txHash, native.txHash);
  return {
    'operation': parsed.operation.name,
    'txHash': verified.txHash,
    'signer': verified.signer,
  };
}

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'standalone iOS bundle signs and verifies all eight chains',
    () async {
      expect(
        _mnemonic,
        isNotEmpty,
        reason:
            'pass the ignored E2E credential file with --dart-define-from-file',
      );
      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: _mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final evidence = <String, Map<String, String>>{};
      var operation = 0;

      for (final network in _evmNetworks) {
        final signer = _addressFor(addresses, network.chain);
        for (final token in [false, true]) {
          operation++;
          final amount = Amount.parse(
            token ? '1' : '0.000001',
            token ? 6 : 18,
            symbol: token ? 'TEST' : network.symbol,
          );
          final intent = TransferIntent(
            chain: network.chain,
            operation: token
                ? TxOperation.tokenTransfer
                : TxOperation.nativeTransfer,
            from: signer,
            to: _evmRecipient,
            amount: amount,
            tokenContract: token ? _evmToken : null,
            tokenSymbol: token ? 'TEST' : null,
          );
          final raw = Eip1559Tx.forTransfer(
            intent,
            chainId: BigInt.from(network.chainId),
            nonce: BigInt.from(token ? 2 : 1),
            maxPriorityFeePerGas: BigInt.from(1000000000),
            maxFeePerGas: BigInt.from(2000000000),
            gasLimit: BigInt.from(token ? 65000 : 21000),
          ).encodeUnsigned();
          final request = _request(
            operation: operation,
            coin: network.slip44,
            rawTx: raw,
            chainId: network.chainId,
          );
          evidence['${network.chain.name}-${token ? 'token' : 'native'}'] =
              await _signAndVerify(
                crypto: crypto,
                request: request,
                coin: network.coin,
                chain: network.chain,
                expectedSigner: signer,
              );
        }
      }

      for (final token in [false, true]) {
        operation++;
        final amount = Amount.parse(
          token ? '1' : '0.000001',
          6,
          symbol: token ? 'USDT' : 'TRX',
        );
        final intent = TransferIntent(
          chain: Chain.tron,
          operation: token
              ? TxOperation.tokenTransfer
              : TxOperation.nativeTransfer,
          from: addresses.tron,
          to: _tronRecipient,
          amount: amount,
          tokenContract: token ? _tronUsdt : null,
          tokenSymbol: token ? 'USDT' : null,
        );
        final raw = TronRawTx.forTransfer(
          intent,
          refBlockBytes: Uint8List.fromList(const [0x12, 0x34]),
          refBlockHash: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
          expiration: 1900000060000,
          timestamp: 1900000000000,
          feeLimit: token ? 50000000 : null,
        ).encodeRawData();
        final request = _request(operation: operation, coin: 195, rawTx: raw);
        evidence['tron-${token ? 'token' : 'native'}'] = await _signAndVerify(
          crypto: crypto,
          request: request,
          coin: Coin.tron,
          chain: Chain.tron,
          expectedSigner: addresses.tron,
        );
      }

      final solanaMessages = <Uint8List>[
        SolanaMessage.systemTransfer(
          from: addresses.solana,
          to: _solanaRecipient,
          lamports: BigInt.from(1000),
          recentBlockhash: _solanaBlockhash,
        ).serialize(),
        SolanaMessage.splTransferChecked(
          source: _solanaSource,
          destination: SolanaMessage.associatedTokenAddress(
            owner: _solanaRecipient,
            mint: _solanaMint,
          ),
          owner: addresses.solana,
          recipientOwner: _solanaRecipient,
          mint: _solanaMint,
          amount: BigInt.from(1000000),
          decimals: 6,
          recentBlockhash: _solanaBlockhash,
          createDestination: true,
        ).serialize(),
      ];
      for (var index = 0; index < solanaMessages.length; index++) {
        operation++;
        final request = _request(
          operation: operation,
          coin: 501,
          rawTx: solanaMessages[index],
        );
        evidence['solana-${index == 0 ? 'native' : 'token-ata'}'] =
            await _signAndVerify(
              crypto: crypto,
              request: request,
              coin: Coin.solana,
              chain: Chain.solana,
              expectedSigner: addresses.solana,
            );
      }

      expect(evidence, hasLength(16));
      // Only public transaction hashes and derived addresses are emitted.
      // ignore: avoid_print
      print('STANDALONE_COLD_SIGNER_MATRIX=${jsonEncode(evidence)}');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
