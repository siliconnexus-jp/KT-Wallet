import 'dart:typed_data';

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
const _tronHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherTronHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

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
        transport: FakeJsonRpc((m, p) => _ok('0x0de0b6b3a7640000')),
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
          return _ok('0x05f5e100'); // 100_000_000
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

    test('spendable balance reads use the pending block tag', () async {
      final transport = FakeJsonRpc((method, params) {
        if (method == 'eth_getBalance') return _ok('0x2a');
        if (method == 'eth_call') return _ok('0x64');
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
            'baseFeePerGas': ['0x64', '0x64'], // 100
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
      expect(fees.slow.maxFeePerGas, BigInt.from(101));
      expect(fees.fast.maxFeePerGas, BigInt.from(103));
    });

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
        () => rpc.getNonce('0xabc'),
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
        await rpc.getNonce('0xabc');
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

    test('non-hex quantity throws instead of returning garbage', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok('123')),
      );
      expect(() => rpc.getBalance('0xabc'), throwsA(isA<RpcException>()));
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
    test('getBalance reads value from result map', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok({'value': 42})),
      );
      expect(await rpc.getBalance('addr'), BigInt.from(42));
    });

    test('getLatestBlockhash extracts nested blockhash', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok({
            'value': {'blockhash': 'HASH123', 'lastValidBlockHeight': 100},
          }),
        ),
      );
      expect(await rpc.getLatestBlockhash(), 'HASH123');
      final latest = await rpc.getLatestBlockhashInfo();
      expect(latest.blockhash, 'HASH123');
      expect(latest.lastValidBlockHeight, 100);
    });

    test('getBlockHeight requires a non-negative canonical height', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok(123456)),
      );
      expect(await rpc.getBlockHeight(), 123456);
    });

    test('signatureStatus null when unknown', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc(
          (m, p) => _ok({
            'value': [null],
          }),
        ),
      );
      expect(await rpc.signatureStatus('sig'), isNull);
    });

    test('fee and simulation use the exact serialized message', () async {
      final transport = FakeJsonRpc((method, params) {
        if (method == 'getFeeForMessage') return _ok({'value': 5000});
        if (method == 'simulateTransaction') {
          return _ok({
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
            'value': {
              'err': null,
              'accounts': [
                {'lamports': 12345},
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
