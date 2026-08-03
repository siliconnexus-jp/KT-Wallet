import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart'
    show ChainAddresses, Coin, CoreCrypto, SignedTransaction;
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/network_identity.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _JsonTransport implements JsonRpcTransport {
  _JsonTransport(this.results);

  final Map<String, Object?> results;
  final List<String> methods = [];

  @override
  Future<Object?> post(String url, Object body) async {
    final request = body as Map;
    final method = request['method'] as String;
    methods.add(method);
    return {'jsonrpc': '2.0', 'id': request['id'], 'result': results[method]};
  }
}

class _RestTransport implements RestTransport {
  _RestTransport(this.blockId);

  final String blockId;
  final List<String> urls = [];

  @override
  Future<Object?> getJson(String url) async => throw UnimplementedError();

  @override
  Future<Object?> postJson(String url, Object body) async {
    urls.add(url);
    return {'blockID': blockId};
  }
}

class _TronTransferRest implements RestTransport {
  _TronTransferRest({
    required this.genesisBlockId,
    required this.blockId,
    required this.blockNumber,
    required this.blockTimestamp,
  });

  final String genesisBlockId;
  final String blockId;
  final int blockNumber;
  final int blockTimestamp;

  @override
  Future<Object?> getJson(String url) async {
    if (!url.contains('/v1/accounts/')) {
      throw StateError('unexpected TRON request: $url');
    }
    if (url.endsWith('/TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G')) {
      return {
        'data': [
          {'balance': 10000000},
        ],
      };
    }
    return {
      'data': [<String, Object?>{}],
    };
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    if (url.endsWith('/wallet/getblockbynum')) {
      return {'blockID': genesisBlockId};
    }
    if (url.endsWith('/wallet/getnowblock')) {
      return {
        'blockID': blockId,
        'block_header': {
          'raw_data': {'number': blockNumber, 'timestamp': blockTimestamp},
        },
      };
    }
    if (url.endsWith('/wallet/getaccountresource')) {
      return {
        'NetLimit': 1000,
        'NetUsed': 0,
        'freeNetLimit': 600,
        'freeNetUsed': 0,
      };
    }
    if (url.endsWith('/wallet/getchainparameters')) {
      return {
        'chainParameter': [
          {'key': 'getTransactionFee', 'value': 1000},
        ],
      };
    }
    throw StateError('unexpected TRON request: $url');
  }
}

class _BroadcastCapture extends BroadcastService {
  @override
  Future<BroadcastOutcome> broadcast(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    expect(chain, Chain.tron);
    return const BroadcastOutcome.ok('tron-test-signature');
  }
}

/// The TAPOS test below owns transaction construction and expiration only.
/// Production [LocalTransferService] independently verifies native signatures;
/// keep the deliberately non-cryptographic [MockCoreCrypto] out of that
/// separate boundary instead of teaching a fixture to look like a real key.
class _TronConstructionService extends LocalTransferService {
  _TronConstructionService({
    required BroadcastService broadcaster,
    required String Function(Coin) endpoints,
    required RestTransport restTransport,
  }) : super(
         broadcaster: broadcaster,
         endpoints: endpoints,
         restTransport: restTransport,
       );

  @override
  Future<SignedTransaction> signPreparedTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedTronTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async => SignedTransaction(
    signedTx: Uint8List.fromList(const [1]),
    txHash: 'tron-test-signature',
  );
}

class _TronActivationRest implements RestTransport {
  _TronActivationRest({
    required this.genesisBlockId,
    required this.sourceBalance,
  });

  final String genesisBlockId;
  final int sourceBalance;

  @override
  Future<Object?> getJson(String url) async {
    if (url.endsWith('/TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G')) {
      return {
        'data': [
          {'balance': sourceBalance},
        ],
      };
    }
    return {'data': <Object?>[]};
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    if (url.endsWith('/wallet/getblockbynum')) {
      return {'blockID': genesisBlockId};
    }
    if (url.endsWith('/wallet/getnowblock')) {
      return {
        'blockID': List<String>.filled(32, '12').join(),
        'block_header': {
          'raw_data': {'number': 101, 'timestamp': 1780000000000},
        },
      };
    }
    if (url.endsWith('/wallet/getaccountresource')) {
      return <String, Object?>{};
    }
    if (url.endsWith('/wallet/getchainparameters')) {
      return {
        'chainParameter': [
          {'key': 'getTransactionFee', 'value': 1000},
          {'key': 'getCreateAccountFee', 'value': 100000},
          {'key': 'getCreateNewAccountFeeInSystemContract', 'value': 1000000},
        ],
      };
    }
    throw StateError('unexpected TRON request: $url');
  }
}

