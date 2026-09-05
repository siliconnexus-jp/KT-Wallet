import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const copy = KtIntroCopy(
  role: 'Online wallet',
  titles: [
    '100% open source. Front to back.',
    'Security first. Control stays yours.',
    'Manage online. Sign offline.',
  ],
  descriptions: [
    'Wallet apps and the backend gateway are open to inspection.',
    'Review every transaction before signing.',
    'Use separate devices and exchange QR codes.',
  ],
  notes: [
    'Open to review and improvement.',
    'Never share your recovery phrase.',
    'Keep offline keys on the offline device.',
  ],
  frontend: 'Wallet apps',
  backend: 'Backend',
  online: 'Online wallet',
  offline: 'Offline signer',
  next: 'Continue',
  start: 'Start',
  skip: 'Skip intro',
  back: 'Back',
  source: 'Explore source',
  sourceHint: 'Scan with a connected device. No network requests here.',
  copyLink: 'Copy address',
  copied: 'Copied',
  close: 'Close',
  saveFailed: 'Please retry',
);

Widget app({
  required Future<void> Function() save,
  bool offline = false,
  double scale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: KtProductIntro(copy: copy, onComplete: save, offline: offline),
  ),
);

void main() {
  testWidgets('swipe and back keep page content and controls in sync', (
    tester,
  ) async {
    await tester.pumpWidget(app(save: () async {}));
    await tester.drag(
      find.byKey(const ValueKey('product-intro-pages')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('intro-title-1')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('intro-title-0')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('source QR is local and completion only runs on finish', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      app(
        save: () async {
          completed++;
        },
      ),
    );
    await tester.tap(find.text('Explore source'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<KtQrCode>(find.byType(KtQrCode)).data,
      ktSourceRepository,
    );
    expect(find.text(ktSourceRepository), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(completed, 0);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('intro-next')));
      await tester.pumpAndSettle();
    }
    expect(completed, 0);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(completed, 1);
  });

  testWidgets('save failure stays on introduction and retry succeeds', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      KtIntroGate(
        readCompleted: () async => false,
        saveCompleted: () async {
          if (++saves == 1) throw StateError('disk full');
        },
        introBuilder: (complete) => app(save: complete),
        child: const MaterialApp(home: Text('Wallet setup')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();
    expect(find.text('Please retry'), findsOneWidget);
    expect(find.text('Wallet setup'), findsNothing);
    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet setup'), findsOneWidget);
  });

  testWidgets('completed flag skips introduction on next launch', (
    tester,
  ) async {
    await tester.pumpWidget(
      KtIntroGate(
        readCompleted: () async => true,
        saveCompleted: () async => fail('must not save again'),
        introBuilder: (complete) => app(save: complete),
        child: const MaterialApp(home: Text('Wallet setup')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wallet setup'), findsOneWidget);
    expect(find.text(copy.titles.first), findsNothing);
  });

  testWidgets('rapid completion taps persist only once', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        save: () {
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('Skip intro'));
    await tester.pump();
    await tester.tap(find.text('Skip intro'));
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  for (final offline in [false, true]) {
    testWidgets(
      'small screen at large text keeps controls reachable ($offline)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          app(save: () async {}, offline: offline, scale: 2),
        );
        for (var i = 0; i < 3; i++) {
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('intro-next')).hitTestable(),
            findsOneWidget,
          );
          if (i < 2) {
            await tester.tap(find.byKey(const ValueKey('intro-next')));
            await tester.pumpAndSettle();
          }
        }
      },
    );
  }
}
