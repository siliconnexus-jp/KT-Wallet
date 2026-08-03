import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/app_localizations.dart';
import 'screens/signer_onboarding_screens.dart';
import 'developer_mode.dart';
import 'screens/signer_settings_screens.dart';
import 'screens/signer_signing_screens.dart';
import 'security/secure_vault.dart';
import 'signing/mnemonic_review.dart';
import 'state/signer_wallet_controller.dart';

/// Registry of every Cold Signer screen (C1–C21), powering the router + gallery.
final signerRegistry = <String, (String, WidgetBuilder)>{
  'C11 启动页': ('/splash', (c) => const SignerSplashScreen()),
  'C1 欢迎': ('/welcome', (c) => const SignerWelcomeScreen()),
  'C12 助记词安全提示': ('/mnemonic-warn', (c) => const SignerMnemonicWarnScreen()),
  'C3 助记词展示': ('/mnemonic-show', (c) => const SignerMnemonicShowScreen()),
  'C4 助记词校验': ('/mnemonic-verify', (c) => const SignerMnemonicVerifyScreen()),
  'C13 助记词输入': ('/mnemonic-import', (c) => const SignerMnemonicImportScreen()),
  'C14 设置密码': (
    '/set-password',
    (c) => const SignerSetPasswordScreen(preview: true),
  ),
  'C15 生物识别设置': ('/biometric', (c) => const SignerBiometricScreen()),
  'C16 创建成功': ('/created', (c) => const SignerCreatedScreen()),
  'C5 离线首页': ('/home', (c) => const SignerHomeScreen()),
  // The gallery/golden entry keeps the canned design snapshot so existing
  // goldens stay byte-identical; the live route is overridden below.
  'C2 离线安全检查': (
    '/security-check',
    (c) => const SignerSecurityCheckPreviewScreen(),
  ),
  'C6 扫描交易': ('/scan', (c) => const SignerScanScreen()),
  'C7 交易解析确认': ('/parse', (c) => const SignerParseScreen()),
  'C17 风险警告': ('/risk', (c) => const SignerRiskScreen()),
  'C8 身份验证': ('/auth', (c) => const SignerAuthScreen()),
  'C9 签名结果二维码': ('/result-qr', (c) => const SignerResultQrScreen()),
  'C10 地址导出': ('/export', (c) => const SignerAddressExportScreen()),
  'C18 签名记录': ('/records', (c) => const SignerRecordsScreen()),
  'C19 钱包管理': ('/wallet', (c) => const SignerWalletManageScreen()),
  'C20 安全设置': ('/security', (c) => const SignerSecuritySettingsScreen()),
  'C21 删除钱包': ('/delete', (c) => const SignerDeleteScreen()),
};

/// The sign-request handed along the scan → parse → auth → result chain via
/// GoRouter's `extra` slot (null when a screen is opened directly).
SignRequest? _requestExtra(GoRouterState state) {
  final extra = state.extra;
  return extra is SignRequest ? extra : null;
}

SignResult? _resultExtra(GoRouterState state) {
  final extra = state.extra;
  return extra is SignResult ? extra : null;
}

MnemonicReviewFlow? _mnemonicFlow(BuildContext context, GoRouterState state) {
  final extra = state.extra;
  if (extra is MnemonicReviewFlow) return extra;
  final pending = SignerWalletScope.maybeOf(context)?.pendingMnemonic;
  if (pending == null) return null;
  return MnemonicReviewFlow(
    purpose: MnemonicReviewPurpose.onboarding,
    words: pending,
  );
}

