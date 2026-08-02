import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';

/// GatewayClient against the fixed protocol contract: exact request JSON
/// (JSON-RPC 2.0, no batches, `POST {url}/rpc`), typed result parsing per
/// method, and JSON-RPC error → [GatewayException] mapping.

/// Records every request body and serves scripted results/errors.
class _Recorder {
  final requests = <Map<String, Object?>>[];

  /// Scripted JSON-RPC `result` per method.
  Map<String, Object?> results = {};

  /// Scripted JSON-RPC `error` object per method (wins over [results]).
  Map<String, Object?> errors = {};

  late final client = MockClient((request) async {
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://gw.example/rpc');
    expect(request.headers['content-type'], startsWith('application/json'));
    final body = jsonDecode(request.body) as Map<String, Object?>;
    requests.add(body);
    final method = body['method'] as String;
    final error = errors[method];
    if (error != null) {
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'error': error}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': results[method],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('GatewayClient request framing', () {
    test(
      'JSON-RPC 2.0 envelope: jsonrpc/id/method/params, POST {url}/rpc',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {'ok': true, 'version': '1.0.0'},
          };
        // Trailing slash is normalized away (requests still hit {url}/rpc).
        final client = GatewayClient(
          baseUrl: 'https://gw.example/',
          client: recorder.client,
        );

        expect(await client.health(), isTrue);
        expect(await client.health(), isTrue);

        expect(recorder.requests, hasLength(2));
        final first = recorder.requests[0];
        expect(first['jsonrpc'], '2.0');
        expect(first['method'], 'kt_health');
        expect(first['id'], isA<int>());
        expect(first.containsKey('params'), isFalse); // kt_health takes none
        // ids are unique per call (no batches, but still well-formed JSON-RPC).
        expect(recorder.requests[1]['id'], isNot(first['id']));
      },
    );

