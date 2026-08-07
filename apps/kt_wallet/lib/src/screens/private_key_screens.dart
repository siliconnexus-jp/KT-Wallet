import 'dart:async';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/secure_screen.dart';
import '../state/networks.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';
import '../widgets/token_icon.dart';

/// OKX-aligned private-key export flow.
///
/// The three warning pages and account directory are Flutter UI. Native code
/// owns authentication, derivation and clipboard writes; the complete private
/// key never returns over the MethodChannel. Safe copy returns only the six
/// characters intentionally withheld from the clipboard for manual entry.
class PrivateKeyExportScreen extends StatefulWidget {
  const PrivateKeyExportScreen({super.key, this.walletId});

  final String? walletId;

  @override
  State<PrivateKeyExportScreen> createState() => _PrivateKeyExportScreenState();
}

class _PrivateKeyExportScreenState extends State<PrivateKeyExportScreen>
    with WidgetsBindingObserver {
  static const _countdownStart = 3;

  Timer? _countdownTimer;
  int _page = 0;
  int _seconds = _countdownStart;
  bool _authenticating = false;
  String? _authError;
  String? _sessionId;
  CoreCrypto? _crypto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCountdown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _crypto = WalletScope.of(context).crypto;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(
        _crypto?.endPrivateKeyExport(sessionId).catchError((_) {}) ??
            Future<void>.value(),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _countdownTimer?.cancel();
      final sessionId = _sessionId;
      if (sessionId != null) {
        _sessionId = null;
        unawaited(
          _crypto?.endPrivateKeyExport(sessionId).catchError((_) {}) ??
              Future<void>.value(),
        );
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _sessionId == null) {
      if (mounted) {
        setState(() {
          _page = _page.clamp(0, 2);
          _seconds = _countdownStart;
          _authenticating = false;
        });
      }
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_seconds <= 1) {
        timer.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _nextWarning() {
    if (_seconds != 0 || _page >= 2) return;
    setState(() {
      _page++;
      _seconds = _countdownStart;
      _authError = null;
    });
    _startCountdown();
  }

  HotWallet? _wallet() {
    final controller = WalletScope.of(context);
    final wallet = widget.walletId == null
        ? controller.current
        : controller.wallets
              .where((candidate) => candidate.id == widget.walletId)
              .firstOrNull;
    return wallet is HotWallet ? wallet : null;
  }

  Future<void> _authenticate() async {
    if (_seconds != 0 || _authenticating) return;
    final wallet = _wallet();
    if (wallet == null) return;
    setState(() {
      _authenticating = true;
      _authError = null;
    });
    try {
      final crypto = _crypto;
      if (crypto == null) return;
      final sessionId = await crypto.beginPrivateKeyExport(wallet.id);
      if (!mounted) {
        unawaited(crypto.endPrivateKeyExport(sessionId));
        return;
      }
      setState(() {
        _sessionId = sessionId;
        _authenticating = false;
      });
    } on CoreCryptoException {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _authError = AppLocalizations.of(context).privateKeyAuthFailed;
      });
    }
  }

  void _expireSession() {
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(
        _crypto?.endPrivateKeyExport(sessionId).catchError((_) {}) ??
            Future<void>.value(),
      );
    }
    if (!mounted) return;
    setState(() {
      _sessionId = null;
      _page = 2;
      _seconds = _countdownStart;
      _authError = AppLocalizations.of(context).privateKeySessionExpired;
    });
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet();
    final sessionId = _sessionId;
    return SecureContent(
      child: sessionId != null && wallet != null
          ? _PrivateKeyDirectory(
              wallet: wallet,
              sessionId: sessionId,
              crypto: _crypto!,
              onSessionExpired: _expireSession,
            )
          : _warningScreen(context),
    );
  }

  Widget _warningScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [
      l10n.privateKeyWarningOneTitle,
      l10n.privateKeyWarningTwoTitle,
      l10n.privateKeyWarningThreeTitle,
    ];
    final bodies = [
      l10n.privateKeyWarningOneBody,
      l10n.privateKeyWarningTwoBody,
      l10n.privateKeyWarningThreeBody,
    ];
    final icons = [
      Icons.no_photography_outlined,
      Icons.copy_all_outlined,
      Icons.key_rounded,
    ];
    final primaryLabel = _page == 2
        ? l10n.privateKeyBackupNow
        : l10n.privateKeyAcknowledge;
    final displayedPrimary = _seconds > 0
        ? l10n.privateKeyCountdownButton(primaryLabel, _seconds)
        : primaryLabel;
    return KtScreen(
      key: const ValueKey('private-key-warning-screen'),
      backgroundColor: WalletColors.surface,
      navBar: KtNavBar(
        title: '',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      gap: 0,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrivateKeyPrimaryButton(
            key: const ValueKey('private-key-warning-primary'),
            label: displayedPrimary,
            loading: _authenticating,
            onPressed: _seconds == 0
                ? (_page == 2 ? _authenticate : _nextWarning)
                : null,
          ),
          const SizedBox(height: 10),
          _PrivateKeySecondaryButton(
            key: const ValueKey('private-key-warning-cancel'),
            label: l10n.privateKeyNotNow,
            onPressed: _authenticating
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: Column(
            key: ValueKey('private-key-warning-page-$_page'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 70),
              Center(child: _WarningGraphic(icon: icons[_page])),
              const SizedBox(height: 70),
              Text(
                l10n.privateKeyWarningProgress(_page + 1, 3),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                titles[_page],
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.24,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                bodies[_page],
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.65,
                  color: WalletColors.text3,
                ),
              ),
              if (_authError != null) ...[
                const SizedBox(height: 18),
                Container(
                  key: const ValueKey('private-key-auth-error'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WalletColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 19,
                        color: WalletColors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _authError!,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: WalletColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _WarningGraphic extends StatelessWidget {
  const _WarningGraphic({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    height: 112,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          const Color(0xFFFF3D78).withValues(alpha: 0.20),
          const Color(0xFFFF3D78).withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ),
    ),
    child: ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFFFF315F), Color(0xFFE8206C)],
      ).createShader(rect),
      child: Icon(icon, size: 58, color: Colors.white),
    ),
  );
}

class _PrivateKeyPrimaryButton extends StatelessWidget {
  const _PrivateKeyPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    width: double.infinity,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: WalletColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: WalletColors.border,
        disabledForegroundColor: WalletColors.text3,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      child: loading
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    ),
  );
}

