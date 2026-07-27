import 'dart:convert';

import 'package:chains/chains.dart'
    show Amount, Chain, Eip1559Tx, TransferIntent, TxOperation;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/explorer_links.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---- fakes ------------------------------------------------------------------

/// 按 URL 分发 JSON-RPC 请求的假传输层。
class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc(this.handler);
  final Future<Object?> Function(String url, Object body) handler;
  final seenUrls = <String>[];
  @override
  Future<Object?> post(String url, Object body) {
    seenUrls.add(url);
    return handler(url, body);
  }
}

class _FakeRest implements RestTransport {
  _FakeRest(this.onGet);
  final Future<Object?> Function(String url) onGet;
  final seenUrls = <String>[];
  @override
  Future<Object?> getJson(String url) {
    seenUrls.add(url);
    return onGet(url);
  }

  @override
  Future<Object?> postJson(String url, Object body) =>
      throw UnimplementedError('本测试不应发起 POST');
}

class _CountingBalanceService extends BalanceService {
  int calls = 0;
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    calls++;
    final results = {
      for (final coin in Coin.values)
        coin: BalanceResult.ok(
          Amount(raw: BigInt.from(1000000), decimals: 6, symbol: 'X'),
        ),
    };
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class _CountingPriceService extends PriceService {
  int calls = 0;
  final Map<Coin, double>? quotes;
  _CountingPriceService([this.quotes]);
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async {
    calls++;
    return quotes;
  }
}

/// 链上参数拉取总是失败的测试替身——驱动 W6 的回退路径。
class _ThrowingParamsService extends ChainParamsService {
  _ThrowingParamsService()
    : super(jsonRpcTransport: _FakeJsonRpc((url, body) async => null));
  @override
  Future<EvmChainParams> fetchEvmParams(
    Chain chain,
    String fromAddress,
  ) async => throw StateError('node unreachable');
}

class _FakeTokenService extends TokenBalanceService {
  _FakeTokenService(this.results);
  final Map<String, BalanceResult> results;
  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      results;
}

const _addresses = ChainAddresses(
  eth: '0xEthAddr',
  polygon: '0xPolyAddr',
  tron: 'TTronAddr',
  solana: 'SolAddr',
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: _addresses,
        backedUp: true,
      ),
    ],
  ),
);

