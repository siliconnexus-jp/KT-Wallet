import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/device_mode.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/transaction_confirmation_service.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import 'support/full_device_evidence.dart';

const _resumeJson = String.fromEnvironment('KT_E2E_HISTORY_RESUME_JSON');
const _resumeMode = String.fromEnvironment(
  'KT_E2E_HISTORY_RESUME_MODE',
  defaultValue: 'history-resume',
);
const _oneWeiSepoliaHash =
    '0xc8fa48d646f0507d4f60114fb681a46f8db5f22ff9b1b652e10316583ee58a4a';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'physical iPhone resumes at sent/received history without replaying setup',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      expect(_resumeJson, isNotEmpty);
      tester.platformDispatcher.localesTestValue = const <Locale>[Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final resume = _ResumeEvidence.parse(_resumeJson);
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      final runId = 'ios-history-resume-$stamp';
      final evidence = await FullDeviceEvidence.create(runId: runId);
      evidence.startFrameworkErrorCapture();
      binding.reportData = <String, dynamic>{
        'evidence_source': 'Documents/kt-e2e-evidence/latest',
        'run_id': runId,
        'device_udid': const String.fromEnvironment('KT_E2E_DEVICE_UDID'),
      };

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = AppPrefsController();
      await prefs.load();
      await prefs.setAppLock(false);
      final mode = DeviceModeController(initial: DeviceMode.wallet);
      final locale = LocaleController(initial: const Locale('zh'));
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final database = db.WalletDatabase(
        NativeDatabase(File(evidence.databasePath)),
      );
      final store = WalletStore(database);
      final fundedWallet = HotWallet(
        id: 'kt-e2e-resume-funded-$stamp',
        name: '测试发送钱包',
        avatarColor: 0xFF0EA5E9,
        addresses: resume.fundedAddresses,
        sortOrder: 0,
        backedUp: true,
      );
      final receiverWallet = HotWallet(
        id: 'kt-e2e-resume-receiver-$stamp',
        name: '测试收款钱包',
        avatarColor: 0xFF10B981,
        addresses: resume.receiverAddresses,
        sortOrder: 1,
        backedUp: true,
      );
      await store.save(fundedWallet);
      await store.save(receiverWallet);
      final wallets = WalletController(
        WalletManager(initial: <Wallet>[fundedWallet, receiverWallet]),
        store: store,
      );
      await wallets.saveOutgoingTransaction(
        id: resume.transactionId,
        coin: Coin.eth,
        networkId: 'eth-sepolia',
        contract: resume.contract,
        from: resume.from,
        to: resume.to,
        amountRaw: '1000000',
        feeRaw: resume.feeRaw,
        hash: resume.hash,
        status: db.TxStatus.confirmed,
        signMode: db.SignMode.local,
        createdAt: resume.createdAt,
        broadcastAt: resume.broadcastAt,
      );
      await wallets.saveIncomingForLocalWallets(
        coin: Coin.eth,
        networkId: 'eth-sepolia',
        contract: resume.contract,
        from: resume.from,
        to: resume.to,
        amountRaw: '1000000',
        hash: resume.hash,
        createdAt: resume.createdAt,
        broadcastAt: resume.broadcastAt,
      );
      final incomingId =
          'incoming_${receiverWallet.id}_${resume.hash}_${resume.contract}';
      expect(
        await wallets.updateTransactionStatusForWallet(
          receiverWallet.id,
          incomingId,
          db.TxStatus.confirmed,
          hash: resume.hash,
          broadcastAt: resume.broadcastAt,
          lastCheckedAt: resume.lastCheckedAt,
          clearLastCheckOutcome: true,
        ),
        isTrue,
      );

      final confirmationService = TransactionConfirmationService(
        endpoints: effectiveRpcEndpoints(prefs, networks),
      );
      try {
        final live = await confirmationService
            .check(Chain.ethereum, resume.hash)
            .timeout(const Duration(minutes: 2));
        expect(live.status, db.TxStatus.confirmed);
        expect(live.confirmations, anyOf(isNull, greaterThan(0)));
        await evidence.setFact('phase', 'history-resume');
        await evidence.setFact('skipped_phases', <String>[
          'device mode selection',
          'wallet creation',
          'mnemonic import',
          'receive walkthrough',
          'security setup',
          'new transfer signing',
          'new transaction broadcast',
        ]);
        await evidence.setFact('source_run_id', resume.sourceRunId);
        await evidence.setFact('reused_real_transaction', <String, Object?>{
          'hash': resume.hash,
          'network': 'eth-sepolia',
          'contract': resume.contract,
          'amount_raw': '1000000',
          'decimals': 6,
          'display_amount': '1 USDT',
          'live_status': live.status.name,
          'live_confirmations': live.confirmations,
        });

        await binding.convertFlutterSurfaceToImage();
        await tester.pumpWidget(
          RepaintBoundary(
            key: evidence.screenshotBoundaryKey,
            child: RootApp(
              modeController: mode,
              localeController: locale,
              walletBootstrap: () async => wallets,
              walletPrefs: prefs,
              walletNetworks: networks,
            ),
          ),
        );
        await _waitUntil(
          tester,
          () => _semanticsFinder(
            '测试发送钱包, 普通',
          ).hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, 'R01 从发送钱包首页续跑');

        await _tapSemantics(tester, '记录');
        await _waitUntil(
          tester,
          () => find.text('交易记录').hitTestable().evaluate().isNotEmpty,
        );
        final outgoingRow = _historyRowForHash(resume.hash);
        await _waitUntil(
          tester,
          () => outgoingRow.evaluate().isNotEmpty,
          timeout: const Duration(minutes: 2),
        );
        await tester.ensureVisible(outgoingRow);
        expect(find.text('-1 USDT'), findsWidgets);
        await evidence.scanPage(
          binding,
          tester,
          'R02 发送钱包真实交易记录',
          facts: <String, Object?>{'transaction_hash': resume.hash},
        );
        if (_resumeMode == 'history-zero-detail') {
          final zeroAmountRow = _historyRowForHash(_oneWeiSepoliaHash);
          await _waitUntil(
            tester,
            () => zeroAmountRow.evaluate().isNotEmpty,
            timeout: const Duration(minutes: 2),
          );
          await tester.ensureVisible(zeroAmountRow);
          await tester.pumpAndSettle();
          await evidence.snapshot(
            binding,
            tester,
            'Z01 定位显示为零的 ETH 记录',
            facts: const <String, Object?>{
              'transaction_hash': _oneWeiSepoliaHash,
              'rpc_value_hex': '0x1',
              'rpc_value_raw': '1',
              'decimals': 18,
              'exact_amount': '0.000000000000000001 ETH',
              'list_display': '-0 ETH',
            },
          );
          await tester.tap(zeroAmountRow);
          await _waitUntil(
            tester,
            () => find
                .byKey(const ValueKey('transaction-export-receipt'))
                .hitTestable()
                .evaluate()
                .isNotEmpty,
          );
          await evidence.scanPage(
            binding,
            tester,
            'Z02 显示为零的 ETH 交易详情',
            facts: const <String, Object?>{
              'transaction_hash': _oneWeiSepoliaHash,
              'rpc_value_raw': '1',
              'expected_detail_raw_amount': '1',
            },
          );
          final explorer = find.byTooltip('在区块浏览器查看').hitTestable();
          expect(explorer, findsOneWidget);
          const explorerUrl =
              'https://sepolia.etherscan.io/tx/$_oneWeiSepoliaHash';
          await evidence.event(
            '点击区块浏览器入口',
            details: const <String, Object?>{
              'control': '交易详情右上角 ↗',
              'expected_url': explorerUrl,
              'transaction_hash': _oneWeiSepoliaHash,
            },
          );
          await tester.tap(explorer);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(FullDeviceEvidence.viewerPause),
          );
          await evidence.event(
            '区块浏览器入口点击完成',
            details: <String, Object?>{
              'expected_url': explorerUrl,
              'app_lifecycle_after_tap': tester.binding.lifecycleState?.name,
            },
          );
          await evidence.complete();
          return;
        }
        await tester.ensureVisible(outgoingRow);
        await tester.tap(outgoingRow);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('transaction-export-receipt'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('-1 USDT').hitTestable(), findsOneWidget);
        expect(find.text('1000000').hitTestable(), findsOneWidget);
        await evidence.scanPage(binding, tester, 'R03 USDT 发送交易详情');
        if (_resumeMode == 'history-local-explorer') {
          final explorer = find
              .byKey(const ValueKey('view-transaction-in-explorer'))
              .hitTestable();
          expect(explorer, findsOneWidget);
          expect(
            find.widgetWithText(OutlinedButton, '在区块浏览器查看').hitTestable(),
            findsOneWidget,
          );
          final explorerUrl = 'https://sepolia.etherscan.io/tx/${resume.hash}';
          await evidence.snapshot(
            binding,
            tester,
            'L01 本机交易区块浏览器按钮',
            facts: <String, Object?>{
              'transaction_hash': resume.hash,
              'expected_url': explorerUrl,
              'button_label': '在区块浏览器查看',
            },
          );
          await evidence.event(
            '点击本机交易区块浏览器按钮',
            details: <String, Object?>{
              'control': '在区块浏览器查看',
              'expected_url': explorerUrl,
              'transaction_hash': resume.hash,
            },
          );
          await tester.tap(explorer);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(FullDeviceEvidence.viewerPause),
          );
          await evidence.event(
            '本机交易区块浏览器按钮点击完成',
            details: <String, Object?>{
              'expected_url': explorerUrl,
              'app_lifecycle_after_tap': tester.binding.lifecycleState?.name,
            },
          );
          await evidence.complete();
          return;
        }

        await _tapBack(tester);
        await _waitUntil(
          tester,
          () => find.text('交易记录').hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, 'R04 详情返回交易记录');
        await _tapBack(tester);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('home-tab-0'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        await _scrollCurrentPageToTop(tester);
        await _waitUntil(
          tester,
          () => _semanticsFinder(
            '测试发送钱包, 普通',
          ).hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, 'R05 交易记录返回首页');

        await _tapSemantics(tester, '测试发送钱包, 普通');
        await _waitUntil(
          tester,
          () => find.text('测试收款钱包').hitTestable().evaluate().isNotEmpty,
        );
        await tester.tap(find.text('测试收款钱包').hitTestable());
        await _waitUntil(
          tester,
          () =>
              wallets.current?.id == receiverWallet.id &&
              _semanticsFinder(
                '测试收款钱包, 普通',
              ).hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, 'R06 切换到收款钱包');

        await _tapSemantics(tester, '记录');
        await _waitUntil(
          tester,
          () => find.text('交易记录').hitTestable().evaluate().isNotEmpty,
        );
        final incomingRow = _historyRowForHash(resume.hash);
        await _waitUntil(
          tester,
          () => incomingRow.evaluate().isNotEmpty,
          timeout: const Duration(minutes: 2),
        );
        await tester.ensureVisible(incomingRow);
        expect(find.text('+1 USDT'), findsWidgets);
        await evidence.scanPage(
          binding,
          tester,
          'R07 收款钱包真实入账记录',
          facts: <String, Object?>{
            'transaction_hash': resume.hash,
            'amount_raw': '1000000',
            'decimals': 6,
          },
        );
        await tester.ensureVisible(incomingRow);
        await tester.tap(incomingRow);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('transaction-export-receipt'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('+1 USDT').hitTestable(), findsOneWidget);
        expect(find.text('1000000').hitTestable(), findsOneWidget);
        await evidence.scanPage(binding, tester, 'R08 USDT 收款交易详情');
        await evidence.complete();
      } on Object catch (error, stackTrace) {
        await evidence.fail(error, stackTrace);
        rethrow;
      } finally {
        evidence.stopFrameworkErrorCapture();
        confirmationService.close();
        prefs.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

class _ResumeEvidence {
  const _ResumeEvidence({
    required this.sourceRunId,
    required this.fundedAddresses,
    required this.receiverAddresses,
    required this.transactionId,
    required this.contract,
    required this.from,
    required this.to,
    required this.feeRaw,
    required this.hash,
    required this.createdAt,
    required this.broadcastAt,
    required this.lastCheckedAt,
  });

  factory _ResumeEvidence.parse(String encoded) {
    final root = jsonDecode(encoded);
    if (root is! Map<String, Object?> ||
        root['funded_wallet_addresses'] is! Map<String, Object?> ||
        root['receiver_wallet_addresses'] is! Map<String, Object?> ||
        root['transaction'] is! Map<String, Object?>) {
      throw const FormatException('Invalid history-resume payload.');
    }
    final transaction = root['transaction']! as Map<String, Object?>;
    final funded = ChainAddresses.fromMap(
      root['funded_wallet_addresses']! as Map<String, Object?>,
    );
    final receiver = ChainAddresses.fromMap(
      root['receiver_wallet_addresses']! as Map<String, Object?>,
    );
    final hash = transaction['hash'];
    final contract = transaction['contract'];
    if (root['source_run_id'] is! String ||
        transaction['id'] is! String ||
        hash is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash) ||
        contract is! String ||
        contract.toLowerCase() !=
            '0xc4dcc311c028e341fd8602d8eb89c5de94625927' ||
        transaction['amount_raw'] != '1000000' ||
        transaction['network_id'] != 'eth-sepolia' ||
        transaction['status'] != 'confirmed' ||
        transaction['from'] is! String ||
        transaction['to'] is! String ||
        transaction['created_at'] is! int ||
        transaction['broadcast_at'] is! int ||
        transaction['last_checked_at'] is! int) {
      throw const FormatException('Unsafe history-resume transaction.');
    }
    return _ResumeEvidence(
      sourceRunId: root['source_run_id']! as String,
      fundedAddresses: funded,
      receiverAddresses: receiver,
      transactionId: transaction['id']! as String,
      contract: contract,
      from: transaction['from']! as String,
      to: transaction['to']! as String,
      feeRaw: transaction['fee_raw'] as String?,
      hash: hash,
      createdAt: transaction['created_at']! as int,
      broadcastAt: transaction['broadcast_at']! as int,
      lastCheckedAt: transaction['last_checked_at']! as int,
    );
  }

  final String sourceRunId;
  final ChainAddresses fundedAddresses;
  final ChainAddresses receiverAddresses;
  final String transactionId;
  final String contract;
  final String from;
  final String to;
  final String? feeRaw;
  final String hash;
  final int createdAt;
  final int broadcastAt;
  final int lastCheckedAt;
}

