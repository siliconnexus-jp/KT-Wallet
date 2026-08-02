import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/history_service.dart';

/// TronGrid history parsing: fixtures mirror the real response shapes of
/// `/v1/accounts/{addr}/transactions/trc20` (base58 addresses) and
/// `/v1/accounts/{addr}/transactions` (41-prefixed hex addresses).
///
/// The queried wallet is the well-known base58/hex pair
/// TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t ↔ 41a614f803b6fd780986a42c78ec9c7f77e6ded13c.
const _me = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _meHex = '41a614f803b6fd780986a42c78ec9c7f77e6ded13c';
const _other = 'TVjsyZ7fYF3qLF6BQgPmTEZy1xrNNyVAAA';
const _otherHex = '41b3dcf27c251da9363f1a4888257c16676cf54edf';

Map<String, Object?> _trc20Item({
  required String hash,
  required String from,
  required String to,
  required int ts,
  String value = '120500000',
  String symbol = 'USDT',
  int decimals = 6,
  String contract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
}) => {
  'transaction_id': hash,
  'token_info': {
    'symbol': symbol,
    'address': contract,
    'decimals': decimals,
    'name': 'Tether USD',
  },
  'block_timestamp': ts,
  'from': from,
  'to': to,
  'type': 'Transfer',
  'value': value,
};

Map<String, Object?> _nativeTransferItem({
  required String hash,
  required String ownerHex,
  required int ts,
  int amount = 5000000,
  String contractRet = 'SUCCESS',
}) => {
  'ret': [
    {'contractRet': contractRet, 'fee': 1100000},
  ],
  'signature': ['00'],
  'txID': hash,
  'net_usage': 0,
  'raw_data_hex': '0a02...',
  'net_fee': 100000,
  'energy_usage': 0,
  'blockNumber': 62000000,
  'block_timestamp': ts,
  'energy_fee': 0,
  'energy_usage_total': 0,
  'raw_data': {
    'contract': [
      {
        'parameter': {
          'value': {
            'amount': amount,
            'owner_address': ownerHex,
            'to_address': ownerHex == _meHex ? _otherHex : _meHex,
          },
          'type_url': 'type.googleapis.com/protocol.TransferContract',
        },
        'type': 'TransferContract',
      },
    ],
    'ref_block_bytes': 'ab12',
    'ref_block_hash': 'cd34ef56',
    'expiration': ts + 60000,
    'timestamp': ts,
  },
};

/// A TRC-20 transfer as it also appears in the native list (its
/// TriggerSmartContract wrapper) — must be skipped, not double-counted.
Map<String, Object?> _nativeTriggerItem({
  required String hash,
  required int ts,
}) => {
  'ret': [
    {'contractRet': 'SUCCESS'},
  ],
  'txID': hash,
  'block_timestamp': ts,
  'raw_data': {
    'contract': [
      {
        'parameter': {
          'value': {
            'data': 'a9059cbb...',
            'owner_address': _meHex,
            'contract_address': '41a614f803b6fd780986a42c78ec9c7f77e6ded13c',
          },
          'type_url': 'type.googleapis.com/protocol.TriggerSmartContract',
        },
        'type': 'TriggerSmartContract',
      },
    ],
  },
};

