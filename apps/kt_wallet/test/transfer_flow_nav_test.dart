import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';

/// Walks the full transfer navigation, proving the screens are wired into one
/// flow driven by the current wallet type.
Future<void> _open(WidgetTester tester, String galleryEntry) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

Future<void> _openHome(WidgetTester tester) => _open(tester, 'W1/W20 首页');

/// The send screen no longer pre-fills anything on a live path, so every flow
/// test types the transfer it wants to walk through. Address is a real,
/// checksum-valid TRON account (NOT the USDT contract that used to be seeded).
Future<void> _enterTransfer(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D');
  await tester.enterText(fields.at(1), '12.5');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hot wallet: home → transfer → confirm → auth → result → home', (
    tester,
  ) async {
    final originalAuth = BiometricAuth.instance;
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
    addTearDown(() => BiometricAuth.instance = originalAuth);
    await _openHome(tester);
    // Default wallet 日常钱包 is hot.
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('USDT'), findsWidgets); // transfer input
    await _enterTransfer(tester);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Hot confirm shows 确认转账.
    expect(find.text('确认转账'), findsOneWidget);

    await tester.tap(find.text('确认转账'));
    await tester.pumpAndSettle();
    expect(find.text('验证以确认转账'), findsOneWidget); // auth sheet

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('交易已提交'), findsOneWidget); // result

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('日常钱包'), findsOneWidget); // back on home
  });

  testWidgets('watch wallet: transfer confirm generates a sign-request QR', (
    tester,
  ) async {
    await _openHome(tester);
    // Switch to the watch wallet (主钱包).
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主钱包').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await _enterTransfer(tester);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Watch confirm shows the air-gap button, not local sign.
    expect(find.text('生成待签名二维码'), findsOneWidget);

    // The QR screen runs a periodic frame-cycling timer, so pumpAndSettle
    // would never settle; pump discrete frames instead.
    await tester.tap(find.text('生成待签名二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('待签名交易'), findsOneWidget); // W6 QR screen
  });

  testWidgets('token detail: send opens the transfer input screen', (
    tester,
  ) async {
    await _open(tester, 'W3 Token 详情');
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('收款地址'), findsOneWidget); // W4 transfer input
  });

  testWidgets('token detail: receive opens the receive screen', (tester) async {
    await _open(tester, 'W3 Token 详情');
    await tester.tap(find.text('收款'));
    await tester.pumpAndSettle();
    // W14 receive, live: shows the current wallet's TRON address (default
    // chain) — the demo seed wallet 日常钱包.
    expect(find.text('USDT · TRON'), findsOneWidget);
    expect(find.text('TaPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa'), findsOneWidget);
  });
}
