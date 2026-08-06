import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/device_mode.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:kt_wallet/src/widgets/pin_pad.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';
import 'support/full_device_evidence.dart';

const _fundedMnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
const _walletPin = '260806';
const _expectedFundedEvm = '0xb787f3c2f96403b5a73dc66de68e4a6395d4e632';
const _expectedFundedTron = 'TWDUoCRgRec4rwcbMR9FMP6gj232qnYmzY';
const _expectedFundedSolana = 'poaanuPuS731Dp1ppH1RABhz1pTwJFdrS7vbrhaHYuj';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'physical iPhone full create/import/receive/transfer/history journey',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      expect(_fundedMnemonic.trim(), isNotEmpty);
      tester.platformDispatcher.localesTestValue = const <Locale>[Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      final runId = 'ios-full-device-$stamp';
      final createdWalletId = 'kt-e2e-created-$stamp';
      final fundedWalletId = 'kt-e2e-funded-$stamp';
      final evidence = await FullDeviceEvidence.create(runId: runId);
      evidence.startFrameworkErrorCapture();
      binding.reportData = <String, dynamic>{
        'evidence_source': 'Documents/kt-e2e-evidence/latest',
        'run_id': runId,
        'device_udid': const String.fromEnvironment('KT_E2E_DEVICE_UDID'),
      };
      final crypto = _PhysicalIosE2eCoreCrypto();
      final pinStorage = _NamespacedSecurePinStorage();
      final originalPin = WalletPin.instance;
      WalletPin.instance = WalletPin(pinStorage);
      await WalletPin.instance.clear();

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = AppPrefsController();
      await prefs.load();
      await prefs.setAppLock(false);
      // The app-password route is a real UI/PBKDF2/Keychain flow. Selecting it
      // up front prevents an unscriptable out-of-process Face ID sheet from
      // interrupting a fully unattended run.
      await prefs.setAuthMethod(AuthMethod.password);
      final mode = DeviceModeController();
      final locale = LocaleController(initial: const Locale('zh'));
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final transferSession = TransferSession();
      final database = db.WalletDatabase(
        NativeDatabase(File(evidence.databasePath)),
      );
      final wallets = _QueuedIdWalletController(
        WalletManager(),
        crypto: crypto,
        store: WalletStore(database),
        walletIds: <String>[createdWalletId, fundedWalletId],
      );

      await evidence.setSecret('wallet_pin', _walletPin);
      await evidence.setSecret('funded_import_mnemonic', _fundedMnemonic);
      await evidence.setFact(
        'device_udid_expected_from_runner',
        const String.fromEnvironment('KT_E2E_DEVICE_UDID'),
      );
      await evidence.setFact('network_environment', 'testnet');
      await evidence.setFact('chain_data_source', 'real Gateway/RPC');
      await evidence.setFact('crypto_source', 'real iOS Wallet Core');
      await evidence.setFact(
        'authentication',
        'real wallet PIN UI + PBKDF2 + namespaced iOS Keychain; '
            'native Wallet Core test signing bypass exists only in DEBUG and '
            'only for kt-e2e-* wallet IDs',
      );

      var nativeCleaned = false;
      try {
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
              walletTransferSession: transferSession,
            ),
          ),
        );

        await _waitUntil(
          tester,
          () => find.text('选择设备模式').evaluate().isNotEmpty,
        );
        await evidence.scanPage(binding, tester, '01 首启设备模式选择');
        await evidence.event(
          '点击控件',
          details: const <String, Object?>{'label': '联网钱包'},
        );
        await tester.tap(find.text('联网钱包'));
        await _waitUntil(
          tester,
          () => find.text('创建新钱包').evaluate().isNotEmpty,
        );
        expect(mode.mode, DeviceMode.wallet);
        await evidence.scanPage(binding, tester, '02 空钱包添加入口');

        await evidence.event(
          '点击控件',
          details: const <String, Object?>{'label': '创建新钱包'},
        );
        await tester.tap(find.text('创建新钱包'));
        await _waitUntil(
          tester,
          () => find.text('显示助记词').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 45),
        );
        await evidence.scanPage(binding, tester, '03 创建钱包安全提示');

        await tester.tap(find.text('显示助记词'));
        await _waitUntil(
          tester,
          () => find.byKey(const Key('mnemonic-word-0')).evaluate().isNotEmpty,
        );
        final displayedCreatedWords = <String>[
          for (var i = 0; i < 12; i++)
            tester.widget<Text>(find.byKey(Key('mnemonic-word-$i'))).data!,
        ];
        final displayedCreatedMnemonic = displayedCreatedWords.join(' ');
        expect(displayedCreatedMnemonic.split(' '), hasLength(12));
        expect(
          displayedCreatedMnemonic,
          wallets.pendingMnemonic,
          reason:
              'The phrase read from the physical UI must be the phrase '
              'held for native wallet creation.',
        );
        await evidence.setSecret(
          'created_mnemonic_read_from_device_ui',
          displayedCreatedMnemonic,
        );
        await evidence.scanPage(
          binding,
          tester,
          '04 创建助记词完整展示',
          facts: <String, Object?>{
            'word_count': displayedCreatedWords.length,
            'words_read_via_widget_keys': displayedCreatedWords,
          },
        );

        await tester.tap(find.text('我已手写备份，开始校验'));
        await _waitUntil(tester, () => find.text('校验备份').evaluate().isNotEmpty);
        await evidence.scanPage(binding, tester, '05 助记词校验未选择');
        final challengeWord = displayedCreatedWords[3];
        await evidence.event(
          '选择助记词校验答案',
          details: <String, Object?>{
            'position': 4,
            'selected_word': challengeWord,
          },
        );
        final challengeOption = find.text(challengeWord).hitTestable();
        expect(challengeOption, findsOneWidget);
        await tester.tap(challengeOption);
        await tester.pumpAndSettle();
        await evidence.snapshot(
          binding,
          tester,
          '06 助记词校验已选择',
          facts: <String, Object?>{
            'position': 4,
            'selected_word': challengeWord,
          },
        );
        final mnemonicConfirm = find
            .widgetWithText(KtPrimaryButton, '确认')
            .hitTestable();
        expect(mnemonicConfirm, findsOneWidget);
        await tester.tap(mnemonicConfirm);
        await _waitForWalletCreationOutcome(binding, tester, evidence);
        final createdWallet = wallets.current! as HotWallet;
        expect(createdWallet.id, createdWalletId);
        final createdAddresses = _addressesJson(createdWallet.addresses);
        await evidence.setFact('created_wallet_id', createdWallet.id);
        await evidence.setFact('created_wallet_addresses', createdAddresses);
        await evidence.scanPage(
          binding,
          tester,
          '07 新建钱包首页',
          facts: <String, Object?>{
            'wallet_name': createdWallet.name,
            'wallet_id': createdWallet.id,
            'addresses': createdAddresses,
          },
        );

        await _tapSemantics(tester, '钱包 1, 普通');
        await _waitUntil(tester, () => find.text('添加钱包').evaluate().isNotEmpty);
        await evidence.scanPage(binding, tester, '08 钱包切换器');
        final addWalletButton = find.widgetWithText(KtPrimaryButton, '添加钱包');
        await tester.ensureVisible(addWalletButton);
        await tester.pumpAndSettle();
        expect(addWalletButton.hitTestable(), findsOneWidget);
        await tester.tap(addWalletButton);
        await _waitUntil(
          tester,
          () => find.text('导入助记词').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('导入助记词'));
        await _waitUntil(
          tester,
          () => find.byType(TextField).evaluate().length == 12,
        );
        await evidence.scanPage(binding, tester, '09 导入助记词空表单');

        final importWords = _fundedMnemonic.trim().split(RegExp(r'\s+'));
        expect(importWords, hasLength(12));
        for (var i = 0; i < importWords.length; i++) {
          final field = find.byType(TextField).at(i);
          await tester.ensureVisible(field);
          await tester.enterText(field, importWords[i]);
          await tester.pump();
          expect(
            tester.widget<TextField>(field).controller!.text,
            importWords[i],
          );
          await evidence.snapshot(
            binding,
            tester,
            '10 导入助记词输入 ${i + 1} of 12',
            facts: <String, Object?>{
              'field_index': i + 1,
              'entered_word': importWords[i],
              'completed_fields': i + 1,
            },
            screenshot: false,
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await evidence.scanPage(
          binding,
          tester,
          '11 导入助记词完整表单',
          facts: <String, Object?>{
            'mnemonic_read_back_from_fields': <String>[
              for (final field in tester.widgetList<TextField>(
                find.byType(TextField),
              ))
                field.controller!.text,
            ].join(' '),
          },
        );
        final importButton = find.widgetWithText(KtPrimaryButton, '导入');
        await tester.ensureVisible(importButton);
        expect(
          tester.widget<KtPrimaryButton>(importButton).onPressed,
          isNotNull,
        );
        await tester.tap(importButton);
        await _waitUntil(
          tester,
          () => find.text('导入钱包 2').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 45),
        );
        final fundedWallet = wallets.current! as HotWallet;
        expect(fundedWallet.id, fundedWalletId);
        expect(fundedWallet.addresses.eth.toLowerCase(), _expectedFundedEvm);
        expect(fundedWallet.addresses.tron, _expectedFundedTron);
        expect(fundedWallet.addresses.solana, _expectedFundedSolana);
        final fundedAddresses = _addressesJson(fundedWallet.addresses);
        await evidence.setFact('funded_wallet_id', fundedWallet.id);
        await evidence.setFact('funded_wallet_addresses', fundedAddresses);

        final liveBalances = await _waitForFundedHomeBalances(tester);
        await evidence.setFact('funded_home_balance_labels', liveBalances);
        await evidence.scanPage(
          binding,
          tester,
          '12 导入测试钱包真实余额首页',
          facts: <String, Object?>{'funded_balance_labels': liveBalances},
        );

        await _exerciseReceiveFlows(
          binding,
          tester,
          evidence,
          fundedWallet.addresses,
        );
        await _tapBack(tester);
        await _waitUntil(
          tester,
          () => find.byKey(const ValueKey('home-tab-2')).evaluate().isNotEmpty,
        );
        expect(wallets.current?.id, fundedWalletId);
        await evidence.scanPage(
          binding,
          tester,
          '24 收款返回测试钱包首页',
          facts: <String, Object?>{
            'current_wallet_id': wallets.current?.id,
            'current_wallet_name': wallets.current?.name,
          },
        );

        await tester.tap(find.byKey(const ValueKey('home-tab-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('安全设置'));
        await _waitUntil(
          tester,
          () => find.text('App 锁').evaluate().isNotEmpty,
        );
        await evidence.scanPage(binding, tester, '30 安全设置初始状态');
        expect(prefs.appLock, isFalse);
        await _tapSemantics(tester, 'App 锁');
        await _waitUntil(
          tester,
          () => find.text('设置 6 位密码').evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, '31 设置钱包 PIN 第一遍');
        await _enterPinWithEvidence(
          binding,
          tester,
          evidence,
          _walletPin,
          phase: '设置第一遍',
          closesAfterSix: false,
        );
        expect(find.text('再次输入以确认'), findsOneWidget);
        await evidence.snapshot(binding, tester, '32 设置钱包 PIN 第二遍');
        await _enterPinWithEvidence(
          binding,
          tester,
          evidence,
          _walletPin,
          phase: '设置第二遍',
          closesAfterSix: true,
        );
        await _waitUntil(tester, () => prefs.appLock);
        expect(await WalletPin.instance.isSet(), isTrue);
        await evidence.scanPage(
          binding,
          tester,
          '33 App 锁已启用',
          facts: const <String, Object?>{
            'app_lock': true,
            'pin_storage': 'namespaced iOS Keychain',
          },
        );

        await tester.tap(find.text('验证方式'));
        await _waitUntil(
          tester,
          () => find.widgetWithText(ListTile, '钱包密码').evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, '34 验证方式选择器');
        await tester.tap(find.widgetWithText(ListTile, '钱包密码'));
        await tester.pumpAndSettle();
        expect(prefs.authMethod, AuthMethod.password);
        await evidence.snapshot(
          binding,
          tester,
          '35 验证方式保持钱包密码',
          facts: const <String, Object?>{'auth_method': 'password'},
        );
        await _tapBack(tester);
        await tester.tap(find.byKey(const ValueKey('home-tab-0')));
        await tester.pumpAndSettle();

        final ethTransaction = await _submitRealSepoliaTransfer(
          binding,
          tester,
          evidence,
          wallets,
          transferSession,
          assetSubtitle: 'Sepolia',
          symbol: 'ETH',
          recipient: createdWallet.addresses.eth,
          amount: '0.00001',
          slug: 'eth',
        );
        await tester.tap(find.text('返回首页'));
        await _waitUntil(tester, () => find.text('转账').evaluate().isNotEmpty);

        final usdtTransaction = await _submitRealSepoliaTransfer(
          binding,
          tester,
          evidence,
          wallets,
          transferSession,
          assetSubtitle: 'Sepolia · ERC-20',
          symbol: 'USDT',
          recipient: createdWallet.addresses.eth,
          amount: '1',
          slug: 'usdt',
        );
        expect(usdtTransaction.amountRaw, '1000000');
        await evidence.setFact(
          'sepolia_eth_transaction',
          _transactionJson(ethTransaction),
        );
        await evidence.setFact(
          'sepolia_usdt_transaction',
          _transactionJson(usdtTransaction),
        );

        await tester.tap(find.text('返回首页'));
        await _waitUntil(tester, () => find.text('记录').evaluate().isNotEmpty);
        await _tapSemantics(tester, '记录');
        final outgoingUsdtRow = _historyRowForHash(usdtTransaction.hash!);
        await _waitUntil(
          tester,
          () => outgoingUsdtRow.evaluate().isNotEmpty,
          timeout: const Duration(minutes: 2),
        );
        await evidence.scanPage(binding, tester, '60 发送钱包交易记录');
        expect(outgoingUsdtRow, findsOneWidget);
        await tester.ensureVisible(outgoingUsdtRow);
        await tester.tap(outgoingUsdtRow);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('transaction-export-receipt'))
              .evaluate()
              .isNotEmpty,
        );
        await evidence.scanPage(
          binding,
          tester,
          '61 USDT 发送交易详情',
          facts: <String, Object?>{
            'full_transaction': _transactionJson(usdtTransaction),
          },
        );

        await _tapBack(tester);
        await _waitUntil(
          tester,
          () => find.text('交易记录').hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, '61A 发送详情返回记录列表');
        await _tapBack(tester);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('home-tab-0'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('home-tab-0')).hitTestable(),
        );
        await tester.pumpAndSettle();
        await _waitUntil(
          tester,
          () =>
              wallets.current?.id == fundedWallet.id &&
              _semanticsFinder(
                '导入钱包 2, 普通',
              ).hitTestable().evaluate().isNotEmpty,
        );
        await evidence.snapshot(binding, tester, '61B 记录返回发送钱包首页');
        await _tapSemantics(tester, '导入钱包 2, 普通');
        await _waitUntil(tester, () => find.text('钱包 1').evaluate().isNotEmpty);
        await tester.tap(find.text('钱包 1'));
        await _waitUntil(
          tester,
          () =>
              find.text('钱包 1').evaluate().isNotEmpty &&
              wallets.current?.id == createdWallet.id,
        );
        await evidence.scanPage(binding, tester, '62 切换到收款钱包');
        await _tapSemantics(tester, '记录');
        final incomingUsdtRow = _historyRowForHash(usdtTransaction.hash!);
        await _waitUntil(
          tester,
          () => incomingUsdtRow.evaluate().isNotEmpty,
          timeout: const Duration(minutes: 2),
        );
        await evidence.scanPage(
          binding,
          tester,
          '63 收款钱包入账记录',
          facts: <String, Object?>{
            'source_hash': usdtTransaction.hash,
            'expected_amount_raw': '1000000',
            'expected_decimals': 6,
            'expected_display': '+1 USDT',
          },
        );
        expect(incomingUsdtRow, findsOneWidget);
        await tester.ensureVisible(incomingUsdtRow);
        await tester.tap(incomingUsdtRow);
        await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('transaction-export-receipt'))
              .evaluate()
              .isNotEmpty,
        );
        await evidence.scanPage(binding, tester, '64 USDT 收款交易详情');

        await _cleanupNativeWallets(crypto, <String>[
          createdWalletId,
          fundedWalletId,
        ]);
        nativeCleaned = true;
        await WalletPin.instance.clear();
        await evidence.complete();
      } on Object catch (error, stackTrace) {
        await evidence.fail(error, stackTrace);
        rethrow;
      } finally {
        evidence.stopFrameworkErrorCapture();
        if (!nativeCleaned) {
          try {
            await _cleanupNativeWallets(crypto, <String>[
              createdWalletId,
              fundedWalletId,
            ]);
          } on Object {
            // Preserve the original journey failure; the private report keeps
            // the failing step and run-scoped wallet IDs for manual cleanup.
          }
        }
        try {
          await WalletPin.instance.clear();
        } on Object {
          // The namespaced key cannot affect production PIN state.
        }
        WalletPin.instance = originalPin;
        prefs.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Finder _historyRowForHash(String hash) {
  final normalized = hash.toLowerCase();
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('history-record-') &&
        key.value.toLowerCase().contains(normalized);
  }, description: 'history row bound to transaction $hash');
}

