import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/backup_qr_image.dart';
import '../state/signer_wallet_controller.dart';

/// Only native-encrypted entropy reaches this screen, never a recovery phrase.
class SignerQrBackupScreen extends StatefulWidget {
  const SignerQrBackupScreen({
    super.key,
    required this.walletId,
    this.files,
    this.renderer,
  });
  final String walletId;
  final SignerBackupImagePicker? files;
  final Future<Uint8List> Function(String)? renderer;

  @override
  State<SignerQrBackupScreen> createState() => _SignerQrBackupScreenState();
}

class _SignerQrBackupScreenState extends State<SignerQrBackupScreen>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Uint8List? _png;
  String? _error;
  bool _accepted = false;
  bool _busy = false;
  int _operation = 0;

  @override
  void didUpdateWidget(covariant SignerQrBackupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walletId != widget.walletId) {
      _operation++;
      _png = null;
      _accepted = false;
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _password.addListener(_edited);
    _confirm.addListener(_edited);
  }

  void _edited() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void dispose() {
    _operation++;
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _confirm.dispose();
    _png = null;
    super.dispose();
  }

  bool get _isCurrent {
    final wallet = SignerWalletScope.maybeOf(context);
    return wallet?.hasWallet == true &&
        wallet?.localWalletId == widget.walletId;
  }

  Future<void> _generate() async {
    if (_busy ||
        !_accepted ||
        !_isCurrent ||
        CoreCryptoValidation.backupPasswordIssue(_password.text) != null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.backupPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final operation = ++_operation;
    Uint8List? sealed;
    try {
      final pending = SignerWalletScope.maybeOf(context)!.createEncryptedBackup(
        walletId: widget.walletId,
        password: _password.text,
      );
      _password.clear();
      _confirm.clear();
      sealed = await pending;
      if (!mounted || !_isCurrent || operation != _operation) return;
      final payload = WalletBackupQr.encode(sealed);
      final png =
          await (widget.renderer?.call(payload) ??
              renderBrandedQrPng(
                payload: payload,
                title: l10n.backupQrTitle,
                instruction: l10n.backupQrImageInstruction,
                brandName: 'KT Cold Signer',
                accent: SignerColors.ok,
              ));
      if (mounted && _isCurrent && operation == _operation) {
        setState(() => _png = png);
      }
    } on AuthCancelledException {
      // Cancellation leaves the form available, with no exported image.
    } catch (_) {
      if (mounted) setState(() => _error = l10n.backupFailed);
    } finally {
      sealed?.fillRange(0, sealed.length, 0);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _png == null || !_isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final saved = await (widget.files ?? const SignerBackupImagePicker())
          .save(_png!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? l10n.backupSaved : l10n.backupCancelled),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = l10n.backupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? error,
  }) => TextField(
    controller: controller,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    keyboardType: TextInputType.visiblePassword,
    style: const TextStyle(color: SignerColors.text),
    decoration: InputDecoration(
      labelText: label,
      errorText: error,
      errorMaxLines: 3,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallet = SignerWalletScope.maybeOf(context);
    final available = _isCurrent;
    final issue = _password.text.isEmpty
        ? null
        : CoreCryptoValidation.backupPasswordIssue(_password.text);
    final passwordError = switch (issue) {
      BackupPasswordIssue.tooShort => l10n.backupPasswordTooShort,
      BackupPasswordIssue.tooLong => l10n.backupPasswordTooLong,
      BackupPasswordIssue.predictable => l10n.backupPasswordTooWeak,
      null => null,
    };
    return KtScreen(
      theme: AppTheme.signer,
      navBar: KtNavBar(
        title: l10n.backupQrTitle,
        theme: AppTheme.signer,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: available
          ? KtPrimaryButton(
              key: const ValueKey('signer-backup-submit'),
              label: _png == null ? l10n.backupQrGenerate : l10n.backupQrSave,
              style: KtButtonStyle.signer,
              loading: _busy,
              onPressed: _busy
                  ? null
                  : _png != null
                  ? _save
                  : _accepted &&
                        CoreCryptoValidation.backupPasswordIssue(
                              _password.text,
                            ) ==
                            null &&
                        _confirm.text.isNotEmpty
                  ? _generate
                  : null,
            )
          : null,
      children: [
        if (!available)
          Text(l10n.signRejectNoWallet)
        else ...[
          KtCard(
            theme: AppTheme.signer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  wallet!.metadata!.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: SignerColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.signerBackupScope,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: SignerColors.text2,
                  ),
                ),
              ],
            ),
          ),
          if (_png != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(_png!, semanticLabel: l10n.backupQrTitle),
            ),
            Text(
              l10n.signerBackupLocalWarning,
              style: const TextStyle(color: SignerColors.text2, height: 1.5),
            ),
          ] else ...[
            Text(
              l10n.backupQrIntro,
              style: const TextStyle(color: SignerColors.text2, height: 1.5),
            ),
            KtCard(
              theme: AppTheme.signer,
              child: Column(
                children: [
                  _field(
                    _password,
                    l10n.backupPasswordLabel,
                    error: passwordError,
                  ),
                  const SizedBox(height: 16),
                  _field(_confirm, l10n.backupPasswordConfirm),
                ],
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('signer-backup-risk'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _accepted,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _accepted = value ?? false),
              title: Text(
                l10n.signerBackupLocalWarning,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: SignerColors.text2,
                ),
              ),
            ),
          ],
          if (_error != null)
            Text(_error!, style: const TextStyle(color: SignerColors.danger)),
        ],
      ],
    );
  }
}
