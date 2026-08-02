import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/app_prefs.dart';
import '../widgets/pin_pad.dart';
import 'biometric_auth.dart';
import 'wallet_pin.dart';

/// Authentication gate for security-sensitive transaction operations.
///
/// The configured method is attempted first. A capability-level biometric
/// failure may fall back to the wallet PIN; a failed/cancelled biometric
/// verdict never falls through automatically.
abstract class TransactionAuthGate {
  const TransactionAuthGate();

  Future<bool> authenticate(
    BuildContext context, {
    required AuthMethod method,
    required String reason,
  });
}

class LocalTransactionAuthGate extends TransactionAuthGate {
  const LocalTransactionAuthGate({this.biometricAuth, this.pin});

  final BiometricAuth? biometricAuth;
  final WalletPin? pin;

  @override
  Future<bool> authenticate(
    BuildContext context, {
    required AuthMethod method,
    required String reason,
  }) async {
    final walletPin = pin ?? WalletPin.instance;
    if (method == AuthMethod.password) {
      return _showPin(context, walletPin);
    }
    final outcome = await (biometricAuth ?? BiometricAuth.instance)
        .authenticate(reason: reason);
    if (!context.mounted) return false;
    return switch (outcome) {
      BiometricOutcome.success => true,
      BiometricOutcome.failure => false,
      BiometricOutcome.unavailable => _showPin(context, walletPin),
    };
  }

  Future<bool> _showPin(BuildContext context, WalletPin pin) async {
    if (!await pin.isSet() || !context.mounted) return false;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: WalletColors.surface,
          builder: (_) => _TransactionPinSheet(pin: pin),
        ) ??
        false;
  }
}

class FakeTransactionAuthGate extends TransactionAuthGate {
  const FakeTransactionAuthGate(this.result);
  final bool result;

  @override
  Future<bool> authenticate(
    BuildContext context, {
    required AuthMethod method,
    required String reason,
  }) async => result;
}

class _TransactionPinSheet extends StatefulWidget {
  const _TransactionPinSheet({required this.pin});
  final WalletPin pin;

  @override
  State<_TransactionPinSheet> createState() => _TransactionPinSheetState();
}

class _TransactionPinSheetState extends State<_TransactionPinSheet> {
  String _entry = '';
  String? _error;
  bool _busy = false;

  Future<void> _key(String key) async {
    if (_busy) return;
    if (key == 'del') {
      if (_entry.isNotEmpty) {
        setState(() {
          _entry = _entry.substring(0, _entry.length - 1);
          _error = null;
        });
      }
      return;
    }
    if (_entry.length >= 6) return;
    setState(() {
      _entry += key;
      _error = null;
    });
    if (_entry.length != 6) return;
    setState(() => _busy = true);
    final verdict = await widget.pin.verify(_entry);
    if (!mounted) return;
    if (verdict.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entry = '';
      _busy = false;
      _error = verdict.isLocked
          ? l10n.pinLockedRetry(verdict.lockRemaining!.inSeconds + 1)
          : l10n.pinIncorrect;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.usePasscode,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 18),
            PinDots(filled: _entry.length),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: WalletColors.red),
              ),
            ],
            const SizedBox(height: 18),
            PinPad(onKey: _key),
          ],
        ),
      ),
    );
  }
}