class _PhysicalIosE2eCoreCrypto extends MethodChannelCoreCrypto {
  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) async {
    await super.storeWallet(
      walletId: walletId,
      mnemonic: mnemonic,
      requireAuth: false,
      kdfPassword: kdfPassword,
    );
    registerE2eWalletCleanup(this, walletId);
  }

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async {
    CoreCryptoValidation.checkWalletId(walletId);
    CoreCryptoValidation.checkSigningInput(signingInput);
    if (!walletId.startsWith('kt-e2e-')) {
      throw ArgumentError.value(walletId, 'walletId');
    }
    final map = await channel.invokeMethod<Map<Object?, Object?>>(
      'signTransactionForIntegrationTest',
      <String, Object?>{
        'walletId': walletId,
        'coin': coin.name,
        'signingInput': signingInput,
      },
    );
    if (map == null ||
        map['signedTx'] is! Uint8List ||
        map['txHash'] is! String) {
      throw StateError('iOS integration signing returned an invalid result');
    }
    return SignedTransaction(
      signedTx: map['signedTx']! as Uint8List,
      txHash: map['txHash']! as String,
    );
  }

  @override
  Future<void> deleteWallet(String walletId) async {
    CoreCryptoValidation.checkWalletId(walletId);
    if (!walletId.startsWith('kt-e2e-')) {
      return super.deleteWallet(walletId);
    }
    final deleted = await channel.invokeMethod<bool>(
      'deleteWalletForIntegrationTest',
      <String, Object?>{'walletId': walletId},
    );
    if (deleted != true) throw StateError('iOS integration deletion failed');
  }
}

