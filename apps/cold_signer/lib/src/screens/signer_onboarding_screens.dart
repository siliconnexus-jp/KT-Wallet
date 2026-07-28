import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/biometric_auth.dart';
import '../signing/mnemonic_quiz.dart';
import '../state/signer_wallet_controller.dart';

const _t = AppTheme.signer;

/// The canned design-snapshot mnemonic. The gallery/golden baseline renders
/// this fixed list; the live create flow substitutes the freshly generated
/// words via the router's live overrides.
const _mnemonic = [
  'ripple',
  'canyon',
  'script',
  'harbor',
  'velvet',
  'noble',
  'orbit',
  'meadow',
  'signal',
  'pledge',
  'quartz',
  'ember',
];

Widget _signerBtn(
  String label, {
  bool contrast = false,
  VoidCallback? onPressed,
}) => KtPrimaryButton(
  label: label,
  style: contrast ? KtButtonStyle.signerContrast : KtButtonStyle.signer,
  onPressed: onPressed ?? () {},
);

Widget _wordGrid(List<String> words) => ScreenshotSensitiveBuilder(
  builder: (context, concealed) => Column(
    children: [
      for (var r = 0; r < (words.length / 2).ceil(); r++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              for (var c = 0; c < 2; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: SignerColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          (r * 2 + c + 1).toString().padLeft(2, '0'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: KtFonts.mono,
                            color: Color(0xFF5A616C),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Keyed so flow tests can read the (possibly generated)
                        // word at each position; keys never affect rendering.
                        ExcludeSemantics(
                          excluding: concealed,
                          child: Text(
                            words[r * 2 + c],
                            key: Key('mnemonic-word-${r * 2 + c}'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              fontFamily: KtFonts.mono,
                              color: concealed
                                  ? SignerColors.surface
                                  : SignerColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ],
  ),
);

/// C11 启动页.
class SignerSplashScreen extends StatelessWidget {
  const SignerSplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: SignerColors.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: SignerColors.border),
              ),
              child: const Icon(
                Icons.verified_user,
                size: 48,
                color: SignerColors.ok,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  l10n.appName,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: SignerColors.text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.splashTagline,
              style: const TextStyle(fontSize: 14, color: SignerColors.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// C1 欢迎.
class SignerWelcomeScreen extends StatelessWidget {
  const SignerWelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget feat(IconData icon, String t, String s) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SignerColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SignerColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: SignerColors.blue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SignerColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: SignerColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Only in the combined single-installer app: an escape hatch back to the
    // device-mode picker, so a mistaken "offline signer" choice doesn't force
    // the user through onboarding (or a data wipe) to undo it. Nothing is
    // configured yet at this point, so no confirmation is needed.
    final modeScope = DeviceModeScope.maybeOf(context);
    return KtScreen(
      theme: _t,
      gap: 24,
      bottom: Column(
        children: [
          _signerBtn(
            l10n.createNewWallet,
            contrast: true,
            onPressed: () async {
              // Live flow: generate the real mnemonic this create session will
              // back up and verify. Absent scope (goldens) nothing changes.
              await SignerWalletScope.maybeOf(context)?.beginCreate();
              if (!context.mounted) return;
              unawaited(context.push('/mnemonic-warn'));
            },
          ),
          const SizedBox(height: 12),
          _signerBtn(
            l10n.importExistingWallet,
            onPressed: () => context.push('/mnemonic-import'),
          ),
          if (modeScope != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: modeScope.exitMode,
              child: Text(
                l10n.deviceModeSwitchTitle,
                style: const TextStyle(fontSize: 13, color: SignerColors.text2),
              ),
            ),
          ],
        ],
      ),
      children: [
        const SizedBox(height: 8),
        Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: SignerColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: SignerColors.border),
              ),
              child: const Icon(
                Icons.verified_user,
                size: 44,
                color: SignerColors.ok,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  l10n.appName,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: SignerColors.text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.welcomeSubtitle,
              style: const TextStyle(fontSize: 15, color: SignerColors.text2),
            ),
          ],
        ),
        feat(
          Icons.airplanemode_active,
          l10n.welcomeFeatOfflineTitle,
          l10n.welcomeFeatOfflineDesc,
        ),
        feat(Icons.key, l10n.welcomeFeatLocalTitle, l10n.welcomeFeatLocalDesc),
      ],
    );
  }
}

/// C12 助记词安全提示.
class SignerMnemonicWarnScreen extends StatelessWidget {
  const SignerMnemonicWarnScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget rule(IconData icon, String t, String s) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SignerColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SignerColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: SignerColors.warn),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: SignerColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: SignerColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(
        title: l10n.securityNoticeTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
        trailingText: '1 / 4',
      ),
      bottom: _signerBtn(
        l10n.showMnemonic,
        onPressed: () => context.push('/mnemonic-show'),
      ),
      children: [
        Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: SignerColors.danger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.key,
                size: 34,
                color: SignerColors.danger,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.mnemonicWillGenerate,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
          ],
        ),
        rule(
          Icons.workspace_premium,
          l10n.ruleFullControlTitle,
          l10n.ruleFullControlDesc,
        ),
        rule(Icons.edit, l10n.ruleHandwriteTitle, l10n.ruleHandwriteDesc),
        rule(Icons.block, l10n.ruleNoCaptureTitle, l10n.ruleNoCaptureDesc),
      ],
    );
  }
}

