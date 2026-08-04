import 'dart:convert';

import 'package:chains/chains.dart' show Amount, solanaTokenProgram;
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
const _tronBurn = 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb';
const _tronHashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _tronHashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _tronHashC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _tronHashD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _tronTrace =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _solanaOwner = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';
const _solanaRecipient = '4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT';
const _solanaAta = 'BGocb4GEpbTFm8UFV2VsDSaBXHELPfAXrvd4vtt8QWrA';
const _solanaSenderAta = 'A1TMhSGzQxMr1TboBKtgixKz1sS6REASMxPo1qsyTSJd';
const _solanaSignature =
    '5h6xBEauJ3PK6SWCZ1PGjBvj8vDdWG3KpwATGy1ARAXFSDwt8GFXM7W5Ncn16wmqokgpiKRLuS83KUxyZyv2sUYv';
const _solanaOtherSignature =
    '4ReKprwf3WdLHRrzp4ctPWNBsQDPL3VZz3zMmoZfcGJMJCHh5Vq937mPdyxhCbw54wNnA6hZ7KfNpQdpt13yY7A9';
const _evmOwner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _evmOther = '0x1111111111111111111111111111111111111111';
const _evmHash =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _emptyExplorerEnvelope() => {
  'status': '1',
  'message': 'OK',
  'result': <Object?>[],
};

Map<String, Object?> _validEvmNormalItem({
  String hash = _evmHash,
  String from = _evmOther,
  String to = _evmOwner,
  String value = '1',
}) => {
  'hash': hash,
  'from': from,
  'to': to,
  'value': value,
  'timeStamp': '1700000000',
  'isError': '0',
  'txreceipt_status': '1',
};

Map<String, Object?> _solanaEmptyTokenAccounts() => {
  'context': {'slot': 114},
  'value': <Object?>[],
};

List<Object?> _solanaSignatureRows() => [
  {
    'signature': _solanaSignature,
    'slot': 114,
    'err': null,
    'memo': null,
    'blockTime': 1700000500,
    'confirmationStatus': 'confirmed',
    'transactionIndex': 4,
  },
];