Finder _historyRowForHash(String hash) {
  final normalized = hash.toLowerCase();
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('history-record-') &&
        key.value.toLowerCase().contains(normalized);
  }, description: 'history row bound to real transaction $hash');
}

Finder _semanticsFinder(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
  description: 'Semantics(label: $label)',
);

Future<void> _tapSemantics(WidgetTester tester, String label) async {
  final finder = _semanticsFinder(label);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final target = find
      .descendant(
        of: finder,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector ||
              widget is InkWell ||
              widget is ButtonStyleButton ||
              widget is IconButton,
        ),
      )
      .hitTestable();
  await tester.tap(
    target.evaluate().isNotEmpty ? target.first : finder.hitTestable(),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapBack(WidgetTester tester) async {
  final back = find.byTooltip('返回').hitTestable();
  expect(back, findsOneWidget);
  await tester.tap(back);
  await tester.pumpAndSettle();
}

Future<void> _scrollCurrentPageToTop(WidgetTester tester) async {
  for (final element in find.byType(Scrollable).hitTestable().evaluate()) {
    final widget = element.widget as Scrollable;
    if (widget.axisDirection != AxisDirection.down &&
        widget.axisDirection != AxisDirection.up) {
      continue;
    }
    final state = tester.state<ScrollableState>(find.byWidget(widget));
    if (state.position.pixels != state.position.minScrollExtent) {
      state.position.jumpTo(state.position.minScrollExtent);
      await tester.pumpAndSettle();
    }
    return;
  }
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('UI condition was not reached');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
