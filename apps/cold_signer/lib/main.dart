import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'l10n/app_localizations.dart';
import 'src/screens/signer_onboarding_screens.dart';
import 'src/developer_mode.dart';
import 'src/observability/native_incidents.dart';
import 'src/signer_router.dart';
import 'src/state/locale_controller.dart';
import 'src/state/signer_wallet_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ColdSignerNativeIncidents.instance.ingest();
  final localeController = LocaleController();
  await localeController.load();
  runApp(
    ColdSignerApp(
      localeController: localeController,
      initialLocation: '/welcome',
    ),
  );
}

class ColdSignerApp extends StatefulWidget {
  ColdSignerApp({
    super.key,
    LocaleController? localeController,
    SignerWalletController? walletController,
    String initialLocation = '/',
  }) : localeController = localeController ?? LocaleController(),
       walletController = walletController ?? SignerWalletController(),
       initialLocation = !developerFixturesEnabled && initialLocation == '/'
           ? '/welcome'
           : initialLocation;

  final LocaleController localeController;

  /// Persistent wallet state (vault, PIN, anti-replay records). Tests inject
  /// one backed by fakes; the default uses the platform secure store.
  final SignerWalletController walletController;

  /// Where the router starts: the debug-only gallery ('/') for tests and local
  /// visual review, or the C1 welcome screen in every release build.
  /// A '/welcome' start is upgraded to the C5 home once the vault reports an
  /// existing wallet (see [_resolveInitialLocation]).
  final String initialLocation;

  @override
  State<ColdSignerApp> createState() => _ColdSignerAppState();
}

class _ColdSignerAppState extends State<ColdSignerApp> {
  /// Built immediately for the gallery default; for embedded starts only
  /// after the vault has been read, so the first routed frame is already the
  /// right one (home vs. welcome).
  GoRouter? _router;
  bool _storageUnavailable = false;

  @override
  void initState() {
    super.initState();
    // Pick up a persisted language override (no-op if none / in tests).
    widget.localeController.load();
    if (widget.initialLocation == '/') {
      // Standalone dev gallery: boots straight to '/', untouched by wallet
      // state. Vault state still loads so gallery-driven live flows work.
      _router = buildSignerRouter(initialLocation: '/');
      _loadGalleryWallet();
    } else {
      _resolveInitialLocation();
    }
  }

  Future<void> _loadGalleryWallet() async {
    try {
      await widget.walletController.load();
    } on Object {
      if (mounted) setState(() => _storageUnavailable = true);
    }
  }

  Future<void> _resolveInitialLocation() async {
    final wallet = widget.walletController;
    try {
      await wallet.load();
    } on Object {
      if (mounted) setState(() => _storageUnavailable = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _storageUnavailable = false;
      _router = buildSignerRouter(
        initialLocation:
            wallet.hasWallet && widget.initialLocation == '/welcome'
            ? '/home'
            : widget.initialLocation,
      );
    });
  }

  void _retrySecureStorage() {
    if (!mounted) return;
    setState(() {
      _storageUnavailable = false;
      _router = null;
    });
    _resolveInitialLocation();
  }

  ThemeData get _theme => ThemeData(
    fontFamily: 'Inter',
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SignerColors.ok,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: SignerColors.bg,
  );

  @override
  Widget build(BuildContext context) {
    final router = _router;
    return ListenableBuilder(
      listenable: widget.localeController,
      builder: (context, _) => ScreenSecurityGuard(
        locale: widget.localeController.locale,
        child: SignerWalletScope(
          controller: widget.walletController,
          child: LocaleScope(
            controller: widget.localeController,
            child: _storageUnavailable
                ? MaterialApp(
                    onGenerateTitle: (context) =>
                        AppLocalizations.of(context).appName,
                    debugShowCheckedModeBanner: false,
                    locale: widget.localeController.locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: _theme,
                    home: Builder(
                      builder: (context) => _SignerStorageUnavailableScreen(
                        onRetry: _retrySecureStorage,
                      ),
                    ),
                    builder: (context, child) =>
                        KtDeviceChrome(mockStatusBar: false, child: child!),
                  )
                : router == null
                // One frame at most, while the vault decides home vs. welcome.
                ? MaterialApp(
                    onGenerateTitle: (context) =>
                        AppLocalizations.of(context).appName,
                    debugShowCheckedModeBanner: false,
                    locale: widget.localeController.locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: _theme,
                    home: const SignerSplashScreen(),
                    builder: (context, child) =>
                        KtDeviceChrome(mockStatusBar: false, child: child!),
                  )
                : MaterialApp.router(
                    onGenerateTitle: (context) =>
                        AppLocalizations.of(context).appName,
                    debugShowCheckedModeBanner: false,
                    locale: widget.localeController.locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: _theme,
                    routerConfig: router,
                    builder: (context, child) =>
                        KtDeviceChrome(mockStatusBar: false, child: child!),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Secure storage is part of the signing boundary. If it cannot be read, the
/// signer must not guess that no wallet exists and offer onboarding, nor keep
/// a process-local password. It remains blocked until an explicit retry can
/// access the platform-protected store again.
class _SignerStorageUnavailableScreen extends StatelessWidget {
  const _SignerStorageUnavailableScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.gpp_bad_outlined,
                size: 52,
                color: SignerColors.danger,
              ),
              const SizedBox(height: 18),
              Text(
                l10n.secureStorageUnavailableTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: SignerColors.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.secureStorageUnavailableDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: SignerColors.text2,
                ),
              ),
              const SizedBox(height: 24),
              KtPrimaryButton(label: l10n.actionRetry, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
