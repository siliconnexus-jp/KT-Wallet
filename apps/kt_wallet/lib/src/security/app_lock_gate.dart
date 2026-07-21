import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/app_prefs.dart';
import '../state/flutter_test_env.dart';
import '../state/locale_controller.dart';
import 'biometric_auth.dart';

/// Wallet-mode startup gate: when the security-settings "App 锁" preference is
/// on, the wallet UI stays hidden behind a dark lock screen until a
/// [BiometricAuth] prompt succeeds.
///
/// If the device cannot authenticate at all (no biometric hardware, nothing
/// enrolled, plugin absent — widget tests), the gate lets the user straight
/// through: the online app has no PIN of its own yet, so a hard lock with no
/// fallback would brick the wallet rather than protect it.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    required this.localeController,
    this.prefs,
    this.auth,
  });

  /// The wallet subtree revealed once the gate is open.
  final Widget child;

  /// Drives the lock screen's own MaterialApp locale (it renders outside
  /// [KtWalletApp], so it cannot inherit the wallet's localization).
  final LocaleController localeController;

  /// Injectable preferences / authenticator (tests); production defaults.
  final AppPrefsController? prefs;
  final BiometricAuth? auth;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

enum _LockState { resolving, locked, unlocked }

class _AppLockGateState extends State<AppLockGate> {
  late final AppPrefsController _prefs = widget.prefs ?? AppPrefsController();
  BiometricAuth get _auth => widget.auth ?? BiometricAuth.instance;

  _LockState _state = _LockState.resolving;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // SharedPreferences' channel is dead under `flutter test` (its future
    // would never complete); tests drive the gate through an injected
    // controller's in-memory state instead.
    if (!isFlutterTestEnv) await _prefs.load();
    if (!mounted) return;
    if (!_prefs.appLock) {
      setState(() => _state = _LockState.unlocked);
      return;
    }
    // Honest shortcut: with no way to prompt (and no app PIN existing on the
    // online side yet) the lock cannot be satisfied — let the user through.
    final canPrompt = await _auth.canAuthenticate();
    if (!mounted) return;
    setState(() => _state = canPrompt ? _LockState.locked : _LockState.unlocked);
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final l10n = await AppLocalizations.delegate.load(
        widget.localeController.locale ?? AppLocalizations.supportedLocales.first);
    final outcome = await _auth.authenticate(reason: l10n.appLock);
    _prompting = false;
    if (!mounted) return;
    switch (outcome) {
      case BiometricOutcome.success:
      // Availability vanished mid-session (e.g. biometrics disabled in the
      // system settings): same no-fallback reasoning as in [_resolve].
      case BiometricOutcome.unavailable:
        setState(() => _state = _LockState.unlocked);
      case BiometricOutcome.failure:
        // Stay locked; the button remains available for another attempt.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LockState.unlocked:
        return widget.child;
      case _LockState.resolving:
        // Same plain dark splash the wallet bootstrap shows.
        return const ColoredBox(color: SignerColors.bg);
      case _LockState.locked:
        return _LockScreenApp(localeController: widget.localeController, onUnlock: _unlock);
    }
  }
}

/// Minimal dark lock screen. Hosts its own MaterialApp because it renders
/// outside [KtWalletApp] (no Directionality/l10n above it otherwise) — same
/// pattern as the bootstrap error screen.
class _LockScreenApp extends StatelessWidget {
  const _LockScreenApp({required this.localeController, required this.onUnlock});

  final LocaleController localeController;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) => MaterialApp(
        title: 'KT Wallet',
        debugShowCheckedModeBanner: false,
        locale: localeController.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent, brightness: Brightness.dark),
          scaffoldBackgroundColor: SignerColors.bg,
        ),
        home: Builder(
          builder: (context) {
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
                      const Icon(Icons.lock_outline, size: 48, color: SignerColors.text2),
                      const SizedBox(height: 16),
                      Text(l10n.appLock,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: SignerColors.text)),
                      const SizedBox(height: 8),
                      Text(l10n.appLockDesc,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, height: 1.6, color: SignerColors.text2)),
                      const SizedBox(height: 24),
                      KtPrimaryButton(label: l10n.useFaceId, onPressed: onUnlock),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
