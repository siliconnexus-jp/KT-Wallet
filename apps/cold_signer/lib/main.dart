import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'l10n/app_localizations.dart';
import 'src/signer_router.dart';
import 'src/state/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeController = LocaleController();
  await localeController.load();
  runApp(ColdSignerApp(localeController: localeController));
}

class ColdSignerApp extends StatefulWidget {
  ColdSignerApp({super.key, LocaleController? localeController, this.initialLocation = '/'})
      : localeController = localeController ?? LocaleController();

  final LocaleController localeController;

  /// Where the router starts: the dev gallery ('/') for the standalone app,
  /// or the C1 welcome screen when embedded behind kt_wallet's mode picker.
  final String initialLocation;

  @override
  State<ColdSignerApp> createState() => _ColdSignerAppState();
}

class _ColdSignerAppState extends State<ColdSignerApp> {
  late final _router = buildSignerRouter(initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    // Pick up a persisted language override (no-op if none / in tests).
    widget.localeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: widget.localeController,
      child: ListenableBuilder(
        listenable: widget.localeController,
        builder: (context, _) => MaterialApp.router(
          title: 'Cold Signer',
          debugShowCheckedModeBanner: false,
          locale: widget.localeController.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Inter',
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(seedColor: SignerColors.ok, brightness: Brightness.dark),
            scaffoldBackgroundColor: SignerColors.bg,
          ),
          routerConfig: _router,
          builder: (context, child) => KtDeviceChrome(mockStatusBar: false, child: child!),
        ),
      ),
    );
  }
}