class _QueuedIdWalletController extends WalletController {
  // A super parameter cannot name WalletController's library-private field.
  // ignore: use_super_parameters
  _QueuedIdWalletController(
    WalletManager manager, {
    required CoreCrypto crypto,
    required WalletStore store,
    required List<String> walletIds,
  }) : _walletIds = List<String>.of(walletIds),
       super(manager, crypto: crypto, store: store);

  final List<String> _walletIds;

  @override
  String allocateWalletId() {
    if (_walletIds.isEmpty) {
      throw StateError('No reserved E2E wallet ID remains');
    }
    return _walletIds.removeAt(0);
  }
}

class _NamespacedSecurePinStorage implements PinStorage {
  static const _prefix = 'kt.full_device_e2e.';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _key(String key) => '$_prefix$key';

  @override
  Future<void> delete(String key) => _storage.delete(key: _key(key));

  @override
  Future<String?> read(String key) => _storage.read(key: _key(key));

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: _key(key), value: value);
}

Future<void> _exerciseReceiveFlows(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  FullDeviceEvidence evidence,
  ChainAddresses addresses,
) async {
  await _tapSemantics(tester, '收款');
  await _waitUntil(tester, () => find.text('收款').evaluate().isNotEmpty);
  final scenarios = <({Coin coin, String picker, String pill, String slug})>[
    (coin: Coin.tron, picker: 'TRON', pill: 'USDT · TRON', slug: 'tron'),
    (
      coin: Coin.eth,
      picker: 'Ethereum',
      pill: 'ETH · Ethereum',
      slug: 'ethereum',
    ),
    (
      coin: Coin.polygon,
      picker: 'Polygon',
      pill: 'POL · Polygon',
      slug: 'polygon',
    ),
    (coin: Coin.base, picker: 'Base', pill: 'ETH · Base', slug: 'base'),
    (
      coin: Coin.arbitrum,
      picker: 'Arbitrum One',
      pill: 'ETH · Arbitrum',
      slug: 'arbitrum',
    ),
    (
      coin: Coin.avalanche,
      picker: 'Avalanche C-Chain',
      pill: 'AVAX · Avalanche',
      slug: 'avalanche',
    ),
    (
      coin: Coin.bnb,
      picker: 'BNB Smart Chain',
      pill: 'BNB · BNB Smart Chain',
      slug: 'bnb',
    ),
    (coin: Coin.solana, picker: 'Solana', pill: 'SOL · Solana', slug: 'solana'),
  ];

  var currentPill = scenarios.first.pill;
  for (final scenario in scenarios) {
    if (scenario.pill != currentPill) {
      await tester.tap(find.text(currentPill));
      await tester.pumpAndSettle();
      await evidence.snapshot(binding, tester, '20 收款网络选择器 ${scenario.slug}');
      await tester.tap(find.text(scenario.picker));
      await tester.pumpAndSettle();
      currentPill = scenario.pill;
    }
    final address = addresses.forCoin(scenario.coin);
    expect(find.text(scenario.pill), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    expect(tester.widget<KtQrCode>(find.byType(KtQrCode)).data, address);
    await evidence.scanPage(
      binding,
      tester,
      '21 收款 ${scenario.slug}',
      facts: <String, Object?>{
        'coin': scenario.coin.name,
        'displayed_address': address,
        'qr_payload': tester.widget<KtQrCode>(find.byType(KtQrCode)).data,
      },
    );
    await tester.tap(find.byKey(const ValueKey('receive-copy')));
    await _waitUntil(tester, () => find.text('地址已复制').evaluate().isNotEmpty);
    await evidence.snapshot(
      binding,
      tester,
      '22 收款地址复制反馈 ${scenario.slug}',
      facts: <String, Object?>{'copied_address': address},
      screenshot: false,
    );
  }

  await _exerciseRealSolanaAirdrop(binding, tester, evidence);

  final save = find.byKey(const ValueKey('receive-save-image'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await _waitUntil(
    tester,
    () => find.text('已保存到相册').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 90),
  );
  await evidence.snapshot(binding, tester, '23 收款图片保存成功');
}

Future<void> _exerciseRealSolanaAirdrop(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  FullDeviceEvidence evidence,
) async {
  final action = find.byKey(const ValueKey('faucet-action')).hitTestable();
  expect(action, findsOneWidget);
  expect(find.text('领取测试币'), findsOneWidget);
  await evidence.snapshot(binding, tester, '22A Solana 领取测试币操作前');
  await evidence.event(
    '点击控件',
    details: const <String, Object?>{
      'label': '领取测试币',
      'network': 'Solana Devnet',
      'source': 'real active RPC requestAirdrop',
    },
  );
  await tester.tap(action);
  await tester.pump();
  await evidence.snapshot(binding, tester, '22B Solana 测试币请求中');

  const outcomes = <String>[
    '空投成功，余额稍后刷新',
    '请求过于频繁，请稍后重试',
    '测试币服务暂时不可用',
    '水龙头拒绝了该地址或请求',
    '水龙头测试币余额不足',
    '水龙头拒绝了请求',
    '测试币服务返回了无效响应',
    '已打开测试币水龙头',
    '无法打开外部应用，请稍后重试',
  ];
  await _waitUntil(
    tester,
    () => outcomes.any((message) => find.text(message).evaluate().isNotEmpty),
    timeout: const Duration(seconds: 45),
  );
  final outcome = outcomes.firstWhere(
    (message) => find.text(message).evaluate().isNotEmpty,
  );
  await evidence.snapshot(
    binding,
    tester,
    '22C Solana 领取测试币真实结果',
    facts: <String, Object?>{'result_message': outcome},
  );
}

Future<db.Transaction> _submitRealSepoliaTransfer(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  FullDeviceEvidence evidence,
  WalletController wallets,
  TransferSession session, {
  required String assetSubtitle,
  required String symbol,
  required String recipient,
  required String amount,
  required String slug,
}) async {
  await _tapSemantics(tester, '转账');
  await _waitUntil(tester, () => find.text('收款地址').evaluate().isNotEmpty);
  await evidence.scanPage(binding, tester, '40 $slug 转账空表单');

  await tester.tap(find.byKey(const ValueKey('transfer-asset')));
  await tester.pumpAndSettle();
  await evidence.scanPage(binding, tester, '41 $slug 资产选择器');
  final networkChoice = find.byWidgetPredicate(
    (widget) =>
        widget is Text && (widget.data ?? '').startsWith('$assetSubtitle · 可用'),
    description: 'asset subtitle starting with "$assetSubtitle · 可用"',
  );
  expect(networkChoice, findsOneWidget);
  await tester.ensureVisible(networkChoice);
  await tester.tap(networkChoice);
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), recipient);
  await tester.pumpAndSettle();
  await evidence.snapshot(
    binding,
    tester,
    '42 $slug 收款地址已输入',
    facts: <String, Object?>{'recipient': recipient},
  );
  expect(find.textContaining('地址格式正确'), findsOneWidget);

  await tester.enterText(fields.at(1), amount);
  await tester.pumpAndSettle();
  await evidence.snapshot(
    binding,
    tester,
    '43 $slug 金额已输入',
    facts: <String, Object?>{'amount': amount, 'symbol': symbol},
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final fastFee = find.text('快');
  await tester.ensureVisible(fastFee);
  await tester.pumpAndSettle();
  final fastFeeTarget = fastFee.hitTestable();
  expect(fastFeeTarget, findsOneWidget);
  await evidence.snapshot(binding, tester, '43A $slug 手续费控件已可见');
  await tester.tap(fastFeeTarget);
  await tester.pumpAndSettle();
  await evidence.snapshot(binding, tester, '44 $slug 手续费切换为快');
  final standardFee = find.text('标准');
  await tester.ensureVisible(standardFee);
  await tester.pumpAndSettle();
  final standardFeeTarget = standardFee.hitTestable();
  expect(standardFeeTarget, findsOneWidget);
  await tester.tap(standardFeeTarget);
  await tester.pumpAndSettle();
  await evidence.scanPage(binding, tester, '45 $slug 完整转账表单');

  final next = find.widgetWithText(KtPrimaryButton, '下一步').hitTestable();
  expect(next, findsOneWidget);
  await tester.tap(next);
  await _waitUntil(tester, () => find.text('确认交易').evaluate().isNotEmpty);
  final confirmButton = find.widgetWithText(KtPrimaryButton, '确认转账');
  final feeDeadline = DateTime.now().add(const Duration(minutes: 2));
  while (confirmButton.evaluate().isEmpty ||
      tester.widget<KtPrimaryButton>(confirmButton).onPressed == null) {
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final preparationFailure = session.preparationFailure;
    if (preparationFailure != null) {
      await evidence.scanPage(
        binding,
        tester,
        '46A $slug 真实网络费估算失败',
        facts: <String, Object?>{
          'error_message': '无法估算网络费，暂时无法发送',
          'preparation_failure': preparationFailure,
        },
      );
      throw TestFailure(
        'Real fee estimation failed on the $slug confirmation screen: '
        '$preparationFailure',
      );
    }
    if (DateTime.now().isAfter(feeDeadline)) {
      throw TimeoutException('$slug fee estimation did not become ready');
    }
  }
  final draft = session.draft!;
  await evidence.scanPage(
    binding,
    tester,
    '46 $slug 确认转账与真实费用',
    facts: <String, Object?>{
      'symbol': draft.symbol,
      'network': draft.networkLabel,
      'recipient': draft.recipient,
      'amount_text': draft.amountText,
      'amount_raw': draft.amount.raw.toString(),
      'decimals': draft.amount.decimals,
      'token_contract': draft.tokenContract,
    },
  );

  final confirmTarget = confirmButton.hitTestable();
  expect(confirmTarget, findsOneWidget);
  await tester.tap(confirmTarget);
  await _waitUntil(tester, () => find.text('验证以确认转账').evaluate().isNotEmpty);
  await evidence.scanPage(binding, tester, '47 $slug 转账验证方式');
  await tester.tap(find.widgetWithText(KtPrimaryButton, '钱包密码'));
  await _waitUntil(tester, () => find.byType(PinDots).evaluate().isNotEmpty);
  await evidence.snapshot(binding, tester, '48 $slug 转账 PIN 初始状态');
  await _enterPinWithEvidence(
    binding,
    tester,
    evidence,
    _walletPin,
    phase: '$slug 转账验证',
    closesAfterSix: true,
  );

  await _waitForSubmitted(tester, timeout: const Duration(minutes: 3));
  final hash = session.broadcastTxHash;
  expect(hash, isNotNull);
  await evidence.setFact('$slug.broadcast_hash', hash);
  await evidence.snapshot(
    binding,
    tester,
    '49 $slug 广播已提交',
    facts: <String, Object?>{'transaction_hash': hash},
  );

  String? previousStatus;
  String? previousConfirmations;
  var observedTransition = false;
  var observedPending = false;
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final status = _visibleStatus(tester);
    final confirmations = _confirmationValue(tester);
    if (status == '确认中' || status == '已提交' || confirmations == '--') {
      observedPending = true;
    }
    if (status != previousStatus || confirmations != previousConfirmations) {
      if (previousStatus != null || previousConfirmations != null) {
        observedTransition = true;
      }
      previousStatus = status;
      previousConfirmations = confirmations;
      await evidence.snapshot(
        binding,
        tester,
        '50 $slug 状态变化 ${status ?? 'unknown'} ${confirmations ?? 'unknown'}',
        facts: <String, Object?>{
          'status': status,
          'confirmations': confirmations,
          'transaction_hash': hash,
        },
      );
    }
    if (status == '已确认' &&
        confirmations != null &&
        RegExp(r'^[1-9]\d*$').hasMatch(confirmations)) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  expect(previousStatus, '已确认');
  expect(previousConfirmations, matches(RegExp(r'^[1-9]\d*$')));
  await evidence.event(
    '$slug 确认状态采样完成',
    details: <String, Object?>{
      'observed_pending_frame': observedPending,
      'observed_ui_transition': observedTransition,
      'rapid_confirmation_before_first_sample':
          !observedPending && !observedTransition,
      'final_status': previousStatus,
      'final_confirmations': previousConfirmations,
      'transaction_hash': hash,
    },
  );

  final transactions = await wallets.localTransactions(
    networkIds: <String>{ethSepolia.id},
  );
  final transaction = transactions.singleWhere((tx) => tx.hash == hash);
  expect(transaction.status, db.TxStatus.confirmed);
  if (symbol == 'USDT') {
    expect(transaction.amountRaw, '1000000');
  }
  await evidence.scanPage(
    binding,
    tester,
    '51 $slug 链上确认完成',
    facts: <String, Object?>{
      'confirmations': previousConfirmations,
      'transaction': _transactionJson(transaction),
    },
  );
  return transaction;
}

Future<void> _enterPinWithEvidence(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  FullDeviceEvidence evidence,
  String pin, {
  required String phase,
  required bool closesAfterSix,
}) async {
  for (var i = 0; i < pin.length; i++) {
    final digit = pin[i];
    final digitKey = _semanticsFinder(digit).hitTestable();
    expect(digitKey, findsOneWidget);
    await tester.tap(digitKey);
    await tester.pump();
    final dots = find.byType(PinDots);
    final filled = dots.evaluate().isEmpty
        ? null
        : tester.widget<PinDots>(dots).filled;
    if (i < pin.length - 1) expect(filled, i + 1);
    if (i == pin.length - 1 && !closesAfterSix) expect(filled, 0);
    if (i == pin.length - 1 && closesAfterSix && filled != null) {
      expect(filled, pin.length);
    }
    await evidence.snapshot(
      binding,
      tester,
      '$phase 输入第 ${i + 1} 位',
      facts: <String, Object?>{
        'entered_digit': digit,
        'entered_count': i + 1,
        'pin_dots_filled_after_input': filled,
      },
      screenshot: false,
    );
  }
}

Future<Map<String, String>> _waitForFundedHomeBalances(
  WidgetTester tester,
) async {
  final result = <String, String>{};
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final value = text.data;
      if (value == null) continue;
      for (final symbol in const <String>['ETH', 'USDT']) {
        final match = RegExp(
          '^([0-9]+(?:\\.[0-9]+)?) ${RegExp.escape(symbol)} · ',
        ).firstMatch(value);
        if (match != null && double.parse(match.group(1)!) > 0) {
          result[symbol] = value;
        }
      }
    }
    if (result.length == 2) return result;
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TimeoutException('Funded ETH and USDT balance labels were not visible');
}