    test(
      'health(): false on {ok:false}, error answers and transport failure',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {'ok': false},
          };
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).health(),
          isFalse,
        );

        recorder.errors = {
          'kt_health': {'code': -32601, 'message': 'method not found'},
        };
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).health(),
          isFalse,
        );

        final dead = MockClient((request) async => http.Response('down', 503));
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: dead,
          ).health(),
          isFalse,
        );
      },
    );

    test('timeout becomes a privacy-safe transport exception', () async {
      final slow = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('{}', 200);
      });
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: slow,
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        client.getPrices(const ['ETH']),
        throwsA(isA<GatewayTransportException>()),
      );
    });

    test('non-200 status becomes a privacy-safe transport exception', () async {
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: MockClient((request) async => http.Response('oops', 502)),
      );
      await expectLater(
        client.getPrices(const ['ETH']),
        throwsA(isA<GatewayTransportException>()),
      );
    });
  });

  group('kt_getBalances', () {
    test(
      'exact params and typed native + per-token rows (incl. errors)',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'native': {
                'raw': '1000000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
              },
              'tokens': [
                {
                  'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                  'raw': '120500000',
                  'decimals': 6,
                  'symbol': 'USDT',
                },
                {
                  'contract': '0xBadToken',
                  'raw': '0',
                  'decimals': 6,
                  'symbol': 'BAD',
                  'error': 'execution reverted',
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final balances = await client.getBalances(
          chain: Coin.eth,
          address: '0xEthAddr',
          tokens: const [
            GatewayTokenQuery(
              contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              decimals: 6,
              symbol: 'USDT',
            ),
            GatewayTokenQuery(
              contract: '0xBadToken',
              decimals: 6,
              symbol: 'BAD',
            ),
          ],
        );

        expect(recorder.requests.single['params'], {
          'chain': 'eth',
          'address': '0xEthAddr',
          'tokens': [
            {
              'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              'decimals': 6,
              'symbol': 'USDT',
            },
            {'contract': '0xBadToken', 'decimals': 6, 'symbol': 'BAD'},
          ],
        });
        expect(balances.native.raw, BigInt.parse('1000000000000000000'));
        expect(balances.native.decimals, 18);
        expect(balances.native.symbol, 'ETH');
        expect(balances.tokens, hasLength(2));
        expect(balances.tokens[0].raw, BigInt.from(120500000));
        expect(balances.tokens[0].error, isNull);
        // Per-token error: no raw value, the error string is preserved.
        expect(balances.tokens[1].error, 'execution reverted');
        expect(balances.tokens[1].raw, isNull);
      },
    );

    test(
      'native-only call omits the tokens param; chain names match the enum',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'native': {'raw': '5000000', 'decimals': 6, 'symbol': 'TRX'},
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final balances = await client.getBalances(
          chain: Coin.tron,
          address: 'TTronAddr',
        );
        expect(recorder.requests.single['params'], {
          'chain': 'tron',
          'address': 'TTronAddr',
        });
        expect(balances.native.raw, BigInt.from(5000000));
        expect(balances.tokens, isEmpty);
        // The wire names of every supported chain.
        expect(Coin.values.map(GatewayClient.chainName), [
          'eth',
          'polygon',
          'base',
          'arbitrum',
          'avalanche',
          'bnb',
          'tron',
          'solana',
        ]);
      },
    );

    test('malformed result (missing native) throws FormatException', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getBalances': {'tokens': <Object?>[]},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects native decimals or symbol that contradict the chain',
      () async {
        for (final native in <Map<String, Object?>>[
          {'raw': '1000000000000000000', 'decimals': 0, 'symbol': 'ETH'},
          {'raw': '1000000000000000000', 'decimals': 18, 'symbol': 'BTC'},
        ]) {
          final recorder = _Recorder()
            ..results = {
              'kt_getBalances': {'native': native},
            };
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          );
          await expectLater(
            client.getBalances(chain: Coin.eth, address: '0xA'),
            throwsA(isA<FormatException>()),
            reason: 'gateway metadata must not rescale or relabel native money',
          );
        }
      },
    );
  });

  group('kt_getPortfolio', () {
    test('parses per-chain results and preserves partial failures', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getPortfolio': {
            'accounts': [
              {
                'chain': 'eth',
                'result': {
                  'native': {
                    'raw': '1000000000000000000',
                    'decimals': 18,
                    'symbol': 'ETH',
                  },
                  'tokens': const <Object?>[],
                },
              },
              {'chain': 'solana', 'error': 'upstream unavailable'},
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      final result = await client.getPortfolio(const [
        GatewayPortfolioQuery(
          chain: Coin.eth,
          address: '0x1111111111111111111111111111111111111111',
        ),
        GatewayPortfolioQuery(
          chain: Coin.solana,
          address: '11111111111111111111111111111111',
        ),
      ]);

      expect(
        result.balances[Coin.eth]!.native.raw,
        BigInt.parse('1000000000000000000'),
      );
      expect(result.failedChains, contains(Coin.solana));
      expect(recorder.requests.single['method'], 'kt_getPortfolio');
      final params = recorder.requests.single['params'] as Map<String, Object?>;
      expect(params['accounts'], hasLength(2));
    });

    test(
      'isolates a portfolio row with contradictory native metadata',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getPortfolio': {
              'accounts': [
                {
                  'chain': 'eth',
                  'result': {
                    'native': {
                      'raw': '1000000000000000000',
                      'decimals': 6,
                      'symbol': 'ETH',
                    },
                  },
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final result = await client.getPortfolio(const [
          GatewayPortfolioQuery(chain: Coin.eth, address: '0xA'),
        ]);

        expect(result.balances, isEmpty);
        expect(result.failedChains, {Coin.eth});
      },
    );
  });

  group('kt_getPrices', () {
    test(
      'exact params; unknown symbols omitted by the gateway stay absent',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': 2500.5, 'change24h': 3.25},
                'TRX': {'usd': 0.12, 'change24h': -1.5},
              },
              'fiatPerUsd': {'USD': 1, 'CNY': 7.2, 'JPY': 151.5},
              'cachedAtMs': 1753000000000,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final prices = await client.getPrices(const [
          'ETH',
          'POL',
          'TRX',
          'SOL',
        ]);

        expect(recorder.requests.single['params'], {
          'symbols': ['ETH', 'POL', 'TRX', 'SOL'],
        });
        expect(prices.usdBySymbol, {'ETH': 2500.5, 'TRX': 0.12});
        expect(prices.change24hBySymbol, {'ETH': 3.25, 'TRX': -1.5});
        expect(prices.fiatPerUsd, {'USD': 1, 'CNY': 7.2, 'JPY': 151.5});
        expect(prices.cachedAtMs, 1753000000000);
      },
    );

    test('rejects non-positive or non-finite market truth', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getPrices': {
            'prices': {
              'ETH': {'usd': -2500, 'change24h': 1.5},
              'POL': {'usd': 0, 'change24h': -2},
              'TRX': {'usd': 0.12, 'change24h': 3.25},
            },
            'fiatPerUsd': {'USD': 0, 'CNY': -7.2, 'JPY': 151.5},
          },
        };
      final prices = await GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      ).getPrices(const ['ETH', 'POL', 'TRX']);

      expect(prices.usdBySymbol, {'TRX': 0.12});
      expect(prices.change24hBySymbol, {'TRX': 3.25});
      expect(prices.fiatPerUsd, {'USD': 1, 'JPY': 151.5});
    });
  });

  group('kt_getChainParams', () {
    test(
      'decimal nonce and three fee tiers parse into chains/rpc types',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getChainParams': {
              'nonce': '42',
              'fees': {
                'slow': {
                  'maxPriorityFeePerGas': '1000000000',
                  'maxFeePerGas': '20000000000',
                },
                'standard': {
                  'maxPriorityFeePerGas': '2000000000',
                  'maxFeePerGas': '30000000000',
                },
                'fast': {
                  'maxPriorityFeePerGas': '3000000000',
                  'maxFeePerGas': '40000000000',
                },
              },
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final params = await client.getChainParams(
          chain: Coin.polygon,
          address: '0xFrom',
        );

        expect(recorder.requests.single['params'], {
          'chain': 'polygon',
          'address': '0xFrom',
        });
        expect(params.nonce, 42);
        expect(params.fees.slow.maxPriorityFeePerGas, BigInt.from(1000000000));
        expect(params.fees.standard.maxFeePerGas, BigInt.from(30000000000));
        expect(params.fees.fast.maxPriorityFeePerGas, BigInt.from(3000000000));
      },
    );

    test('-32602 for a non-EVM chain surfaces as GatewayException', () async {
      final recorder = _Recorder()
        ..errors = {
          'kt_getChainParams': {'code': -32602, 'message': 'invalid params'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getChainParams(chain: Coin.tron, address: 'T...'),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', -32602)
              .having((e) => e.isUnsupported, 'isUnsupported', isFalse),
        ),
      );
    });
  });

  group('EVM preflight', () {
    test(
      'simulation and gas estimation carry exact network-scoped call',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {
              'ok': true,
              'networks': ['polygon-amoy'],
            },
            'kt_simulateEvmTransfer': {'returnData': '0x${'0' * 63}1'},
            'kt_estimateEvmGas': {'gas': '65432'},
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
          networks: (_) => 'polygon-amoy',
        );
        final args = (
          chain: Coin.polygon,
          from: '0xFrom',
          to: '0xToken',
          value: BigInt.from(15),
          data: '0xa9059cbb',
        );

        expect(
          await client.simulateEvmTransfer(
            chain: args.chain,
            from: args.from,
            to: args.to,
            value: args.value,
            data: args.data,
            blockTag: 'latest',
          ),
          '0x${'0' * 63}1',
        );
        expect(
          await client.estimateEvmGas(
            chain: args.chain,
            from: args.from,
            to: args.to,
            value: args.value,
            data: args.data,
          ),
          BigInt.from(65432),
        );

        final calls = recorder.requests.where(
          (r) => r['method'] != 'kt_health',
        );
        expect(calls, hasLength(2));
        expect(calls.first['params'], {
          'chain': 'polygon',
          'network': 'polygon-amoy',
          'from': '0xFrom',
          'to': '0xToken',
          'value': '15',
          'data': '0xa9059cbb',
          'blockTag': 'latest',
        });
        expect(calls.last['params'], {
          'chain': 'polygon',
          'network': 'polygon-amoy',
          'from': '0xFrom',
          'to': '0xToken',
          'value': '15',
          'data': '0xa9059cbb',
        });
      },
    );

    test('malformed simulation and zero gas fail closed', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_simulateEvmTransfer': {'returnData': 'not-hex'},
          'kt_estimateEvmGas': {'gas': '0'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.simulateEvmTransfer(
          chain: Coin.eth,
          from: '0xFrom',
          to: '0xTo',
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
      await expectLater(
        client.estimateEvmGas(
          chain: Coin.eth,
          from: '0xFrom',
          to: '0xTo',
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
    });

    test(
      'uncached spendable balances parse and carry token contract',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmSpendableBalances': {
              'nativePending': '900000000000000000',
              'nativeLatest': '1000000000000000000',
              'token': '2500000',
              'pendingAvailable': false,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final balances = await client.getEvmSpendableBalances(
          chain: Coin.eth,
          address: '0xFrom',
          tokenContract: '0xToken',
        );
        expect(balances.native, BigInt.parse('900000000000000000'));
        expect(balances.nativeLatest, BigInt.parse('1000000000000000000'));
        expect(balances.token, BigInt.from(2500000));
        expect(balances.pendingAvailable, isFalse);
        expect(recorder.requests.single['params'], {
          'chain': 'eth',
          'address': '0xFrom',
          'tokenContract': '0xToken',
        });
      },
    );

    test('missing requested token balance fails closed', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getEvmSpendableBalances': {'native': '1'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getEvmSpendableBalances(
          chain: Coin.eth,
          address: '0xFrom',
          tokenContract: '0xToken',
        ),
        throwsFormatException,
      );
    });
  });

  group('kt_getHistory', () {
    test('ok status with records; malformed rows are skipped', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {
            'status': 'ok',
            'records': [
              {
                'hash': '0xaaa',
                'direction': 'out',
                'from': '0xEthAddr',
                'to': '0xRecipient',
                'amountRaw': '1500000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
                'timestampMs': 1753000000000,
                'status': 'ok',
              },
              {
                'hash': '0xbbb',
                'direction': 'in',
                'amountRaw': '2000000',
                'decimals': 6,
                'symbol': 'USDT',
                'timestampMs': 1752000000000,
                'status': 'failed',
              },
              {'direction': 'in', 'timestampMs': 1}, // no hash → skipped
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.eth,
        address: '0xEthAddr',
        limit: 20,
      );

      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'address': '0xEthAddr',
        'limit': 20,
      });
      expect(history.unsupported, isFalse);
      expect(history.records, hasLength(2));
      expect(history.records[0].hash, '0xaaa');
      expect(history.records[0].outgoing, isTrue);
      expect(history.records[0].fromAddress, '0xEthAddr');
      expect(history.records[0].toAddress, '0xRecipient');
      expect(history.records[0].status, GatewayTransactionStatus.confirmed);
      expect(history.records[0].amountRaw, BigInt.parse('1500000000000000000'));
      expect(history.records[1].outgoing, isFalse);
      expect(history.records[1].status, GatewayTransactionStatus.failed);
    });

    test('status unsupported maps to the typed unsupported result', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {'status': 'unsupported', 'records': <Object?>[]},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.solana,
        address: 'SolAddr',
      );
      expect(history.unsupported, isTrue);
      expect(history.records, isEmpty);
    });
  });

  group('kt_getTransactionStatus', () {
    test('maps chain-authoritative status and sends the exact hash', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {'status': 'confirmed'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      final status = await client.getTransactionStatus(
        chain: Coin.avalanche,
        hash: '0xreceipt',
      );

      expect(status, GatewayTransactionStatus.confirmed);
      expect(recorder.requests.single['params'], {
        'chain': 'avalanche',
        'hash': '0xreceipt',
      });
    });

    test('rejects an unknown status instead of assuming pending', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {'status': 'indexed-later'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getTransactionStatus(chain: Coin.eth, hash: '0xreceipt'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('kt_getEvmTokenApprovals', () {
    test('requires consent and parses the complete typed approval row', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_health': {
            'ok': true,
            'networks': ['eth-mainnet'],
          },
          'kt_getEvmTokenApprovals': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'tokenName': 'Token',
                'tokenSymbol': 'TOK',
                'decimals': 18,
                'balance': '5',
                'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'spenderName': 'Router',
                'spenderTag': 'Example',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 1700000000,
                'transaction':
                    '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                'risk': 'unsafe',
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
        networks: (_) => 'eth-mainnet',
      );

      await expectLater(
        client.getEvmTokenApprovals(
          chain: Coin.eth,
          address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
          privacyConsent: false,
        ),
        throwsArgumentError,
      );
      expect(recorder.requests, isEmpty);

      final result = await client.getEvmTokenApprovals(
        chain: Coin.eth,
        address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        privacyConsent: true,
      );
      expect(result.network, 'eth-mainnet');
      expect(result.source, 'goplus');
      expect(result.approvals, hasLength(1));
      expect(result.approvals.single.unlimited, isTrue);
      expect(result.approvals.single.risk, GatewayTokenApprovalRisk.unsafe);
      expect(recorder.requests.last['params'], {
        'chain': 'eth',
        'network': 'eth-mainnet',
        'address': '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        'privacyConsent': true,
      });
    });

    test(
      'malformed rows fail closed instead of becoming an empty list',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmTokenApprovals': {
              'status': 'ok',
              'source': 'goplus',
              'network': 'eth-mainnet',
              'approvals': [
                {'tokenAddress': 'missing-fields'},
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getEvmTokenApprovals(
            chain: Coin.eth,
            address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
            privacyConsent: true,
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('kt_broadcast and error mapping', () {
    test('payload passthrough and txHash back', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_broadcast': {'txHash': '0xfeedbead'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final hash = await client.broadcast(chain: Coin.eth, payload: '0x02ab01');
      expect(hash, '0xfeedbead');
      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'payload': '0x02ab01',
      });
    });

    test(
      '-32000 upstream_error surfaces the node message and upstream',
      () async {
        final recorder = _Recorder()
          ..errors = {
            'kt_broadcast': {
              'code': -32000,
              'message': 'upstream_error',
              'data': {'upstream': 'eth-node', 'message': 'nonce too low'},
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.broadcast(chain: Coin.eth, payload: '0x02'),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.code, 'code', -32000)
                .having((e) => e.isUpstreamError, 'isUpstreamError', isTrue)
                .having((e) => e.message, 'message', 'upstream_error')
                .having((e) => e.upstream, 'upstream', 'eth-node')
                .having(
                  (e) => e.upstreamMessage,
                  'upstreamMessage',
                  'nonce too low',
                ),
          ),
        );
      },
    );

    test(
      '-32002 unsupported and -32001 rate_limited map onto the flags',
      () async {
        final recorder = _Recorder()
          ..errors = {
            'kt_getHistory': {'code': -32002, 'message': 'unsupported'},
            'kt_getPrices': {'code': -32001, 'message': 'rate_limited'},
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getHistory(chain: Coin.eth, address: '0xA'),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.isUnsupported, 'isUnsupported', isTrue)
                .having((e) => e.isUpstreamError, 'isUpstreamError', isFalse),
          ),
        );
        await expectLater(
          client.getPrices(const ['ETH']),
          throwsA(
            isA<GatewayException>().having((e) => e.code, 'code', -32001),
          ),
        );
      },
    );

    test(
      'transport failures never expose a credential-bearing gateway URL',
      () async {
        const canary = 'gateway-client-secret-canary';
        final client = GatewayClient(
          baseUrl: 'https://gateway.example/v1/$canary',
          client: MockClient((request) async {
            throw http.ClientException('connection refused', request.url);
          }),
        );

        Object? thrown;
        try {
          await client.broadcast(chain: Coin.eth, payload: '0x02');
        } on Object catch (error) {
          thrown = error;
        }

        expect(thrown, isA<GatewayTransportException>());
        expect(thrown.toString(), isNot(contains(canary)));
        expect(thrown.toString(), isNot(contains('gateway.example')));
      },
    );
  });
}
