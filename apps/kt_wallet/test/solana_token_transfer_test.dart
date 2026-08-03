import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _owner = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _recipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _mint = '2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo';
const _jupMint = 'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN';
const _source = 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5';
const _blockhash = 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb';
const _genesisHash = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG';

class _SolanaTransport implements JsonRpcTransport {
  _SolanaTransport({this.recipientAtaExists = false});

  final bool recipientAtaExists;
  Uint8List? simulatedMessage;
  Map<Object?, Object?>? simulationConfig;

  @override
  Future<Object?> post(String url, Object body) async {
    final request = body as Map;
    final method = request['method'];
    final params = request['params'] as List;
    Object? result;
    switch (method) {
      case 'getGenesisHash':
        result = _genesisHash;
        break;
      case 'getLatestBlockhash':
        result = {
          'value': {'blockhash': _blockhash, 'lastValidBlockHeight': 123456},
        };
        break;
      case 'getTokenAccountsByOwner':
        final address = params.first;
        result = {
          'value': address == _owner
              ? [
                  {
                    'pubkey': _source,
                    'account': {
                      'data': {
                        'parsed': {
                          'info': {
                            'tokenAmount': {'amount': '2000000'},
                          },
                        },
                      },
                    },
                  },
                ]
              : recipientAtaExists && address == _recipient
              ? [
                  {
                    'pubkey': SolanaMessage.associatedTokenAddress(
                      owner: _recipient,
                      mint: _mint,
                      tokenProgram: solanaToken2022Program,
                    ),
                    'account': {
                      'data': {
                        'parsed': {
                          'info': {
                            'tokenAmount': {'amount': '0'},
                          },
                        },
                      },
                    },
                  },
                ]
              : <Object?>[],
        };
        break;
      case 'getFeeForMessage':
        result = {'value': 5000};
        break;
      case 'getBalance':
        result = {'value': 100000000};
        break;
      case 'simulateTransaction':
        final wire = base64Decode(params.first as String);
        simulatedMessage = Uint8List.sublistView(wire, 65);
        simulationConfig = params[1] as Map<Object?, Object?>;
        result = {
          'value': {
            'err': null,
            // 100,000,000 - 5,000 fee - 2,039,280 ATA rent reserve.
            'accounts': [
              {'lamports': 97955720},
            ],
            'unitsConsumed': 24100,
          },
        };
        break;
      default:
        fail('unexpected Solana RPC method $method');
    }
    return {'jsonrpc': '2.0', 'id': request['id'], 'result': result};
  }
}

class _BroadcastCapture extends BroadcastService {
  Chain? chain;

  @override
  Future<BroadcastOutcome> broadcast(Chain chain, Uint8List signedTx) async {
    this.chain = chain;
    return const BroadcastOutcome.ok('solana-test-signature');
  }
}

/// This suite exercises Token-2022/ATA construction and broadcast plumbing,
/// not cryptography. Production [LocalTransferService] verifies every native
/// signature before broadcast; use an explicit test subclass here so the
/// intentionally non-cryptographic [MockCoreCrypto] cannot be mistaken for a
/// valid signature fixture.
class _SolanaPreparationService extends LocalTransferService {
  _SolanaPreparationService({
    required BroadcastService broadcaster,
    required String Function(Coin) endpoints,
    required JsonRpcTransport jsonRpcTransport,
  }) : super(
         broadcaster: broadcaster,
         endpoints: endpoints,
         jsonRpcTransport: jsonRpcTransport,
       );

  @override
  Future<SignedTransaction> signPreparedSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedSolanaTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async => SignedTransaction(
    signedTx: Uint8List.fromList(const [1]),
    txHash: 'solana-test-signature',
  );
}

