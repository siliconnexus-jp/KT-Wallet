import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../platform/file_exchange.dart';
import '../security/secure_screen.dart';
import '../security/wallet_backup.dart';
import '../state/wallet_scope.dart';

/// W32 加密备份 — seals the active wallet's key material under a password the
/// user chooses and hands the file to the system document picker, which is
/// where iCloud Drive lives.
///
/// The password never leaves this screen and the plaintext key material never
/// enters Dart: [CoreCrypto.createBackup] reads the entropy natively behind a
/// biometric prompt and returns it already sealed.
class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key, this.files, this.clock});

  /// Injected in tests; production uses the platform channel.
  final FileExchange? files;
  final DateTime Function()? clock;

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  FileExchange get _files => widget.files ?? FileExchange.instance;
  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  @override
  void initState() {
    super.initState();
    // Enables/disables the button as the user types.
    _password.addListener(_onEdited);
    _confirm.addListener(_onEdited);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onEdited() {
    if (_error != null) setState(() => _error = null);
    setState(() {});
  }

  bool get _canSubmit =>
      !_busy &&
      _password.text.length >= CoreCryptoValidation.minBackupPasswordLength &&
      _confirm.text.isNotEmpty;

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.backupPasswordMismatch);
      return;
    }
    final wallets = WalletScope.of(context);
    final wallet = wallets.current;
    if (wallet == null) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();

    setState(() => _busy = true);
    try {
      final sealed = await wallets.crypto.createBackup(
        walletId: wallet.id,
        password: _password.text,
      );
      final now = _clock();
      final saved = await _files.saveFile(
        suggestedName: WalletBackupFile.suggestedFileName(now),
        bytes: WalletBackupFile.encode(sealed: sealed, createdAt: now),
      );
      if (!mounted) return;
      final message = switch (saved.outcome) {
        FileExchangeOutcome.done =>
          saved.location == null || saved.location!.isEmpty
              ? l10n.backupSaved
              : l10n.backupSavedTo(saved.location!),
        FileExchangeOutcome.cancelled => l10n.backupCancelled,
        FileExchangeOutcome.unsupported => l10n.backupUnsupported,
        FileExchangeOutcome.failed => l10n.backupFailed,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
      if (saved.outcome == FileExchangeOutcome.done) {
        // Leave the password fields behind rather than keeping a second copy
        // of it alive in a text field on a screen the user may walk away from.
        if (mounted) unawaited(Navigator.of(context).maybePop());
      }
    } on AuthCancelledException {
      // The user dismissed the biometric prompt: not an error worth shouting.
    } on CoreCryptoException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooShort =
        _password.text.isNotEmpty &&
        _password.text.length < CoreCryptoValidation.minBackupPasswordLength;
    // The password is as good as the phrase itself while it is on screen.
    return SecureContent(
      child: KtScreen(
        navBar: KtNavBar(
          title: l10n.backupEncryptedTitle,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        bottom: KtPrimaryButton(
          label: l10n.backupCreate,
          onPressed: _canSubmit ? _create : null,
        ),
        children: [
          Text(
            l10n.backupIntro,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: WalletColors.text2,
            ),
          ),
          KtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  controller: _password,
                  label: l10n.backupPasswordLabel,
                  error: tooShort ? l10n.backupPasswordTooShort : null,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _confirm,
                  label: l10n.backupPasswordConfirm,
                  error: _error,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WalletColors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: WalletColors.amber,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.backupPasswordWarning,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: Color(0xFF8A6100),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? error,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: WalletColors.text2),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        enabled: !_busy,
        decoration: InputDecoration(
          isDense: true,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 15, color: WalletColors.text),
      ),
    ],
  );
}

/// W33 从备份恢复 — picks a `.ktbak` file, asks for its password, and hands the
/// recovered phrase to the ordinary import path.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key, this.files});

  final FileExchange? files;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _password = TextEditingController();
  PickedFile? _picked;
  bool _busy = false;
  String? _error;

  FileExchange get _files => widget.files ?? FileExchange.instance;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _files.pickFile(
      extensions: const [WalletBackupFile.fileExtension],
    );
    if (picked == null || !mounted) return;
    // Validate the envelope at pick time so a wrong file is called out before
    // the user types a password that was never going to work.
    try {
      WalletBackupFile.decode(picked.bytes);
    } on BackupFormatException catch (e) {
      setState(() {
        _picked = null;
        _error = e.reason.contains('too new')
            ? l10n.restoreTooNew
            : l10n.restoreNotABackup;
      });
      return;
    }
    setState(() {
      _picked = picked;
      _error = null;
    });
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final picked = _picked;
    if (picked == null) return;
    final wallets = WalletScope.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();

    setState(() => _busy = true);
    String? mnemonic;
    try {
      mnemonic = await wallets.crypto.readBackup(
        blob: WalletBackupFile.decode(picked.bytes),
        password: _password.text,
      );
    } on BackupFormatException {
      setState(() => _error = l10n.restoreNotABackup);
    } on CoreCryptoException {
      // GCM cannot tell a wrong password from a damaged file, and neither can
      // we — say both rather than guess.
      setState(() => _error = l10n.restoreWrongPassword);
    } finally {
      if (mounted && mnemonic == null) setState(() => _busy = false);
    }
    if (mnemonic == null || !mounted) return;

    try {
      await wallets.importWallet(
        mnemonic,
        name: l10n.walletImportedName(wallets.count + 1),
      );
    } on CoreCryptoException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.restoreWrongPassword;
        });
      }
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.restoreRestored)));
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final picked = _picked;
    return SecureContent(
      child: KtScreen(
        navBar: KtNavBar(
          title: l10n.restoreFromBackup,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        bottom: KtPrimaryButton(
          label: l10n.restoreAction,
          onPressed: picked != null && _password.text.isNotEmpty && !_busy
              ? _restore
              : null,
        ),
        children: [
          Text(
            l10n.restoreFromBackupDesc,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: WalletColors.text2,
            ),
          ),
          KtCard(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : _pick,
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_open,
                    size: 20,
                    color: WalletColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      picked == null
                          ? l10n.restorePickFile
                          : l10n.backupFileChosen(picked.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: WalletColors.text,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: WalletColors.text3,
                  ),
                ],
              ),
            ),
          ),
          KtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.restoreEnterPassword,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WalletColors.text2,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    isDense: true,
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    color: WalletColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
