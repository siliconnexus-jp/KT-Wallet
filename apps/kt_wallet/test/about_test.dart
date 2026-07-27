import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_info.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/screens/about_screen.dart';

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

class _FakeExternalActions extends ExternalActions {
  _FakeExternalActions({this.succeeds = true});

  final bool succeeds;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }

  @override
  Future<void> share({required String text, String? subject}) async {}

  @override
  Future<void> shareFile({
    required String path,
    required String mimeType,
    String? text,
    String? subject,
  }) async {}
}

void main() {
  test('the displayed version matches pubspec', () {
    // AppInfo.version is hand-copied from pubspec (no package_info_plus for
    // one string). That is only acceptable while something checks it.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    // "1.0.0+1" — the build number is not shown to the user.
    final declared = line.split(':')[1].trim().split('+').first;
    expect(AppInfo.version, declared);
  });

  test('the repository URL is the real one, over https', () {
    final uri = Uri.parse(AppInfo.repositoryUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(uri.path, '/siliconnexus-jp/KT-Wallet');
  });

  testWidgets('shows the version and the repository URL in full', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text(AppInfo.version), findsOneWidget);
    // Printed in full, not hidden behind a label: a link the user cannot read
    // is a link they have to take on trust.
    expect(find.text(AppInfo.repositoryUrl), findsOneWidget);
    expect(find.text('开源地址'), findsOneWidget);
  });

  testWidgets('tapping the row opens the repository', (tester) async {
    final actions = _FakeExternalActions();
    final previous = ExternalActions.instance;
    ExternalActions.instance = actions;
    addTearDown(() => ExternalActions.instance = previous);

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about-repository')));
    await tester.pumpAndSettle();

    expect(actions.opened.single.toString(), AppInfo.repositoryUrl);
  });

  testWidgets('with no browser it falls back to the clipboard', (tester) async {
    final actions = _FakeExternalActions(succeeds: false);
    final previous = ExternalActions.instance;
    ExternalActions.instance = actions;
    addTearDown(() => ExternalActions.instance = previous);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about-repository')));
    await tester.pumpAndSettle();

    // A dead end would leave the user with no way to reach the source at all.
    expect(copied, AppInfo.repositoryUrl);
    expect(find.text('链接已复制'), findsOneWidget);
  });
}
