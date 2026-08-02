import 'support/e2e_credential_batch.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

const _walletId = 'cold-signer-native-matrix-v1';
const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
const _evmRecipient = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _evmToken = '0x1111111111111111111111111111111111111111';
const _tronRecipient = 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR';
const _solanaRecipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _solanaSource = 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5';
const _solanaMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _solanaBlockhash = 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb';

const _evmNetworks =
    <({Chain chain, Coin coin, int chainId, String label, String symbol})>[
      (
        chain: Chain.ethereum,
        coin: Coin.eth,
        chainId: 11155111,
        label: 'Sepolia',
        symbol: 'ETH',
      ),
      (
        chain: Chain.polygon,
        coin: Coin.polygon,
        chainId: 80002,
        label: 'Polygon Amoy',
        symbol: 'POL',
      ),
      (
        chain: Chain.base,
        coin: Coin.base,
        chainId: 84532,
        label: 'Base Sepolia',
        symbol: 'ETH',
      ),
      (
        chain: Chain.arbitrum,
        coin: Coin.arbitrum,
        chainId: 421614,
        label: 'Arbitrum Sepolia',
        symbol: 'ETH',
      ),
      (
        chain: Chain.avalanche,
        coin: Coin.avalanche,
        chainId: 43113,
        label: 'Avalanche Fuji',
        symbol: 'AVAX',
      ),
      (
        chain: Chain.bnb,
        coin: Coin.bnb,
        chainId: 97,
        label: 'BNB Smart Chain Testnet',
        symbol: 'BNB',
      ),
    ];

Uint8List _assembledPayload(AirgapPayload payload, Uint8List requestId) {
  final aggregator = FrameAggregator();
  final frames = encodeQrFrames(payload, reqId: requestId);
  expect(frames, isNotEmpty);
  for (final encoded in frames) {
    aggregator.addFrame(AirgapFrame.decode(base64Url.decode(encoded)));
  }
  expect(aggregator.state, AggregatorState.done);
  return aggregator.payload!;
}

SignRequest _requestRoundTrip(SignRequest request) {
  final payload = _assembledPayload(request, request.reqId);
  final decoded = AirgapPayload.decode(payload);
  expect(decoded, isA<SignRequest>());
  return decoded as SignRequest;
}