/// C3 助记词展示.
class SignerMnemonicShowScreen extends StatelessWidget {
  const SignerMnemonicShowScreen({super.key, this.words});

  /// The real generated mnemonic (live create flow, via the router override);
  /// null renders the canned demo list — the gallery/golden baseline.
  final List<String>? words;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 18,
      navBar: KtNavBar(
        title: l10n.backupMnemonicTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
        trailingText: '2 / 4',
      ),
      bottom: _signerBtn(
        l10n.mnemonicShowConfirmBtn,
        onPressed: () => context.push('/mnemonic-verify'),
      ),
      children: [
        Text(
          l10n.mnemonicShowInstruction,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: SignerColors.text2,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SignerColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.no_photography,
                size: 18,
                color: SignerColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.mnemonicShowWarning,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: SignerColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
        _wordGrid(words ?? _mnemonic),
      ],
    );
  }
}

/// C4 助记词校验.
class SignerMnemonicVerifyScreen extends StatefulWidget {
  const SignerMnemonicVerifyScreen({super.key, this.challenge});

  /// The live challenge over the real generated mnemonic (router override);
  /// null falls back to the fixed demo challenge — the golden baseline.
  final QuizQuestion? challenge;

  @override
  State<SignerMnemonicVerifyScreen> createState() =>
      _SignerMnemonicVerifyScreenState();
}

