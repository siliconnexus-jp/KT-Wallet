import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'l10n/app_localizations.dart';
import 'src/screens/signer_onboarding_screens.dart';
import 'src/signer_router.dart';
import 'src/state/locale_controller.dart';
import 'src/state/signer_wallet_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    this.initialLocation = '/',
  }) : localeController = localeController ?? LocaleController(),
       walletController = walletController ?? SignerWalletController();

  final LocaleController localeController;

  /// Persistent wallet state (vault, PIN, anti-replay records). Tests inject
  /// one backed by fakes; the default uses the platform secure store.
  final SignerWalletController walletController;

  /// Where the router starts: the dev gallery ('/') for the standalone app,
  /// or the C1 welcome screen when embedded behind kt_wallet's mode picker.
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

  @override
  void initState() {
    super.initState();
    // Pick up a persisted language override (no-op if none / in tests).
    widget.localeController.load();
    if (widget.initialLocation == '/') {
      // Standalone dev gallery: boots straight to '/', untouched by wallet
      // state. Vault state still loads so gallery-driven live flows work.
      _router = buildSignerRouter(initialLocation: '/');
      widget.walletController.load();
    } else {
      _resolveInitialLocation();
    }
  }

  Future<void> _resolveInitialLocation() async {
    final wallet = widget.walletController;
    await wallet.load();
    if (!mounted) return;
    setState(() {
      _router = buildSignerRouter(
        initialLocation:
            wallet.hasWallet && widget.initialLocation == '/welcome'
            ? '/home'
            : widget.initialLocation,
      );
    });
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
    return ScreenSecurityGuard(
      child: SignerWalletScope(
        controller: widget.walletController,
        child: LocaleScope(
          controller: widget.localeController,
          child: ListenableBuilder(
            listenable: widget.localeController,
            builder: (context, _) => router == null
                // One frame at most, while the vault decides home vs. welcome.
                ? MaterialApp(
                    title: 'KT Wallet Cold Signer',
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
                    title: 'KT Wallet Cold Signer',
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
