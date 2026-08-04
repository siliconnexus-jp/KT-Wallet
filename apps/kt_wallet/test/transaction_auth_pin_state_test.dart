import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/transaction_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';

void main() {
  testWidgets('corrupt PIN state denies transaction auth without escaping', (
    tester,
  ) async {
    final storage = InMemoryPinStorage()
      ..values[WalletPin.pinKey] = '{"iterations":1000}';
    final gate = LocalTransactionAuthGate(
      pin: WalletPin(storage, iterations: 1000),
    );
    bool? result;
    var escaped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              try {
                result = await gate.authenticate(
                  context,
                  method: AuthMethod.password,
                  reason: 'test',
                );
              } on Object {
                escaped = true;
              }
            },
            child: const Text('AUTH'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('AUTH'));
    await tester.pumpAndSettle();

    expect(escaped, isFalse);
    expect(result, isFalse);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
