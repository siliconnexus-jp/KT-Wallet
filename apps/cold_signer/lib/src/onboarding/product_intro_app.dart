import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/locale_controller.dart';
import '../widgets/signer_brand_mark.dart';

const signerIntroCompletedKey = 'signer.productIntro.v1';

/// Local first-use preference, independent of the other application.
class SignerIntroApp extends StatelessWidget {
  const SignerIntroApp({
    super.key,
    required this.localeController,
    required this.child,
  });
  final LocaleController localeController;
  final Widget child;

  @override
  Widget build(BuildContext context) => KtIntroGate(
    readCompleted: () async =>
        (await SharedPreferences.getInstance()).getBool(
          signerIntroCompletedKey,
        ) ??
        false,
    saveCompleted: () async {
      final saved = await (await SharedPreferences.getInstance()).setBool(
        signerIntroCompletedKey,
        true,
      );
      if (!saved) throw StateError('Introduction preference was not saved');
    },
    child: child,
    introBuilder: (complete) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: localeController.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: ktSignerTheme(),
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return KtProductIntro(
            offline: true,
            brandMark: const SignerBrandMark(size: 38),
            onComplete: complete,
            copy: KtIntroCopy(
              role: l10n.introRole,
              titles: [
                l10n.introOpenTitle,
                l10n.introSecurityTitle,
                l10n.introPairTitle,
              ],
              descriptions: [
                l10n.introOpenDescription,
                l10n.introSecurityDescription,
                l10n.introPairDescription,
              ],
              notes: [
                l10n.introOpenNote,
                l10n.introSecurityNote,
                l10n.introPairNote,
              ],
              frontend: l10n.introFrontend,
              backend: l10n.introBackend,
              online: l10n.introOnline,
              offline: l10n.introOffline,
              next: l10n.introNext,
              start: l10n.introStart,
              skip: l10n.introSkip,
              back: l10n.introBack,
              source: l10n.introSource,
              sourceHint: l10n.introSourceHint,
              copyLink: l10n.introCopyLink,
              copied: l10n.introCopied,
              close: l10n.done,
              saveFailed: l10n.introSaveFailed,
            ),
          );
        },
      ),
    ),
  );
}