/// Live builders that replace a registry entry's design-snapshot builder when
/// the app actually navigates there (the registry itself is the golden/gallery
/// baseline and must keep rendering the original snapshot). Unlike the
/// registry's [WidgetBuilder]s these also see the [GoRouterState], so the
/// signing chain can pass the decoded request between screens.
final _liveOverrides = <String, Widget Function(BuildContext, GoRouterState)>{
  '/security-check': (c, s) => const SignerSecurityCheckScreen(),
  '/mnemonic-show': (c, s) =>
      SignerMnemonicShowScreen(flow: _mnemonicFlow(c, s)),
  '/mnemonic-verify': (c, s) {
    final flow = _mnemonicFlow(c, s);
    return SignerMnemonicVerifyScreen(
      flow: flow,
      challenge: flow == null
          ? null
          : SignerWalletScope.maybeOf(c)?.buildVerifyChallengeFor(flow.words),
    );
  },
  '/set-password': (c, s) => const SignerSetPasswordScreen(),
  '/parse': (c, s) => SignerParseScreen(request: _requestExtra(s)),
  '/auth': (c, s) => SignerAuthScreen(request: _requestExtra(s)),
  '/result-qr': (c, s) =>
      SignerResultQrScreen(request: _requestExtra(s), result: _resultExtra(s)),
};

const _sensitiveMnemonicRoutes = {
  '/mnemonic-show',
  '/mnemonic-verify',
  '/mnemonic-import',
};

GoRouter buildSignerRouter({String initialLocation = '/'}) {
  final galleryMode = developerFixturesEnabled && initialLocation == '/';
  return GoRouter(
    initialLocation: galleryMode ? '/' : initialLocation,
    redirect: (context, state) => signerProductionRouteRedirect(
      galleryMode: galleryMode,
      uri: state.uri,
      extra: state.extra,
      hasPendingMnemonic:
          SignerWalletScope.maybeOf(context)?.pendingMnemonic != null,
      hasWallet: SignerWalletScope.maybeOf(context)?.hasWallet ?? false,
      onboardingStage:
          SignerWalletScope.maybeOf(context)?.onboardingStage ??
          SignerOnboardingStage.idle,
      currentWalletId: SignerWalletScope.maybeOf(context)?.localWalletId,
    ),
    routes: [
      GoRoute(
        path: '/',
        redirect: galleryMode ? null : (c, s) => '/welcome',
        builder: (c, s) =>
            galleryMode ? const _Gallery() : const SizedBox.shrink(),
      ),
      for (final entry in signerRegistry.entries)
        GoRoute(
          path: entry.value.$1,
          builder: (c, s) {
            final live = galleryMode && entry.value.$1 == '/set-password'
                ? null
                : _liveOverrides[entry.value.$1];
            final screen = live == null ? entry.value.$2(c) : live(c, s);
            if (!_sensitiveMnemonicRoutes.contains(entry.value.$1)) {
              return screen;
            }
            return _SensitiveSignerContent(child: screen);
          },
        ),
    ],
  );
}

