import 'package:cold_signer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, String galleryEntry) async {
  await tester.pumpWidget(ColdSignerApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create onboarding: welcome → warn → show → verify → password',
      (tester) async {
    await _open(tester, 'C1 欢迎');
    await tester.tap(find.text('创建新钱包'));
    await tester.pumpAndSettle();
    expect(find.text('接下来将生成助记词'), findsOneWidget); // C12 warn

    await tester.tap(find.text('显示助记词'));
    await tester.pumpAndSettle();
    expect(find.text('备份助记词'), findsOneWidget); // C3 show

    await tester.tap(find.text('我已手写备份，开始验证'));
    await tester.pumpAndSettle();
    expect(find.text('第 9 个单词是？'), findsOneWidget); // C4 verify

    // Must pick the correct 9th word before 确认 is enabled.
    await tester.tap(find.text('signal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('设置 6 位密码'), findsOneWidget); // C14 password
  });

  testWidgets('sign session: home → scan → parse → auth → result',
      (tester) async {
    await _open(tester, 'C5 离线首页');
    await tester.tap(find.text('扫描待签名交易'));
    await tester.pumpAndSettle();
    // C6 scan screen; tap the camera to simulate frames complete.
    await tester.tap(find.byIcon(Icons.qr_code_2).first);
    await tester.pumpAndSettle();
    expect(find.text('确认交易内容'), findsOneWidget); // C7 parse

    await tester.tap(find.text('确认签名'));
    await tester.pumpAndSettle();
    expect(find.text('验证以完成签名'), findsOneWidget); // C8 auth

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('签名完成'), findsOneWidget); // C9 result QR
  });
}
