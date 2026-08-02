import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_info.dart';
import 'package:kt_wallet/src/observability/diagnostic_bundle.dart';
import 'package:kt_wallet/src/observability/diagnostic_telemetry.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/screens/about_screen.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home, {Locale locale = const Locale('zh')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

class _FakeExternalActions extends ExternalActions {
  _FakeExternalActions({this.succeeds = true, this.shareFileFails = false});

  final bool succeeds;
  final bool shareFileFails;
  final List<Uri> opened = [];
  final List<({String path, String mimeType, String? text, String? subject})>
  sharedFiles = [];

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
  }) async {
    if (shareFileFails) throw StateError('system share unavailable');
    sharedFiles.add((
      path: path,
      mimeType: mimeType,
      text: text,
      subject: subject,
    ));
  }
}

class _FakeTelemetryUploader implements DiagnosticTelemetryUploader {
  _FakeTelemetryUploader({
    this.result = DiagnosticTelemetryUploadResult.sent,
    this.error,
  });

  final DiagnosticTelemetryUploadResult result;
  final Object? error;
  int calls = 0;
  String? gatewayBaseUrl;
  DiagnosticTelemetryReport? report;

  @override
  Future<DiagnosticTelemetryUploadResult> upload({
    required String gatewayBaseUrl,
    required DiagnosticTelemetryReport report,
  }) async {
    calls += 1;
    this.gatewayBaseUrl = gatewayBaseUrl;
    this.report = report;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('all trust and disclosure links stay on the canonical repository', () {
    for (final value in [
      AppInfo.privacyPolicyUrl,
      AppInfo.securityAndRiskUrl,
      AppInfo.securityPolicyUrl,
      AppInfo.thirdPartyNoticesUrl,
      AppInfo.securityReportUrl,
    ]) {
      final uri = Uri.parse(value);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, startsWith('/siliconnexus-jp/KT-Wallet/'));
    }
  });

