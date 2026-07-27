import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/secure_screen.dart';

/// FLAG_SECURE must be up on every screen that can put a recovery phrase — in
/// whole or in part — in front of the user, in BOTH device modes. It used to
/// be latched by signer mode alone, so the online wallet's backup / verify /
/// import / view-phrase screens told the user "don't screenshot this" while
/// the OS happily allowed it.
void main() {
  late List<bool> calls;

  setUp(() {
    SecureScreen.resetForTest();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('kt/secure_screen'), (
          call,
        ) async {
          if (call.method == 'setSecure') calls.add(call.arguments as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('kt/secure_screen'),
          null,
        );
    SecureScreen.resetForTest();
  });

  testWidgets('mounting sensitive content raises the flag, unmounting clears '
      'it', (tester) async {
    expect(SecureScreen.isSecure, isFalse);

    await tester.pumpWidget(
      const MaterialApp(home: SecureContent(child: Text('phrase'))),
    );
    await tester.pump();
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pump();
    expect(SecureScreen.isSecure, isFalse);
    expect(SecureScreen.holders, 0);
    expect(calls, [true, false]);
  });

  testWidgets('nested/overlapping sensitive screens keep the flag up until '
      'the last one goes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecureContent(child: SecureContent(child: Text('phrase'))),
      ),
    );
    await tester.pump();
    expect(SecureScreen.holders, 2);
    // One channel call, not two: the flag is already up.
    expect(calls, [true]);

    await tester.pumpWidget(
      const MaterialApp(home: SecureContent(child: Text('phrase'))),
    );
    await tester.pump();
    expect(SecureScreen.holders, 1);
    expect(SecureScreen.isSecure, isTrue, reason: 'one holder is still up');
    expect(calls, [true], reason: 'the flag never dropped, so no new call');

    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pump();
    expect(calls, [true, false]);
  });

  test('signer mode latches the flag independently of screen holders', () {
    SecureScreen.modeSecure = true;
    expect(calls, [true]);

    SecureScreen.retain();
    SecureScreen.release();
    expect(
      calls,
      [true],
      reason: 'a screen coming and going must not clear the mode latch',
    );

    SecureScreen.modeSecure = false;
    expect(calls, [true, false]);
  });

  test('a screen holder keeps the flag up after the mode latch drops', () {
    SecureScreen.modeSecure = true;
    SecureScreen.retain();
    SecureScreen.modeSecure = false;
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true]);

    SecureScreen.release();
    expect(calls, [true, false]);
  });

  test('an unbalanced release cannot lower the flag under a live holder', () {
    SecureScreen.retain();
    SecureScreen.release();
    SecureScreen.release(); // stray
    expect(SecureScreen.holders, 0);

    SecureScreen.retain();
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true, false, true]);
  });
}
