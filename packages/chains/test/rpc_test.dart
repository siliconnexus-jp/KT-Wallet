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

Map<String, Object?> _ok(Object? result) =>
    {'jsonrpc': '2.0', 'id': 1, 'result': result};

void main() {
  group('EvmRpc', () {
    test('getBalance parses a hex quantity', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok('0x0de0b6b3a7640000')),
      );
      expect(await rpc.getBalance('0xabc'), BigInt.parse('1000000000000000000'));
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
          '0xcontract', '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
      expect(bal, BigInt.from(100000000));
      final call = params[0] as Map;
      expect(call['data'], startsWith('0x70a08231'));
    });

    test('feeHistory yields slow<=standard<=fast tiers', () async {
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok({
              'baseFeePerGas': ['0x64', '0x64'], // 100
              'reward': [
                ['0x1', '0x2', '0x3'],
                ['0x1', '0x2', '0x3'],
              ],
            })),
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
        transport: FakeJsonRpc((m, p) => {
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32000, 'message': 'nonce too low'},
            }),
      );
      expect(
        () => rpc.getNonce('0xabc'),
        throwsA(isA<RpcException>()
            .having((e) => e.code, 'code', -32000)),
      );
    });

    test('non-hex quantity throws instead of returning garbage', () async {
      final rpc = EvmRpc(url: 'x', transport: FakeJsonRpc((m, p) => _ok('123')));
      expect(() => rpc.getBalance('0xabc'), throwsA(isA<RpcException>()));
    });

    test('malformed feeHistory throws RpcException, not an untyped error',
        () async {
      // Missing reward field.
      final rpc = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok({'baseFeePerGas': ['0x1']})),
      );
      expect(() => rpc.estimateFees(), throwsA(isA<RpcException>()));

      // Short reward row.
      final rpc2 = EvmRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok({
              'baseFeePerGas': ['0x1'],
              'reward': [
                ['0x1']
              ],
            })),
      );
      expect(() => rpc2.estimateFees(), throwsA(isA<RpcException>()));
    });
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
        transport: FakeJsonRpc((m, p) => _ok({
              'value': {'blockhash': 'HASH123', 'lastValidBlockHeight': 100}
            })),
      );
      expect(await rpc.getLatestBlockhash(), 'HASH123');
    });

    test('signatureStatus null when unknown', () async {
      final rpc = SolanaRpc(
        url: 'x',
        transport: FakeJsonRpc((m, p) => _ok({
              'value': [null]
            })),
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
      expect(
        transport.requests.map((request) => request['method']),
        ['getFeeForMessage', 'simulateTransaction'],
      );
    });
  });

  group('TronRpc', () {
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
        transport: FakeRest(onGet: (u) => {
              'data': [
                {'balance': 1420000000}
              ]
            }),
      );
      expect(await rpc.getTrxBalance('Tabc'), BigInt.from(1420000000));
    });

    test('broadcast returns txid on success', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(onPost: (u, b) => {'result': true, 'txid': 'abc123'}),
      );
      expect(await rpc.broadcast({'raw': 'x'}), 'abc123');
    });

    test('broadcast throws on rejection (not silently retried)', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(
            onPost: (u, b) => {'result': false, 'message': 'TAPOS error'}),
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

    test('a full transaction JSON still goes to broadcasttransaction', () async {
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
    });

    // TronGrid answers node-level failures with a top-level `Error` and no
    // `code`/`message`; reading only the latter reported "rejected: null".
    test('a top-level Error is surfaced, never swallowed as null', () async {
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
            contains('NullPointerException'),
          ),
        ),
      );
    });

    test('a reasonless rejection says so instead of printing null', () async {
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
            allOf(contains('no reason given'), isNot(contains('null'))),
          ),
        ),
      );
    });

    test('malformed balance is an error, not a silent zero', () async {
      final rpc = TronRpc(
        baseUrl: 'https://api',
        transport: FakeRest(onGet: (u) => {
              'data': [
                {'balance': 'oops'}
              ]
            }),
      );
      expect(() => rpc.getTrxBalance('Tabc'), throwsA(isA<RpcException>()));
    });

    test('TRC-20 fee limit comes from energy, resources and chain price',
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
    });
  });
}