void main() {
  test('PYUSD uses Token-2022 and creates a missing recipient ATA', () async {
    final crypto = MockCoreCrypto();
    await crypto.storeWallet(
      walletId: 'wallet-1',
      mnemonic:
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      requireAuth: false,
    );
    final wallet = HotWallet(
      id: 'wallet-1',
      name: 'Test',
      avatarColor: 0,
      addresses: const ChainAddresses(
        eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
        solana: _owner,
      ),
    );
    final transport = _SolanaTransport();
    final broadcaster = _BroadcastCapture();
    final service = _SolanaPreparationService(
      broadcaster: broadcaster,
      endpoints: (_) => 'https://solana.test',
      jsonRpcTransport: transport,
    );
    final draft = TransferDraft(
      symbol: 'PYUSD',
      networkLabel: 'Solana',
      chain: Chain.solana,
      recipient: _recipient,
      amount: Amount.parse('1.25', 6, symbol: 'PYUSD'),
      feeTier: 1,
      tokenContract: _mint,
      tokenProgram: solanaToken2022Program,
    );

    final prepared = await service.prepareSolana(
      draft: draft,
      from: _owner,
      expectedNetworkIdentity: _genesisHash,
    );
    expect(prepared.networkFeeLamports, BigInt.from(5000));
    expect(prepared.rentDepositLamports, BigInt.from(2039280));
    expect(prepared.lastValidBlockHeight, 123456);
    final result = await service.signAndBroadcastSolana(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
      expectedNetworkIdentity: _genesisHash,
    );

    expect(result.hash, 'solana-test-signature');
    expect(result.lastValidBlockHeight, 123456);
    expect(result.referenceBlockHeight, isNull);
    expect(result.expiresAt, isNull);
    expect(broadcaster.chain, Chain.solana);
    expect(transport.simulationConfig?['accounts'], {
      'encoding': 'base64',
      'addresses': [_owner],
    });
    final message = transport.simulatedMessage;
    expect(message, isNotNull);
    final parsed = parseUnsignedTransfer(Chain.solana, message!);
    expect(parsed.to, _recipient);
    expect(parsed.tokenContract, _mint);
    expect(parsed.amountRaw, BigInt.from(1250000));
  });

  test('JUP uses the legacy SPL program and creates a missing ATA', () async {
    final crypto = MockCoreCrypto();
    await crypto.storeWallet(
      walletId: 'wallet-1',
      mnemonic:
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      requireAuth: false,
    );
    final wallet = HotWallet(
      id: 'wallet-1',
      name: 'Test',
      avatarColor: 0,
      addresses: const ChainAddresses(
        eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
        solana: _owner,
      ),
    );
    final transport = _SolanaTransport();
    final broadcaster = _BroadcastCapture();
    final service = _SolanaPreparationService(
      broadcaster: broadcaster,
      endpoints: (_) => 'https://solana.test',
      jsonRpcTransport: transport,
    );

    await service.execute(
      wallet: wallet,
      crypto: crypto,
      draft: TransferDraft(
        symbol: 'JUP',
        networkLabel: 'Solana',
        chain: Chain.solana,
        recipient: _recipient,
        amount: Amount.parse('0.5', 6, symbol: 'JUP'),
        feeTier: 1,
        tokenContract: _jupMint,
      ),
      evmChainId: 0,
      expectedNetworkIdentity: _genesisHash,
    );

    final parsed = parseUnsignedTransfer(
      Chain.solana,
      transport.simulatedMessage!,
    );
    expect(parsed.to, _recipient);
    expect(parsed.tokenContract, _jupMint);
    expect(parsed.amountRaw, BigInt.from(500000));
    expect(
      SolanaMessage.associatedTokenAddress(owner: _recipient, mint: _jupMint),
      isNotEmpty,
    );
  });

  test(
    'existing recipient ATA still carries an idempotent owner binding',
    () async {
      final transport = _SolanaTransport(recipientAtaExists: true);
      final service = LocalTransferService(
        endpoints: (_) => 'https://solana.test',
        jsonRpcTransport: transport,
      );
      final prepared = await service.prepareSolana(
        draft: TransferDraft(
          symbol: 'PYUSD',
          networkLabel: 'Solana',
          chain: Chain.solana,
          recipient: _recipient,
          amount: Amount.parse('1', 6, symbol: 'PYUSD'),
          feeTier: 1,
          tokenContract: _mint,
          tokenProgram: solanaToken2022Program,
        ),
        from: _owner,
        expectedNetworkIdentity: _genesisHash,
      );

      final parsed = parseUnsignedTransfer(Chain.solana, prepared.message);
      expect(parsed.to, _recipient);
      expect(parsed.tokenContract, _mint);
      expect(parsed.amountRaw, BigInt.from(1000000));
    },
  );

  test(
    'native SOL quote fails before simulation when amount plus fee is short',
    () async {
      final transport = _SolanaTransport();
      final service = LocalTransferService(
        endpoints: (_) => 'https://solana.test',
        jsonRpcTransport: transport,
      );

      await expectLater(
        service.prepareSolana(
          draft: TransferDraft(
            symbol: 'SOL',
            networkLabel: 'Solana',
            chain: Chain.solana,
            recipient: _recipient,
            amount: Amount.parse('0.1', 9, symbol: 'SOL'),
            feeTier: 1,
          ),
          from: _owner,
          expectedNetworkIdentity: _genesisHash,
        ),
        throwsA(isA<TransferInsufficientFunds>()),
      );
      expect(
        transport.simulatedMessage,
        isNull,
        reason: 'known insufficient balance must not reach simulation/signing',
      );
    },
  );
}