String? _confirmationValue(WidgetTester tester) {
  final row = find.byKey(const ValueKey('broadcast-confirmations'));
  if (row.evaluate().isEmpty) return null;
  final values = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((text) => text.data)
      .whereType<String>()
      .where((text) => text == '--' || RegExp(r'^\d+$').hasMatch(text))
      .toList();
  return values.isEmpty ? null : values.last;
}

String? _visibleStatus(WidgetTester tester) {
  for (final candidate in const <String>['已确认', '确认中', '已提交', '状态未知']) {
    if (find.text(candidate).evaluate().isNotEmpty) return candidate;
  }
  return null;
}

Future<void> _waitForSubmitted(
  WidgetTester tester, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (find.text('交易已提交').evaluate().isEmpty) {
    final snackbars = find.byType(SnackBar);
    if (snackbars.evaluate().isNotEmpty) {
      final messages = tester
          .widgetList<Text>(
            find.descendant(of: snackbars, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.isNotEmpty)
          .join(' | ');
      throw TestFailure(
        'Transfer failed before result screen: '
        '${messages.isEmpty ? 'unknown snackbar error' : messages}',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Transfer result screen was not reached');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

Future<void> _cleanupNativeWallets(
  CoreCrypto crypto,
  Iterable<String> walletIds,
) async {
  for (final walletId in walletIds) {
    if (await crypto.walletExists(walletId)) {
      await crypto.deleteWallet(walletId);
    }
  }
}

Future<void> _waitForWalletCreationOutcome(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  FullDeviceEvidence evidence,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  const errorKey = ValueKey('mnemonic-verify-submit-error');
  var observingFrames = true;
  var unavailableFrameObserved = false;
  void observeFrame(Duration _) {
    if (!observingFrames) return;
    if (find.text('无法显示助记词').evaluate().isNotEmpty) {
      unavailableFrameObserved = true;
    }
    WidgetsBinding.instance.addPostFrameCallback(observeFrame);
  }

  WidgetsBinding.instance.addPostFrameCallback(observeFrame);
  try {
    while (true) {
      if (unavailableFrameObserved) {
        await evidence.snapshot(
          binding,
          tester,
          '06A 助记词确认后闪现错误页',
          facts: const <String, Object?>{
            'error': '无法显示助记词',
            'observed_by': 'post-frame widget-tree observer',
          },
        );
        await evidence.event(
          '助记词确认后闪现错误页',
          details: const <String, Object?>{'message': '无法显示助记词'},
        );
        throw TestFailure(
          'The mnemonic-unavailable page flashed after a successful confirm',
        );
      }

      final inlineError = find.byKey(errorKey);
      if (inlineError.evaluate().isNotEmpty) {
        final messages = find
            .descendant(of: inlineError, matching: find.byType(Text))
            .evaluate()
            .map((element) => (element.widget as Text).data ?? '')
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        await evidence.snapshot(
          binding,
          tester,
          '06A 助记词确认后钱包创建失败',
          facts: <String, Object?>{'error_messages': messages},
        );
        await evidence.event(
          '钱包创建失败',
          details: <String, Object?>{'stage': '助记词校验确认后', 'messages': messages},
        );
        throw TestFailure(
          'Wallet creation failed after mnemonic verification: '
          '${messages.isEmpty ? 'unknown inline error' : messages.join(' | ')}',
        );
      }

      final snackBars = find.byType(SnackBar);
      if (snackBars.evaluate().isNotEmpty) {
        final messages = find
            .descendant(of: snackBars, matching: find.byType(Text))
            .evaluate()
            .map((element) => (element.widget as Text).data ?? '')
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        final isFailure = messages.any(
          (message) =>
              message.contains('失败') ||
              message.contains('未完成') ||
              message.contains('需要通过身份验证') ||
              message.contains('有误'),
        );
        if (isFailure) {
          await evidence.snapshot(
            binding,
            tester,
            '06A 助记词确认后错误提示',
            facts: <String, Object?>{'error_messages': messages},
          );
          await evidence.event(
            '助记词确认错误提示',
            details: <String, Object?>{'messages': messages},
          );
          throw TestFailure(
            'Mnemonic verification showed an error: ${messages.join(' | ')}',
          );
        }
      }

      if (find.text('钱包 1').evaluate().isNotEmpty) return;
      if (DateTime.now().isAfter(deadline)) {
        await evidence.snapshot(
          binding,
          tester,
          '06A 助记词确认后等待超时',
          facts: const <String, Object?>{'expected': '钱包首页或明确错误信息'},
        );
        throw TimeoutException(
          'Wallet creation produced neither the home screen nor a visible error',
        );
      }
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } finally {
    observingFrames = false;
  }
}

Future<void> _tapSemantics(WidgetTester tester, String label) async {
  await _dismissScreenSecurityWarning(tester);
  final finder = _semanticsFinder(label);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final interactiveDescendant = find
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
  final target = interactiveDescendant.evaluate().isNotEmpty
      ? interactiveDescendant.first
      : finder.hitTestable();
  expect(target, findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _semanticsFinder(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
  description: 'Semantics(label: $label)',
);

Future<void> _tapBack(WidgetTester tester) async {
  await _dismissScreenSecurityWarning(tester);
  final back = find.byTooltip('返回').hitTestable();
  expect(back, findsOneWidget);
  await tester.tap(back);
  await tester.pumpAndSettle();
}

Future<void> _dismissScreenSecurityWarning(WidgetTester tester) async {
  final close = find
      .byKey(const ValueKey('screen-security-warning-close'))
      .hitTestable();
  if (close.evaluate().isEmpty) return;
  await tester.tap(close);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(FullDeviceEvidence.viewerPause),
  );
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

Map<String, String> _addressesJson(ChainAddresses addresses) =>
    <String, String>{
      for (final coin in Coin.values) coin.name: addresses.forCoin(coin),
    };

Map<String, Object?> _transactionJson(db.Transaction tx) => <String, Object?>{
  'id': tx.id,
  'wallet_id': tx.walletId,
  'coin': tx.coin,
  'network_id': tx.networkId,
  'contract': tx.contract,
  'direction': tx.direction.name,
  'operation': tx.operation.name,
  'from': tx.fromAddr,
  'to': tx.toAddr,
  'amount_raw': tx.amountRaw,
  'fee_raw': tx.feeRaw,
  'hash': tx.hash,
  'status': tx.status.name,
  'sign_mode': tx.signMode.name,
  'created_at': tx.createdAt,
  'broadcast_at': tx.broadcastAt,
  'last_checked_at': tx.lastCheckedAt,
};
