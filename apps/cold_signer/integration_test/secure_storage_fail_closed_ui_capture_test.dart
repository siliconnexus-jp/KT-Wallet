import 'dart:io';

import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/state/locale_controller.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _UnavailableVaultStorage implements VaultStorage {
  const _UnavailableVaultStorage();

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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KT Cold Signer blocks onboarding when storage is unavailable', (
    tester,
  ) async {
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final wallet = SignerWalletController(
      storage: const _UnavailableVaultStorage(),
    );
    await tester.pumpWidget(
      ColdSignerApp(
        localeController: LocaleController(initial: const Locale('en')),
        walletController: wallet,
        initialLocation: '/welcome',
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Secure storage unavailable'), findsOneWidget);
    expect(find.text('Create new wallet'), findsNothing);
    expect(find.text('Import existing wallet'), findsNothing);

    final platform = Platform.isIOS ? 'ios' : 'android';
    final fileName = '$platform-secure-storage-signer-locked';
    final png = await binding.takeScreenshot(fileName);
    final path = '${Directory.systemTemp.path}/$fileName.png';
    await File(path).writeAsBytes(png, flush: true);
    // Contains only fixed localization and a security-state illustration.
    // ignore: avoid_print
    print('SECURE_STORAGE_CAPTURE FILE=$path');
  });
}