  test('security policy defines a private process and forbids secrets', () {
    final policy = File('../../SECURITY.md').readAsStringSync();
    expect(policy, contains('/security/advisories/new'));
    expect(policy, contains('Do not open a public issue'));
    expect(policy, contains('never ask a reporter to send a recovery phrase'));
    expect(policy, contains('within 3 business days'));
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

  testWidgets('trust rows open their exact canonical documents', (
    tester,
  ) async {
    final actions = _FakeExternalActions();
    final previous = ExternalActions.instance;
    ExternalActions.instance = actions;
    addTearDown(() => ExternalActions.instance = previous);

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();

    final cases = <Key, String>{
      const ValueKey('about-privacy'): AppInfo.privacyPolicyUrl,
      const ValueKey('about-security-risk'): AppInfo.securityAndRiskUrl,
      const ValueKey('about-security-policy'): AppInfo.securityPolicyUrl,
      const ValueKey('about-third-party'): AppInfo.thirdPartyNoticesUrl,
      const ValueKey('about-report-security'): AppInfo.securityReportUrl,
    };
    for (final entry in cases.entries) {
      final target = find.byKey(entry.key);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(actions.opened.last.toString(), entry.value);
    }
    expect(actions.opened, hasLength(cases.length));
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

  testWidgets('diagnostic export discloses privacy limits before sharing', (
    tester,
  ) async {
    final actions = _FakeExternalActions();
    final store = FakeDiagnosticBundleFileStore();
    final previousActions = ExternalActions.instance;
    final previousStore = DiagnosticBundleFileStore.instance;
    ExternalActions.instance = actions;
    DiagnosticBundleFileStore.instance = store;
    addTearDown(() {
      ExternalActions.instance = previousActions;
      DiagnosticBundleFileStore.instance = previousStore;
    });

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('about-export-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('导出诊断包？'), findsOneWidget);
    expect(find.text('包含'), findsOneWidget);
    expect(find.text('永不包含'), findsOneWidget);
    expect(find.textContaining('地址、余额、金额、交易'), findsOneWidget);
    expect(actions.sharedFiles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(actions.sharedFiles, hasLength(1));
    expect(actions.sharedFiles.single.mimeType, 'application/json');
    expect(actions.sharedFiles.single.path, store.filePath);
    expect(store.writtenJson, isNotNull);
    expect(store.removed, [store.filePath]);
    expect(find.text('诊断包已准备好'), findsOneWidget);
  });

  testWidgets('cancelling diagnostic disclosure creates no file', (
    tester,
  ) async {
    final actions = _FakeExternalActions();
    final store = FakeDiagnosticBundleFileStore();
    final previousActions = ExternalActions.instance;
    final previousStore = DiagnosticBundleFileStore.instance;
    ExternalActions.instance = actions;
    DiagnosticBundleFileStore.instance = store;
    addTearDown(() {
      ExternalActions.instance = previousActions;
      DiagnosticBundleFileStore.instance = previousStore;
    });

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('about-export-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(store.writtenJson, isNull);
    expect(actions.sharedFiles, isEmpty);
    expect(store.removed, isEmpty);
  });

  testWidgets('failed diagnostic share still removes the temporary file', (
    tester,
  ) async {
    final actions = _FakeExternalActions(shareFileFails: true);
    final store = FakeDiagnosticBundleFileStore();
    final previousActions = ExternalActions.instance;
    final previousStore = DiagnosticBundleFileStore.instance;
    ExternalActions.instance = actions;
    DiagnosticBundleFileStore.instance = store;
    addTearDown(() {
      ExternalActions.instance = previousActions;
      DiagnosticBundleFileStore.instance = previousStore;
    });

    await tester.pumpWidget(_app(const AboutScreen()));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('about-export-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(store.writtenJson, isNotNull);
    expect(store.removed, [store.filePath]);
    expect(actions.sharedFiles, isEmpty);
    expect(find.text('无法创建诊断包'), findsOneWidget);
  });

  testWidgets(
    'diagnostic privacy disclosure is localized in English and Japanese',
    (tester) async {
      for (final localeAndTitle in const [
        (Locale('en'), 'Export diagnostics?'),
        (Locale('ja'), '診断パッケージを書き出しますか？'),
      ]) {
        await tester.pumpWidget(
          _app(const AboutScreen(), locale: localeAndTitle.$1),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('about-export-diagnostics'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text(localeAndTitle.$2), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('kt-dialog-cancel')));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('anonymous upload requires a fresh disclosure confirmation', (
    tester,
  ) async {
    final uploader = _FakeTelemetryUploader();
    await tester.pumpWidget(_app(AboutScreen(telemetryUploader: uploader)));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('about-upload-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('发送匿名性能报告？'), findsOneWidget);
    expect(find.textContaining('不会在后台自动上传，也不会自动重试'), findsOneWidget);
    expect(find.textContaining('计数、成功/失败数和 P50/P95'), findsOneWidget);
    expect(find.textContaining('钱包或设备标识、地址、余额'), findsOneWidget);
    expect(find.textContaining('时间戳、错误文本、调用栈'), findsOneWidget);
    expect(uploader.calls, 0);

    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(uploader.calls, 1);
    expect(uploader.gatewayBaseUrl, AppPrefsController.defaultGatewayUrl);
    expect(uploader.report, isNotNull);
    expect(find.text('匿名性能报告已发送'), findsOneWidget);
  });

  testWidgets('cancelling anonymous upload sends nothing', (tester) async {
    final uploader = _FakeTelemetryUploader();
    await tester.pumpWidget(_app(AboutScreen(telemetryUploader: uploader)));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('about-upload-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(uploader.calls, 0);
  });

  testWidgets('direct mode refuses diagnostics after consent', (tester) async {
    final prefs = AppPrefsController();
    await prefs.setGatewayUrl(null);
    final uploader = _FakeTelemetryUploader();
    await tester.pumpWidget(
      _app(
        AppPrefsScope(
          controller: prefs,
          child: AboutScreen(telemetryUploader: uploader),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('about-upload-diagnostics'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(uploader.calls, 0);
    expect(find.textContaining('直接连接模式不会上传诊断'), findsOneWidget);
  });

  testWidgets('anonymous upload reports no samples and failures honestly', (
    tester,
  ) async {
    for (final entry in <_FakeTelemetryUploader, String>{
      _FakeTelemetryUploader(result: DiagnosticTelemetryUploadResult.noSamples):
          '目前没有可发送的性能样本',
      _FakeTelemetryUploader(error: StateError('offline')): '匿名性能报告发送失败；没有自动重试',
    }.entries) {
      await tester.pumpWidget(_app(AboutScreen(telemetryUploader: entry.key)));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('about-upload-diagnostics'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