Map<String, Object?> _rpcResult(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('端点解析优先级', () {
    test('偏好设置覆盖 > 活动网络 > 内置默认', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.setRpcOverride(Coin.eth, 'https://my-node.example');
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );

      final resolve = effectiveRpcEndpoints(prefs, networks);
      // 1. 用户手填的 RPC 覆盖永远最高。
      expect(resolve(Coin.eth), 'https://my-node.example');
      // 2. 无覆盖时使用活动网络(测试网环境 → Sepolia/Amoy/Nile/Devnet)。
      expect(resolve(Coin.polygon), polygonAmoy.rpcUrl);
      expect(resolve(Coin.tron), tronNile.rpcUrl);
      expect(resolve(Coin.solana), solanaDevnet.rpcUrl);
      // 3. 两个来源都缺席 → 内置默认(与主网 profile 相同的 URL)。
      final fallback = effectiveRpcEndpoints(null, null);
      for (final coin in Coin.values) {
        expect(fallback(coin), defaultRpcEndpointFor(coin));
      }
      // 主网 profile 的 URL 与内置默认字节一致(回归保证)。
      final mainnet = effectiveRpcEndpoints(null, NetworkController());
      for (final coin in Coin.values) {
        expect(mainnet(coin), defaultRpcEndpointFor(coin), reason: '$coin');
      }
    });

    test('BalanceService 经解析器把请求发到测试网端点(假传输断言 URL)', () async {
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final jsonRpc = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({'context': <String, Object?>{}, 'value': 0})
            : _rpcResult('0x0'),
      );
      final rest = _FakeRest((url) async => {'data': <Object?>[]});
      final service = BalanceService(
        endpoints: effectiveRpcEndpoints(null, networks),
        jsonRpcTransport: jsonRpc,
        restTransport: rest,
      );

      await service.fetchAll(_addresses);
      expect(
        jsonRpc.seenUrls,
        containsAll([
          ethSepolia.rpcUrl,
          polygonAmoy.rpcUrl,
          solanaDevnet.rpcUrl,
        ]),
      );
      expect(rest.seenUrls.single, '${tronNile.rpcUrl}/v1/accounts/TTronAddr');
    });
  });

  group('环境切换驱动市场刷新', () {
    testWidgets('切到测试网触发一次 refresh;无关变化不触发', (tester) async {
      final networks = NetworkController();
      final wallets = _wallets();
      final balances = _CountingBalanceService();
      final controller = MarketController(
        wallets: wallets,
        balances: balances,
        prices: _CountingPriceService(),
        tokens: _FakeTokenService(const {}),
      );
      await tester.pumpWidget(
        _app(
          NetworkScope(
            controller: networks,
            child: MarketScopeHost(
              wallets: wallets,
              controller: controller,
              child: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(balances.calls, 1); // 首次进入首页的刷新

      // 环境切换改变了每条链的有效端点 → 必须重新拉取。
      await networks.setEnvironment(NetworkEnvironment.testnet);
      await tester.pumpAndSettle();
      expect(balances.calls, 2);

      // 切回主网同理。
      await networks.setEnvironment(NetworkEnvironment.mainnet);
      await tester.pumpAndSettle();
      expect(balances.calls, 3);

      // 相同环境的重复设置不产生新的通知/刷新。
      await networks.setEnvironment(NetworkEnvironment.mainnet);
      await tester.pumpAndSettle();
      expect(balances.calls, 3);
      controller.dispose();
    });
  });

  group('测试网代币注册表', () {
    test('测试网环境查询七条链各自的测试稳定币', () async {
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final jsonRpc = _FakeJsonRpc((url, body) async {
        final request = body as Map;
        if (request['method'] == 'getTokenAccountsByOwner') {
          return {
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': {'value': <Object>[]},
          };
        }
        return _rpcResult('0x0');
      });
      final rest = _FakeRest((url) async => {'data': <Object>[]});
      final service = TokenBalanceService(
        registry: networkTokenRegistry(networks),
        endpoints: effectiveRpcEndpoints(null, networks),
        jsonRpcTransport: jsonRpc,
        restTransport: rest,
      );

      expect(service.tokens, [
        usdtSepoliaToken,
        usdcPolygonAmoyToken,
        usdcBaseSepoliaToken,
        usdcArbitrumSepoliaToken,
        usdcAvalancheFujiToken,
        usdtTronNileToken,
        usdcSolanaDevnetToken,
      ]);
      final results = await service.fetchAll(_addresses);
      for (final token in service.tokens) {
        expect(results[token.id]!.amount!.raw, BigInt.zero);
      }
      expect(jsonRpc.seenUrls, [
        ethSepolia.rpcUrl,
        polygonAmoy.rpcUrl,
        baseSepolia.rpcUrl,
        arbitrumSepolia.rpcUrl,
        avalancheFuji.rpcUrl,
        solanaDevnet.rpcUrl,
      ]);
      expect(rest.seenUrls, [
        '${tronNile.rpcUrl}/v1/accounts/${_addresses.tron}',
      ]);
    });

    test('主网环境注册表包含七条链的内置稳定币', () {
      final networks = NetworkController();
      expect(networkTokenRegistry(networks)(), [
        usdtEthToken,
        usdcPolygonToken,
        // 除以太坊外,每条 EVM 主网都同时带 USDC 与 USDT。
        usdtPolygonToken,
        usdcBaseToken,
        usdtBaseToken,
        usdcArbitrumToken,
        usdtArbitrumToken,
        usdcAvalancheToken,
        usdtAvalancheToken,
        usdtTronToken,
        usdcSolanaToken,
        usdtSolanaToken,
      ]);
      // 无网络来源(旧接线)也解析为完整主网注册表。
      expect(networkTokenRegistry(null)(), builtinTokens);
    });
  });

  group('测试网价格抑制', () {
    test('全测试网时完全跳过价格拉取,法币价值为 null', () async {
      final prices = _CountingPriceService({Coin.eth: 2000.0});
      final controller = MarketController(
        wallets: _wallets(),
        balances: _CountingBalanceService(),
        prices: prices,
        tokens: _FakeTokenService(const {}),
        isTestnet: (_) => true,
      );
      await controller.refresh();
      expect(prices.calls, 0); // 无可定价资产 → 连询价都不发
      expect(controller.pricesUsd, isNull);
      for (final coin in Coin.values) {
        expect(controller.fiatValueUsd(coin), isNull, reason: '$coin');
      }
      expect(controller.totalUsd, isNull);
      controller.dispose();
    });

    test('混合环境仍拉取一次价格,但测试网链的法币价值保持 null', () async {
      final prices = _CountingPriceService({
        for (final c in Coin.values) c: 1.0,
      });
      final controller = MarketController(
        wallets: _wallets(),
        balances: _CountingBalanceService(),
        prices: prices,
        tokens: _FakeTokenService(const {}),
        isTestnet: (coin) => coin == Coin.eth, // 仅 ETH 在 Sepolia
      );
      await controller.refresh();
      expect(prices.calls, 1);
      expect(controller.fiatValueUsd(Coin.eth), isNull); // 测试网 → 抑制
      expect(controller.fiatValueUsd(Coin.tron), isNotNull); // 主网 → 正常
      controller.dispose();
    });
  });

  group('首页测试网标识', () {
    MarketController liveController({bool testnet = false}) => MarketController(
      wallets: _wallets(),
      balances: _CountingBalanceService(),
      prices: _CountingPriceService(
        testnet ? null : {for (final c in Coin.values) c: 1.0},
      ),
      tokens: _FakeTokenService(const {}),
      isTestnet: (_) => testnet,
    );

    testWidgets('测试网作用域下显示琥珀徽章、法币总额 -- 与提示语', (tester) async {
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final controller = liveController(testnet: true);
      await tester.pumpWidget(
        _app(
          NetworkScope(
            controller: networks,
            child: MarketScope(
              controller: controller,
              child: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 琥珀测试网徽章(首页头部)。
      expect(find.text('测试网'), findsWidgets);
      // 法币总额被抑制为 '--',并带解释小字。
      expect(find.text('测试网资产无市场价格'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing); // 任何法币数字都不出现
      // 原生余额仍然真实展示(1 X = 1000000 raw / 6 decimals)。
      expect(find.textContaining('1 '), findsWidgets);
      // 网络芯片显示活动测试网名称("Ethereum" 仍作为资产行名出现,
      // 故只断言测试网芯片存在)。
      expect(find.text('Sepolia'), findsOneWidget);
      expect(find.text('Amoy'), findsOneWidget);
      expect(find.text('Nile'), findsOneWidget);
      expect(find.text('Devnet'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('无作用域时首页与从前逐字节一致(演示常量,无徽章)', (tester) async {
      await tester.pumpWidget(_app(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text(r'$862.40'), findsOneWidget); // 已知演示字符串
      expect(find.text('测试网'), findsNothing);
      expect(find.text('测试网资产无市场价格'), findsNothing);
      expect(find.text('Ethereum'), findsWidgets); // 主网芯片 + 演示资产行
      expect(find.text('Sepolia'), findsNothing);
    });
  });

  group('EVM chainId 跟随活动网络', () {
    final draft = TransferDraft(
      symbol: 'ETH',
      networkLabel: 'Ethereum',
      chain: Chain.ethereum,
      decimals: 18,
      recipient: '0x52908400098527886E0F7030069857D2E4169EE7',
      amount: Amount.parse('0.5', 18, symbol: 'ETH'),
      feeTier: 1,
    );
    const from = '0x8617E340B3D01FA5F11F306F4090FD50E238070D';

    test('Sepolia 活动时编码的 rawTx 携带 chainId 11155111(字节级比对)', () {
      final raw = rawTxFor(draft, from: from, evmChainId: 11155111);
      final gwei = BigInt.from(1000000000);
      final expected = Eip1559Tx.forTransfer(
        TransferIntent(
          chain: Chain.ethereum,
          operation: TxOperation.nativeTransfer,
          from: from,
          to: draft.recipient,
          amount: draft.amount,
        ),
        chainId: BigInt.from(11155111),
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.two * gwei,
        maxFeePerGas: BigInt.from(40) * gwei,
        gasLimit: BigInt.from(21000),
      ).encodeUnsigned();
      expect(raw, expected);
      // 与主网编码必然不同(签名域隔离正是要点)。
      expect(raw, isNot(rawTxFor(draft, from: from)));
    });

    testWidgets('W6 在 Sepolia 手续费估算失败时闭合，不生成可签名请求', (tester) async {
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final session = TransferSession()..draft = draft;
      // 节点不可达时不得再用演示 nonce/费率生成可签名交易。
      final service = _ThrowingParamsService();
      await tester.pumpWidget(
        _app(
          NetworkScope(
            controller: networks,
            child: TransferSessionScope(
              session: session,
              child: SignRequestQrScreen(paramsService: service),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(session.request, isNull);
      expect(
        find.text('Unable to estimate the network fee. Sending is disabled.'),
        findsOneWidget,
      );
    });

    test('buildSignRequest 把活动网络的 chainId 与名称写进协议字段', () {
      final request = buildSignRequest(
        draft: draft,
        walletId: 'WLT-TEST',
        fromAddress: from,
        evmChainId: 11155111,
        networkLabel: 'Sepolia',
      );
      expect(request.chainId, 11155111);
      // 签名器显示的网络行必须是真话:Sepolia 而非 Ethereum。
      expect(request.summary![SummaryKeys.network], 'Sepolia');
      // 默认(无网络来源)保持主网常量 —— 演示/金样不变。
      final mainnet = buildSignRequest(
        draft: draft,
        walletId: 'WLT-TEST',
        fromAddress: from,
      );
      expect(mainnet.chainId, 1);
      expect(mainnet.summary![SummaryKeys.network], 'Ethereum');
    });
  });

  group('区块浏览器链接跟随网络', () {
    test('各网络的交易链接格式', () {
      expect(
        explorerTxUrl(ethSepolia, '0xabc'),
        'https://sepolia.etherscan.io/tx/0xabc',
      );
      expect(
        explorerTxUrl(ethMainnet, '0xabc'),
        'https://etherscan.io/tx/0xabc',
      );
      expect(
        explorerTxUrl(tronMainnet, 'deadbeef'),
        'https://tronscan.org/#/transaction/deadbeef',
      );
      expect(
        explorerTxUrl(tronNile, 'deadbeef'),
        'https://nile.tronscan.org/#/transaction/deadbeef',
      );
      // Devnet 的 ?cluster=devnet 查询串必须保留在路径之后。
      expect(
        explorerTxUrl(solanaDevnet, 'sig'),
        'https://explorer.solana.com/tx/sig?cluster=devnet',
      );
      // 无 explorerUrl 的自定义网络回退到该链的主网浏览器。
      const custom = Network(
        id: 'custom-1',
        chain: Chain.ethereum,
        name: 'My Sepolia',
        rpcUrl: 'https://rpc.example',
        symbol: 'ETH',
        evmChainId: 11155111,
        isTestnet: true,
      );
      expect(explorerTxUrl(custom, '0xabc'), 'https://etherscan.io/tx/0xabc');
    });

    testWidgets('交易详情打开的链接使用活动 TRON 网络(Nile 覆盖)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final networks = NetworkController();
      await networks.setOverride(Chain.tron, 'tron-nile');
      final originalActions = ExternalActions.instance;
      final actions = FakeExternalActions();
      ExternalActions.instance = actions;
      addTearDown(() => ExternalActions.instance = originalActions);

      await tester.pumpWidget(
        _app(NetworkScope(controller: networks, child: const TxDetailScreen())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump();
      expect(
        actions.opened.single.toString(),
        startsWith('https://nile.tronscan.org/#/transaction/'),
      );
    });
  });

  group('历史记录跟随活动 TRON 网络', () {
    test('测试网环境下 TronGrid 请求发往 Nile(路径不变)', () async {
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final seen = <String>[];
      final service = HistoryService(
        endpoints: effectiveRpcEndpoints(null, networks),
        client: MockClient((request) async {
          seen.add(request.url.toString());
          return http.Response(jsonEncode({'data': <Object?>[]}), 200);
        }),
      );
      final result = await service.fetch(Coin.tron, 'TTronAddr');
      expect(result.status, HistoryStatus.ok);
      expect(seen, hasLength(2)); // trc20 + native,并发两条
      for (final url in seen) {
        expect(url, startsWith('https://nile.trongrid.io/v1/accounts/'));
      }
      service.close();
    });
  });
}