/// Android prevents capture before pixels are produced; iOS cannot prevent a
/// one-shot screenshot, but it does report recording/mirroring while active.
/// Conceal the phrase only for that ongoing capture state. Screenshot events
/// remain warning-only and do not retroactively blank the user's screen.
class _SensitiveSignerContent extends StatelessWidget {
  const _SensitiveSignerContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AndroidScreenshotBlocked(
    child: ValueListenableBuilder<bool>(
      valueListenable: ScreenSecurity.captured,
      child: child,
      builder: (context, captured, child) {
        if (!captured) return child!;
        final l10n = AppLocalizations.of(context);
        return ColoredBox(
          color: SignerColors.bg,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_outlined,
                    size: 52,
                    color: SignerColors.text2,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.screenCaptureBlocked,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SignerColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.screenCaptureBlockedHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      height: 1.5,
                      color: SignerColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Rejects direct production navigation into signing stages that require
/// authenticated in-memory protocol state. A URL/deep link cannot synthesize
/// a request or a signed response, while the explicit debug gallery remains
/// available to widget/golden tests.
String? signerProductionRouteRedirect({
  required bool galleryMode,
  required Uri uri,
  Object? extra,
  bool hasPendingMnemonic = false,
  bool hasWallet = false,
  SignerOnboardingStage onboardingStage = SignerOnboardingStage.idle,
  String? currentWalletId,
}) {
  if (galleryMode) return null;
  final path = uri.path;
  final resumeOnboarding = switch (onboardingStage) {
    SignerOnboardingStage.mnemonicReview => '/mnemonic-show',
    SignerOnboardingStage.pinSetup => '/set-password',
    SignerOnboardingStage.biometricSetup => '/biometric',
    SignerOnboardingStage.completed => '/home',
    SignerOnboardingStage.idle => '/welcome',
  };

  if (hasWallet) {
    if (const {
      '/welcome',
      '/mnemonic-warn',
      '/mnemonic-import',
    }.contains(path)) {
      return '/home';
    }
    if (path == '/biometric' &&
        onboardingStage != SignerOnboardingStage.completed) {
      return '/home';
    }
    if (const {'/mnemonic-show', '/mnemonic-verify'}.contains(path)) {
      final flow = extra is MnemonicReviewFlow ? extra : null;
      if (flow?.purpose != MnemonicReviewPurpose.backup) return '/home';
    }
    if (path == '/created' &&
        (onboardingStage != SignerOnboardingStage.completed ||
            extra is! WalletMetadata ||
            extra.walletId != currentWalletId)) {
      return '/home';
    }
  } else {
    if (const {
      '/home',
      '/scan',
      '/parse',
      '/risk',
      '/auth',
      '/result-qr',
      '/export',
      '/records',
      '/wallet',
      '/security',
      '/delete',
      '/created',
    }.contains(path)) {
      return resumeOnboarding;
    }
    if (path == '/mnemonic-import' &&
        onboardingStage != SignerOnboardingStage.idle) {
      return resumeOnboarding;
    }
    if (path == '/mnemonic-warn' &&
        const {
          SignerOnboardingStage.pinSetup,
          SignerOnboardingStage.biometricSetup,
        }.contains(onboardingStage)) {
      return resumeOnboarding;
    }
    if (path == '/mnemonic-show') {
      final flow = extra is MnemonicReviewFlow ? extra : null;
      if (flow?.purpose == MnemonicReviewPurpose.backup ||
          (flow?.purpose == MnemonicReviewPurpose.onboarding &&
              onboardingStage != SignerOnboardingStage.mnemonicReview) ||
          (flow == null &&
              onboardingStage != SignerOnboardingStage.mnemonicReview)) {
        return resumeOnboarding;
      }
    }
    if (path == '/mnemonic-verify' &&
        onboardingStage != SignerOnboardingStage.mnemonicReview) {
      return resumeOnboarding;
    }
    if (path == '/set-password' &&
        onboardingStage != SignerOnboardingStage.pinSetup) {
      return resumeOnboarding;
    }
    if (path == '/biometric' &&
        onboardingStage != SignerOnboardingStage.biometricSetup) {
      return resumeOnboarding;
    }
  }
  return switch (uri.path) {
    '/mnemonic-show' when extra is! MnemonicReviewFlow && !hasPendingMnemonic =>
      hasWallet ? '/home' : '/welcome',
    '/mnemonic-verify' when extra is! MnemonicReviewFlow =>
      hasWallet ? '/home' : '/welcome',
    '/wallet' when !hasWallet => '/welcome',
    '/parse' || '/auth' when extra is! SignRequest => '/scan',
    '/result-qr' when extra is! SignResult => '/scan',
    _ => null,
  };
}

class _Gallery extends StatelessWidget {
  const _Gallery();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SignerColors.bg,
    appBar: AppBar(
      title: const Text(
        'KT Cold Signer — 屏幕库',
        style: TextStyle(color: SignerColors.text),
      ),
      backgroundColor: SignerColors.surface,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in signerRegistry.entries)
          Card(
            color: SignerColors.surface,
            child: ListTile(
              title: Text(
                entry.key,
                style: const TextStyle(color: SignerColors.text),
              ),
              subtitle: Text(
                entry.value.$1,
                style: const TextStyle(
                  fontFamily: KtFonts.mono,
                  fontSize: 12,
                  color: SignerColors.text2,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: SignerColors.text2,
              ),
              onTap: () => context.go(entry.value.$1),
            ),
          ),
      ],
    ),
  );
}