class _SignerMnemonicVerifyScreenState
    extends State<SignerMnemonicVerifyScreen> {
  // The canned demo challenge (design snapshot): position 9 → 'signal'.
  static const _demoPosition = 9; // 1-based
  static const _demoOptions = [
    'harbor',
    'signal',
    'quartz',
    'meadow',
    'orbit',
    'pledge',
  ];

  int get _challengePosition => widget.challenge?.position ?? _demoPosition;
  List<String> get _options => widget.challenge?.options ?? _demoOptions;
  String get _correct =>
      widget.challenge?.correctWord ?? _mnemonic[_demoPosition - 1]; // 'signal'

  String? _selected;

  void _confirm() {
    if (_selected == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (_selected == _correct) {
      context.push('/set-password');
    } else {
      setState(() => _selected = null);
      messenger.showSnackBar(SnackBar(content: Text(l10n.verifyWrong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 24,
      navBar: KtNavBar(
        title: l10n.verifyBackupTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
        trailingText: '3 / 4',
      ),
      bottom: _signerBtn(
        l10n.actionConfirm,
        onPressed: _selected == null ? null : _confirm,
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final done in [true, true, false])
              Container(
                width: 28,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: done ? SignerColors.ok : SignerColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        Column(
          children: [
            Text(
              l10n.mnemonicWordChallenge(_challengePosition),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mnemonicChallengeHint,
              style: const TextStyle(fontSize: 13, color: SignerColors.text2),
            ),
          ],
        ),
        Column(
          children: [
            for (var r = 0; r < 3; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (var c = 0; c < 2; c++) ...[
                      if (c > 0) const SizedBox(width: 10),
                      Expanded(
                        child: () {
                          final word = _options[r * 2 + c];
                          final sel = word == _selected;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _selected = word),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: sel
                                    ? SignerColors.ok.withValues(alpha: 0.08)
                                    : SignerColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel
                                      ? SignerColors.ok
                                      : SignerColors.border,
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                word,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: KtFonts.mono,
                                  color: sel
                                      ? SignerColors.ok
                                      : SignerColors.text,
                                ),
                              ),
                            ),
                          );
                        }(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// C13 助记词输入.
class SignerMnemonicImportScreen extends StatefulWidget {
  const SignerMnemonicImportScreen({super.key});
  @override
  State<SignerMnemonicImportScreen> createState() =>
      _SignerMnemonicImportScreenState();
}

class _SignerMnemonicImportScreenState
    extends State<SignerMnemonicImportScreen> {
  int _wordCount = 12;
  bool _busy = false;
  String? _error;
  final List<TextEditingController> _fields = List.generate(
    24,
    (_) => TextEditingController(),
  );

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final controller = SignerWalletScope.maybeOf(context);
    if (controller == null) {
      unawaited(context.push('/set-password'));
      return;
    }
    final phrase = _fields.take(_wordCount).map((e) => e.text.trim()).join(' ');
    setState(() {
      _busy = true;
      _error = null;
    });
    final valid = await controller.beginImport(phrase);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!valid) {
      setState(() => _error = '助记词无效，请检查单词、数量与 BIP-39 校验和');
      return;
    }
    unawaited(context.push('/set-password'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (SignerWalletScope.maybeOf(context) == null) {
      return _mnemonicImportPreview(context, l10n);
    }
    return KtScreen(
      theme: _t,
      gap: 18,
      navBar: KtNavBar(
        title: l10n.importWalletTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: _signerBtn(
        _busy ? '正在校验…' : l10n.actionImport,
        onPressed: _busy ? null : _import,
      ),
      children: [
        KtSegmented(
          theme: _t,
          options: [
            l10n.wordCountOption(12),
            l10n.wordCountOption(18),
            l10n.wordCountOption(24),
          ],
          selected: const [12, 18, 24].indexOf(_wordCount),
          onChanged: (index) => setState(() {
            _wordCount = const [12, 18, 24][index];
            _error = null;
          }),
        ),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SignerColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: SignerColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SignerColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Column(
          children: [
            for (var r = 0; r < (_wordCount / 2).ceil(); r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (var c = 0; c < 2; c++) ...[
                      if (c > 0) const SizedBox(width: 10),
                      Expanded(
                        child: () {
                          final idx = r * 2 + c;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: SignerColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: SignerColors.border),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  (idx + 1).toString().padLeft(2, '0'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: KtFonts.mono,
                                    color: Color(0xFF5A616C),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _fields[idx],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: idx + 1 == _wordCount
                                        ? TextInputAction.done
                                        : TextInputAction.next,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontFamily: KtFonts.mono,
                                      color: SignerColors.text,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Widget _mnemonicImportPreview(BuildContext context, AppLocalizations l10n) {
  const typed = [
    'ripple',
    'canyon',
    'script',
    'harbor',
    'velvet',
    'noble',
    'orbit',
    '',
    '',
    '',
    '',
    '',
  ];
  return KtScreen(
    theme: _t,
    gap: 18,
    navBar: KtNavBar(
      title: l10n.importWalletTitle,
      theme: _t,
      onBack: () => Navigator.of(context).maybePop(),
    ),
    bottom: _signerBtn(
      l10n.actionImport,
      onPressed: () => context.push('/set-password'),
    ),
    children: [
      KtSegmented(
        theme: _t,
        options: [
          l10n.wordCountOption(12),
          l10n.wordCountOption(18),
          l10n.wordCountOption(24),
        ],
        selected: 0,
      ),
      Column(
        children: [
          for (var r = 0; r < 6; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (var c = 0; c < 2; c++) ...[
                    if (c > 0) const SizedBox(width: 10),
                    Expanded(
                      child: () {
                        final idx = r * 2 + c;
                        final active = idx == 7;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: SignerColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active
                                  ? SignerColors.blue
                                  : SignerColors.border,
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                (idx + 1).toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: KtFonts.mono,
                                  color: Color(0xFF5A616C),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                typed[idx],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: KtFonts.mono,
                                  color: SignerColors.text,
                                ),
                              ),
                            ],
                          ),
                        );
                      }(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// C14 设置密码 (numpad). Two-phase: enter 6 digits, then re-enter to confirm.
class SignerSetPasswordScreen extends StatefulWidget {
  const SignerSetPasswordScreen({super.key});
  @override
  State<SignerSetPasswordScreen> createState() =>
      _SignerSetPasswordScreenState();
}

class _SignerSetPasswordScreenState extends State<SignerSetPasswordScreen> {
  String _entry = '';
  String? _first; // the first pass, once 6 digits entered
  bool _oldVerified = false;

  void _onKey(String k) {
    if (k == 'del') {
      if (_entry.isNotEmpty) {
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      }
      return;
    }
    if (k.isEmpty || _entry.length >= 6) return;
    setState(() => _entry += k);
    if (_entry.length == 6) _onComplete();
  }

  Future<void> _onComplete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final controller = SignerWalletScope.maybeOf(context);
    if (controller?.hasWallet == true && !_oldVerified) {
      final verdict = await controller!.pinLock.verify(_entry);
      if (!mounted) return;
      if (!verdict.isOk) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.pinIncorrect)));
        setState(() => _entry = '');
        return;
      }
      setState(() {
        _oldVerified = true;
        _entry = '';
      });
      return;
    }
    if (_first == null) {
      // First pass done; ask for confirmation.
      setState(() {
        _first = _entry;
        _entry = '';
      });
    } else if (_entry == _first) {
      // Live flow: enroll the real PIN (PBKDF2 hash into the secure vault)
      // before moving on. Without a scope (goldens) this is a pure no-op and
      // the screen behaves exactly like the design snapshot.
      if (controller != null) await controller.setPin(_entry);
      if (!mounted) return;
      unawaited(context.push('/biometric'));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.passwordMismatch)));
      setState(() {
        _first = null;
        _entry = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final changingExisting =
        SignerWalletScope.maybeOf(context)?.hasWallet == true;
    final confirming = _first != null;
    final prompt = changingExisting && !_oldVerified
        ? l10n.enterPinToSign
        : confirming
        ? l10n.setPasswordConfirmPrompt
        : l10n.setPasswordPrompt;
    return KtScreen(
      theme: _t,
      gap: 28,
      navBar: KtNavBar(
        title: l10n.setPasswordTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
        trailingText: '4 / 4',
      ),
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            Text(
              prompt,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.setPasswordDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 6; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: i < _entry.length
                      ? SignerColors.text
                      : SignerColors.surface2,
                  shape: BoxShape.circle,
                  border: i < _entry.length
                      ? null
                      : Border.all(color: SignerColors.border),
                ),
              ),
          ],
        ),
        Column(
          children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', 'del'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final k in row)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onKey(k),
                        child: Container(
                          width: 72,
                          height: 72,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k.isEmpty || k == 'del'
                                ? null
                                : SignerColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: k == 'del'
                              ? const Icon(
                                  Icons.backspace_outlined,
                                  size: 22,
                                  color: SignerColors.text2,
                                )
                              : Text(
                                  k,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w500,
                                    color: SignerColors.text,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// C15 生物识别设置.
class SignerBiometricScreen extends StatelessWidget {
  const SignerBiometricScreen({super.key});

  Future<void> _finish(BuildContext context, {required bool biometric}) async {
    final controller = SignerWalletScope.maybeOf(context);
    try {
      if (biometric && !await BiometricAuth.instance.canAuthenticate()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('此设备尚未设置可用的生物识别')));
        return;
      }
      await controller?.completeOnboarding();
      if (biometric) {
        await controller?.setBiometricEnabled(true);
      }
      if (context.mounted) unawaited(context.push('/created'));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('钱包安全存储失败，未保存任何密钥')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 28,
      navBar: KtNavBar(title: l10n.biometricTitle, theme: _t),
      bottom: Column(
        children: [
          _signerBtn(
            l10n.enableFaceId,
            onPressed: () => _finish(context, biometric: true),
          ),
          const SizedBox(height: 12),
          // Skipping biometrics still completes wallet creation.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _finish(context, biometric: false),
            child: Text(
              l10n.biometricSkip,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: SignerColors.text2,
              ),
            ),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: SignerColors.surface,
              borderRadius: BorderRadius.circular(60),
              border: Border.all(color: SignerColors.border),
            ),
            child: const Icon(Icons.face, size: 60, color: SignerColors.blue),
          ),
        ),
        Column(
          children: [
            Text(
              l10n.enableFaceId,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.biometricDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.7,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// C16 创建成功.
class SignerCreatedScreen extends StatefulWidget {
  const SignerCreatedScreen({super.key});
  @override
  State<SignerCreatedScreen> createState() => _SignerCreatedScreenState();
}

class _SignerCreatedScreenState extends State<SignerCreatedScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 24,
      bottom: Column(
        children: [
          _signerBtn(
            l10n.exportPublicAddress,
            onPressed: () => context.push('/export'),
          ),
          const SizedBox(height: 12),
          // "Later" skips address export and lands on the offline home.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.go('/home'),
            child: Text(
              l10n.later,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: SignerColors.text2,
              ),
            ),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 48),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: SignerColors.ok.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: SignerColors.ok,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 34,
                  color: Color(0xFF0A0C0F),
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            Text(
              l10n.walletCreated,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mnemonicBackedUpVerified,
              style: const TextStyle(fontSize: 14, color: SignerColors.text2),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SignerColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _KvRow(l10n.walletNameLabel, l10n.walletMainName),
              const SizedBox(height: 12),
              _KvRow(l10n.mnemonicBackupLabel, l10n.verified, ok: true),
              const SizedBox(height: 12),
              _KvRow(l10n.supportedNetworks, 'ETH · POL · TRX · SOL'),
            ],
          ),
        ),
      ],
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow(this.k, this.v, {this.ok = false});
  final String k, v;
  final bool ok;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(k, style: const TextStyle(fontSize: 13, color: SignerColors.text2)),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          v,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: ok ? SignerColors.ok : SignerColors.text,
          ),
        ),
      ),
    ],
  );
}
