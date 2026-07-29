import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _open(WidgetTester tester, String galleryEntry) async {
  // Pin the locale so the localized UI asserted below is in Chinese.
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  tester.platformDispatcher.localeTestValue = const Locale('zh');
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  await tester.pumpWidget(ColdSignerApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.ensureVisible(find.text(galleryEntry));
  await tester.pumpAndSettle();
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

Future<void> _sendScreenshotEvent(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'kt/screen_security',
    const StandardMethodCodec().encodeMethodCall(MethodCall('screenshotTaken')),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('screenshot event warns without hiding phrase words', (
    tester,
  ) async {
    await _open(tester, 'C3 助记词展示');
    final wordFinder = find.byKey(const Key('mnemonic-word-0'));

    expect(tester.widget<Text>(wordFinder).style?.color, SignerColors.text);
    await _sendScreenshotEvent(tester);
    expect(tester.widget<Text>(wordFinder).style?.color, SignerColors.text);
    expect(
      find.byKey(const ValueKey('screen-security-warning')),
      findsOneWidget,
    );
    expect(find.text('当前屏幕已被截图，请注意您的钱包安全'), findsOneWidget);
  });

  testWidgets('create onboarding: welcome → warn → show → verify → password', (
    tester,
  ) async {
    await _open(tester, 'C1 欢迎');
    await tester.tap(find.text('创建新钱包'));
    await tester.pumpAndSettle();
    expect(find.text('接下来将生成助记词'), findsOneWidget); // C12 warn

    await tester.tap(find.text('显示助记词'));
    await tester.pumpAndSettle();
    expect(find.text('备份助记词'), findsOneWidget); // C3 show

    // The live flow generates a REAL random mnemonic; read the words off the
    // C3 grid (keyed per position) exactly like a user copying the backup.
    final words = [
      for (var i = 0; i < 12; i++)
        tester.widget<Text>(find.byKey(Key('mnemonic-word-$i'))).data!,
    ];

    await tester.tap(find.text('我已手写备份，开始验证'));
    await tester.pumpAndSettle();
    expect(find.textContaining('个单词是？'), findsOneWidget); // C4 verify

    // Answer the challenge with the word at the challenged position.
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
    expect(find.text('设置 6 位密码'), findsOneWidget); // C14 password
  });

  testWidgets('set-password numpad: enter, mismatch resets, match advances', (
    tester,
  ) async {
    await _open(tester, 'C14 设置密码');
    expect(find.text('设置 6 位密码'), findsOneWidget);

    Future<void> enter(String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    // First pass, then confirmation prompt appears.
    await enter('123456');
    expect(find.text('再次输入以确认'), findsOneWidget);

    // Mismatch drops back to the first step.
    await enter('654321');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('设置 6 位密码'), findsOneWidget);

    // Matching entries advance to biometric setup.
    await enter('123456');
    await enter('123456');
    expect(find.text('启用 Face ID'), findsWidgets); // C15 biometric
  });

  testWidgets('sign session: home → scan → parse → auth → result', (
    tester,
  ) async {
    await _open(tester, 'C5 离线首页');
    await tester.tap(find.text('扫描待签名交易'));
    await tester.pumpAndSettle();
    // C6 scan screen: every simulated capture feeds one real frame into the
    // aggregator; the last one completes the payload and navigates.
    final frameCount = demoSignRequestFrames().length;
    for (var i = 0; i < frameCount; i++) {
      await tester.tap(find.byIcon(Icons.qr_code_2).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('确认交易内容'), findsOneWidget); // C7 parse

    await tester.tap(find.text('确认签名'));
    await tester.pumpAndSettle();
    expect(find.text('验证以完成签名'), findsOneWidget); // C8 auth

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('签名完成'), findsOneWidget); // C9 result QR
  });

  testWidgets('risk warning: back-to-home returns to the offline home', (
    tester,
  ) async {
    await _open(tester, 'C17 风险警告');
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget); // C5 home
  });

  testWidgets('address export: done returns to the offline home', (
    tester,
  ) async {
    await _open(tester, 'C10 地址导出');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget); // C5 home
  });

  testWidgets('biometric setup: skip advances to wallet-created', (
    tester,
  ) async {
    await _open(tester, 'C15 生物识别设置');
    await tester.tap(find.text('暂不启用，仅使用密码'));
    await tester.pumpAndSettle();
    expect(find.text('钱包创建完成'), findsOneWidget); // C16 created
  });

  testWidgets('created: "later" skips export and lands on the offline home', (
    tester,
  ) async {
    await _open(tester, 'C16 创建成功');
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(find.text('扫描待签名交易'), findsOneWidget); // C5 home
  });

  testWidgets(
    'auth: device-passcode alternative also completes the signature',
    (tester) async {
      await _open(tester, 'C8 身份验证');
      await tester.tap(find.text('改用设备密码'));
      await tester.pumpAndSettle();
      expect(find.text('签名完成'), findsOneWidget); // C9 result QR
    },
  );

  testWidgets('result QR: void signature confirms, snackbars, returns home', (
    tester,
  ) async {
    await _open(tester, 'C9 签名结果二维码');
    await tester.tap(find.text('作废本次签名'));
    await tester.pumpAndSettle();
    expect(find.text('作废本次签名？'), findsOneWidget); // confirm dialog

    // Cancel keeps the result screen.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('签名完成'), findsOneWidget);

    // Confirm voids and returns home with a snackbar.
    await tester.tap(find.text('作废本次签名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作废本次签名').last); // dialog's destructive action
    await tester.pumpAndSettle();
    expect(find.text('签名已作废'), findsOneWidget);
    expect(find.text('扫描待签名交易'), findsOneWidget); // C5 home
  });

  testWidgets('home: settings gear opens security settings', (tester) async {
    await _open(tester, 'C5 离线首页');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('修改 App 密码'), findsOneWidget); // C20
  });

  testWidgets('home: security banner opens the live security check', (
    tester,
  ) async {
    await _open(tester, 'C5 离线首页');
    await tester.tap(find.text('安全检查通过 · 飞行模式已开启'));
    await tester.pumpAndSettle();
    expect(find.text('离线安全检查'), findsOneWidget); // live C2
    expect(find.text('重新检查'), findsOneWidget);
    // Let the default probe's DNS timeout fire so no fake timer stays pending.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('wallet manage: backup check re-enters the mnemonic flow', (
    tester,
  ) async {
    await _open(tester, 'C19 钱包管理');
    await tester.tap(find.text('助记词备份验证'));
    await tester.pumpAndSettle();
    expect(find.text('备份助记词'), findsOneWidget); // C3 show
  });

  testWidgets('wallet manage: export row opens address export', (tester) async {
    await _open(tester, 'C19 钱包管理');
    await tester.tap(find.text('导出公开地址'));
    await tester.pumpAndSettle();
    expect(find.text('全部地址'), findsOneWidget); // C10 export
  });

  testWidgets('wallet manage: delete row opens the delete flow', (
    tester,
  ) async {
    await _open(tester, 'C19 钱包管理');
    await tester.tap(find.text('删除钱包'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除钱包'), findsOneWidget); // C21
  });

  testWidgets('wallet manage: destroy-all row opens the delete flow', (
    tester,
  ) async {
    await _open(tester, 'C19 钱包管理');
    await tester.tap(find.text('销毁全部钱包数据'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除钱包'), findsOneWidget); // C21 (closest flow)
  });

  testWidgets('wallet manage: rename dialog updates the wallet name', (
    tester,
  ) async {
    await _open(tester, 'C19 钱包管理');
    expect(find.text('主钱包'), findsOneWidget);
    await tester.tap(find.text('修改钱包名称'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '旅行签名器');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('旅行签名器'), findsOneWidget);
    expect(find.text('主钱包'), findsNothing);
  });

  testWidgets(
    'security settings: toggles are live and password row navigates',
    (tester) async {
      await _open(tester, 'C20 安全设置');

      Alignment bioKnob() =>
          (tester
                  .widget<Align>(
                    find.descendant(
                      of: find.byKey(const ValueKey('toggle-biometric')),
                      matching: find.byType(Align),
                    ),
                  )
                  .alignment)
              as Alignment;

      // Biometric toggle flips off and back on.
      expect(bioKnob(), Alignment.centerRight);
      await tester.tap(find.byKey(const ValueKey('toggle-biometric')));
      await tester.pump();
      expect(bioKnob(), Alignment.centerLeft);
      await tester.tap(find.byKey(const ValueKey('toggle-biometric')));
      await tester.pump();
      expect(bioKnob(), Alignment.centerRight);

      // Per-sign verification is V1-mandatory: tapping explains via snackbar.
      await tester.tap(find.byKey(const ValueKey('toggle-verify-every-sign')));
      await tester.pump();
      expect(find.text('不可关闭（V1 强制）'), findsNWidgets(2)); // row sub + snackbar
      await tester.pumpAndSettle();

      await tester.tap(find.text('修改 App 密码'));
      await tester.pumpAndSettle();
      expect(find.text('设置 6 位密码'), findsOneWidget); // C14
    },
  );

  testWidgets('records: segmented filter narrows the list', (tester) async {
    await _open(tester, 'C18 签名记录');
    expect(find.text('120.00 USDT'), findsOneWidget);
    expect(find.text('0.25 ETH'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(KtSegmented), matching: find.text('已拒绝')),
    );
    await tester.pumpAndSettle();
    expect(find.text('未知合约调用 · TRON'), findsOneWidget);
    expect(find.text('0.25 ETH'), findsNothing);
    expect(find.text('120.00 USDT'), findsNothing);
  });

  testWidgets('address export: chain filter narrows the list, not the QR', (
    tester,
  ) async {
    await _open(tester, 'C10 地址导出');
    // The export QR always carries the full 4-account payload.
    expect(find.byType(KtQrCode), findsOneWidget);
    expect(find.text('包含 4 条链公开地址 · 不含任何私密数据'), findsOneWidget);
    expect(find.text('TRON'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(KtSegmented),
        matching: find.text('Ethereum'),
      ),
    );
    await tester.pumpAndSettle();
    // The list narrows to the selected chain…
    expect(find.text('TRON'), findsNothing);
    expect(find.text('Solana'), findsNothing);
    // …but the QR payload is untouched: still all 4 exported accounts.
    expect(find.text('包含 4 条链公开地址 · 不含任何私密数据'), findsOneWidget);
  });

  testWidgets('delete wallet: destructive confirm returns to onboarding', (
    tester,
  ) async {
    await _open(tester, 'C21 删除钱包');
    await tester.tap(find.text('永久删除钱包'));
    await tester.pumpAndSettle();
    // On-screen warning card + the confirm dialog title.
    expect(find.text('此操作不可恢复'), findsNWidgets(2));

    // The dialog's destructive action navigates back to C1 welcome.
    await tester.tap(find.text('永久删除钱包').last);
    await tester.pumpAndSettle();
    expect(find.text('创建新钱包'), findsOneWidget); // C1 welcome
  });
}
