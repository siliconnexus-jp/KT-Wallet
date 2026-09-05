import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/backup_qr_image.dart';
import '../state/signer_wallet_controller.dart';
import '../widgets/scan_viewfinder.dart';

class SignerQrImportScreen extends StatefulWidget {
  const SignerQrImportScreen({super.key, this.picker, this.reader});
  final SignerBackupImagePicker? picker;
  final BackupQrImageReader? reader;

  @override
  State<SignerQrImportScreen> createState() => _SignerQrImportScreenState();
}

class _SignerQrImportScreenState extends State<SignerQrImportScreen>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  String? _payload;
  String? _error;
  bool _busy = false;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _password.clear();
      _operation++;
    }
  }

  @override
  void dispose() {
    _operation++;
    _payload = null;
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    super.dispose();
  }

  void _accept(String value) {
    WalletBackupQr.decode(value);
    _password.clear();
    setState(() {
      _payload = value;
      _error = null;
    });
  }

  Future<void> _select({required bool camera}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _password.clear();
    try {
      String? value;
      if (camera) {
        value = await context.push<String>('/qr-import/scan');
      } else {
        final bytes = await (widget.picker ?? const SignerBackupImagePicker())
            .pick();
        if (bytes != null) {
          value = await (widget.reader ?? const BackupQrImageReader()).read(
            bytes,
          );
        }
      }
      if (mounted && value != null) _accept(value);
    } on Object {
      if (mounted) {
        setState(() {
          _payload = null;
          _error = AppLocalizations.of(context).qrImportInvalid;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy || _payload == null || _password.text.isEmpty) return;
    final wallet = SignerWalletScope.maybeOf(context);
    if (wallet == null) return;
    final operation = ++_operation;
    bool active() => mounted && operation == _operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final valid = await wallet.beginQrImport(
        _payload!,
        _password.text,
        isActive: active,
      );
      if (!mounted || !active()) return;
      if (!valid) {
        setState(() => _error = AppLocalizations.of(context).qrImportInvalid);
        return;
      }
      _password.clear();
      _payload = null;
      context.go('/set-password');
    } on AuthUnavailableException {
      if (active()) {
        setState(
          () => _error = AppLocalizations.of(context).walletDeviceAuthRequired,
        );
      }
    } on AuthLockedException {
      if (active()) {
        setState(
          () =>
              _error = AppLocalizations.of(context).walletCreationAuthRequired,
        );
      }
    } on CryptoUnavailableException {
      if (active()) {
        setState(
          () => _error = AppLocalizations.of(context).walletSecureStorageFailed,
        );
      }
    } on Object {
      if (active()) {
        setState(
          () => _error = AppLocalizations.of(context).qrImportWrongPassword,
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: AppTheme.signer,
      navBar: KtNavBar(
        theme: AppTheme.signer,
        title: l10n.qrImportTitle,
        onBack: () => context.pop(),
      ),
      bottom: KtPrimaryButton(
        style: KtButtonStyle.signer,
        label: l10n.qrImportContinue,
        loading: _busy,
        onPressed: !_busy && _payload != null && _password.text.isNotEmpty
            ? _restore
            : null,
      ),
      children: [
        const Icon(
          Icons.qr_code_2_rounded,
          size: 56,
          color: SignerColors.accent,
        ),
        Text(
          l10n.qrImportDescription,
          textAlign: TextAlign.center,
          style: const TextStyle(color: SignerColors.text2, height: 1.5),
        ),
        KtGlassSurface(
          dark: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                key: const ValueKey('qr-import-scan'),
                onPressed: _busy ? null : () => _select(camera: true),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(l10n.qrImportScan),
              ),
              const Divider(color: SignerColors.border),
              TextButton.icon(
                key: const ValueKey('qr-import-image'),
                onPressed: _busy ? null : () => _select(camera: false),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.qrImportImage),
              ),
            ],
          ),
        ),
        if (_payload != null) ...[
          Text(
            l10n.qrImportReady,
            style: const TextStyle(color: SignerColors.accent),
          ),
          TextField(
            key: const ValueKey('qr-import-password'),
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            maxLength: 128,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _restore(),
            style: const TextStyle(color: SignerColors.text),
            decoration: InputDecoration(
              labelText: l10n.qrImportPassword,
              counterText: '',
            ),
          ),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: SignerColors.danger, height: 1.5),
            ),
          ),
        Text(
          l10n.qrImportSafety,
          style: const TextStyle(
            color: SignerColors.text2,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class SignerBackupScanScreen extends StatefulWidget {
  const SignerBackupScanScreen({super.key});
  @override
  State<SignerBackupScanScreen> createState() => _SignerBackupScanScreenState();
}

class _SignerBackupScanScreenState extends State<SignerBackupScanScreen> {
  bool _done = false;
  String? _error;
  void _scanned(String value) {
    if (_done || !mounted) return;
    try {
      WalletBackupQr.decode(value);
      _done = true;
      context.pop(value);
    } on BackupFormatException {
      setState(() => _error = AppLocalizations.of(context).qrImportInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: AppTheme.signer,
      navBar: KtNavBar(
        theme: AppTheme.signer,
        title: l10n.qrImportScan,
        onBack: () => context.pop(),
      ),
      children: [
        Text(
          l10n.qrImportDescription,
          style: const TextStyle(color: SignerColors.text2),
        ),
        ScanViewfinder(
          height: 320,
          frameColor: SignerColors.accent,
          onScanned: _scanned,
        ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: SignerColors.danger),
            ),
          ),
      ],
    );
  }
}
