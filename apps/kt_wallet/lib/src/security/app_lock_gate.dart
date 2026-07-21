import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/app_prefs.dart';
import '../state/flutter_test_env.dart';
import '../state/locale_controller.dart';
import '../widgets/pin_pad.dart';
import 'biometric_auth.dart';
import 'wallet_pin.dart';

/// Wallet-mode startup gate: when the security-settings "App 锁" preference is
/// on, the wallet UI stays hidden behind a dark lock screen until a
/// [BiometricAuth] prompt succeeds — or, when biometrics are unavailable or
/// fail, until the enrolled app PIN ([WalletPin]) is entered on the numpad.
///
/// Order: biometrics if available → on failure or unavailability → PIN numpad
/// (with persisted-lockout messaging). The historical pass-through survives in
/// exactly one legacy state: app-lock is on but no PIN was ever enrolled AND
/// the device cannot show a biometric prompt — then a hard lock would brick
/// the wallet rather than protect it, so the gate lets the user through.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    required this.localeController,
    this.prefs,
    this.auth,
    this.pin,
  });

  /// The wallet subtree revealed once the gate is open.
  final Widget child;

  /// Drives the lock screen's own MaterialApp locale (it renders outside
  /// [KtWalletApp], so it cannot inherit the wallet's localization).
  final LocaleController localeController;

  /// Injectable preferences / authenticator / PIN (tests); production defaults.
  final AppPrefsController? prefs;
  final BiometricAuth? auth;
  final WalletPin? pin;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

enum _LockState { resolving, lockedBio, lockedPin, unlocked }

class _AppLockGateState extends State<AppLockGate> {
  late final AppPrefsController _prefs = widget.prefs ?? AppPrefsController();
  BiometricAuth get _auth => widget.auth ?? BiometricAuth.instance;
  WalletPin get _pin => widget.pin ?? WalletPin.instance;

  _LockState _state = _LockState.resolving;
  bool _pinSet = false;
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
    _pinSet = await _pin.isSet();
    final canPrompt = await _auth.canAuthenticate();
    if (!mounted) return;
    setState(() {
      if (canPrompt) {
        _state = _LockState.lockedBio;
      } else if (_pinSet) {
        _state = _LockState.lockedPin;
      } else {
        // Legacy pass-through: app-lock was switched on before the PIN
        // fallback existed (or biometrics vanished before a PIN was ever
        // enrolled). With no way to prompt and nothing to verify against,
        // a hard lock would brick the wallet — let the user through.
        _state = _LockState.unlocked;
      }
    });
  }

  Future<void> _promptBiometric() async {
    if (_prompting) return;
    _prompting = true;
    final l10n = await AppLocalizations.delegate.load(
        widget.localeController.locale ?? AppLocalizations.supportedLocales.first);
    final outcome = await _auth.authenticate(reason: l10n.appLock);
    _prompting = false;
    if (!mounted) return;
    switch (outcome) {
      case BiometricOutcome.success:
        setState(() => _state = _LockState.unlocked);
      case BiometricOutcome.unavailable:
        // Availability vanished mid-session (e.g. biometrics disabled in the
        // system settings): fall back to the PIN when one exists; otherwise
        // the same legacy pass-through reasoning as in [_resolve].
        setState(() => _state = _pinSet ? _LockState.lockedPin : _LockState.unlocked);
      case BiometricOutcome.failure:
        // A failed prompt falls back to the PIN numpad when one is enrolled;
        // without one the button remains available for another attempt.
        if (_pinSet) setState(() => _state = _LockState.lockedPin);
    }
  }

  void _onPinVerified() {
    if (mounted) setState(() => _state = _LockState.unlocked);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LockState.unlocked:
        return widget.child;
      case _LockState.resolving:
        // Same plain dark splash the wallet bootstrap shows.
        return const ColoredBox(color: SignerColors.bg);
      case _LockState.lockedBio:
        return _LockScreenApp(
          localeController: widget.localeController,
          body: (l10n) => _BiometricLockBody(
            l10n: l10n,
            onUnlock: _promptBiometric,
            // Direct PIN path so the user is never forced through a prompt
            // they know will fail (e.g. wet fingers).
            onUsePin: _pinSet ? () => setState(() => _state = _LockState.lockedPin) : null,
          ),
        );
      case _LockState.lockedPin:
        return _LockScreenApp(
          localeController: widget.localeController,
          body: (l10n) => _PinLockBody(l10n: l10n, pin: _pin, onVerified: _onPinVerified),
        );
    }
  }
}

