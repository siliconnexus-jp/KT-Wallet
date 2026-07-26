import 'dart:math';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full live loop, end to end, on fakes (fake vault, in-memory records,
/// seeded Random): welcome → create (REAL generated mnemonic) → verify (real
/// word) → set PIN → home → scan the demo request → auth with the REAL PIN →
/// result → re-scan the same request → risk screen (anti-replay).
void main() {
  SignerWalletController controller(
    InMemoryVaultStorage storage,
    InMemorySignRecordPersistence records,
    MockCoreCrypto crypto,
  ) => SignerWalletController(
    storage: storage,
    records: records,
        crypto: crypto,
        deviceProbe: () async => const DeviceState(
          networkReachable: false,
          airplaneMode: true,
          bluetoothOn: false,
          devicePasscodeSet: true,
          biometricEnrolled: true,
          screenCaptured: false,
          rootedOrJailbroken: false,
        ),
    random: Random(42),
    pinIterations: 500,
  );

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> scanAllFrames(WidgetTester tester) async {
    final frameCount = demoSignRequestFrames().length;
    for (var i = 0; i < frameCount; i++) {
      await tester.tap(find.byIcon(Icons.qr_code_2).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('full live loop: create → real PIN → sign → replay blocked', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final storage = InMemoryVaultStorage();
    final records = InMemorySignRecordPersistence();
    final crypto = MockCoreCrypto();
    final wallet = controller(storage, records, crypto);

    await tester.pumpWidget(
      ColdSignerApp(walletController: wallet, initialLocation: '/welcome'),
    );
    await tester.pumpAndSettle();

    // No wallet in the vault → boots to C1 welcome.
    expect(find.text('创建新钱包'), findsOneWidget);
    await tester.tap(find.text('创建新钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示助记词'));
    await tester.pumpAndSettle();

    // C3 shows the REAL generated mnemonic — not the canned demo list.
    final words = [
      for (var i = 0; i < 12; i++)
        tester.widget<Text>(find.byKey(Key('mnemonic-word-$i'))).data!,
    ];
    expect(wallet.pendingMnemonic, words);
    expect(
      words,
      isNot([
        'ripple',
        'canyon',
        'script',
        'harbor',
        'velvet',
        'noble',
        'orbit',
        'meadow',
        'signal',
        'pledge',
        'quartz',
        'ember',
      ]),
    );

    // C4 challenges a real position of the real words.
    await tester.tap(find.text('我已手写备份，开始验证'));
    await tester.pumpAndSettle();
    final challengeText = tester
        .widget<Text>(find.textContaining('个单词是？'))
        .data!;
    final position = int.parse(
      RegExp(r'第 (\d+) 个').firstMatch(challengeText)!.group(1)!,
    );
    await tester.tap(find.text(words[position - 1]).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // C14: the real PIN is enrolled (entered twice).
    expect(find.text('设置 6 位密码'), findsOneWidget);
    await tapDigits(tester, '135790');
    expect(find.text('再次输入以确认'), findsOneWidget);
    await tapDigits(tester, '135790');
    expect(await wallet.pinLock.isSet(), isTrue);

    // C15 biometric (skip) → C16 created: the wallet is persisted.
    await tester.tap(find.text('暂不启用，仅使用密码'));
    await tester.pumpAndSettle();
    expect(find.text('钱包创建完成'), findsOneWidget);
    expect(wallet.hasWallet, isTrue);
    expect(wallet.pendingMnemonic, isNull, reason: 'mnemonic must not linger');
    expect(storage.values.containsKey(SecureVault.mnemonicKey), isFalse);
    expect(crypto.storedWalletCount, 1);

    // → C5 home → C6 scan the demo request → C7 parse.
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget);
    await tester.tap(find.text('扫描待签名交易'));
    await tester.pumpAndSettle();
    await scanAllFrames(tester);
    expect(find.text('确认交易内容'), findsOneWidget);

    // C8 auth: the passcode path now demands the REAL PIN.
    await tester.tap(find.text('确认签名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改用设备密码'));
    await tester.pumpAndSettle();
    expect(find.text('输入 App 密码以完成签名'), findsOneWidget);

    // A wrong PIN is refused and stays on the sheet.
    await tapDigits(tester, '000000');
    expect(find.text('密码错误，请重试'), findsOneWidget);
    expect(find.text('签名完成'), findsNothing);

    // The correct PIN completes the signature → C9 result QR.
    await tapDigits(tester, '135790');
    expect(find.text('签名完成'), findsOneWidget);

    // The reqId was committed to the ledger BEFORE the result was shown.
    final row = await records.get(demoSignRequest().reqIdHex);
    expect(row, isNotNull);
    expect(row!.status, RequestStatus.signed);
    expect(row.walletId, wallet.localWalletId);

    // Replay: re-scanning the SAME request must be blocked → C17 risk.
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget);
    await tester.tap(find.text('扫描待签名交易'));
    await tester.pumpAndSettle();
    await scanAllFrames(tester);
    expect(find.text('已禁止签名'), findsOneWidget); // C17 risk (duplicate)
  });

  testWidgets('boot: existing wallet upgrades /welcome to the C5 home', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final storage = InMemoryVaultStorage();
    final crypto = MockCoreCrypto();
    const mnemonic =
        'abandon ability able about above absent absorb abstract absurd abuse access accident';
    await crypto.storeWallet(
      walletId: demoWalletId,
      mnemonic: mnemonic,
      requireAuth: false,
    );
    final addresses = await crypto.deriveAddresses(demoWalletId);
    await SecureVault(storage).storeMetadata(
      WalletMetadata(
        walletId: demoWalletId,
        name: '主钱包',
        createdAt: 1786000000,
        addresses: addresses.toMap(),
      ),
    );

    await tester.pumpWidget(
      ColdSignerApp(
        walletController: controller(
          storage,
          InMemorySignRecordPersistence(),
          crypto,
        ),
        initialLocation: '/welcome',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget); // C5 home
    expect(find.text('创建新钱包'), findsNothing);
  });

  testWidgets('delete wallet wipes the vault, PIN and records', (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final storage = InMemoryVaultStorage();
    final records = InMemorySignRecordPersistence();
    final crypto = MockCoreCrypto();
    await records.put(
      const SignatureRecord(
        reqId: '7f3a2c915ed408b6',
        date: 1786000000,
        coin: 'slip44:195',
        operation: 'transfer',
        toAddress: 'T',
        amount: '1',
        status: RequestStatus.signed,
      ),
    );
    final wallet = controller(storage, records, crypto);
    await wallet.pinLock.setPin('135790');
    const mnemonic =
        'abandon ability able about above absent absorb abstract absurd abuse access accident';
    await crypto.storeWallet(
      walletId: demoWalletId,
      mnemonic: mnemonic,
      requireAuth: false,
    );
    final addresses = await crypto.deriveAddresses(demoWalletId);
    await SecureVault(storage).storeMetadata(
      WalletMetadata(
        walletId: demoWalletId,
        name: '主钱包',
        createdAt: 1786000000,
        addresses: addresses.toMap(),
      ),
    );

    await tester.pumpWidget(
      ColdSignerApp(walletController: wallet, initialLocation: '/delete'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除钱包').last); // confirm dialog
    await tester.pumpAndSettle();

    expect(find.text('创建新钱包'), findsOneWidget); // back on C1 welcome
    expect(wallet.hasWallet, isFalse);
    expect(storage.values, isEmpty, reason: 'mnemonic + PIN keys wiped');
    expect(await records.all(), isEmpty, reason: 'anti-replay ledger wiped');
  });
}