void main() {
  const solanaGenesis = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG';
  const tronGenesis =
      '0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc';

  test('EVM chain id must match before transaction state is fetched', () async {
    final json = _JsonTransport({'eth_chainId': '0x1'});
    final verifier = RpcNetworkIdentityVerifier(
      jsonRpcTransport: json,
      endpoints: (_) => 'https://rpc.invalid',
    );

    await expectLater(
      verifier.verifyEvm(Chain.ethereum, 11155111),
      throwsA(
        isA<NetworkIdentityException>()
            .having((e) => e.expected, 'expected', '11155111')
            .having((e) => e.actual, 'actual', '1'),
      ),
    );
    expect(json.methods, ['eth_chainId']);
  });

  test('Solana genesis hash is pinned', () async {
    final json = _JsonTransport({'getGenesisHash': solanaGenesis});
    final verifier = RpcNetworkIdentityVerifier(
      jsonRpcTransport: json,
      endpoints: (_) => 'https://solana.invalid',
    );

    await verifier.verifySolana(solanaGenesis);
    await expectLater(
      verifier.verifySolana('another-cluster'),
      throwsA(isA<NetworkIdentityException>()),
    );
    expect(json.methods, ['getGenesisHash', 'getGenesisHash']);
  });

  test('TRON block zero identity is pinned', () async {
    final rest = _RestTransport(tronGenesis);
    final verifier = RpcNetworkIdentityVerifier(
      restTransport: rest,
      endpoints: (_) => 'https://tron.invalid/',
    );

    await verifier.verifyTron(tronGenesis);
    await expectLater(
      verifier.verifyTron('another-network'),
      throwsA(isA<NetworkIdentityException>()),
    );
    expect(
      rest.urls,
      everyElement('https://tron.invalid/wallet/getblockbynum'),
    );
  });

  test('TRON execution preserves TAPOS and canonical expiration', () async {
    const blockTimestamp = 1780000000000;
    final rest = _TronTransferRest(
      genesisBlockId: tronGenesis,
      blockId: List<String>.filled(32, '12').join(),
      blockNumber: 987654,
      blockTimestamp: blockTimestamp,
    );
    final crypto = MockCoreCrypto();
    await crypto.storeWallet(
      walletId: 'wallet',
      mnemonic:
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      requireAuth: false,
    );
    final wallet = HotWallet(
      id: 'wallet',
      name: 'TRON',
      avatarColor: 0,
      addresses: const ChainAddresses(
        eth: '0x0000000000000000000000000000000000000001',
        polygon: '0x0000000000000000000000000000000000000001',
        tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
        solana: '11111111111111111111111111111111',
      ),
    );
    final service = _TronConstructionService(
      broadcaster: _BroadcastCapture(),
      endpoints: (_) => 'https://tron.invalid',
      restTransport: rest,
    );

    final result = await service.executeNonEvm(
      wallet: wallet,
      crypto: crypto,
      draft: TransferDraft(
        symbol: 'TRX',
        networkLabel: 'TRON Nile',
        chain: Chain.tron,
        recipient: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
        amount: Amount.parse('1', 6, symbol: 'TRX'),
        feeTier: 1,
      ),
      expectedNetworkIdentity: tronGenesis,
    );

    expect(result.hash, 'tron-test-signature');
    expect(result.referenceBlockHeight, 987654);
    expect(
      result.expiresAt,
      blockTimestamp + const Duration(minutes: 10).inMilliseconds,
    );
    expect(result.lastValidBlockHeight, isNull);
  });

  test(
    'TRON quote includes new-account activation and bandwidth maximum',
    () async {
      final service = LocalTransferService(
        endpoints: (_) => 'https://tron.invalid',
        restTransport: _TronActivationRest(
          genesisBlockId: tronGenesis,
          sourceBalance: 5000000,
        ),
      );
      final prepared = await service.prepareTron(
        draft: TransferDraft(
          symbol: 'TRX',
          networkLabel: 'TRON Nile',
          chain: Chain.tron,
          recipient: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
          amount: Amount.parse('1', 6, symbol: 'TRX'),
          feeTier: 1,
        ),
        from: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
        expectedNetworkIdentity: tronGenesis,
      );

      expect(prepared.maximumFeeSun, BigInt.from(1100000));
      expect(prepared.referenceBlockHeight, 101);
      expect(
        parseUnsignedTransfer(Chain.tron, prepared.rawTx).amountRaw,
        BigInt.from(1000000),
      );
    },
  );

  test(
    'TRON quote rejects amount plus activation fee above live balance',
    () async {
      final service = LocalTransferService(
        endpoints: (_) => 'https://tron.invalid',
        restTransport: _TronActivationRest(
          genesisBlockId: tronGenesis,
          sourceBalance: 2000000,
        ),
      );

      await expectLater(
        service.prepareTron(
          draft: TransferDraft(
            symbol: 'TRX',
            networkLabel: 'TRON Nile',
            chain: Chain.tron,
            recipient: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
            amount: Amount.parse('1', 6, symbol: 'TRX'),
            feeTier: 1,
          ),
          from: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
          expectedNetworkIdentity: tronGenesis,
        ),
        throwsA(isA<TransferInsufficientFunds>()),
      );
    },
  );

  test('prepareEvm fails closed before nonce, fee or gas requests', () async {
    final json = _JsonTransport({'eth_chainId': '0x1'});
    final service = LocalTransferService(
      endpoints: (coin) {
        expect(coin, Coin.eth);
        return 'https://rpc.invalid';
      },
      jsonRpcTransport: json,
    );

    await expectLater(
      service.prepareEvm(
        draft: TransferDraft(
          symbol: 'ETH',
          networkLabel: 'Sepolia',
          chain: Chain.ethereum,
          recipient: '0x000000000000000000000000000000000000dEaD',
          amount: Amount.parse('0.001', 18, symbol: 'ETH'),
          feeTier: 1,
        ),
        from: '0x0000000000000000000000000000000000000001',
        evmChainId: 11155111,
      ),
      throwsA(isA<NetworkIdentityException>()),
    );
    expect(
      json.methods,
      ['eth_chainId'],
      reason: 'wrong network must stop before nonce/fee/gas and signing',
    );
  });
}
