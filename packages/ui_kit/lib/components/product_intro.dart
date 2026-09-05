import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/colors.dart';
import 'primary_button.dart';
import 'qr_code.dart';

const ktSourceRepository = 'https://github.com/siliconnexus-jp/KT-Wallet';

/// Keep the content page usable when translated controls grow with Dynamic Type.
class _IntroFooterViewport extends StatelessWidget {
  const _IntroFooterViewport({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight:
          (MediaQuery.sizeOf(context).height > 0
              ? MediaQuery.sizeOf(context).height
              : View.of(context).physicalSize.height /
                    View.of(context).devicePixelRatio) *
          .4,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: child,
    ),
  );
}

/// Presentation only: apps own their onboarding preferences and wallet state.
class KtIntroGate extends StatefulWidget {
  const KtIntroGate({
    super.key,
    required this.readCompleted,
    required this.saveCompleted,
    required this.introBuilder,
    required this.child,
  });
  final Future<bool> Function() readCompleted;
  final Future<void> Function() saveCompleted;
  final Widget Function(Future<void> Function()) introBuilder;
  final Widget child;

  @override
  State<KtIntroGate> createState() => _KtIntroGateState();
}

class _KtIntroGateState extends State<KtIntroGate> {
  bool? _completed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var completed = false;
    try {
      completed = await widget.readCompleted();
    } on Object {
      // A missing preference can show the introduction again, never skip it.
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _complete() async {
    await widget.saveCompleted();
    if (mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) => _completed == null
      ? const SizedBox.expand()
      : _completed!
      ? widget.child
      : widget.introBuilder(_complete);
}

class KtIntroCopy {
  const KtIntroCopy({
    required this.role,
    required this.titles,
    required this.descriptions,
    required this.notes,
    required this.frontend,
    required this.backend,
    required this.online,
    required this.offline,
    required this.next,
    required this.start,
    required this.skip,
    required this.back,
    required this.source,
    required this.sourceHint,
    required this.copyLink,
    required this.copied,
    required this.close,
    required this.saveFailed,
  });
  final String role;
  final List<String> titles;
  final List<String> descriptions;
  final List<String> notes;
  final String frontend, backend, online, offline;
  final String next, start, skip, back, source, sourceHint;
  final String copyLink, copied, close, saveFailed;
}

/// Three concise pages using bundled icons and locally generated QR content.
/// No networking, remote images, or dependency on either application.
class KtProductIntro extends StatefulWidget {
  const KtProductIntro({
    super.key,
    required this.copy,
    required this.onComplete,
    this.offline = false,
  });
  final KtIntroCopy copy;
  final Future<void> Function() onComplete;
  final bool offline;

  @override
  State<KtProductIntro> createState() => _KtProductIntroState();
}

class _KtProductIntroState extends State<KtProductIntro> {
  final _pages = PageController();
  int _page = 0;
  bool _saving = false;
  bool _moving = false;

  Color get _bg => widget.offline ? SignerColors.bg : WalletColors.bg;
  Color get _surface =>
      widget.offline ? SignerColors.surface : WalletColors.surface;
  Color get _ink => widget.offline ? SignerColors.text : WalletColors.text;
  Color get _muted => widget.offline ? SignerColors.text2 : WalletColors.text2;
  Color get _accent => widget.offline ? SignerColors.ok : WalletColors.accent;
  Color get _border =>
      widget.offline ? SignerColors.border : WalletColors.border;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _move(int page) async {
    if (_moving || _saving) return;
    _moving = true;
    try {
      if (MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context)) {
        _pages.jumpToPage(page);
      } else {
        await _pages.animateToPage(
          page,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _moving = false;
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onComplete();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.copy.saveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSource() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _surface,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.copy.source,
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.copy.sourceHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: const KtQrCode(data: ktSourceRepository, size: 180),
            ),
            const SizedBox(height: 20),
            SelectableText(
              ktSourceRepository,
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: ktSourceRepository),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(widget.copy.copied)));
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(widget.copy.copyLink),
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                minimumSize: const Size(48, 48),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: _muted,
                minimumSize: const Size(48, 48),
              ),
              child: Text(widget.copy.close),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final skip = TextButton(
      onPressed: _saving ? null : _finish,
      style: TextButton.styleFrom(
        foregroundColor: _muted,
        minimumSize: const Size(48, 48),
      ),
      child: Text(copy.skip),
    );
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.offline
                                  ? Icons.shield_outlined
                                  : Icons.account_balance_wallet_outlined,
                              size: 21,
                              color: widget.offline
                                  ? SignerColors.bg
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.offline
                                      ? 'KT Cold Signer'
                                      : 'KT Wallet',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  copy.role,
                                  style: TextStyle(color: _muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (!largeText) skip,
                        ],
                      ),
                      if (largeText) skip,
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('product-intro-pages'),
                    controller: _pages,
                    itemCount: 3,
                    physics: _saving
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, page) => LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          key: ValueKey('intro-scroll-$page'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: (constraints.maxHeight - 32).clamp(
                                0,
                                double.infinity,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ExcludeSemantics(
                                  child: MediaQuery.withNoTextScaling(
                                    child: _hero(page),
                                  ),
                                ),
                                const SizedBox(height: 30),
                                Text(
                                  copy.titles[page],
                                  key: ValueKey('intro-title-$page'),
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 32,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  copy.descriptions[page],
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 15,
                                    height: 1.65,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _surface,
                                    border: Border.all(color: _border),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        page == 0
                                            ? Icons.code_rounded
                                            : page == 1
                                            ? Icons.lock_outline
                                            : Icons.qr_code_2,
                                        color: _accent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          copy.notes[page],
                                          style: TextStyle(
                                            color: _ink,
                                            fontSize: 13,
                                            height: 1.55,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                _IntroFooterViewport(
                  child: Column(
                    children: [
                      Semantics(
                        label: '${_page + 1} / 3',
                        liveRegion: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: 24,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i == _page ? _accent : _border,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_page > 0) ...[
                            IconButton(
                              onPressed: _saving
                                  ? null
                                  : () => _move(_page - 1),
                              tooltip: copy.back,
                              color: _muted,
                              icon: const Icon(Icons.arrow_back),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: KtPrimaryButton(
                              key: const ValueKey('intro-next'),
                              label: _page == 2 ? copy.start : copy.next,
                              style: widget.offline
                                  ? KtButtonStyle.signerContrast
                                  : KtButtonStyle.wallet,
                              loading: _saving,
                              onPressed: _page == 2
                                  ? _finish
                                  : () => _move(_page + 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _showSource,
                        style: TextButton.styleFrom(
                          foregroundColor: _muted,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.code_rounded, size: 17),
                        label: Text(
                          copy.source,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(int page) {
    if (page == 0) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(
              '100%',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: _accent,
                fontSize: 92,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'OPEN SOURCE',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _tag(Icons.phone_iphone, widget.copy.frontend),
                _tag(Icons.dns_outlined, widget.copy.backend),
                _tag(Icons.verified_outlined, 'MPL-2.0'),
              ],
            ),
          ],
        ),
      );
    }
    if (page == 1) {
      return Center(
        child: SizedBox(
          width: 210,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 198,
                height: 198,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _border),
                ),
              ),
              Container(
                width: 152,
                height: 152,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.07),
                ),
              ),
              Icon(Icons.shield_outlined, size: 104, color: _accent),
              Icon(Icons.lock_rounded, size: 31, color: _accent),
              Positioned(right: 0, top: 18, child: _tag(Icons.key, '')),
              Positioned(
                left: 0,
                bottom: 18,
                child: _tag(Icons.fingerprint, ''),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: _phone(false, widget.copy.online)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Icon(Icons.qr_code_2, color: _accent, size: 34),
                  const SizedBox(height: 8),
                  Icon(Icons.swap_horiz, color: _muted, size: 24),
                ],
              ),
            ),
            Expanded(child: _phone(true, widget.copy.offline)),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _accent),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _phone(bool offline, String label) => Column(
    children: [
      Container(
        width: 88,
        height: 118,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 2),
        ),
        child: Icon(
          offline
              ? Icons.shield_outlined
              : Icons.account_balance_wallet_outlined,
          color: offline
              ? (widget.offline ? SignerColors.ok : WalletColors.green)
              : (widget.offline ? SignerColors.blue : WalletColors.accent),
          size: 36,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        style: TextStyle(color: _muted, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    ],
  );
}