Map<String, Object?> _solanaNativeTransaction({
  int slot = 114,
  List<Object?>? signatures,
  bool includeTransfer = true,
}) => {
  'blockTime': 1700000500,
  'slot': slot,
  'transactionIndex': 4,
  'version': 'legacy',
  'meta': {
    'err': null,
    'fee': 5000,
    'preBalances': [2000000000, 0],
    'postBalances': [999995000, 1000000000],
    'preTokenBalances': <Object?>[],
    'postTokenBalances': <Object?>[],
  },
  'transaction': {
    'message': {
      'accountKeys': [_solanaOwner, _solanaRecipient],
      'instructions': includeTransfer
          ? [
              {
                'program': 'system',
                'parsed': {
                  'type': 'transfer',
                  'info': {
                    'source': _solanaOwner,
                    'destination': _solanaRecipient,
                    'lamports': 1000000000,
                  },
                },
              },
            ]
          : <Object?>[],
    },
    'signatures': signatures ?? [_solanaSignature],
  },
};

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
    // Wrong length, alphabet, or Base58Check checksum return null.
    expect(tronAddressHex('Ta'), isNull);
    expect(tronAddressHex('0OIl'), isNull);
    expect(tronAddressHex('${_me.substring(0, _me.length - 1)}m'), isNull);
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
            expect(request.url.queryParameters['only_confirmed'], 'true');
            return {
              'data': [
                _trc20Item(hash: _tronHashA, from: _me, to: _other, ts: 3000),
                _trc20Item(
                  hash: _tronHashB,
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
            expect(request.url.queryParameters['only_confirmed'], 'true');
            return {'data': <Object?>[], 'success': true};
          }
          expect(request.url.path, '/v1/accounts/$_me/transactions');
          expect(request.url.queryParameters['limit'], '20');
          expect(request.url.queryParameters['only_confirmed'], 'true');
          return {
            'data': [
              _nativeTransferItem(hash: _tronHashC, ownerHex: _meHex, ts: 2000),
              _nativeTransferItem(
                hash: _tronHashD,
                ownerHex: '41b3dcf27c251da9363f1a4888257c16676cf54edf',
                ts: 500,
                amount: 1000000,
                contractRet: 'REVERT',
              ),
              // TRC-20 wrapper duplicate of tx-out-usdt: skipped (not a TransferContract).
              _nativeTriggerItem(hash: _tronHashA, ts: 3000),
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
        _tronHashA,
        _tronHashC,
        _tronHashB,
        _tronHashD,
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
      expect(
        outUsdt.timestamp,
        DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
      );

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
                  hash: _tronHashA,
                  from: _other,
                  to: _me,
                  ts: 100,
                  contract: _tronBurn,
                ),
              ],
              'success': true,
            };
          }
          return {'data': <Object?>[], 'success': true};
        },
      );

      final record = (await service.fetch(Coin.tron, _me)).records.single;
      expect(record.amountText, '120.5 USDT');
      expect(record.assetSymbol, 'USDT');
      expect(record.assetContract, _tronBurn);
      expect(record.assetVerified, isFalse);
      expect(record.impersonatesProtectedSymbol, isTrue);
    },
  );

  test(
    'TRON keeps native movement sharing a hash with a TRC-20 event',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/transactions/trc20')) {
            return {
              'data': [
                _trc20Item(
                  hash: _tronHashA,
                  from: _other,
                  to: _me,
                  ts: 1700000000000,
                ),
              ],
              'success': true,
            };
          }
          if (request.url.path.endsWith('/internal-transactions')) {
            return {'data': <Object?>[], 'success': true};
          }
          return {
            'data': [
              _nativeTransferItem(
                hash: _tronHashA,
                ownerHex: _meHex,
                ts: 1700000000000,
              ),
            ],
            'success': true,
          };
        },
      );

      final result = await service.fetch(Coin.tron, _me);
      expect(result.status, HistoryStatus.ok);
      expect(result.records, hasLength(2));
      expect(result.records.map((record) => record.assetSymbol), {
        'USDT',
        null,
      });
    },
  );

  test(
    'TRON: unparseable token amount fails closed, not partial history',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/trc20')) {
            final item = _trc20Item(
              hash: _tronHashA,
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
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
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
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final result = payload['method'] == 'getTokenAccountsByOwner'
            ? {
                'context': {'slot': 114},
                'value': <Object?>[],
              }
            : <Object?>[];
        return {'jsonrpc': '2.0', 'id': payload['id'], 'result': result};
      },
    );
    for (final coin in [Coin.eth, Coin.polygon, Coin.solana]) {
      final result = await service.fetch(
        coin,
        coin == Coin.solana ? _solanaOwner : _evmOwner,
      );
      expect(result.status, HistoryStatus.ok, reason: '$coin');
      expect(result.records, isEmpty);
    }
  });

  test('Solana direct history rejects a stale JSON-RPC response id', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://api.mainnet-beta.solana.com',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 2, 'result': <Object?>[]}),
          200,
        ),
      ),
    );

    final result = await service.fetch(Coin.solana, _solanaOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test(
    'Solana direct history rejects a signature row without its canonical slot',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://api.mainnet-beta.solana.com',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final result = switch (payload['method']) {
            'getTokenAccountsByOwner' => {
              'context': {'slot': 114},
              'value': <Object?>[],
            },
            'getSignaturesForAddress' => [
              {
                'signature': _solanaSignature,
                'err': null,
                'memo': null,
                'blockTime': 1700000500,
                'confirmationStatus': 'confirmed',
              },
            ],
            'getTransaction' => {
              'meta': {
                'err': null,
                'preBalances': [2000000000, 0],
                'postBalances': [1000000000, 1000000000],
                'preTokenBalances': <Object?>[],
                'postTokenBalances': <Object?>[],
              },
              'transaction': {
                'message': {
                  'accountKeys': [_solanaOwner, _solanaRecipient],
                  'instructions': [
                    {
                      'program': 'system',
                      'parsed': {
                        'type': 'transfer',
                        'info': {
                          'source': _solanaOwner,
                          'destination': _solanaRecipient,
                          'lamports': 1000000000,
                        },
                      },
                    },
                  ],
                },
              },
            },
            _ => fail('unexpected Solana RPC method ${payload['method']}'),
          };
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': payload['id'],
              'result': result,
            }),
            200,
          );
        }),
      );

      final result = await service.fetch(Coin.solana, _solanaOwner);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test('Solana direct history rejects an invalid transaction index', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://api.mainnet-beta.solana.com',
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final result = switch (payload['method']) {
          'getTokenAccountsByOwner' => _solanaEmptyTokenAccounts(),
          'getSignaturesForAddress' => [
            {..._solanaSignatureRows().single as Map, 'transactionIndex': -1},
          ],
          _ => fail('unexpected Solana RPC method ${payload['method']}'),
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': payload['id'], 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.solana, _solanaOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test(
    'Solana fee-only balance movement is not displayed as a transfer',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://api.mainnet-beta.solana.com',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final result = switch (payload['method']) {
            'getTokenAccountsByOwner' => {
              'context': {'slot': 114},
              'value': <Object?>[],
            },
            'getSignaturesForAddress' => [
              {
                'signature': _solanaSignature,
                'slot': 114,
                'err': null,
                'memo': null,
                'blockTime': 1700000500,
                'confirmationStatus': 'confirmed',
              },
            ],
            'getTransaction' => {
              'blockTime': 1700000500,
              'slot': 114,
              'version': 'legacy',
              'meta': {
                'err': null,
                'fee': 5000,
                'preBalances': [2000000000, 0],
                'postBalances': [1999995000, 0],
                'preTokenBalances': <Object?>[],
                'postTokenBalances': <Object?>[],
              },
              'transaction': {
                'message': {
                  'accountKeys': [_solanaOwner, _solanaRecipient],
                  'instructions': <Object?>[],
                },
                'signatures': [_solanaSignature],
              },
            },
            _ => fail('unexpected Solana RPC method ${payload['method']}'),
          };
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': payload['id'],
              'result': result,
            }),
            200,
          );
        }),
      );

      final result = await service.fetch(Coin.solana, _solanaOwner);
      expect(result.status, HistoryStatus.ok);
      expect(result.records, isEmpty);
    },
  );

  test('Solana native history excludes the network fee from amount', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://api.mainnet-beta.solana.com',
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final result = switch (payload['method']) {
          'getTokenAccountsByOwner' => _solanaEmptyTokenAccounts(),
          'getSignaturesForAddress' => _solanaSignatureRows(),
          'getTransaction' => _solanaNativeTransaction(),
          _ => fail('unexpected Solana RPC method ${payload['method']}'),
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': payload['id'], 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.solana, _solanaOwner);
    expect(result.status, HistoryStatus.ok);
    final record = result.records.single;
    expect(record.hash, _solanaSignature);
    expect(record.amountText, '1 SOL');
    expect(record.fromAddress, _solanaOwner);
    expect(record.toAddress, _solanaRecipient);
    expect(record.status, ChainTxStatus.confirmed);
  });

  test(
    'Solana direct history binds transaction slot and queried signature',
    () async {
      final invalidTransactions = <Map<String, Object?>>[
        _solanaNativeTransaction(slot: 115),
        _solanaNativeTransaction(signatures: [_solanaOtherSignature]),
      ];
      for (final transaction in invalidTransactions) {
        final service = HistoryService(
          endpoints: (_) => 'https://api.mainnet-beta.solana.com',
          client: MockClient((request) async {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            final result = switch (payload['method']) {
              'getTokenAccountsByOwner' => _solanaEmptyTokenAccounts(),
              'getSignaturesForAddress' => _solanaSignatureRows(),
              'getTransaction' => transaction,
              _ => fail('unexpected Solana RPC method ${payload['method']}'),
            };
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': payload['id'],
                'result': result,
              }),
              200,
            );
          }),
        );

        final result = await service.fetch(Coin.solana, _solanaOwner);
        expect(result.status, HistoryStatus.error, reason: '$transaction');
        expect(result.records, isEmpty);
      }
    },
  );

  test(
    'Solana direct history validates the owner before network access',
    () async {
      var requests = 0;
      final service = HistoryService(
        endpoints: (_) => 'https://api.mainnet-beta.solana.com',
        client: MockClient((request) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );

      final result = await service.fetch(Coin.solana, 'not-a-public-key');
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
      expect(requests, 0);
    },
  );

  test(
    'EVM direct history validates the owner before network access',
    () async {
      var requests = 0;
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          requests += 1;
          return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
        }),
      );

      final result = await service.fetch(Coin.eth, '0xnot-an-address');
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
      expect(requests, 0);
    },
  );

  test('EVM direct history rejects ambiguous explorer envelopes', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        if (request.url.queryParameters['action'] == 'txlist') {
          return http.Response(
            '{"status":"1","message":"OK","result":[],"Result":[]}',
            200,
          );
        }
        return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('EVM direct history rejects duplicate JSON members', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        if (request.url.queryParameters['action'] == 'txlist') {
          return http.Response(
            '{"status":"0","status":"1","message":"OK","result":[]}',
            200,
          );
        }
        return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('EVM direct history rejects unknown transaction fields', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        final result = request.url.queryParameters['action'] == 'txlist'
            ? [
                {..._validEvmNormalItem(), 'Hash': _evmHash},
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('EVM direct history rejects rows not bound to the owner', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        final result = request.url.queryParameters['action'] == 'txlist'
            ? [
                _validEvmNormalItem(
                  from: '0x2222222222222222222222222222222222222222',
                  to: '0x3333333333333333333333333333333333333333',
                ),
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('EVM direct history rejects responses larger than requested', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        final result = request.url.queryParameters['action'] == 'txlist'
            ? [
                _validEvmNormalItem(),
                _validEvmNormalItem(
                  hash:
                      '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                ),
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner, limit: 1);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test(
    'EVM direct history rejects malformed rows instead of reporting empty',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          if (action != 'txlist') {
            return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
          }
          return http.Response(
            jsonEncode({
              'status': '1',
              'message': 'OK',
              'result': [
                {
                  'hash': '0xshort',
                  'from': _evmOther,
                  'to': _evmOwner,
                  'value': '-1',
                  'timeStamp': '1700000000',
                  'isError': '0',
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.fetch(Coin.eth, _evmOwner);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test(
    'EVM direct history fails closed when internal history is unavailable',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          if (request.url.queryParameters['action'] == 'txlistinternal') {
            return http.Response('upstream unavailable', 503);
          }
          return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
        }),
      );

      final result = await service.fetch(Coin.eth, _evmOwner);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test(
    'EVM direct history rejects explicitly incomplete internal indexes',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          if (request.url.queryParameters['action'] == 'txlistinternal') {
            return http.Response(
              jsonEncode({
                'status': '2',
                'message':
                    'Some internal transactions within this block range have not yet been processed',
                'result': <Object?>[],
              }),
              200,
            );
          }
          return http.Response(jsonEncode(_emptyExplorerEnvelope()), 200);
        }),
      );

      final result = await service.fetch(Coin.eth, _evmOwner);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

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
                  // Blockscout uses these names for internal transactions;
                  // Etherscan uses hash/traceId for the same concepts.
                  'transactionHash': _evmHash,
                  'index': '0_1',
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
    expect(result.records.single.id, '$_evmHash:internal:0_1');
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
    expect(result.records.single.status, ChainTxStatus.confirmed);
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
                    'hash': _evmHash,
                    'logIndex': '3',
                    'from': '0x1111111111111111111111111111111111111111',
                    'to': address,
                    'value': '2500000',
                    'timeStamp': '1700000200',
                    'tokenDecimal': '6',
                    'tokenSymbol': 'FAKE',
                    'contractAddress':
                        '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                    // Official tokentx rows are successful receipt events and
                    // expose canonical block evidence, not execution flags.
                    'blockNumber': '4730207',
                    'blockHash':
                        '0x022c5e6a3d2487a8ccf8946a2ffb74938bf8e5c8a3f6d91b41c56378a96b5c37',
                    'transactionIndex': '81',
                    'confirmations': '1',
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
      expect(record.status, ChainTxStatus.confirmed);
    },
  );

  test('EVM direct history rejects official-token decimals mismatch', () async {
    final service = HistoryService(
      endpoints: (_) => 'https://rpc.ankr.com/eth',
      client: MockClient((request) async {
        final result = request.url.queryParameters['action'] == 'tokentx'
            ? [
                {
                  'hash': _evmHash,
                  'from': _evmOther,
                  'to': _evmOwner,
                  'value': '2500000',
                  'timeStamp': '1700000200',
                  'tokenDecimal': '18',
                  'tokenSymbol': 'USDT',
                  'contractAddress':
                      '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                  'blockNumber': '4730207',
                  'blockHash':
                      '0x022c5e6a3d2487a8ccf8946a2ffb74938bf8e5c8a3f6d91b41c56378a96b5c37',
                  'transactionIndex': '81',
                  'confirmations': '1',
                },
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.eth, _evmOwner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test(
    'EVM direct history rejects token decimals the UI cannot render',
    () async {
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          final result = request.url.queryParameters['action'] == 'tokentx'
              ? [
                  {
                    'hash': _evmHash,
                    'from': _evmOther,
                    'to': _evmOwner,
                    'value': '1',
                    'timeStamp': '1700000200',
                    'tokenDecimal': '${Amount.maxDecimals + 1}',
                    'tokenSymbol': 'CUSTOM',
                    'contractAddress':
                        '0x2222222222222222222222222222222222222222',
                    'blockNumber': '4730207',
                    'blockHash':
                        '0x022c5e6a3d2487a8ccf8946a2ffb74938bf8e5c8a3f6d91b41c56378a96b5c37',
                    'transactionIndex': '81',
                    'confirmations': '1',
                  },
                ]
              : <Object?>[];
          return http.Response(
            jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
            200,
          );
        }),
      );

      final result = await service.fetch(Coin.eth, _evmOwner);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test(
    'EVM token event without canonical block evidence fails closed',
    () async {
      const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          final result = request.url.queryParameters['action'] == 'tokentx'
              ? [
                  {
                    'hash': _evmHash,
                    'from': address,
                    'to': '0x1111111111111111111111111111111111111111',
                    'value': '1',
                    'timeStamp': '1700000200',
                    'tokenDecimal': '6',
                    'tokenSymbol': 'TEST',
                    'contractAddress':
                        '0x2222222222222222222222222222222222222222',
                  },
                ]
              : <Object?>[];
          return http.Response(
            jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
            200,
          );
        }),
      );

      final result = await service.fetch(Coin.eth, address);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test(
    'Solana direct history finds an incoming SPL transfer through its ATA',
    () async {
      const owner = _solanaOwner;
      const ata = _solanaAta;
      const sender = _solanaRecipient;
      const senderAta = _solanaSenderAta;
      const mint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
      final rpcIds = <Object?>[];
      final service = HistoryService(
        endpoints: (_) => 'https://api.mainnet-beta.solana.com',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          rpcIds.add(payload['id']);
          final method = payload['method'];
          final params = payload['params'] as List<dynamic>;
          final Object? result;
          if (method == 'getTokenAccountsByOwner') {
            final program = (params[1] as Map)['programId'];
            result = {
              'context': {'slot': 114},
              'value': program == solanaTokenProgram
                  ? [
                      {
                        'pubkey': ata,
                        'account': {
                          'data': {
                            'program': 'spl-token',
                            'parsed': {
                              'info': {
                                'isNative': false,
                                'mint': mint,
                                'owner': owner,
                                'state': 'initialized',
                                'tokenAmount': {
                                  'amount': '1000000',
                                  'decimals': 6,
                                  'uiAmount': 1,
                                  'uiAmountString': '1',
                                },
                              },
                              'type': 'account',
                            },
                            'space': 165,
                          },
                          'executable': false,
                          'lamports': 2039280,
                          'owner': solanaTokenProgram,
                          'rentEpoch': 1,
                          'space': 165,
                        },
                      },
                    ]
                  : <Object?>[],
            };
          } else if (method == 'getSignaturesForAddress') {
            result = params.first == ata
                ? [
                    {
                      'signature': _solanaSignature,
                      'slot': 114,
                      'blockTime': 1700000300,
                      'err': null,
                      'memo': null,
                      'confirmationStatus': 'confirmed',
                    },
                  ]
                : <Object?>[];
          } else if (method == 'getTransaction') {
            result = {
              'blockTime': 1700000300,
              'slot': 114,
              'version': 'legacy',
              'meta': {
                'err': null,
                'fee': 5000,
                'preBalances': [100, 100],
                'postBalances': [100, 100],
                'preTokenBalances': [
                  {
                    'accountIndex': 0,
                    'mint': mint,
                    'owner': sender,
                    'programId': solanaTokenProgram,
                    'uiTokenAmount': {
                      'amount': '3000000',
                      'decimals': 6,
                      'uiAmount': 3,
                      'uiAmountString': '3',
                    },
                  },
                  {
                    'accountIndex': 1,
                    'mint': mint,
                    'owner': owner,
                    'programId': solanaTokenProgram,
                    'uiTokenAmount': {
                      'amount': '1000000',
                      'decimals': 6,
                      'uiAmount': 1,
                      'uiAmountString': '1',
                    },
                  },
                ],
                'postTokenBalances': [
                  {
                    'accountIndex': 0,
                    'mint': mint,
                    'owner': sender,
                    'programId': solanaTokenProgram,
                    'uiTokenAmount': {
                      'amount': '1000000',
                      'decimals': 6,
                      'uiAmount': 1,
                      'uiAmountString': '1',
                    },
                  },
                  {
                    'accountIndex': 1,
                    'mint': mint,
                    'owner': owner,
                    'programId': solanaTokenProgram,
                    'uiTokenAmount': {
                      'amount': '3000000',
                      'decimals': 6,
                      'uiAmount': 3,
                      'uiAmountString': '3',
                    },
                  },
                ],
              },
              'transaction': {
                'message': {
                  // The wallet owner is deliberately absent; only its ATA was
                  // touched by this incoming token transfer.
                  'accountKeys': [senderAta, ata],
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
                'signatures': [_solanaSignature],
              },
            };
          } else {
            fail('unexpected Solana RPC method $method');
          }
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': payload['id'],
              'result': result,
            }),
            200,
          );
        }),
      );

      final record = (await service.fetch(Coin.solana, owner)).records.single;
      expect(record.hash, _solanaSignature);
      expect(record.outgoing, isFalse);
      expect(record.fromAddress, sender);
      expect(record.toAddress, owner);
      expect(record.amountText, '2 USDC');
      expect(record.assetContract, mint);
      expect(record.assetVerified, isTrue);
      expect(record.status, ChainTxStatus.confirmed);
      expect(rpcIds.toSet(), hasLength(rpcIds.length));
    },
  );

  test(
    'TRON direct history includes TRC-10 and internal TRX receipts',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/transactions/trc20')) {
            return {'data': <Object?>[], 'success': true};
          }
          if (request.url.path.endsWith('/internal-transactions')) {
            return {
              'data': [
                {
                  'tx_id': _tronHashA,
                  'internal_tx_id': _tronTrace,
                  'from_address': '41b3dcf27c251da9363f1a4888257c16676cf54edf',
                  'to_address': _meHex,
                  'block_timestamp': 3000,
                  'data': {
                    'rejected': false,
                    'call_value': {'_': '2500000'},
                  },
                },
              ],
              'success': true,
            };
          }
          final trc10 = _nativeTransferItem(
            hash: _tronHashB,
            ownerHex: _meHex,
            ts: 2000,
            amount: 42,
          );
          final contract =
              ((trc10['raw_data'] as Map)['contract'] as List).first as Map;
          contract['type'] = 'TransferAssetContract';
          final parameter = contract['parameter'] as Map;
          parameter['type_url'] =
              'type.googleapis.com/protocol.TransferAssetContract';
          (parameter['value'] as Map)['asset_name'] = '1002000';
          return {
            'data': [trc10],
            'success': true,
          };
        },
      );

      final records = (await service.fetch(Coin.tron, _me)).records;
      expect(records.map((record) => record.id), [
        '$_tronHashA:internal:$_tronTrace',
        '$_tronHashB:trc10:1002000',
      ]);
      expect(records.first.amountText, '2.5 TRX');
      expect(records.first.status, ChainTxStatus.confirmed);
      expect(records.last.amountText, '42 TRC10');
      expect(records.last.assetVerified, isFalse);
      expect(records.last.status, ChainTxStatus.confirmed);
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

  test(
    'TRON direct history validates checksum before network access',
    () async {
      var requests = 0;
      final service = _service(
        body: (_) {
          requests += 1;
          return {'data': <Object?>[], 'success': true};
        },
      );

      final invalidChecksum = '${_me.substring(0, _me.length - 1)}m';
      final result = await service.fetch(Coin.tron, invalidChecksum);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
      expect(requests, 0);
    },
  );

  test('TRON direct history rejects duplicate envelope members', () async {
    final service = HistoryService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/transactions/trc20')) {
          return http.Response('{"data":[],"data":[],"success":true}', 200);
        }
        return http.Response(
          jsonEncode({'data': <Object?>[], 'success': true}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects success=false', () async {
    final service = _service(
      body: (_) => {'data': <Object?>[], 'success': false},
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects unknown TRC-20 row members', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/transactions/trc20')) {
          return {
            'data': [
              {
                ..._trc20Item(
                  hash: _tronHashA,
                  from: _other,
                  to: _me,
                  ts: 1700000000000,
                ),
                'Value': '1',
              },
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects rows not bound to the owner', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/transactions/trc20')) {
          return {
            'data': [
              _trc20Item(
                hash: _tronHashA,
                from: _other,
                to: _tronBurn,
                ts: 1700000000000,
              ),
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects responses larger than requested', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/transactions/trc20')) {
          return {
            'data': [
              _trc20Item(
                hash: _tronHashA,
                from: _other,
                to: _me,
                ts: 1700000000000,
              ),
              _trc20Item(
                hash: _tronHashB,
                from: _other,
                to: _me,
                ts: 1700000000001,
              ),
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me, limit: 1);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test(
    'TRON direct history rejects official-token decimals mismatch',
    () async {
      final service = _service(
        body: (request) {
          if (request.url.path.endsWith('/transactions/trc20')) {
            return {
              'data': [
                _trc20Item(
                  hash: _tronHashA,
                  from: _other,
                  to: _me,
                  ts: 1700000000000,
                  decimals: 18,
                ),
              ],
              'success': true,
            };
          }
          return {'data': <Object?>[], 'success': true};
        },
      );

      final result = await service.fetch(Coin.tron, _me);
      expect(result.status, HistoryStatus.error);
      expect(result.records, isEmpty);
    },
  );

  test('TRON direct history rejects ambiguous pagination metadata', () async {
    final service = _service(
      body: (_) => {
        'data': <Object?>[],
        'success': true,
        'meta': {'page_size': 0, 'Page_size': 0},
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects unknown native row members', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/transactions') &&
            !request.url.path.endsWith('/internal-transactions')) {
          return {
            'data': [
              {
                ..._nativeTransferItem(
                  hash: _tronHashA,
                  ownerHex: _otherHex,
                  ts: 1700000000000,
                ),
                'TxID': _tronHashB,
              },
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON direct history rejects unknown internal data members', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/internal-transactions')) {
          return {
            'data': [
              {
                'tx_id': _tronHashA,
                'internal_tx_id': _tronTrace,
                'from_address': _otherHex,
                'to_address': _meHex,
                'block_timestamp': 1700000000000,
                'data': {
                  'rejected': false,
                  'call_value': {'_': 1},
                  'Rejected': true,
                },
              },
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('TRON approval events are not asset history', () async {
    final service = _service(
      body: (request) {
        if (request.url.path.endsWith('/transactions/trc20')) {
          return {
            'data': [
              {'type': 'Approval'},
            ],
            'success': true,
          };
        }
        return {'data': <Object?>[], 'success': true};
      },
    );

    final result = await service.fetch(Coin.tron, _me);
    expect(result.status, HistoryStatus.ok);
    expect(result.records, isEmpty);
  });

  test(
    'TRON internal history preserves TRX and TRC-10 from one trace',
    () async {
      final service = _service(
        body: (request) {
          expect(
            request.url.queryParameters['order_by'],
            'block_timestamp,desc',
          );
          if (request.url.path.endsWith('/internal-transactions')) {
            return {
              'data': [
                {
                  'tx_id': _tronHashA,
                  'internal_tx_id': _tronTrace,
                  'from_address': _otherHex,
                  'to_address': _meHex,
                  'block_timestamp': 1700000000000,
                  'data': {
                    'rejected': false,
                    'call_value': {'_': '2500000'},
                    'call_token_value': {'_': '7'},
                    'token_id': '1002000',
                  },
                },
              ],
              'success': true,
            };
          }
          return {'data': <Object?>[], 'success': true};
        },
      );

      final result = await service.fetch(Coin.tron, _me);
      expect(result.status, HistoryStatus.ok);
      expect(result.records, hasLength(2));
      expect(result.records.map((record) => record.id), {
        '$_tronHashA:internal:$_tronTrace',
        '$_tronHashA:internal:$_tronTrace:trc10:1002000',
      });
      expect(result.records.map((record) => record.amountText), {
        '2.5 TRX',
        '7 TRC10',
      });
    },
  );

  test(
    'EVM direct history keeps missing or contradictory execution evidence unknown',
    () async {
      const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final service = HistoryService(
        endpoints: (_) => 'https://rpc.ankr.com/eth',
        client: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          final result = action == 'txlist'
              ? [
                  {
                    'hash':
                        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                    'from': address,
                    'to': '0x1111111111111111111111111111111111111111',
                    'value': '1000000000000000',
                    'timeStamp': '1700000400',
                  },
                  {
                    'hash':
                        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
                    'from': address,
                    'to': '0x2222222222222222222222222222222222222222',
                    'value': '2000000000000000',
                    'timeStamp': '1700000300',
                    'isError': '0',
                    'txreceipt_status': '0',
                  },
                ]
              : <Object?>[];
          return http.Response(
            jsonEncode({'status': '1', 'message': 'OK', 'result': result}),
            200,
          );
        }),
      );

      final records = (await service.fetch(Coin.eth, address)).records;
      expect(records, hasLength(2));
      expect(
        records.map((record) => record.status),
        everyElement(ChainTxStatus.unknown),
      );
    },
  );

  test('Solana direct history requires explicit success evidence', () async {
    const owner = _solanaOwner;
    const recipient = _solanaRecipient;
    final service = HistoryService(
      endpoints: (_) => 'https://api.mainnet-beta.solana.com',
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final method = payload['method'];
        final Object? result;
        if (method == 'getTokenAccountsByOwner') {
          result = {
            'context': {'slot': 114},
            'value': <Object?>[],
          };
        } else if (method == 'getSignaturesForAddress') {
          result = [
            {'signature': 'missing-status-signature', 'blockTime': 1700000500},
          ];
        } else if (method == 'getTransaction') {
          result = {
            'meta': {
              'preBalances': [2000000000, 0],
              'postBalances': [1000000000, 1000000000],
              'preTokenBalances': <Object?>[],
              'postTokenBalances': <Object?>[],
            },
            'transaction': {
              'message': {
                'accountKeys': [owner, recipient],
                'instructions': [
                  {
                    'program': 'system',
                    'parsed': {
                      'info': {'source': owner, 'destination': recipient},
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
          jsonEncode({'jsonrpc': '2.0', 'id': payload['id'], 'result': result}),
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.solana, owner);
    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
  });

  test('Solana direct history rejects duplicate RPC result members', () async {
    const owner = _solanaOwner;
    var calls = 0;
    final service = HistoryService(
      endpoints: (_) => 'https://api.mainnet-beta.solana.com',
      client: MockClient((request) async {
        calls += 1;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final method = payload['method'];
        final Object result = switch (method) {
          'getTokenAccountsByOwner' => {
            'context': {'slot': 114},
            'value': <Object?>[],
          },
          'getSignaturesForAddress' => <Object?>[],
          _ => throw StateError('unexpected Solana method $method'),
        };
        final valid = jsonEncode(result);
        return http.Response(
          '{"jsonrpc":"2.0","id":${payload['id']},'
          '"result":null,"result":$valid}',
          200,
        );
      }),
    );

    final result = await service.fetch(Coin.solana, owner);

    expect(result.status, HistoryStatus.error);
    expect(result.records, isEmpty);
    expect(calls, 1, reason: 'the first ambiguous response must stop the read');
  });

  test(
    'TRON direct native and internal rows require explicit execution evidence',
    () async {
      final native = _nativeTransferItem(
        hash: _tronHashA,
        ownerHex: _meHex,
        ts: 2000,
      )..remove('ret');
      final service = _service(
        body: (request) {
          expect(request.url.queryParameters['only_confirmed'], 'true');
          if (request.url.path.endsWith('/transactions/trc20')) {
            return {'data': <Object?>[], 'success': true};
          }
          if (request.url.path.endsWith('/internal-transactions')) {
            return {
              'data': [
                {
                  'tx_id': _tronHashB,
                  'internal_tx_id': _tronTrace,
                  'from_address': _otherHex,
                  'to_address': _meHex,
                  'block_timestamp': 3000,
                  'data': {
                    'call_value': {'_': '1000000'},
                  },
                },
              ],
              'success': true,
            };
          }
          return {
            'data': [native],
            'success': true,
          };
        },
      );

      final records = (await service.fetch(Coin.tron, _me)).records;
      expect(records, hasLength(2));
      expect(
        records.map((record) => record.status),
        everyElement(ChainTxStatus.unknown),
      );
    },
  );
}
