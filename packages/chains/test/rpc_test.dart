import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:test/test.dart';

/// Fake transport that replays recorded responses and records requests, so RPC
/// parsing/fee logic is tested without a network (detailed-design.md §4.3, §8).
class FakeJsonRpc implements JsonRpcTransport {
  FakeJsonRpc(this.responder);
  final Object? Function(String method, List<Object?> params) responder;
  final List<Map<String, Object?>> requests = [];

  @override
  Future<Object?> post(String url, Object body) async {
    final map = body as Map<String, Object?>;
    requests.add(map);
    return responder(map['method'] as String, map['params'] as List);
  }
}

class FakeRest implements RestTransport {
  FakeRest({this.onGet, this.onPost});
  final Object? Function(String url)? onGet;
  final Object? Function(String url, Object body)? onPost;
  final List<String> gets = [];
  final List<(String, Object)> posts = [];

  @override
  Future<Object?> getJson(String url) async {
    gets.add(url);
    return onGet!(url);
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    posts.add((url, body));
    return onPost!(url, body);
  }
}

Map<String, Object?> _ok(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

const _evmHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _otherEvmHash =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _evmFrom = '0x3333333333333333333333333333333333333333';
const _otherEvmFrom = '0x4444444444444444444444444444444444444444';
const _tronHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherTronHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _solanaOwner = 'A1TMhSGzQxMr1TboBKtgixKz1sS6REASMxPo1qsyTSJd';
const _solanaOtherOwner = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';
const _solanaMint = '2cHr7QS3xfuSV8wdxo3ztuF4xbiarF6Nrgx3qpx3HzXR';
const _solanaOtherMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _solanaTokenAccount = 'BGocb4GEpbTFm8UFV2VsDSaBXHELPfAXrvd4vtt8QWrA';
const _solanaSignature =
    '4cdd1oX7cfVALfr26tP52BZ6cSzrgnNGtYD7BFhm6FFeZV5sPTnRvg6NRn8yC6DbEikXcrNChBM5vVJnTgKhGhVu';

Map<String, Object?> _solanaTokenAccountRow({
  String pubkey = _solanaTokenAccount,
  String owner = _solanaOwner,
  String mint = _solanaMint,
  String amount = '420000000000000',
  int decimals = 6,
  Object? uiAmount = 420000000.0,
  String uiAmountString = '420000000',
  String state = 'initialized',
  String accountProgram = solanaTokenProgram,
  String parsedProgram = 'spl-token',
  bool executable = false,
}) => {
  'pubkey': pubkey,
  'account': {
    'data': {
      'program': parsedProgram,
      'parsed': {
        'info': {
          'isNative': false,
          'mint': mint,
          'owner': owner,
          'state': state,
          'tokenAmount': {
            'amount': amount,
            'decimals': decimals,
            'uiAmount': uiAmount,
            'uiAmountString': uiAmountString,
          },
        },
        'type': 'account',
      },
      'space': 165,
    },
    'executable': executable,
    'lamports': 2039280,
    'owner': accountProgram,
    'rentEpoch': 1.8446744073709552e19,
    'space': 165,
  },
};

Map<String, Object?> _solanaTokenResult({List<Object?>? rows}) => {
  'context': {'apiVersion': '4.1.2', 'slot': 341197933},
  'value': rows ?? [_solanaTokenAccountRow()],
};

Map<String, Object?> _solanaSignatureStatusResult({
  int contextSlot = 82,
  Object? entry = const {
    'slot': 48,
    'confirmations': null,
    'err': null,
    'status': {'Ok': null},
    'confirmationStatus': 'finalized',
  },
}) => {
  'context': {'slot': contextSlot},
  'value': [entry],
};

Map<String, Object?> _evmReceipt({
  String transactionHash = _evmHash,
  String blockHash =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  Object? blockNumber = '0x64',
  Object? transactionIndex = '0x0',
  Object? status = '0x1',
}) => {
  'transactionHash': transactionHash,
  'blockHash': blockHash,
  'blockNumber': blockNumber,
  'transactionIndex': transactionIndex,
  'status': status,
};

void main() {
  group('EVM pending transaction evidence', () {
    test('binds canonical hash sender and nonce', () {
      final evidence = parseEvmPendingTransactionEvidence(
        {
          'hash': _evmHash,
          'from': _evmFrom,
          'nonce': '0x7',
          'blockHash': null,
          'providerExtension': true,
        },
        expectedTransactionHash: _evmHash,
        expectedFrom: _evmFrom,
      );

      expect(evidence.transactionHash, _evmHash);
      expect(evidence.from, _evmFrom);
      expect(evidence.nonce, BigInt.from(7));
    });

    test('rejects unbound or non-canonical consumed fields', () {
      final valid = <String, Object?>{
        'hash': _evmHash,
        'from': _evmFrom,
        'nonce': '0x7',
      };
      final invalid = <Map<String, Object?>>[
        {...valid}..remove('hash'),
        {...valid, 'hash': _otherEvmHash},
        {...valid}..remove('from'),
        {...valid, 'from': _otherEvmFrom},
        {...valid}..remove('nonce'),
        {...valid, 'nonce': '0x00'},
        {...valid, 'nonce': '0x-1'},
        {...valid, 'nonce': '0X7'},
        {...valid, 'nonce': '0x${'1' * 65}'},
      ];

      for (final row in invalid) {
        expect(
          () => parseEvmPendingTransactionEvidence(
            row,
            expectedTransactionHash: _evmHash,
            expectedFrom: _evmFrom,
          ),
          throwsA(isA<RpcException>()),
          reason: '$row',
        );
      }
    });

    test('rejects invalid request identity before transport', () async {
      final transport = FakeJsonRpc((m, p) => _ok(null));
      final rpc = EvmRpc(url: 'x', transport: transport);

      await expectLater(
        rpc.getPendingTransactionEvidence('0xshort', expectedFrom: _evmFrom),
        throwsA(isA<RpcException>()),
      );
      await expectLater(
        rpc.getPendingTransactionEvidence(_evmHash, expectedFrom: '0xshort'),
        throwsA(isA<RpcException>()),
      );
      await expectLater(
        rpc.getTransactionReceipt('0xshort'),
        throwsA(isA<RpcException>()),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('EVM receipt evidence', () {
    test('binds complete canonical evidence to the requested hash', () {
      final evidence = parseEvmReceiptEvidence(
        _evmReceipt(),
        expectedTransactionHash: _evmHash.toUpperCase().replaceFirst(
          '0X',
          '0x',
        ),
      );

      expect(evidence.transactionHash, _evmHash);
      expect(evidence.blockNumber, BigInt.from(100));
      expect(evidence.transactionIndex, BigInt.zero);
      expect(evidence.succeeded, isTrue);
      expect(
        parseEvmReceiptEvidence(
          _evmReceipt(status: '0x0'),
          expectedTransactionHash: _evmHash,
        ).succeeded,
        isFalse,
      );
    });

    test('rejects a different hash or incomplete inclusion evidence', () {
      final invalid = [
        _evmReceipt(transactionHash: _otherEvmHash),
        {..._evmReceipt()}..remove('transactionHash'),
        {..._evmReceipt()}..remove('blockHash'),
        {..._evmReceipt()}..remove('blockNumber'),
        {..._evmReceipt()}..remove('transactionIndex'),
      ];

      for (final receipt in invalid) {
        expect(
          () => parseEvmReceiptEvidence(
            receipt,
            expectedTransactionHash: _evmHash,
          ),
          throwsA(isA<RpcException>()),
        );
      }
    });

    test('rejects non-canonical hashes, quantities, and status', () {
      final invalid = [
        _evmReceipt(blockHash: '0xabc'),
        _evmReceipt(blockNumber: '0x00'),
        _evmReceipt(blockNumber: '100'),
        _evmReceipt(blockNumber: '0x${'1' * 65}'),
        _evmReceipt(transactionIndex: '-1'),
        _evmReceipt(status: 0),
        _evmReceipt(status: '0x01'),
      ];

      for (final receipt in invalid) {
        expect(
          () => parseEvmReceiptEvidence(
            receipt,
            expectedTransactionHash: _evmHash,
          ),
          throwsA(isA<RpcException>()),
        );
      }
      expect(
        () => parseEvmReceiptEvidence(
          _evmReceipt(),
          expectedTransactionHash: '0xhash',
        ),
        throwsA(isA<RpcException>()),
      );
    });
  });

  group('EvmRpc', () {
    test('getBalance parses a hex quantity', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok('0xde0b6b3a7640000')),
      );
      expect(
        await rpc.getBalance('0xabc'),
        BigInt.parse('1000000000000000000'),
      );
    });

    test('getBlockNumber parses the latest hex block height', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((method, params) {
          expect(method, 'eth_blockNumber');
          expect(params, isEmpty);
          return _ok('0x66');
        }),
      );

      expect(await rpc.getBlockNumber(), BigInt.from(102));
    });

    test('erc20Balance builds balanceOf calldata and parses result', () async {
      late List<Object?> params;
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) {
          params = p;
          return _ok('0x${'0' * 56}05f5e100'); // ABI uint256: 100_000_000
        }),
      );
      final bal = await rpc.erc20Balance(
        '0xcontract',
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
      expect(bal, BigInt.from(100000000));
      final call = params[0] as Map;
      expect(call['data'], startsWith('0x70a08231'));
    });

    test('erc20Balance requires one exact ABI uint256 word', () async {
      for (final result in <String>['0x0', '0x${'0' * 62}', '0x${'0' * 66}']) {
        final rpc = EvmRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) => _ok(result)),
        );
        await expectLater(
          rpc.erc20Balance('0xcontract', '0xowner'),
          throwsA(isA<RpcException>()),
        );
      }
    });

    test('spendable balance reads use the pending block tag', () async {
      final transport = FakeJsonRpc((method, params) {
        if (method == 'eth_getBalance') return _ok('0x2a');
        if (method == 'eth_call') return _ok('0x${'0' * 62}64');
        throw StateError('unexpected $method');
      });
      final rpc = EvmRpc(url: 'x', transport: transport);

      expect(
        await rpc.getBalance('0xowner', blockTag: 'pending'),
        BigInt.from(42),
      );
      expect(
        await rpc.erc20Balance(
          '0xtoken',
          '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          blockTag: 'pending',
        ),
        BigInt.from(100),
      );
      expect(transport.requests[0]['params'], ['0xowner', 'pending']);
      expect((transport.requests[1]['params'] as List).last, 'pending');
    });

    test(
      'eth_call simulates the exact transfer against pending state',
      () async {
        late String method;
        late List<Object?> params;
        final rpc = EvmRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) {
            method = m;
            params = p;
            return _ok('0x');
          }),
        );

        expect(
          await rpc.call(
            from: '0xfrom',
            to: '0xto',
            value: BigInt.from(42),
            data: '0xabcdef',
          ),
          '0x',
        );
        expect(method, 'eth_call');
        expect(params[1], 'pending');
        expect(params[0], {
          'from': '0xfrom',
          'to': '0xto',
          'value': '0x2a',
          'data': '0xabcdef',
        });
      },
    );

    test('eth_call rejects malformed return bytes', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok('not-hex')),
      );
      expect(
        () => rpc.call(
          from: '0xfrom',
          to: '0xto',
          value: BigInt.zero,
          data: '0x',
        ),
        throwsA(isA<RpcException>()),
      );
    });

    test('feeHistory yields slow<=standard<=fast tiers', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok({
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x64', '0x64', '0x64'], // 100
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x1', '0x2', '0x3'],
            ],
          }),
        ),
      );
      final fees = await rpc.estimateFees();
      expect(fees.slow.maxPriorityFeePerGas, BigInt.from(1));
      expect(fees.standard.maxPriorityFeePerGas, BigInt.from(2));
      expect(fees.fast.maxPriorityFeePerGas, BigInt.from(3));
      expect(fees.slow.maxFeePerGas, BigInt.from(201));
      expect(fees.fast.maxFeePerGas, BigInt.from(203));
    });

    test(
      'feeHistory rejects ambiguous or inconsistent official shapes',
      () async {
        final invalid = <Map<String, Object?>>[
          {
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x2', '0x3', '0x4'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x2', '0x3', '0x4'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x2', '0x3', '0x4'],
            ],
            'nextBaseFeePerGas': '0x12',
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x2', '0x3', '0x4'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [-0.01, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
              ['0x2', '0x3', '0x4'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x1', '0x2', '0x3', '0x4'],
              ['0x2', '0x3', '0x4', '0x5'],
            ],
          },
          {
            'oldestBlock': '0x64',
            'baseFeePerGas': ['0x10', '0x11', '0x12'],
            'gasUsedRatio': [0.5, 0.75],
            'reward': [
              ['0x3', '0x2', '0x1'],
              ['0x2', '0x3', '0x4'],
            ],
          },
        ];
        for (final result in invalid) {
          final rpc = EvmRpc(
            url: 'x',
            transport: FakeJsonRpc((m, p) => _ok(result)),
          );
          await expectLater(rpc.estimateFees(), throwsA(isA<RpcException>()));
        }
      },
    );

    test('RPC error response throws RpcException with code', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => {
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32000, 'message': 'nonce too low'},
          },
        ),
      );
      expect(
        () => rpc.getNonce(_evmFrom),
        throwsA(
          isA<RpcException>()
              .having((e) => e.code, 'code', -32000)
              .having(
                (e) => e.message,
                'message',
                'transaction nonce is too low',
              ),
        ),
      );
    });

    test('untrusted node error text is never retained', () async {
      const canary = 'https://malicious-rpc.example/private-provider-key';
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => {
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32000, 'message': canary},
          },
        ),
      );

      Object? thrown;
      try {
        await rpc.getNonce(_evmFrom);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isA<RpcRejectedException>());
      expect(
        (thrown! as RpcRejectedException).message,
        'transaction rejected by network',
      );
      expect((thrown as RpcRejectedException).kind, RpcRejectionKind.rejected);
      expect(thrown.toString(), isNot(contains('private-provider-key')));
    });

    test('network-seen duplicate vocabulary stays alreadyKnown', () {
      for (final message in const [
        'already known',
        'Transaction simulation failed: This transaction has already been processed',
        'transaction already exists',
        'transaction already imported',
      ]) {
        expect(
          publicRpcRejectionKind(message),
          RpcRejectionKind.alreadyKnown,
          reason: message,
        );
        expect(
          publicRpcRejectionMessage(message),
          'transaction is already known by the network',
          reason: message,
        );
      }
      expect(
        publicRpcRejectionKind('unknown transaction'),
        RpcRejectionKind.rejected,
        reason: 'unknown must not substring-match known',
      );
    });

    test('non-hex quantity throws instead of returning garbage', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok('123')),
      );
      expect(() => rpc.getBalance('0xabc'), throwsA(isA<RpcException>()));
    });

    test('EVM quantities must be canonical uint256 values', () async {
      for (final quantity in <String>['0x', '0x00', '0x${'1' * 65}']) {
        final rpc = EvmRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) => _ok(quantity)),
        );
        await expectLater(
          rpc.getBalance('0xabc'),
          throwsA(isA<RpcException>()),
        );
      }
    });

    test(
      'malformed feeHistory throws RpcException, not an untyped error',
      () async {
        // Missing reward field.
        final rpc = EvmRpc(
          url: 'x',
          transport: FakeJsonRpc(
            (m, p) => _ok({
              'baseFeePerGas': ['0x1'],
            }),
          ),
        );
        expect(() => rpc.estimateFees(), throwsA(isA<RpcException>()));

        // Short reward row.
        final rpc2 = EvmRpc(
          url: 'x',
          transport: FakeJsonRpc(
            (m, p) => _ok({
              'baseFeePerGas': ['0x1'],
              'reward': [
                ['0x1'],
              ],
            }),
          ),
        );
        expect(() => rpc2.estimateFees(), throwsA(isA<RpcException>()));
      },
    );
  });

  group('SolanaRpc', () {
    test(
      'getBalance binds the current official context and u64 value',
      () async {
        final rpc = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc(
            (m, p) => _ok({
              'context': {'apiVersion': '4.1.2', 'slot': 90},
              'value': 42,
            }),
          ),
        );
        expect(await rpc.getBalance(_solanaOwner), BigInt.from(42));
      },
    );

    test(
      'getBalance rejects ambiguous identities and financial values',
      () async {
        final invalid = <Object?>[
          {'value': 42},
          {
            'context': {'slot': 90},
            'value': 42,
            'provider': 'node-a',
          },
          {
            'context': {'slot': -1},
            'value': 42,
          },
          {
            'context': {'slot': 90},
            'value': '42',
          },
          {
            'context': {'slot': 90},
            'value': -1,
          },
        ];
        for (final response in invalid) {
          final rpc = SolanaRpc(
            url: 'x',
            transport: FakeJsonRpc((m, p) => _ok(response)),
          );
          await expectLater(
            rpc.getBalance(_solanaOwner),
            throwsA(isA<RpcException>()),
            reason: '$response',
          );
        }

        final transport = FakeJsonRpc((m, p) => throw StateError('network'));
        await expectLater(
          SolanaRpc(url: 'x', transport: transport).getBalance('not-a-key'),
          throwsA(isA<RpcException>()),
        );
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'token accounts bind owner mint program state and exact amount',
      () async {
        final rpc = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) => _ok(_solanaTokenResult())),
        );

        final accounts = await rpc.getTokenAccounts(_solanaOwner, _solanaMint);
        expect(accounts, hasLength(1));
        expect(accounts.single.address, _solanaTokenAccount);
        expect(accounts.single.amount, BigInt.parse('420000000000000'));
        expect(accounts.single.decimals, 6);
        expect(accounts.single.state, SolanaTokenAccountState.initialized);
        expect(
          await rpc.getTokenBalance(_solanaOwner, _solanaMint),
          BigInt.parse('420000000000000'),
        );

        final frozen = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc(
            (m, p) => _ok(
              _solanaTokenResult(
                rows: [_solanaTokenAccountRow(state: 'frozen')],
              ),
            ),
          ),
        );
        expect(
          (await frozen.getTokenAccounts(
            _solanaOwner,
            _solanaMint,
          )).single.state,
          SolanaTokenAccountState.frozen,
        );
      },
    );

    test(
      'token accounts reject unbound, malformed, duplicate and overflowing data',
      () async {
        final duplicate = _solanaTokenAccountRow();
        final invalid = <Object?>[
          {'value': <Object?>[]},
          {..._solanaTokenResult(), 'provider': 'node-a'},
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(owner: _solanaOtherOwner)],
          ),
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(mint: _solanaOtherMint)],
          ),
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(pubkey: 'not-a-key')],
          ),
          _solanaTokenResult(rows: [duplicate, duplicate]),
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(accountProgram: solanaSystemProgram)],
          ),
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(parsedProgram: 'spl-token-2022')],
          ),
          _solanaTokenResult(rows: [_solanaTokenAccountRow(executable: true)]),
          _solanaTokenResult(rows: [_solanaTokenAccountRow(amount: '-1')]),
          _solanaTokenResult(
            rows: [_solanaTokenAccountRow(amount: '18446744073709551616')],
          ),
          _solanaTokenResult(
            rows: [
              _solanaTokenAccountRow(
                amount: '1200000',
                uiAmount: 1.2,
                uiAmountString: '1.3',
              ),
            ],
          ),
          _solanaTokenResult(
            rows: [
              _solanaTokenAccountRow(
                amount: '18446744073709551615',
                decimals: 0,
                uiAmount: null,
                uiAmountString: '18446744073709551615',
              ),
              _solanaTokenAccountRow(
                pubkey: _solanaOtherOwner,
                amount: '1',
                decimals: 0,
                uiAmount: 1,
                uiAmountString: '1',
              ),
            ],
          ),
        ];
        for (final response in invalid) {
          final rpc = SolanaRpc(
            url: 'x',
            transport: FakeJsonRpc((m, p) => _ok(response)),
          );
          await expectLater(
            rpc.getTokenAccounts(_solanaOwner, _solanaMint),
            throwsA(isA<RpcException>()),
            reason: '$response',
          );
        }

        final transport = FakeJsonRpc((m, p) => throw StateError('network'));
        final rpc = SolanaRpc(url: 'x', transport: transport);
        await expectLater(
          rpc.getTokenAccounts('not-an-owner', _solanaMint),
          throwsA(isA<RpcException>()),
        );
        await expectLater(
          rpc.getTokenAccounts(_solanaOwner, 'not-a-mint'),
          throwsA(isA<RpcException>()),
        );
        expect(transport.requests, isEmpty);

        final decimals = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) => _ok(_solanaTokenResult())),
        );
        await expectLater(
          decimals.getTokenAccounts(
            _solanaOwner,
            _solanaMint,
            expectedDecimals: 9,
          ),
          throwsA(isA<RpcException>()),
        );
      },
    );

    test('getLatestBlockhash extracts nested blockhash', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok({
            'context': {'slot': 90},
            'value': {
              'blockhash': 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N',
              'lastValidBlockHeight': 100,
            },
          }),
        ),
      );
      expect(
        await rpc.getLatestBlockhash(),
        'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N',
      );
      final latest = await rpc.getLatestBlockhashInfo();
      expect(latest.blockhash, 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N');
      expect(latest.lastValidBlockHeight, 100);
    });

    test('getBlockHeight requires a non-negative canonical height', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok(123456)),
      );
      expect(await rpc.getBlockHeight(), 123456);
    });

    test(
      'signature status binds the official single-signature shape',
      () async {
        final rpc = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc((m, p) => _ok(_solanaSignatureStatusResult())),
        );
        final result = await rpc.signatureResult(_solanaSignature);
        expect(result, isNotNull);
        expect(result!.slot, 48);
        expect(result.confirmations, isNull);
        expect(result.confirmationStatus, 'finalized');
        expect(result.failed, isFalse);
      },
    );

    test('signatureStatus null only for one explicit null result', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok(_solanaSignatureStatusResult(entry: null)),
        ),
      );
      expect(await rpc.signatureResult(_solanaSignature), isNull);
    });

    test('signature status preserves a canonical execution failure', () async {
      const error = {
        'InstructionError': [1, 'InvalidArgument'],
      };
      final row = {
        'slot': 48,
        'confirmations': 2,
        'err': error,
        'status': {'Err': error},
        'confirmationStatus': null,
      };
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok(_solanaSignatureStatusResult(entry: row)),
        ),
      );

      final result = await rpc.signatureResult(_solanaSignature);
      expect(result, isNotNull);
      expect(result!.slot, 48);
      expect(result.confirmations, 2);
      expect(result.confirmationStatus, isNull);
      expect(result.failed, isTrue);
    });

    test(
      'signature status rejects ambiguous or inconsistent evidence',
      () async {
        final ok = _solanaSignatureStatusResult()['value']! as List<Object?>;
        final row = Map<String, Object?>.from(ok.single! as Map);
        final oversizedError = {'message': List.filled(4097, 'x').join()};
        final invalid = <Object?>[
          {
            'value': [row],
          },
          {..._solanaSignatureStatusResult(), 'provider': 'node-a'},
          {..._solanaSignatureStatusResult(), 'value': <Object?>[]},
          {
            ..._solanaSignatureStatusResult(),
            'value': [row, null],
          },
          _solanaSignatureStatusResult(entry: {...row, 'provider': 'node-a'}),
          _solanaSignatureStatusResult(entry: {...row}..remove('slot')),
          _solanaSignatureStatusResult(entry: {...row, 'slot': -1}),
          _solanaSignatureStatusResult(contextSlot: 47),
          _solanaSignatureStatusResult(entry: {...row, 'confirmations': -1}),
          _solanaSignatureStatusResult(entry: {...row, 'confirmations': '1'}),
          _solanaSignatureStatusResult(
            entry: {...row, 'confirmationStatus': 'accepted'},
          ),
          _solanaSignatureStatusResult(
            entry: {...row, 'confirmationStatus': 'confirmed'},
          ),
          _solanaSignatureStatusResult(entry: {...row, 'confirmations': 1}),
          _solanaSignatureStatusResult(
            entry: {
              ...row,
              'err': {'InstructionError': 0},
            },
          ),
          _solanaSignatureStatusResult(
            entry: {
              ...row,
              'status': {
                'Err': {'InstructionError': 0},
              },
            },
          ),
          _solanaSignatureStatusResult(
            entry: {
              ...row,
              'err': {'InstructionError': 0},
              'status': {
                'Err': {'InstructionError': 1},
              },
            },
          ),
          _solanaSignatureStatusResult(
            entry: {
              ...row,
              'err': oversizedError,
              'status': {'Err': oversizedError},
            },
          ),
        ];
        for (final response in invalid) {
          final rpc = SolanaRpc(
            url: 'x',
            transport: FakeJsonRpc((m, p) => _ok(response)),
          );
          await expectLater(
            rpc.signatureResult(_solanaSignature),
            throwsA(isA<RpcException>()),
            reason: '$response',
          );
        }
      },
    );

    test('signature status rejects a non-canonical txid before RPC', () async {
      final transport = FakeJsonRpc(
        (m, p) => _ok(_solanaSignatureStatusResult()),
      );
      final rpc = SolanaRpc(url: 'x', transport: transport);

      await expectLater(
        rpc.signatureResult('not-a-signature'),
        throwsA(isA<RpcException>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('fee and simulation use the exact serialized message', () async {
      final transport = FakeJsonRpc((method, params) {
        if (method == 'getFeeForMessage') {
          return _ok({
            'context': {'slot': 5068},
            'value': 5000,
          });
        }
        if (method == 'simulateTransaction') {
          return _ok({
            'context': {'slot': 5068},
            'value': {'err': null, 'unitsConsumed': 500},
          });
        }
        throw StateError(method);
      });
      final rpc = SolanaRpc(url: 'x', transport: transport);
      final message = Uint8List.fromList([1, 2, 3]);
      expect(await rpc.getFeeForMessage(message), BigInt.from(5000));
      await rpc.simulateMessage(message);
      expect(transport.requests.map((request) => request['method']), [
        'getFeeForMessage',
        'simulateTransaction',
      ]);
    });

    test(
      'simulation returns requested post-transaction account balances',
      () async {
        final transport = FakeJsonRpc((method, params) {
          expect(method, 'simulateTransaction');
          final config = params[1] as Map;
          expect(config['accounts'], {
            'encoding': 'base64',
            'addresses': ['fee-payer'],
          });
          return _ok({
            'context': {'slot': 5068},
            'value': {
              'err': null,
              'accounts': [
                {
                  'data': ['', 'base64'],
                  'executable': false,
                  'lamports': 12345,
                  'owner': '11111111111111111111111111111111',
                  'rentEpoch': 0,
                  'space': 0,
                },
              ],
              'unitsConsumed': 721,
            },
          });
        });
        final result = await SolanaRpc(url: 'x', transport: transport)
            .simulateMessage(
              Uint8List.fromList([1, 2, 3]),
              accountAddresses: const ['fee-payer'],
            );

        expect(result.accountLamports, {'fee-payer': BigInt.from(12345)});
        expect(result.unitsConsumed, 721);
      },
    );

    test(
      'simulation fails closed when requested account state is absent',
      () async {
        final rpc = SolanaRpc(
          url: 'x',
          transport: FakeJsonRpc(
            (method, params) => _ok({
              'context': {'slot': 5068},
              'value': {'err': null, 'accounts': null},
            }),
          ),
        );

        expect(
          () => rpc.simulateMessage(
            Uint8List.fromList([1, 2, 3]),
            accountAddresses: const ['fee-payer'],
          ),
          throwsA(isA<RpcException>()),
        );
      },
    );

    test(
      'pre-signing RPC results reject ambiguous or inconsistent shapes',
      () async {
        final scenarios = <(String, Future<void> Function(SolanaRpc), Object?)>[
          (
            'blockhash missing context',
            (rpc) async => rpc.getLatestBlockhashInfo(),
            {
              'value': {
                'blockhash': 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N',
                'lastValidBlockHeight': 3090,
              },
            },
          ),
          (
            'blockhash unknown value member',
            (rpc) async => rpc.getLatestBlockhashInfo(),
            {
              'context': {'slot': 2792},
              'value': {
                'blockhash': 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N',
                'lastValidBlockHeight': 3090,
                'valid': true,
              },
            },
          ),
          (
            'invalid blockhash identity',
            (rpc) async => rpc.getLatestBlockhashInfo(),
            {
              'context': {'slot': 2792},
              'value': {'blockhash': 'HASH123', 'lastValidBlockHeight': 3090},
            },
          ),
          (
            'negative last valid height',
            (rpc) async => rpc.getLatestBlockhashInfo(),
            {
              'context': {'slot': 2792},
              'value': {
                'blockhash': 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N',
                'lastValidBlockHeight': -1,
              },
            },
          ),
          (
            'fee missing context',
            (rpc) async => rpc.getFeeForMessage(Uint8List.fromList([1])),
            {'value': 5000},
          ),
          (
            'negative fee',
            (rpc) async => rpc.getFeeForMessage(Uint8List.fromList([1])),
            {
              'context': {'slot': 5068},
              'value': -1,
            },
          ),
          (
            'simulation missing context',
            (rpc) async => rpc.simulateMessage(Uint8List.fromList([1])),
            {
              'value': {'err': null},
            },
          ),
          (
            'simulation unknown value member',
            (rpc) async => rpc.simulateMessage(Uint8List.fromList([1])),
            {
              'context': {'slot': 393226680},
              'value': {'err': null, 'trusted': true},
            },
          ),
          (
            'simulation contradicts fixed blockhash request',
            (rpc) async => rpc.simulateMessage(Uint8List.fromList([1])),
            {
              'context': {'slot': 393226680},
              'value': {
                'err': null,
                'replacementBlockhash': {
                  'blockhash': '6oFLsE7kmgJx9PjR4R63VRNtpAVJ648gCTr3nq5Hihit',
                  'lastValidBlockHeight': 381186895,
                },
              },
            },
          ),
        ];

        for (final (name, invoke, response) in scenarios) {
          final rpc = SolanaRpc(
            url: 'x',
            transport: FakeJsonRpc((method, params) => _ok(response)),
          );
          await expectLater(
            invoke(rpc),
            throwsA(isA<RpcException>()),
            reason: name,
          );
        }
      },
    );
  });

  group('TronRpc', () {
    test(
      'transaction status binds complete evidence to requested txID',
      () async {
        final responses = <Object?>[
          <String, Object?>{},
          {
            'id': _tronHash,
            'blockNumber': 42,
            'receipt': {'result': 'SUCCESS'},
          },
          {
            'id': _tronHash,
            'blockNumber': 42,
            'receipt': {'result': 'OUT_OF_ENERGY'},
          },
          {'id': _tronHash, 'blockNumber': 42, 'receipt': <String, Object?>{}},
          {
            'txID': _tronHash,
            'ret': [
              {'contractRet': 'SUCCESS'},
            ],
          },
          {'id': _tronHash, 'blockNumber': 42, 'receipt': <String, Object?>{}},
          {
            'txID': _tronHash,
            'ret': [
              {'contractRet': 'OUT_OF_ENERGY'},
            ],
          },
          {'id': _tronHash, 'blockNumber': 42, 'result': 'FAILED'},
        ];
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(onPost: (u, b) => responses.removeAt(0)),
        );

        expect(await rpc.transactionSucceeded(_tronHash), isNull);
        expect(await rpc.transactionSucceeded(_tronHash), isTrue);
        expect(await rpc.transactionSucceeded(_tronHash), isFalse);
        expect(await rpc.transactionSucceeded(_tronHash), isTrue);
        expect(await rpc.transactionSucceeded(_tronHash), isFalse);
        expect(await rpc.transactionSucceeded(_tronHash), isFalse);
      },
    );

    test(
      'transaction status rejects mismatched or incomplete evidence',
      () async {
        final invalidInfo = <Map<String, Object?>>[
          {
            'id': _otherTronHash,
            'blockNumber': 42,
            'receipt': {'result': 'SUCCESS'},
          },
          {
            'id': _tronHash,
            'receipt': {'result': 'SUCCESS'},
          },
          {
            'id': _tronHash,
            'blockNumber': 42,
            'receipt': {'result': 'NOT_A_TRON_RESULT'},
          },
        ];
        for (final info in invalidInfo) {
          expect(
            () => parseTronTransactionEvidence(
              info,
              expectedTransactionId: _tronHash,
            ),
            throwsA(isA<RpcException>()),
          );
        }

        final responses = <Object?>[
          {'id': _tronHash, 'blockNumber': 42, 'receipt': <String, Object?>{}},
          {
            'txID': _otherTronHash,
            'ret': [
              {'contractRet': 'SUCCESS'},
            ],
          },
        ];
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(onPost: (u, b) => responses.removeAt(0)),
        );
        await expectLater(
          rpc.transactionSucceeded(_tronHash),
          throwsA(isA<RpcException>()),
        );
      },
    );

    test('getTrxBalance returns 0 for an unactivated account', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(onGet: (u) => {'data': <Object?>[]}),
      );
      expect(await rpc.getTrxBalance('Tabc'), BigInt.zero);
    });

    test('getTrxBalance parses SUN balance', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onGet: (u) => {
            'data': [
              {'balance': 1420000000},
            ],
          },
        ),
      );
      expect(await rpc.getTrxBalance('Tabc'), BigInt.from(1420000000));
    });

    test(
      'account balances preserve activation and requested TRC-20 balance',
      () async {
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(
            onGet: (u) => {
              'data': [
                {
                  'balance': 1200000,
                  'trc20': [
                    {'TToken': '99000000'},
                  ],
                },
              ],
            },
          ),
        );

        final balances = await rpc.getAccountBalances(
          'Tabc',
          tokenContract: 'TToken',
        );
        expect(balances.activated, isTrue);
        expect(balances.trx, BigInt.from(1200000));
        expect(balances.token, BigInt.from(99000000));
      },
    );

    test('malformed requested TRC-20 balance fails closed', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onGet: (u) => {
            'data': [
              {
                'trc20': [
                  {'TToken': 123},
                ],
              },
            ],
          },
        ),
      );

      expect(
        () => rpc.getAccountBalances('Tabc', tokenContract: 'TToken'),
        throwsA(isA<RpcException>()),
      );
    });

    test('broadcast returns txid on success', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onPost: (u, b) => {'result': true, 'txid': 'abc123'},
        ),
      );
      expect(await rpc.broadcast({'raw': 'x'}), 'abc123');
    });

    test('broadcast throws on rejection (not silently retried)', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onPost: (u, b) => {'result': false, 'message': 'TAPOS error'},
        ),
      );
      expect(() => rpc.broadcast({'raw': 'x'}), throwsA(isA<RpcException>()));
    });

    test('TRON duplicate code is normalized as alreadyKnown', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onPost: (u, b) => {
            'result': false,
            'code': 'DUP_TRANSACTION_ERROR',
            'message': '5472616e73616374696f6e20616c7265616479206578697373',
          },
        ),
      );

      await expectLater(
        rpc.broadcast({'transaction': 'ab'}),
        throwsA(
          isA<RpcRejectedException>()
              .having(
                (error) => error.kind,
                'kind',
                RpcRejectionKind.alreadyKnown,
              )
              .having(
                (error) => error.message,
                'message',
                'transaction is already known by the network',
              ),
        ),
      );
    });

    // A signer payload carries the full signed Transaction protobuf, which
    // only /wallet/broadcasthex accepts — posting it to
    // /wallet/broadcasttransaction (which dereferences `raw_data`) made every
    // TRON transfer fail with a bare NullPointerException from the node.
    test('a {transaction} payload goes to broadcasthex, alone', () async {
      final transport = FakeRest(
        onPost: (u, b) => {'result': true, 'txid': 'abc123'},
      );
      final rpc = TronRpc(baseUrl: 'https://api', transport: transport);
      expect(
        await rpc.broadcast({'transaction': 'deadbeef', 'txID': 'abc123'}),
        'abc123',
      );
      expect(transport.posts.single.$1, 'https://api/wallet/broadcasthex');
      // txID must NOT ride along: TronGrid rejects unknown body fields.
      expect(transport.posts.single.$2, {'transaction': 'deadbeef'});
    });

    test(
      'a full transaction JSON still goes to broadcasttransaction',
      () async {
        final transport = FakeRest(
          onPost: (u, b) => {'result': true, 'txid': 'abc123'},
        );
        final rpc = TronRpc(baseUrl: 'https://api', transport: transport);
        final body = {
          'raw_data': {'contract': <Object?>[]},
          'raw_data_hex': '0a02',
          'signature': ['ff'],
        };
        expect(await rpc.broadcast(body), 'abc123');
        expect(
          transport.posts.single.$1,
          'https://api/wallet/broadcasttransaction',
        );
        expect(transport.posts.single.$2, same(body));
      },
    );

    // TronGrid can answer node-level failures with arbitrary Java exception
    // text. The raw provider string must not cross into UI/logging.
    test('a top-level Error is normalized, never surfaced verbatim', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onPost: (u, b) => {
            'Error': 'class java.lang.NullPointerException : null',
          },
        ),
      );
      expect(
        () => rpc.broadcast({'transaction': 'ab'}),
        throwsA(
          isA<RpcException>().having(
            (e) => e.message,
            'message',
            'transaction rejected by network',
          ),
        ),
      );
    });

    test('a reasonless rejection uses the fixed public message', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(onPost: (u, b) => {'result': false}),
      );
      expect(
        () => rpc.broadcast({'transaction': 'ab'}),
        throwsA(
          isA<RpcException>().having(
            (e) => e.message,
            'message',
            'transaction rejected by network',
          ),
        ),
      );
    });

    test('malformed balance is an error, not a silent zero', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onGet: (u) => {
            'data': [
              {'balance': 'oops'},
            ],
          },
        ),
      );
      expect(() => rpc.getTrxBalance('Tabc'), throwsA(isA<RpcException>()));
    });

    test(
      'TRC-20 fee limit comes from energy, resources and chain price',
      () async {
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(
            onPost: (url, body) {
              if (url.endsWith('triggerconstantcontract')) {
                return {
                  'result': {'result': true},
                  'energy_used': 100000,
                };
              }
              if (url.endsWith('getaccountresource')) {
                return {'EnergyLimit': 40000, 'EnergyUsed': 10000};
              }
              if (url.endsWith('getchainparameters')) {
                return {
                  'chainParameter': [
                    {'key': 'getEnergyFee', 'value': 420},
                  ],
                };
              }
              throw StateError(url);
            },
          ),
        );

        final estimate = await rpc.estimateTokenEnergy(
          owner: 'owner',
          contract: 'contract',
          parameter: '00',
        );

        expect(estimate.energyRequired, 100000);
        expect(estimate.energyAvailable, 30000);
        expect(estimate.energyPriceSun, 420);
        expect(estimate.feeLimitSun, 35280000);
      },
    );

    test(
      'bandwidth uses current resources and charges nothing when covered',
      () async {
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(
            onPost: (url, body) {
              if (url.endsWith('getaccountresource')) {
                return {
                  'NetLimit': 1000,
                  'NetUsed': 100,
                  'freeNetLimit': 600,
                  'freeNetUsed': 50,
                };
              }
              if (url.endsWith('getchainparameters')) {
                return {
                  'chainParameter': [
                    {'key': 'getTransactionFee', 'value': 1000},
                  ],
                };
              }
              throw StateError(url);
            },
          ),
        );

        final estimate = await rpc.estimateBandwidthFee(
          owner: 'TOwner',
          rawDataLength: 100,
          activatesRecipient: false,
        );
        expect(estimate.stakedBandwidthAvailable, 900);
        expect(estimate.freeBandwidthAvailable, 550);
        expect(estimate.bandwidthFeeSun, 0);
        expect(estimate.activationFeeSun, 0);
      },
    );

    test(
      'bandwidth burn and activation fees use live chain parameters',
      () async {
        final rpc = TronRpc(
          baseUrl: 'https://api',
          transport: FakeRest(
            onPost: (url, body) {
              if (url.endsWith('getaccountresource')) {
                return <String, Object?>{};
              }
              if (url.endsWith('getchainparameters')) {
                return {
                  'chainParameter': [
                    {'key': 'getTransactionFee', 'value': 1000},
                    {'key': 'getCreateAccountFee', 'value': 100000},
                    {
                      'key': 'getCreateNewAccountFeeInSystemContract',
                      'value': 1000000,
                    },
                  ],
                };
              }
              throw StateError(url);
            },
          ),
        );

        final ordinary = await rpc.estimateBandwidthFee(
          owner: 'TOwner',
          rawDataLength: 100,
          activatesRecipient: false,
        );
        expect(ordinary.bandwidthFeeSun, ordinary.estimatedBandwidth * 1000);

        final activation = await rpc.estimateBandwidthFee(
          owner: 'TOwner',
          rawDataLength: 100,
          activatesRecipient: true,
        );
        expect(activation.bandwidthFeeSun, 100000);
        expect(activation.activationFeeSun, 1000000);
      },
    );

    test('missing activation parameters reject an activation quote', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
          onPost: (url, body) {
            if (url.endsWith('getaccountresource')) return <String, Object?>{};
            return {
              'chainParameter': [
                {'key': 'getTransactionFee', 'value': 1000},
              ],
            };
          },
        ),
      );

      expect(
        () => rpc.estimateBandwidthFee(
          owner: 'TOwner',
          rawDataLength: 100,
          activatesRecipient: true,
        ),
        throwsA(isA<RpcException>()),
      );
    });
  });
}