Future<Map<String, String>> _signRoundTrip({
  required MethodChannelCoreCrypto crypto,
  required SignRequest request,
  required Coin coin,
  required String signer,
}) async {
  final decodedRequest = _requestRoundTrip(request);
  final parsed = parseUnsignedTransfer(
    chainForCoin(decodedRequest.coin),
    decodedRequest.rawTx,
  );
  final native = await crypto.signTransaction(
    walletId: _walletId,
    coin: coin,
    signingInput: decodedRequest.rawTx,
  );
  final result = SignResult(
    reqId: decodedRequest.reqId,
    walletId: decodedRequest.walletId,
    coin: decodedRequest.coin,
    signedTx: native.signedTx,
    signer: signer,
    txHash: native.txHash,
  );
  final resultPayload = _assembledPayload(result, decodedRequest.reqId);
  final verified = await verifySignResultCryptographically(
    resultPayload,
    expected: decodedRequest,
    expectedSigner: signer,
  );
  expect(verified.txHash, native.txHash);
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
    'native Wallet Core closes the air-gap loop for all eight chains',
    () async {
      expect(
        _mnemonic,
        isNotEmpty,
        reason:
            'pass integration_test/.sepolia-e2e.json using '
            '--dart-define-from-file',
      );
      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: _mnemonic,
        requireAuth: false,
      );
      addTearDown(() => crypto.deleteWallet(_walletId));
      final addresses = await crypto.deriveAddresses(_walletId);
      final evidence = <String, Map<String, String>>{};

      for (final network in _evmNetworks) {
        final signer = addressForChain(addresses, network.chain);
        for (final token in [false, true]) {
          final draft = TransferDraft(
            symbol: token ? 'TEST' : network.symbol,
            networkLabel: network.label,
            chain: network.chain,
            recipient: _evmRecipient,
            amount: Amount.parse(
              token ? '1' : '0.000001',
              token ? 6 : 18,
              symbol: token ? 'TEST' : network.symbol,
            ),
            feeTier: 1,
            tokenContract: token ? _evmToken : null,
          );
          final request = buildSignRequest(
            draft: draft,
            walletId: _walletId,
            fromAddress: signer,
            nonce: BigInt.from(token ? 2 : 1),
            maxPriorityFeePerGas: BigInt.from(1000000000),
            maxFeePerGas: BigInt.from(2000000000),
            gasLimit: BigInt.from(token ? 65000 : 21000),
            evmChainId: network.chainId,
            networkLabel: network.label,
          );
          expect(request.chainId, network.chainId);
          evidence['${network.chain.name}-${token ? 'token' : 'native'}'] =
              await _signRoundTrip(
                crypto: crypto,
                request: request,
                coin: network.coin,
                signer: signer,
              );
        }
      }

      for (final token in [false, true]) {
        final draft = TransferDraft(
          symbol: token ? 'USDT' : 'TRX',
          networkLabel: 'TRON Nile',
          chain: Chain.tron,
          recipient: _tronRecipient,
          amount: Amount.parse(
            token ? '1' : '0.000001',
            6,
            symbol: token ? 'USDT' : 'TRX',
          ),
          feeTier: 1,
          tokenContract: token ? usdtTronContract : null,
        );
        final intent = TransferIntent(
          chain: Chain.tron,
          operation: draft.operation,
          from: addresses.tron,
          to: draft.recipient,
          amount: draft.amount,
          tokenContract: draft.tokenContract,
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
        final request = buildSignRequest(
          draft: draft,
          walletId: _walletId,
          fromAddress: addresses.tron,
          networkLabel: 'TRON Nile',
          preparedRawTx: raw,
        );
        evidence['tron-${token ? 'token' : 'native'}'] = await _signRoundTrip(
          crypto: crypto,
          request: request,
          coin: Coin.tron,
          signer: addresses.tron,
        );
      }

      final solanaDrafts = <({TransferDraft draft, Uint8List message})>[
        (
          draft: TransferDraft(
            symbol: 'SOL',
            networkLabel: 'Solana Devnet',
            chain: Chain.solana,
            recipient: _solanaRecipient,
            amount: Amount.parse('0.000001', 9, symbol: 'SOL'),
            feeTier: 1,
          ),
          message: SolanaMessage.systemTransfer(
            from: addresses.solana,
            to: _solanaRecipient,
            lamports: BigInt.from(1000),
            recentBlockhash: _solanaBlockhash,
          ).serialize(),
        ),
        (
          draft: TransferDraft(
            symbol: 'USDC',
            networkLabel: 'Solana Devnet',
            chain: Chain.solana,
            recipient: _solanaRecipient,
            amount: Amount.parse('1', 6, symbol: 'USDC'),
            feeTier: 1,
            tokenContract: _solanaMint,
          ),
          message: SolanaMessage.splTransferChecked(
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
        ),
      ];
      for (var index = 0; index < solanaDrafts.length; index++) {
        final entry = solanaDrafts[index];
        final request = buildSignRequest(
          draft: entry.draft,
          walletId: _walletId,
          fromAddress: addresses.solana,
          networkLabel: 'Solana Devnet',
          preparedRawTx: entry.message,
        );
        evidence['solana-${index == 0 ? 'native' : 'token-ata'}'] =
            await _signRoundTrip(
              crypto: crypto,
              request: request,
              coin: Coin.solana,
              signer: addresses.solana,
            );
      }

      expect(evidence, hasLength(16));
      // Public evidence only: transaction hashes and derived addresses. The
      // mnemonic never appears in logs or the test report.
      // ignore: avoid_print
      print('COLD_SIGNER_NATIVE_MATRIX=${jsonEncode(evidence)}');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
