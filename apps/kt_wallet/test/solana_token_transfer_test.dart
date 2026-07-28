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

class _SolanaTransport implements JsonRpcTransport {
  Uint8List? simulatedMessage;

  @override
  Future<Object?> post(String url, Object body) async {
    final request = body as Map;
    final method = request['method'];
    final params = request['params'] as List;
    Object? result;
    switch (method) {
      case 'getLatestBlockhash':
        result = {
          'value': {'blockhash': _blockhash},
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
        result = {
          'value': {'err': null},
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
    final service = LocalTransferService(
      broadcaster: broadcaster,
      endpoints: (_) => 'https://solana.test',
      jsonRpcTransport: transport,
    );
    final draft = TransferDraft(
      symbol: 'PYUSD',
      networkLabel: 'Solana',
      chain: Chain.solana,
      decimals: 6,
      recipient: _recipient,
      amount: Amount.parse('1.25', 6, symbol: 'PYUSD'),
      feeTier: 1,
      tokenContract: _mint,
      tokenProgram: solanaToken2022Program,
    );

    final hash = await service.execute(
      wallet: wallet,
      crypto: crypto,
      draft: draft,
      evmChainId: 0,
    );

    expect(hash, 'solana-test-signature');
    expect(broadcaster.chain, Chain.solana);
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
    final service = LocalTransferService(
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
        decimals: 6,
        recipient: _recipient,
        amount: Amount.parse('0.5', 6, symbol: 'JUP'),
        feeTier: 1,
        tokenContract: _jupMint,
      ),
      evmChainId: 0,
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
}