class _PrivateKeySecondaryButton extends StatelessWidget {
  const _PrivateKeySecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF1F2F4),
        foregroundColor: WalletColors.text,
        disabledBackgroundColor: WalletColors.border,
        disabledForegroundColor: WalletColors.text3,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}

class _PrivateKeyAccount {
  const _PrivateKeyAccount({
    required this.id,
    required this.title,
    required this.address,
    required this.coin,
    required this.chain,
    required this.networks,
  });

  final String id;
  final String title;
  final String address;
  final Coin coin;
  final Chain chain;
  final List<Network> networks;
}

class _PrivateKeyDirectory extends StatefulWidget {
  const _PrivateKeyDirectory({
    required this.wallet,
    required this.sessionId,
    required this.crypto,
    required this.onSessionExpired,
  });

  final HotWallet wallet;
  final String sessionId;
  final CoreCrypto crypto;
  final VoidCallback onSessionExpired;

  @override
  State<_PrivateKeyDirectory> createState() => _PrivateKeyDirectoryState();
}

class _PrivateKeyDirectoryState extends State<_PrivateKeyDirectory> {
  String? _expandedId;
  String? _revealedId;
  String? _notice;
  Timer? _noticeTimer;
  bool _copying = false;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  List<_PrivateKeyAccount> _accounts(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final networks = NetworkScope.of(context);
    final enabled = widget.wallet.addresses.enabledCoins.toList();
    final evmCoins = enabled.where(_isEvmCoin).toList();
    return [
      if (evmCoins.isNotEmpty)
        _PrivateKeyAccount(
          id: 'evm',
          title: l10n.privateKeyEvmNetworks,
          address: widget.wallet.addresses.forCoin(evmCoins.first),
          coin: Coin.eth,
          chain: Chain.ethereum,
          networks: [
            for (final coin in evmCoins)
              networks.activeFor(_chainForCoin(coin)),
          ],
        ),
      if (enabled.contains(Coin.solana))
        _PrivateKeyAccount(
          id: 'solana',
          title: networks.activeFor(Chain.solana).name,
          address: widget.wallet.addresses.solana,
          coin: Coin.solana,
          chain: Chain.solana,
          networks: [networks.activeFor(Chain.solana)],
        ),
      if (enabled.contains(Coin.tron))
        _PrivateKeyAccount(
          id: 'tron',
          title: networks.activeFor(Chain.tron).name,
          address: widget.wallet.addresses.tron,
          coin: Coin.tron,
          chain: Chain.tron,
          networks: [networks.activeFor(Chain.tron)],
        ),
    ];
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _safeCopy(_PrivateKeyAccount account) async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final suffix = await widget.crypto.copyPrivateKey(
        sessionId: widget.sessionId,
        coin: account.coin,
        mode: PrivateKeyCopyMode.safe,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) =>
            SecureContent(child: _SafeCopySheet(suffix: suffix)),
      );
      if (mounted) {
        _showNotice(AppLocalizations.of(context).privateKeyCopiedSecurely);
      }
    } on CoreCryptoException {
      widget.onSessionExpired();
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _fullCopy(_PrivateKeyAccount account) async {
    if (_copying) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const SecureContent(child: _FullCopySheet()),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _copying = true);
    try {
      await widget.crypto.copyPrivateKey(
        sessionId: widget.sessionId,
        coin: account.coin,
        mode: PrivateKeyCopyMode.full,
      );
      if (mounted) {
        _showNotice(AppLocalizations.of(context).privateKeyCopiedFully);
      }
    } on CoreCryptoException {
      widget.onSessionExpired();
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = _accounts(context);
    return KtScreen(
      key: const ValueKey('private-key-directory-screen'),
      backgroundColor: WalletColors.surface,
      navBar: KtNavBar(
        title: widget.wallet.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      padding: EdgeInsets.zero,
      gap: 0,
      scrollable: false,
      children: [
        if (accounts.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                l10n.privateKeyNoAccounts,
                style: const TextStyle(color: WalletColors.text3),
              ),
            ),
          )
        else
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  key: const ValueKey('private-key-account-list'),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    return _PrivateKeyAccountTile(
                      account: account,
                      sessionId: widget.sessionId,
                      expanded: _expandedId == account.id,
                      copying: _copying,
                      revealed: _revealedId == account.id,
                      onToggle: () => setState(() {
                        _revealedId = null;
                        _expandedId = _expandedId == account.id
                            ? null
                            : account.id;
                      }),
                      onRevealToggle: () => setState(() {
                        _revealedId = _revealedId == account.id
                            ? null
                            : account.id;
                      }),
                      onSafeCopy: () => _safeCopy(account),
                      onFullCopy: () => _fullCopy(account),
                    );
                  },
                ),
                if (_notice != null)
                  Positioned(
                    top: 8,
                    left: 20,
                    right: 20,
                    child: IgnorePointer(
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Color(0xFF35C66B),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _notice!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: WalletColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PrivateKeyAccountTile extends StatelessWidget {
  const _PrivateKeyAccountTile({
    required this.account,
    required this.sessionId,
    required this.expanded,
    required this.revealed,
    required this.copying,
    required this.onToggle,
    required this.onRevealToggle,
    required this.onSafeCopy,
    required this.onFullCopy,
  });

  final _PrivateKeyAccount account;
  final String sessionId;
  final bool expanded;
  final bool revealed;
  final bool copying;
  final VoidCallback onToggle;
  final VoidCallback onRevealToggle;
  final VoidCallback onSafeCopy;
  final VoidCallback onFullCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: Column(
        key: ValueKey('private-key-account-${account.id}'),
        children: [
          InkWell(
            key: ValueKey('private-key-expand-${account.id}'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 82),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ChainIcon(chain: account.chain, size: 42),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          account.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: KtFonts.mono,
                            fontSize: 12,
                            color: WalletColors.text3,
                          ),
                        ),
                        if (account.networks.length > 1) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final network in account.networks)
                                Tooltip(
                                  message: network.name,
                                  child: ChainIcon(
                                    key: ValueKey(
                                      'private-key-network-${network.id}',
                                    ),
                                    chain: network.chain,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: WalletColors.text,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Material(
              color: const Color(0xFFF7F7F8),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('private-key-reveal-${account.id}'),
                onTap: copying ? null : onRevealToggle,
                child: SizedBox(
                  key: ValueKey(
                    revealed
                        ? 'private-key-revealed-${account.id}'
                        : 'private-key-concealed-${account.id}',
                  ),
                  height: 174,
                  width: double.infinity,
                  child: revealed
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: _NativePrivateKeyText(
                                sessionId: sessionId,
                                coin: account.coin,
                              ),
                            ),
                            const Positioned(
                              top: 14,
                              right: 14,
                              child: IgnorePointer(
                                child: Icon(
                                  Icons.visibility_off_outlined,
                                  size: 24,
                                  color: WalletColors.text2,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.visibility_off_outlined,
                              size: 30,
                              color: WalletColors.text,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              l10n.privateKeyPrivacyHint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: WalletColors.text,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PrivateKeyPrimaryButton(
              key: ValueKey('private-key-safe-copy-${account.id}'),
              label: l10n.privateKeySecureCopy,
              icon: Icons.shield_outlined,
              onPressed: copying ? null : onSafeCopy,
            ),
            const SizedBox(height: 10),
            _PrivateKeySecondaryButton(
              key: ValueKey('private-key-full-copy-${account.id}'),
              label: l10n.privateKeyFullCopy,
              icon: Icons.copy_outlined,
              onPressed: copying ? null : onFullCopy,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _NativePrivateKeyText extends StatelessWidget {
  const _NativePrivateKeyText({required this.sessionId, required this.coin});

  static const _viewType = 'kt/private_key_view';

  final String sessionId;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, String>{
      'sessionId': sessionId,
      'coin': coin.name,
    };
    final child = switch (defaultTargetPlatform) {
      TargetPlatform.iOS when !kIsWeb => UiKitView(
        viewType: _viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      TargetPlatform.android when !kIsWeb => AndroidView(
        viewType: _viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      _ => const Center(
        child: Icon(Icons.key_rounded, size: 28, color: WalletColors.text2),
      ),
    };
    return KeyedSubtree(
      key: ValueKey('private-key-native-${coin.name}'),
      child: child,
    );
  }
}

class _SafeCopySheet extends StatelessWidget {
  const _SafeCopySheet({required this.suffix});

  final String suffix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PrivateKeySheetSurface(
      key: const ValueKey('private-key-safe-copy-sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGraphic(
            color: Color(0xFF53D769),
            icon: Icons.check_rounded,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.privateKeySecureCopyTitle,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: WalletColors.text,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.privateKeySecureCopyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: WalletColors.text3,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, character) in suffix.characters.indexed)
                Container(
                  key: ValueKey('private-key-suffix-$index'),
                  width: 46,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: WalletColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    character,
                    style: const TextStyle(
                      fontFamily: KtFonts.mono,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 30),
          _PrivateKeyPrimaryButton(
            label: l10n.privateKeySecureCopyConfirm,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _FullCopySheet extends StatelessWidget {
  const _FullCopySheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PrivateKeySheetSurface(
      key: const ValueKey('private-key-full-copy-sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGraphic(
            color: Color(0xFFFFB020),
            icon: Icons.priority_high_rounded,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.privateKeyFullCopyTitle,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: WalletColors.text,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.privateKeyFullCopyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: WalletColors.text3,
            ),
          ),
          const SizedBox(height: 30),
          _PrivateKeyPrimaryButton(
            key: const ValueKey('private-key-full-copy-confirm'),
            label: l10n.privateKeyCopyAction,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 10),
          _PrivateKeySecondaryButton(
            label: l10n.actionCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class _PrivateKeySheetSurface extends StatelessWidget {
  const _PrivateKeySheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: WalletColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}

class _SheetGraphic extends StatelessWidget {
  const _SheetGraphic({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 94,
    height: 94,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: 0.22), Colors.transparent],
      ),
    ),
    child: Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 29, color: color),
    ),
  );
}

bool _isEvmCoin(Coin coin) => switch (coin) {
  Coin.eth ||
  Coin.polygon ||
  Coin.base ||
  Coin.arbitrum ||
  Coin.avalanche ||
  Coin.bnb => true,
  Coin.tron || Coin.solana => false,
};

Chain _chainForCoin(Coin coin) => switch (coin) {
  Coin.eth => Chain.ethereum,
  Coin.polygon => Chain.polygon,
  Coin.base => Chain.base,
  Coin.arbitrum => Chain.arbitrum,
  Coin.avalanche => Chain.avalanche,
  Coin.bnb => Chain.bnb,
  Coin.tron => Chain.tron,
  Coin.solana => Chain.solana,
};
