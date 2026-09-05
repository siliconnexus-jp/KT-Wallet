import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/security/app_lock_gate.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';

class _UnavailablePinStorage implements PinStorage {
  const _UnavailablePinStorage();

  @override
  Future<void> delete(String key) =>
      Future<void>.error(StateError('secure storage unavailable'));

  @override
  Future<String?> read(String key) =>
      Future<String?>.error(StateError('secure storage unavailable'));

  @override
  Future<void> write(String key, String value) =>
      Future<void>.error(StateError('secure storage unavailable'));
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$platform-$name';
  final png = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(png, flush: true);
  // Contains only fixed localization and a security-state illustration.
  // ignore: avoid_print
  print('SECURE_STORAGE_CAPTURE FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 750)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KT Wallet remains locked when PIN storage is unavailable', (
    tester,
  ) async {
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(
      AppLockGate(
        localeController: LocaleController(initial: const Locale('zh')),
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success),
        pin: WalletPin(const _UnavailablePinStorage(), iterations: 1000),
        child: const MaterialApp(home: Text('SENSITIVE-WALLET-HOME')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('安全存储不可用'), findsOneWidget);
    expect(find.text('SENSITIVE-WALLET-HOME'), findsNothing);
    await _capture(binding, tester, 'secure-storage-wallet-locked');
  });
}
