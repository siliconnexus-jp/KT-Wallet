import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/pin_lock.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('corrupt PIN state stays on the signing gate without escaping', (
    tester,
  ) async {
    final storage = InMemoryVaultStorage()
      ..values[SecureVault.pinKey] = '{"iterations":500}';
    final pin = PinLock(storage, iterations: 500);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SignerPinEntrySheet(pinLock: pin)),
      ),
    );
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('pin-key-$digit')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(SignerPinEntrySheet), findsOneWidget);
    expect(find.text('Secure storage unavailable'), findsOneWidget);
  });
}