HistoryService _service({
  required Object? Function(http.Request request) body,
  Duration timeout = const Duration(seconds: 10),
}) => HistoryService(
  timeout: timeout,
  client: MockClient((request) async {
    final b = body(request);
    if (b is http.Response) return b;
    return http.Response(
      jsonEncode(b),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test('tronAddressHex decodes base58check to the 41-prefixed hex form', () {
    expect(tronAddressHex(_me), _meHex);
    expect(tronHexAddressToBase58(_meHex), _me);
    // Structurally invalid inputs (wrong length / bad alphabet) return null.
    // NOTE: the checksum is deliberately NOT verified — the hex form is only
    // used for direction comparison, so a right-length decode is enough.
    expect(tronAddressHex('Ta'), isNull);
    expect(tronAddressHex('0OIl'), isNull);
  });

  test(
    'TRON: parses TRC-20 + native fixtures, maps direction, merges newest first',
    () async {
      final service = _service(
        body: (request) {
          expect(request.method, 'GET');
          if (request.url.path.endsWith('/transactions/trc20')) {
            expect(request.url.path, '/v1/accounts/$_me/transactions/trc20');
            expect(request.url.queryParameters['limit'], '20');
            return {
              'data': [
                _trc20Item(
                  hash: 'tx-out-usdt',
                  from: _me,
                  to: _other,
                  ts: 3000,
                ),
                _trc20Item(
                  hash: 'tx-in-usdt',
                  from: _other,
                  to: _me,
                  ts: 1000,
                  value: '300000000',
                  symbol: 'USDT',
                ),
              ],
              'success': true,
              'meta': {'at': 1, 'page_size': 2},
            };
          }
          if (request.url.path.endsWith('/internal-transactions')) {
            return {'data': <Object?>[], 'success': true};
          }
          expect(request.url.path, '/v1/accounts/$_me/transactions');
          expect(request.url.queryParameters['limit'], '20');
          return {
            'data': [
              _nativeTransferItem(
                hash: 'tx-out-trx',
                ownerHex: _meHex,
                ts: 2000,
              ),
              _nativeTransferItem(
                hash: 'tx-in-trx-failed',
                ownerHex: '41b3dcf27c251da9363f1a4888257c16676cf54edf',
                ts: 500,
                amount: 1000000,
                contractRet: 'REVERT',
              ),
              // TRC-20 wrapper duplicate of tx-out-usdt: skipped (not a TransferContract).
              _nativeTriggerItem(hash: 'tx-out-usdt', ts: 3000),
            ],
            'success': true,
            'meta': {'at': 1, 'page_size': 3},
          };
        },
      );

      final result = await service.fetch(
        Coin.tron,
        _me,
        networkId: 'tron-nile',
      );
      expect(result.status, HistoryStatus.ok);
      expect(result.records.map((record) => record.networkId).toSet(), {
        'tron-nile',
      });
      // Merged newest-first; the TRC-20 wrapper is not a second transfer.
      expect(result.records.map((r) => r.hash), [
        'tx-out-usdt',
        'tx-out-trx',
        'tx-in-usdt',
        'tx-in-trx-failed',
      ]);

      final outUsdt = result.records[0];
      expect(outUsdt.outgoing, isTrue);
      expect(outUsdt.fromAddress, _me);
      expect(outUsdt.toAddress, _other);
      expect(outUsdt.amountText, '120.5 USDT');
      expect(outUsdt.assetSymbol, 'USDT');
      expect(outUsdt.assetContract, _me);
      expect(outUsdt.assetVerified, isTrue);
      expect(outUsdt.impersonatesProtectedSymbol, isFalse);
      expect(outUsdt.confirmed, isTrue);
      expect(outUsdt.timestamp, DateTime.fromMillisecondsSinceEpoch(3000));

      final outTrx = result.records[1];
      expect(outTrx.outgoing, isTrue); // owner_address (hex) == our address
      expect(outTrx.fromAddress, _me);
      expect(outTrx.toAddress, 'TSNEe5Tf4rnc9zPMNXfaTF5fZfHDDH8oyW');
      expect(outTrx.amountText, '5 TRX');
      expect(outTrx.confirmed, isTrue);

      final inUsdt = result.records[2];
      expect(inUsdt.outgoing, isFalse);
      expect(inUsdt.fromAddress, _other);
      expect(inUsdt.toAddress, _me);
      expect(inUsdt.amountText, '300 USDT');

      final inTrx = result.records[3];
      expect(inTrx.outgoing, isFalse); // someone else's owner_address
      expect(inTrx.fromAddress, 'TSNEe5Tf4rnc9zPMNXfaTF5fZfHDDH8oyW');
      expect(inTrx.toAddress, _me);
      expect(inTrx.amountText, '1 TRX');
      expect(inTrx.confirmed, isFalse); // contractRet REVERT
    },
  );

  test(
    'TRON direct fallback flags a lookalike contract claiming USDT',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/trc20')) {
            return {
              'data': [
                _trc20Item(
                  hash: 'spoof-usdt',
                  from: _other,
                  to: _me,
                  ts: 100,
                  contract: 'TFakeUSDTContract1111111111111111111',
                ),
              ],
            };
          }
          return {'data': <Object?>[]};
        },
      );

      final record = (await service.fetch(Coin.tron, _me)).records.single;
      expect(record.amountText, '120.5 USDT');
      expect(record.assetSymbol, 'USDT');
      expect(record.assetContract, 'TFakeUSDTContract1111111111111111111');
      expect(record.assetVerified, isFalse);
      expect(record.impersonatesProtectedSymbol, isTrue);
    },
  );

  test(
    'TRON: unparseable token amount yields a null amountText, not a crash',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/trc20')) {
            final item = _trc20Item(
              hash: 'tx-weird',
              from: _other,
              to: _me,
              ts: 100,
            );
            item['value'] = 'not-a-number';
            return {
              'data': [item],
              'success': true,
            };
          }
          return {'data': <Object?>[], 'success': true};
        },
      );
      final result = await service.fetch(Coin.tron, _me);
      expect(result.status, HistoryStatus.ok);
      expect(result.records.single.amountText, isNull);
    },
  );

  test(
    'TRON: empty data lists are a real (empty) history, not an error',
    () async {
      final service = _service(
        body: (_) => {'data': <Object?>[], 'success': true},
      );
      final result = await service.fetch(Coin.tron, _me);
      expect(result.status, HistoryStatus.ok);
      expect(result.records, isEmpty);
    },
  );

  test('Ethereum / Polygon / Solana use direct public history APIs', () async {
    final service = _service(
      body: (request) {
        if (request.url.host.contains('blockscout')) {
          return {'status': '1', 'message': 'OK', 'result': <Object?>[]};
        }
        return {'jsonrpc': '2.0', 'id': 1, 'result': <Object?>[]};
      },
    );
    for (final coin in [Coin.eth, Coin.polygon, Coin.solana]) {
      final result = await service.fetch(coin, '0xabc');
      expect(result.status, HistoryStatus.ok, reason: '$coin');
      expect(result.records, isEmpty);
    }
  });

  test('Avalanche direct history includes native internal receipts', () async {
    final actions = <String>[];
    final service = HistoryService(
      endpoints: (coin) => coin == Coin.avalanche
          ? 'https://api.avax-test.network/ext/bc/C/rpc'
          : '',
      client: MockClient((request) async {
        final action = request.url.queryParameters['action']!;
        actions.add(action);
        final result = action == 'txlistinternal'
            ? [
                {
                  'hash': '0xairdrop',
                  'traceId': '0_1',
                  'from': '0x1111111111111111111111111111111111111111',
                  'to': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'value': '5000000000000000',
                  'timeStamp': '1700000100',
                  'isError': '0',
                },
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(
      Coin.avalanche,
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(actions, ['txlist', 'tokentx', 'txlistinternal']);
    expect(result.status, HistoryStatus.ok);
    expect(result.records, hasLength(1));
    expect(result.records.single.id, '0xairdrop:internal:0_1');
    expect(result.records.single.outgoing, isFalse);
    expect(
      result.records.single.fromAddress,
      '0x1111111111111111111111111111111111111111',
    );
    expect(
      result.records.single.toAddress,
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(result.records.single.amountText, '0.005 AVAX');
  });

  test(
    'EVM direct history includes ERC-20 events with verified metadata',
    () async {
      const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          final result = action == 'tokentx'
              ? [
                  {
                    'hash': '0xtoken',
                    'logIndex': '3',
                    'from': '0x1111111111111111111111111111111111111111',
                    'to': address,
                    'value': '2500000',
                    'timeStamp': '1700000200',
                    'tokenDecimal': '18',
                    'tokenSymbol': 'FAKE',
                    'contractAddress':
                        '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                    'isError': '0',
                  },
                ]
              : <Object?>[];
          return http.Response(
            jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
            200,
          );
        }),
      );

      final record = (await service.fetch(Coin.eth, address)).records.single;
      expect(record.id, contains(':token:'));
      expect(record.amountText, '2.5 USDT');
      expect(record.assetSymbol, 'USDT');
      expect(record.assetVerified, isTrue);
      expect(record.outgoing, isFalse);
      expect(record.fromAddress, '0x1111111111111111111111111111111111111111');
      expect(record.toAddress, address);
    },
  );

  test(
    'Solana direct history finds an incoming SPL transfer through its ATA',
    () async {
      const owner = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';
      const ata = 'Ata111111111111111111111111111111111111111';
      const sender = '4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT';
      const senderAta = 'Ata222222222222222222222222222222222222222';
      const mint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
      final service = HistoryService(
        endpoints: (_) => 'https://api.mainnet-beta.solana.com',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final method = payload['method'];
          final params = payload['params'] as List<dynamic>;
          final Object? result;
          if (method == 'getTokenAccountsByOwner') {
            result = {
              'value': [
                {'pubkey': ata},
              ],
            };
          } else if (method == 'getSignaturesForAddress') {
            result = params.first == ata
                ? [
                    {
                      'signature': 'ata-signature',
                      'blockTime': 1700000300,
                      'err': null,
                    },
                  ]
                : <Object?>[];
          } else if (method == 'getTransaction') {
            result = {
              'meta': {
                'err': null,
                'preBalances': [100, 100],
                'postBalances': [100, 100],
                'preTokenBalances': [
                  {
                    'accountIndex': 0,
                    'mint': mint,
                    'owner': sender,
                    'uiTokenAmount': {'amount': '3000000', 'decimals': 6},
                  },
                  {
                    'accountIndex': 1,
                    'mint': mint,
                    'owner': owner,
                    'uiTokenAmount': {'amount': '1000000', 'decimals': 6},
                  },
                ],
                'postTokenBalances': [
                  {
                    'accountIndex': 0,
                    'mint': mint,
                    'owner': sender,
                    'uiTokenAmount': {'amount': '1000000', 'decimals': 6},
                  },
                  {
                    'accountIndex': 1,
                    'mint': mint,
                    'owner': owner,
                    'uiTokenAmount': {'amount': '3000000', 'decimals': 6},
                  },
                ],
              },
              'transaction': {
                'message': {
                  // The wallet owner is deliberately absent; only its ATA was
                  // touched by this incoming token transfer.
                  'accountKeys': [
                    {'pubkey': senderAta},
                    {'pubkey': ata},
                  ],
                  'instructions': [
                    {
                      'program': 'spl-token',
                      'parsed': {
                        'type': 'transfer',
                        'info': {
                          'source': senderAta,
                          'destination': ata,
                          'authority': sender,
                        },
                      },
                    },
                  ],
                },
              },
            };
          } else {
            fail('unexpected Solana RPC method $method');
          }
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}),
            200,
          );
        }),
      );

      final record = (await service.fetch(Coin.solana, owner)).records.single;
      expect(record.hash, 'ata-signature');
      expect(record.outgoing, isFalse);
      expect(record.fromAddress, sender);
      expect(record.toAddress, owner);
      expect(record.amountText, '2 USDC');
      expect(record.assetContract, mint);
      expect(record.assetVerified, isTrue);
    },
  );

  test(
    'TRON direct history includes TRC-10 and internal TRX receipts',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/transactions/trc20')) {
            return {'data': <Object?>[]};
          }
          if (request.url.path.endsWith('/internal-transactions')) {
            return {
              'data': [
                {
                  'tx_id': 'parent',
                  'internal_tx_id': 'trace-1',
                  'from_address': '41b3dcf27c251da9363f1a4888257c16676cf54edf',
                  'to_address': _meHex,
                  'block_timestamp': 3000,
                  'data': {
                    'rejected': false,
                    'call_value': {'_': '2500000'},
                  },
                },
              ],
            };
          }
          final trc10 = _nativeTransferItem(
            hash: 'trc10',
            ownerHex: _meHex,
            ts: 2000,
            amount: 42,
          );
          final contract =
              ((trc10['raw_data'] as Map)['contract'] as List).first as Map;
          contract['type'] = 'TransferAssetContract';
          ((contract['parameter'] as Map)['value'] as Map)['asset_name'] =
              '1002000';
          return {
            'data': [trc10],
          };
        },
      );

      final records = (await service.fetch(Coin.tron, _me)).records;
      expect(records.map((record) => record.id), [
        'parent:internal:trace-1',
        'trc10:trc10:1002000',
      ]);
      expect(records.first.amountText, '2.5 TRX');
      expect(records.last.amountText, '42 TRC10');
      expect(records.last.assetVerified, isFalse);
    },
  );

  test(
    'a 400 for an invalid (demo mock) address surfaces as error status',
    () async {
      final service = _service(
        body: (_) => http.Response('{"success":false,"error":"bad addr"}', 400),
      );
      final result = await service.fetch(Coin.tron, 'Ta');
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test(
    'one failing endpoint of the pair collapses to error (never partial-as-live)',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/trc20')) {
            return {'data': <Object?>[], 'success': true};
          }
          return http.Response('server error', 500);
        },
      );
      expect((await service.fetch(Coin.tron, _me)).status, HistoryStatus.error);
    },
  );

  test('timeout surfaces as error status (never throws)', () async {
    final service = HistoryService(
      timeout: const Duration(milliseconds: 1),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('{"data":[]}', 200);
      }),
    );
    expect((await service.fetch(Coin.tron, _me)).status, HistoryStatus.error);
  });

  test('malformed body surfaces as error status', () async {
    final service = _service(body: (_) => http.Response('not json', 200));
    expect((await service.fetch(Coin.tron, _me)).status, HistoryStatus.error);
  });
}