/// Minimal dark lock screen shell. Hosts its own MaterialApp because it
/// renders outside [KtWalletApp] (no Directionality/l10n above it otherwise) —
/// same pattern as the bootstrap error screen.
class _LockScreenApp extends StatelessWidget {
  const _LockScreenApp({required this.localeController, required this.body});

  final LocaleController localeController;
  final Widget Function(AppLocalizations) body;

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
          builder: (context) => Scaffold(
            backgroundColor: SignerColors.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: body(AppLocalizations.of(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The biometric face of the lock screen (unchanged visuals from the original
/// gate, plus an optional "unlock with PIN" escape hatch).
class _BiometricLockBody extends StatelessWidget {
  const _BiometricLockBody({required this.l10n, required this.onUnlock, this.onUsePin});

  final AppLocalizations l10n;
  final VoidCallback onUnlock;
  final VoidCallback? onUsePin;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        if (onUsePin != null) ...[
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUsePin,
            child: Text(l10n.usePinUnlock,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2)),
          ),
        ],
      ],
    );
  }
}

/// The PIN face of the lock screen: 6-digit numpad verified against
/// [WalletPin] with wrong-PIN and persisted-lockout messaging.
class _PinLockBody extends StatefulWidget {
  const _PinLockBody({required this.l10n, required this.pin, required this.onVerified});

  final AppLocalizations l10n;
  final WalletPin pin;
  final VoidCallback onVerified;

  @override
  State<_PinLockBody> createState() => _PinLockBodyState();
}

class _PinLockBodyState extends State<_PinLockBody> {
  String _entry = '';
  String? _error;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _preflightLockout();
  }

  /// A lockout persisted from a previous session shows its message before the
  /// first key is even pressed.
  Future<void> _preflightLockout() async {
    final remaining = await widget.pin.lockRemaining();
    if (remaining != null && mounted) {
      setState(() => _error = widget.l10n.pinLockedRetry(remaining.inSeconds + 1));
    }
  }

  Future<void> _onKey(String k) async {
    if (_verifying) return;
    if (k == 'del') {
      if (_entry.isNotEmpty) setState(() => _entry = _entry.substring(0, _entry.length - 1));
      return;
    }
    if (_entry.length >= 6) return;
    setState(() {
      _entry += k;
      _error = null;
    });
    if (_entry.length < 6) return;

    setState(() => _verifying = true);
    final verdict = await widget.pin.verify(_entry);
    if (!mounted) return;
    if (verdict.isOk) {
      widget.onVerified();
      return;
    }
    setState(() {
      _entry = '';
      _verifying = false;
      _error = verdict.isLocked
          ? widget.l10n.pinLockedRetry(verdict.lockRemaining!.inSeconds + 1)
          : widget.l10n.pinIncorrect;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 40, color: SignerColors.text2),
        const SizedBox(height: 16),
        Text(widget.l10n.enterPinToUnlock,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: SignerColors.text)),
        const SizedBox(height: 18),
        PinDots(filled: _entry.length, colors: PinPadColors.signer),
        SizedBox(
          height: 36,
          child: Center(
            child: _error == null
                ? null
                : Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: SignerColors.danger)),
          ),
        ),
        PinPad(onKey: _onKey, colors: PinPadColors.signer),
      ],
    );
  }
}
