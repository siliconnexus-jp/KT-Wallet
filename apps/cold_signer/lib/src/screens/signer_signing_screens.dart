import 'dart:async';
import 'dart:convert';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/biometric_auth.dart';
import '../security/device_probe.dart';
import '../security/pin_lock.dart';
import '../security/security_check.dart';
import '../signing/demo_airgap.dart';
import '../signing/frame_scan.dart';
import '../state/signer_wallet_controller.dart';
import '../widgets/scan_viewfinder.dart';

const _t = AppTheme.signer;

/// Short display form of a request id, e.g. REQ-7F3A2C.
String _reqLabel(Uint8List reqId) =>
    'REQ-${reqId.take(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

/// SLIP-44 coin type → display name (V1 supported set).
String _coinName(int coin) => switch (coin) {
  60 => 'Ethereum',
  195 => 'TRON',
  501 => 'Solana',
  966 => 'Polygon',
  8453 => 'Base',
  42161 => 'Arbitrum',
  9000 => 'Avalanche',
  714 => 'BNB Smart Chain',
  _ => 'SLIP-44 #$coin',
};

Chain _chainForCoin(int coin) => switch (coin) {
  60 => Chain.ethereum,
  966 => Chain.polygon,
  8453 => Chain.base,
  42161 => Chain.arbitrum,
  9000 => Chain.avalanche,
  714 => Chain.bnb,
  195 => Chain.tron,
  501 => Chain.solana,
  _ => throw ArgumentError('unsupported coin $coin'),
};

String _addressKeyForCoin(int coin) => switch (coin) {
  60 => 'eth',
  966 => 'polygon',
  8453 => 'base',
  42161 => 'arbitrum',
  9000 => 'avalanche',
  714 => 'bnb',
  195 => 'tron',
  501 => 'solana',
  _ => '',
};

ParsedUnsignedTransfer? _parsedRequest(SignRequest? request) {
  if (request == null) return null;
  try {
    return parseUnsignedTransfer(_chainForCoin(request.coin), request.rawTx);
  } on Object {
    return null;
  }
}

Color _colorForCoin(int coin) => switch (coin) {
  60 => ChainColors.ethereum,
  966 => ChainColors.polygon,
  714 => const Color(0xFFF3BA2F),
  195 => ChainColors.tron,
  501 => ChainColors.solana,
  _ => SignerColors.blue,
};

String _shortAddress(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 7)}…${address.substring(address.length - 6)}';
}

Uint8List _exportRequestId(String walletId) {
  final hash = crc32Bytes(utf8.encode(walletId));
  return Uint8List.fromList([...hash, ...hash]);
}

/// Fail-closed structural whitelist. Wallet Core performs a second, stricter
/// parse immediately before signing; this first pass prevents unsupported
/// payloads from ever reaching the confirmation screen.
bool _isStructurallySupported(SignRequest request) {
  if (request.rawTx.isEmpty) return false;
  if (kDebugMode && request.coin == 195 && request.rawTx.first == 0x7b) {
    return true;
  }
  final ParsedUnsignedTransfer parsed;
  try {
    parsed = parseUnsignedTransfer(_chainForCoin(request.coin), request.rawTx);
  } on Object {
    return false;
  }
  switch (request.coin) {
    case 60:
    case 966:
    case 8453:
    case 42161:
    case 9000:
    case 714:
      return request.chainId != null &&
          parsed.networkId == BigInt.from(request.chainId!);
    case 195:
      return request.chainId == null && parsed.chain == Chain.tron;
    case 501:
      return request.chainId == null && parsed.chain == Chain.solana;
    default:
      return false;
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Local wall-clock rendering of an epoch-seconds timestamp.
String _fmtEpoch(int epochSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

/// Digit grouping for raw integer amounts (120000000 → 120,000,000).
String _group(String digits) {
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

Widget _kv(String k, String v, {bool mono = false, Color? color}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(k, style: const TextStyle(fontSize: 14, color: SignerColors.text2)),
    const SizedBox(width: 16),
    Expanded(
      child: Text(
        v,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: mono ? 13 : 14,
          fontWeight: FontWeight.w500,
          fontFamily: mono ? KtFonts.mono : KtFonts.ui,
          color: color ?? SignerColors.text,
        ),
      ),
    ),
  ],
);

Widget _card(Widget child) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: SignerColors.surface,
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
);

/// C5 离线首页.
class SignerHomeScreen extends StatelessWidget {
  const SignerHomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.walletMainName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: SignerColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const _Dot(SignerColors.ok),
                    const SizedBox(width: 6),
                    Text(
                      l10n.offlineForDays(42),
                      style: const TextStyle(
                        fontSize: 13,
                        color: SignerColors.ok,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/security'),
              child: const Icon(
                Icons.settings_outlined,
                size: 22,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/security-check'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: SignerColors.ok.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user,
                  size: 18,
                  color: SignerColors.ok,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.securityCheckPassed,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: SignerColors.ok,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: SignerColors.ok,
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/scan'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: SignerColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SignerColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: SignerColors.blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    size: 30,
                    color: SignerColors.blue,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.scanPendingTx,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: SignerColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.scanPendingTxDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SignerColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            for (final (icon, label, route) in [
              (Icons.qr_code, l10n.exportAddress, '/export'),
              (Icons.history, l10n.signRecords, '/records'),
              (Icons.shield_outlined, l10n.securityCheck, '/security-check'),
              (Icons.wallet, l10n.walletManage, '/wallet'),
            ]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push(route),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: SignerColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 20, color: SignerColors.text),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: SignerColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.size = 7});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// C2 离线安全检查 — runs the real [SecurityChecks] engine over a device probe
/// and renders one row per [CheckResult], plus an aggregate verdict header.
class SignerSecurityCheckScreen extends StatefulWidget {
  const SignerSecurityCheckScreen({super.key, this.probe = probeDeviceState});

  /// Injectable device probe; tests supply a fixed [DeviceState].
  final Future<DeviceState> Function() probe;

  @override
  State<SignerSecurityCheckScreen> createState() =>
      _SignerSecurityCheckScreenState();
}

class _SignerSecurityCheckScreenState extends State<SignerSecurityCheckScreen> {
  SecurityVerdict? _verdict; // null while a probe is in flight

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_verdict != null) {
      setState(() => _verdict = null); // re-run: back to checking
    }
    final state = await widget.probe();
    if (!mounted) return;
    setState(() => _verdict = SecurityChecks.verdict(state));
  }

  static IconData _checkIcon(String id) => switch (id) {
    'network' => Icons.wifi,
    'airplane' => Icons.airplanemode_active,
    'bluetooth' => Icons.bluetooth,
    'passcode' => Icons.lock,
    'biometric' => Icons.face,
    'screen_capture' => Icons.screenshot_monitor,
    'integrity' => Icons.verified_user,
    _ => Icons.shield_outlined,
  };

  /// Engine check ids → localized labels (the engine has no BuildContext).
  static String _checkLabel(AppLocalizations l10n, String id) => switch (id) {
    'network' => l10n.checkNetwork,
    'airplane' => l10n.checkAirplaneMode,
    'bluetooth' => l10n.checkBluetooth,
    'passcode' => l10n.checkDevicePasscode,
    'biometric' => l10n.checkBiometric,
    'screen_capture' => l10n.checkScreenRecording,
    'integrity' => l10n.checkIntegrity,
    _ => id,
  };

  Widget _resultRow(AppLocalizations l10n, CheckResult r) {
    final (color, icon, levelLabel) = switch (r.level) {
      CheckLevel.pass => (
        SignerColors.ok,
        Icons.check_circle,
        l10n.checkLevelPass,
      ),
      CheckLevel.warn => (SignerColors.warn, Icons.error, l10n.checkLevelWarn),
      CheckLevel.block => (
        SignerColors.danger,
        Icons.cancel,
        l10n.checkLevelBlock,
      ),
    };
    return Row(
      children: [
        Icon(
          _checkIcon(r.id),
          size: 18,
          color: r.level == CheckLevel.pass ? SignerColors.text2 : color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _checkLabel(l10n, r.id),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: SignerColors.text,
                ),
              ),
              if (r.detail != null) ...[
                const SizedBox(height: 2),
                // Engine diagnostics are untranslated; surfaced as-is.
                Text(
                  r.detail!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5A616C),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(levelLabel, style: TextStyle(fontSize: 13, color: color)),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: color),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final verdict = _verdict;
    final (headBg, headColor, headIcon, headTitle) = switch (verdict?.overall) {
      null => (
        SignerColors.surface,
        SignerColors.text2,
        Icons.shield_outlined,
        l10n.securityChecking,
      ),
      CheckLevel.pass => (
        SignerColors.ok.withValues(alpha: 0.10),
        SignerColors.ok,
        Icons.verified_user,
        l10n.securityOverallPass,
      ),
      CheckLevel.warn => (
        SignerColors.warn.withValues(alpha: 0.10),
        SignerColors.warn,
        Icons.warning_amber_rounded,
        l10n.securityOverallWarn,
      ),
      CheckLevel.block => (
        SignerColors.danger.withValues(alpha: 0.10),
        SignerColors.danger,
        Icons.dangerous,
        l10n.securityOverallBlock,
      ),
    };
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(
        title: l10n.offlineSecurityCheck,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: KtPrimaryButton(
        label: l10n.securityRecheck,
        style: KtButtonStyle.signer,
        onPressed: verdict == null ? null : _run,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: headBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(headIcon, size: 22, color: headColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  headTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: headColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (verdict != null)
          _card(
            Column(
              children: [
                for (var i = 0; i < verdict.results.length; i++) ...[
                  if (i > 0) const SizedBox(height: 13),
                  _resultRow(l10n, verdict.results[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Design-snapshot variant of C2 with the canned rows from the original
/// ui-m.md mock. Kept solely as the dev-gallery / golden baseline (the
/// registry builds this so existing goldens stay byte-identical); the app
/// route '/security-check' serves the live [SignerSecurityCheckScreen].
class SignerSecurityCheckPreviewScreen extends StatelessWidget {
  const SignerSecurityCheckPreviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <(IconData, String, String, String)>[
      (Icons.airplanemode_active, l10n.checkAirplaneMode, l10n.statusOn, 'ok'),
      (Icons.wifi_off, 'Wi-Fi', l10n.statusOff, 'ok'),
      (Icons.signal_cellular_alt, l10n.checkCellular, l10n.statusOff, 'ok'),
      (Icons.bluetooth, l10n.checkBluetooth, l10n.statusDetectedOn, 'warn'),
      (Icons.lock, l10n.checkDevicePasscode, l10n.statusEnabled, 'ok'),
      (Icons.face, l10n.checkBiometric, l10n.statusEnabled, 'ok'),
      (
        Icons.screenshot_monitor,
        l10n.checkScreenRecording,
        l10n.statusNotDetected,
        'ok',
      ),
    ];
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(
        title: l10n.offlineSecurityCheck,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SignerColors.warn.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 22,
                color: SignerColors.warn,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.riskCannotSign,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: SignerColors.warn,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.bluetoothWarning,
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
        ),
        _card(
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 13),
                () {
                  final (icon, label, val, s) = items[i];
                  final ok = s == 'ok';
                  return Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: ok ? SignerColors.text2 : SignerColors.warn,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: SignerColors.text,
                          ),
                        ),
                      ),
                      Text(
                        val,
                        style: TextStyle(
                          fontSize: 13,
                          color: ok ? SignerColors.ok : SignerColors.warn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        ok ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: ok ? SignerColors.ok : SignerColors.warn,
                      ),
                    ],
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// C6 扫描交易 — dark camera scaffold.
///
/// With a camera available at runtime the viewfinder hosts a live scanner and
/// every decoded QR string — one base64url AIRGAP-V1 wire frame — feeds the
/// aggregation session; without one, each tap on the viewfinder "captures"
/// the next animated-QR frame kt_wallet would be displaying. Either way,
/// everything past the capture is the real protocol: frames are parsed
/// byte-for-byte via [AirgapFrame.decode], aggregated by a real
/// [FrameAggregator], decoded with [AirgapPayload.decode] and vetted by
/// [SignRequestValidator] before the decoded request is pushed to /parse.
class SignerScanScreen extends StatefulWidget {
  const SignerScanScreen({super.key, this.availability});

  /// Camera probe override for tests; defaults to the process-wide instance.
  final CameraAvailability? availability;

  @override
  State<SignerScanScreen> createState() => _SignerScanScreenState();
}

class _SignerScanScreenState extends State<SignerScanScreen> {
  /// The frame set the hot wallet's animated QR is "displaying".
  List<AirgapFrame> _frames = const [];
  final _session = QrFrameScanSession();
  FrameAggregator get _aggregator => _session.aggregator;
  AggregatorProgress? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kDebugMode || _frames.isNotEmpty) return;
    final demo = demoSignRequest();
    final walletId =
        SignerWalletScope.maybeOf(context)?.localWalletId ?? demo.walletId;
    final targeted = SignRequest(
      reqId: demo.reqId,
      walletId: walletId,
      coin: demo.coin,
      rawTx: demo.rawTx,
      summary: demo.summary,
      createdAt: demo.createdAt,
      expiresAt: demo.expiresAt,
    );
    _frames = Fragmenter(
      chunkSize: demoChunkSize,
    ).fragment(targeted.encode(), reqId: targeted.reqId);
  }

  /// Simulates one camera read: the next un-received frame goes through the
  /// wire encoding and into the aggregator.
  void _captureNext() {
    if (_frames.isEmpty) return;
    if (_aggregator.state == AggregatorState.done ||
        _aggregator.state == AggregatorState.failed) {
      return;
    }
    final next = _aggregator.progress.received;
    final frame = AirgapFrame.decode(_frames[next].encode());
    final progress = _aggregator.addFrame(frame);
    if (_aggregator.state == AggregatorState.done) {
      _onComplete();
      return;
    }
    setState(() => _progress = progress);
  }

  /// One real camera detection. Strings that aren't protocol frames (or that
  /// belong to a foreign session) are counted silently as anomalies inside
  /// [QrFrameScanSession] — a stray QR in view must not abort the scan.
  void _onScanned(String raw) {
    if (_session.isDone) return;
    final progress = _session.add(raw);
    if (_session.isDone) {
      _onComplete();
      return;
    }
    if (progress.received > 0) setState(() => _progress = progress);
  }

  Future<void> _onComplete() async {
    final controller = SignerWalletScope.maybeOf(context);
    // Live flow: the durable drift-backed anti-replay ledger, so a reqId
    // signed once — even before an app restart — routes to /risk as a
    // duplicate. Without a scope (goldens / bare-widget tests) the stateless
    // in-memory store keeps the original demo behavior.
    final SignRecordStore records = controller == null
        ? InMemorySignRecordStore()
        : await controller.loadRecordStore();
    if (!mounted) return;
    final SignRequest request;
    final ValidationResult verdict;
    try {
      final payload = AirgapPayload.decode(_aggregator.payload!);
      if (payload is! SignRequest) {
        // Account exports / results are not signable input.
        unawaited(context.push('/risk'));
        return;
      }
      request = payload;
      // Steps 2–6 of the acceptance check (validator.dart). V1's transaction
      // whitelist is stubbed to "TRON transfers only" until the chains
      // package supplies the real parser.
      final localWalletId = controller?.localWalletId;
      if (controller?.hasWallet == true && localWalletId == null) {
        unawaited(context.push('/risk'));
        return;
      }
      verdict = SignRequestValidator(
        localWalletId: localWalletId ?? demoWalletId,
        records: records,
        transactionAllowed: _isStructurallySupported,
      ).validate(request);
    } on PayloadError {
      unawaited(context.push('/risk'));
      return;
    }
    if (!verdict.isOk) {
      unawaited(context.push('/risk'));
      return;
    }
    unawaited(context.push('/parse', extra: request));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Before the first capture the aggregator hasn't locked a total yet; show
    // the frame-set size (which is what the hot wallet's QR announces anyway).
    final received = _progress?.received ?? 0;
    final total = _progress?.total ?? (_frames.isEmpty ? 1 : _frames.length);
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const KtStatusBar(theme: _t),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KtNavBar(
                title: l10n.scanPendingTx,
                theme: _t,
                leading: Icons.close,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: 24),
            ScanViewfinder(
              height: 360,
              frameColor: SignerColors.ok,
              onSimulatedTap: _captureNext,
              onScanned: _onScanned,
              availability: widget.availability,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.receivingShard(received, total),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 10),
            ShardProgressBar(
              received: received,
              total: total,
              color: SignerColors.ok,
              trackColor: SignerColors.border,
              width: 240,
            ),
          ],
        ),
      ),
    );
  }
}

/// C7 交易解析确认.
///
/// With a decoded [request] (the live scan flow) every field comes from the
/// AIRGAP-V1 payload; without one (dev gallery / goldens) the original canned
/// design snapshot is rendered unchanged.
class SignerParseScreen extends StatelessWidget {
  const SignerParseScreen({super.key, this.request});

  /// The decoded request handed over by the scan screen; null in the gallery.
  final SignRequest? request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final req = request;
    final parsed = _parsedRequest(req);
    final controller = SignerWalletScope.maybeOf(context);
    final testSummary = kDebugMode ? req?.summary ?? const <int, Object?>{} : const <int, Object?>{};
    final headline = req == null
        ? 'TRON · Token Transfer（TRC-20）'
        : parsed == null && kDebugMode
        ? '${_coinName(req.coin)} · ${testSummary['op'] ?? 'Transfer'}'
        : '${_coinName(req.coin)} · '
              '${parsed?.operation == TxOperation.tokenTransfer ? 'Token Transfer' : 'Native Transfer'}';
    final reqLabel = req == null ? 'REQ-7F3A2C' : _reqLabel(req.reqId);
    final amount = req == null
        ? '120.00 USDT'
        : parsed == null
        ? kDebugMode
              ? '${testSummary['amount'] ?? '?'} ${testSummary['token'] ?? ''}'
              : '无法解析'
        : '${_group(parsed.amountRaw.toString())} base units';
    final rawAmount = req == null
        ? '120,000,000'
        : _group(
            parsed?.amountRaw.toString() ??
                (kDebugMode ? '${testSummary['rawAmount'] ?? '?'}' : '?'),
          );
    final decimals = req == null
        ? 6
        : parsed == null && kDebugMode && testSummary['decimals'] is int
        ? testSummary['decimals']! as int
        : 0;
    final from = req == null
        ? 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa'
        : parsed?.from ??
              (kDebugMode ? '${testSummary['from'] ?? ''}' : null) ??
              controller?.metadata?.addresses[_addressKeyForCoin(req.coin)] ??
              '?';
    final to = req == null
        ? 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz'
        : parsed?.to ?? (kDebugMode ? '${testSummary['to'] ?? '?'}' : '?');
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(
        title: l10n.confirmTxContent,
        theme: _t,
        leading: Icons.close,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Row(
        children: [
          SizedBox(
            width: 120,
            height: 52,
            child: OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                backgroundColor: SignerColors.surface,
                side: const BorderSide(color: SignerColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                l10n.reject,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SignerColors.danger,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => context.push('/auth', extra: req),
                icon: const Icon(
                  Icons.edit,
                  size: 18,
                  color: Color(0xFF0A0C0F),
                ),
                label: Text(
                  l10n.confirmSign,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0A0C0F),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: SignerColors.ok,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: SignerColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const _Dot(ChainColors.tron, size: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SignerColors.text,
                  ),
                ),
              ),
              Text(
                reqLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: KtFonts.mono,
                  color: Color(0xFF5A616C),
                ),
              ),
            ],
          ),
        ),
        _card(
          Column(
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  fontFamily: KtFonts.mono,
                  color: SignerColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.rawAmountPrecision(rawAmount, decimals),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: KtFonts.mono,
                  color: SignerColors.text2,
                ),
              ),
            ],
          ),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SignerDetailRow(label: l10n.fromAccount, value: from),
              const SizedBox(height: 16),
              SignerDetailRow(label: l10n.toAddress, value: to),
            ],
          ),
        ),
        // Request metadata card — live flow only, so the gallery snapshot
        // (and its golden) stays byte-identical.
        if (req != null)
          _card(
            Column(
              children: [
                _kv(l10n.requestId, req.reqIdHex.toUpperCase(), mono: true),
                const SizedBox(height: 8),
                _kv(l10n.walletIdLabel, req.walletId, mono: true),
                const SizedBox(height: 8),
                _kv(l10n.createdAtLabel, _fmtEpoch(req.createdAt), mono: true),
                const SizedBox(height: 8),
                // Static expiry display; a live countdown stays a visual concern.
                _kv(l10n.expiresAtLabel, _fmtEpoch(req.expiresAt), mono: true),
                if (parsed?.networkId != null) ...[
                  const SizedBox(height: 8),
                  _kv('Chain ID', '${parsed!.networkId}', mono: true),
                ],
                if (parsed?.tokenContract != null) ...[
                  const SizedBox(height: 8),
                  _kv('Token / Contract', parsed!.tokenContract!, mono: true),
                ],
                if (parsed?.maxFeeRaw != null) ...[
                  const SizedBox(height: 8),
                  _kv(
                    'Maximum fee (base units)',
                    '${parsed!.maxFeeRaw}',
                    mono: true,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// C17 风险警告.
class SignerRiskScreen extends StatelessWidget {
  const SignerRiskScreen({super.key});

  /// The rejected request's raw payload (canned demo data, hex-encoded).
  static const _rawTxHex =
      '0a021f8b220899c14e3b5d2a77e340b8b2d8a8f1335a760802126e0a3174797065'
      '2e676f6f676c65617069732e636f6d2f70726f746f636f6c2e54726967676572'
      '536d617274436f6e747261637412390a15419f2d3c7a44e1b06f8c55d2e4a97b'
      '318d6fa02c1e1215418b44f7d21c39aa66e05f2b90d34c7e81a5f30d6b188094'
      'ebdc0370d8b2d4a8f133';

  Future<void> _showRawTx(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: SignerColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SignerColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.viewRawTxData,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SignerColors.text,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'REQ-9AB301 · TRON',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: KtFonts.mono,
                  color: Color(0xFF5A616C),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SignerColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SelectableText(
                  _rawTxHex,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    fontFamily: KtFonts.mono,
                    color: SignerColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 24,
      navBar: KtNavBar(
        title: l10n.riskWarningTitle,
        theme: _t,
        leading: Icons.close,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => context.go('/home'),
              style: OutlinedButton.styleFrom(
                backgroundColor: SignerColors.surface,
                side: const BorderSide(color: SignerColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                l10n.backToHome,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SignerColors.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showRawTx(context),
            child: Text(
              l10n.viewRawTxData,
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
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: SignerColors.danger.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.dangerous,
              size: 48,
              color: SignerColors.danger,
            ),
          ),
        ),
        Column(
          children: [
            Text(
              l10n.signingBlocked,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: SignerColors.danger,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.signingBlockedDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
        _card(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.description,
                size: 18,
                color: SignerColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.unknownContractCallDetected('approve'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SignerColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.unknownContractCallDesc,
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
        ),
      ],
    );
  }
}

/// C8 身份验证.
class SignerAuthScreen extends StatelessWidget {
  const SignerAuthScreen({super.key, this.request, this.auth});

  /// Request being authorized; forwarded to the result screen so the emitted
  /// SignResult answers the right reqId. Null in the gallery (canned strings).
  final SignRequest? request;

  /// Injectable authenticator; defaults to [BiometricAuth.instance].
  final BiometricAuth? auth;

  /// Authorization granted: commit the reqId to the anti-replay ledger BEFORE
  /// the result QR is shown (crash-safety ordering, DD §3.4) and navigate.
  /// Without a scope or a request nothing is recorded (gallery behavior).
  Future<void> _completeSignature(BuildContext context) async {
    final controller = SignerWalletScope.maybeOf(context);
    final req = request;
    SignResult? result;
    if (controller?.hasWallet == true && req != null) {
      try {
        result = await controller!.signRequest(req);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('签名失败：交易格式、钱包或认证未通过')));
        return;
      }
    }
    if (context.mounted) {
      unawaited(context.push('/result-qr', extra: result ?? req));
    }
  }

  /// The biometric path: a real local_auth prompt. Success authorizes the
  /// signature exactly like a verified PIN; an explicit failure stays on the
  /// screen with a snackbar; an unavailable platform (no hardware, nothing
  /// enrolled, plugin dead in tests) falls back to the PIN sheet — the signer
  /// always has that second factor once a wallet is enrolled.
  Future<void> _faceIdAuth(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final outcome = await (auth ?? BiometricAuth.instance).authenticate(
      reason: l10n.verifyToSign,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case BiometricOutcome.success:
        await _completeSignature(context);
      case BiometricOutcome.unavailable:
        await _passcodeAuth(context);
      case BiometricOutcome.failure:
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.biometricFailedRetry)));
    }
  }

  /// The passcode path. With a real wallet enrolled this demands the actual
  /// app PIN (PBKDF2 verify + persisted lockout); otherwise it stays the
  /// design snapshot's shortcut straight to the result.
  Future<void> _passcodeAuth(BuildContext context) async {
    final controller = SignerWalletScope.maybeOf(context);
    if (controller == null || !controller.hasWallet) {
      return _completeSignature(context);
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: SignerColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PinEntrySheet(pinLock: controller.pinLock),
    );
    if (ok == true && context.mounted) await _completeSignature(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final req = request;
    final parsed = _parsedRequest(req);
    final testSummary = kDebugMode ? req?.summary ?? const <int, Object?>{} : const <int, Object?>{};
    final amount = req == null
        ? '120.00 USDT'
        : parsed == null
        ? kDebugMode
              ? '${testSummary['amount'] ?? '?'} ${testSummary['token'] ?? ''}'
              : '无法解析'
        : '${_group(parsed.amountRaw.toString())} base units';
    final reqLabel = req == null ? 'REQ-7F3A2C' : _reqLabel(req.reqId);
    return KtScreen(
      theme: _t,
      gap: 28,
      navBar: KtNavBar(
        title: l10n.authTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Column(
        children: [
          // Real local_auth prompt; falls back to the PIN sheet when the
          // platform can't prompt (see _faceIdAuth).
          KtPrimaryButton(
            label: l10n.useFaceIdVerify,
            style: KtButtonStyle.signer,
            onPressed: () => _faceIdAuth(context),
          ),
          const SizedBox(height: 12),
          // Alternate auth path: the real app PIN when a wallet exists.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _passcodeAuth(context),
            child: Text(
              l10n.useDevicePasscode,
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
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: SignerColors.surface,
              borderRadius: BorderRadius.circular(56),
              border: Border.all(color: SignerColors.border),
            ),
            child: const Icon(Icons.face, size: 56, color: SignerColors.blue),
          ),
        ),
        Column(
          children: [
            Text(
              l10n.verifyToSign,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.verifyToSignDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
        _card(
          Column(
            children: [
              _kv(l10n.amountLabel, amount, mono: true),
              const SizedBox(height: 8),
              _kv(l10n.requestId, reqLabel, mono: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Modal PIN pad for C8: verifies the enrolled app PIN via [PinLock]
/// (PBKDF2-HMAC-SHA256 + persisted doubling lockout) and pops `true` on
/// success. Only reachable in the live flow — the gallery never shows it.
class _PinEntrySheet extends StatefulWidget {
  const _PinEntrySheet({required this.pinLock});

  final PinLock pinLock;

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  String _entry = '';
  String? _error;
  bool _verifying = false;

  Future<void> _onKey(String k) async {
    if (_verifying) return;
    if (k == 'del') {
      if (_entry.isNotEmpty) {
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      }
      return;
    }
    if (k.isEmpty || _entry.length >= 6) return;
    setState(() {
      _entry += k;
      _error = null;
    });
    if (_entry.length < 6) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _verifying = true);
    final verdict = await widget.pinLock.verify(_entry);
    if (!mounted) return;
    if (verdict.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _entry = '';
      _verifying = false;
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SignerColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.enterPinToSign,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    width: 13,
                    height: 13,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
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
            SizedBox(
              height: 32,
              child: Center(
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SignerColors.danger,
                        ),
                      ),
              ),
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', 'del'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final k in row)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onKey(k),
                        child: Container(
                          width: 64,
                          height: 64,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k.isEmpty || k == 'del'
                                ? null
                                : SignerColors.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: k == 'del'
                              ? const Icon(
                                  Icons.backspace_outlined,
                                  size: 20,
                                  color: SignerColors.text2,
                                )
                              : Text(
                                  k,
                                  style: const TextStyle(
                                    fontSize: 24,
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
      ),
    );
  }
}

/// C9 签名结果二维码 — animated result QR carrying a real AIRGAP-V1 SignResult.
///
/// The result answers [request] (same reqId), is fragmented by the real
/// [Fragmenter], and each frame's wire bytes are base64url-encoded into a
/// scannable [KtQrCode]; a timer cycles the frames like kt_wallet's receiver
/// expects. Without a request (dev gallery / direct navigation) the canonical
/// demo request is answered, so the screen still shows real frames.
class SignerResultQrScreen extends StatefulWidget {
  const SignerResultQrScreen({super.key, this.request, this.result});

  /// The authorized request this result answers; null in the gallery.
  final SignRequest? request;
  final SignResult? result;

  @override
  State<SignerResultQrScreen> createState() => _SignerResultQrScreenState();
}

class _SignerResultQrScreenState extends State<SignerResultQrScreen> {
  /// base64url-encoded wire bytes of each result frame (the QR contents).
  late final List<String> _frameData;
  int _index = 0;
  Timer? _timer;

  /// Frame dwell time; ~600ms is the scan-reliability compromise the animated
  /// QR loop is calibrated for.
  static const _frameInterval = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    final result =
        widget.result ?? demoSignResult(widget.request ?? demoSignRequest());
    final fragments = widget.result == null
        ? demoSignResultFrames(result)
        : Fragmenter().fragment(result.encode(), reqId: result.reqId);
    _frameData = [
      for (final frame in fragments) base64Url.encode(frame.encode()),
    ];
    if (_frameData.length > 1) {
      _timer = Timer.periodic(_frameInterval, (_) {
        setState(() => _index = (_index + 1) % _frameData.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Destructive confirm: voiding invalidates the shown signature QR, then
  /// returns to the offline home with a confirmation snackbar.
  Future<void> _confirmVoid(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.voidSignatureTitle,
        message: l10n.voidSignatureDesc,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.voidThisSignature,
        theme: AppTheme.signer,
        icon: Icons.block_rounded,
        iconColor: SignerColors.danger,
        destructive: true,
      ),
    );
    if (confirmed == true && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.signatureVoided)));
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.signComplete, theme: _t),
      bottom: Column(
        children: [
          KtPrimaryButton(
            label: l10n.done,
            style: KtButtonStyle.signer,
            onPressed: () => context.go('/home'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmVoid(context),
            child: Text(
              l10n.voidThisSignature,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: SignerColors.danger,
              ),
            ),
          ),
        ],
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SignerColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // The current frame of the animated result QR (dark style: white
              // modules on the signer surface).
              KtQrCode(data: _frameData[_index], size: 220, dark: true),
              const SizedBox(height: 14),
              Text(
                l10n.dynamicShard(_index + 1, _frameData.length),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: SignerColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              ShardProgressBar(
                received: _index + 1,
                total: _frameData.length,
                color: SignerColors.ok,
                trackColor: SignerColors.border,
              ),
            ],
          ),
        ),
        Center(
          child: Text(
            l10n.scanResultInstruction,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: SignerColors.text2),
          ),
        ),
      ],
    );
  }
}

/// C10 地址导出 — animated export QR carrying a real AIRGAP-V1 AccountExport.
///
/// The canonical demo export (kt_wallet's watch-wallet accounts) is fragmented
/// by the real [Fragmenter] and each frame's wire bytes are base64url-encoded
/// into a scannable [KtQrCode]; a timer cycles the frames exactly like C9's
/// result QR. The segmented filter below only narrows the address *list* —
/// the QR always carries the full export payload.
class SignerAddressExportScreen extends StatefulWidget {
  const SignerAddressExportScreen({super.key});
  @override
  State<SignerAddressExportScreen> createState() =>
      _SignerAddressExportScreenState();
}

class _SignerAddressExportScreenState extends State<SignerAddressExportScreen> {
  static const _addrs = [
    (ChainColors.ethereum, 'Ethereum', '0x8f3C2a…7E19bE1', "m/44'/60'/0'/0/0"),
    (ChainColors.polygon, 'Polygon', '0x8f3C2a…7E19bE1', "m/44'/60'/0'/0/0"),
    (ChainColors.tron, 'TRON', 'TQm9…L3kFa', "m/44'/195'/0'/0/0"),
    (ChainColors.solana, 'Solana', '6yKp…Vr2W', "m/44'/501'/0'"),
  ];

  int _seg = 0;

  /// base64url-encoded wire bytes of each export frame (the QR contents).
  List<String>? _frameData;
  AccountExport? _export;
  bool _preview = false;

  /// How many accounts the export payload carries (constant — the segmented
  /// filter never changes what the QR encodes).
  int _exportedAccounts = 0;
  int _index = 0;
  Timer? _timer;

  /// Frame dwell time; ~600ms is the scan-reliability compromise the animated
  /// QR loop is calibrated for (same as C9).
  static const _frameInterval = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
  }

  bool _prepared = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;
    final controller = SignerWalletScope.maybeOf(context);
    _preview = controller == null;
    final export = controller?.hasWallet == true
        ? controller!.buildAccountExport()
        : demoAccountExport();
    _export = export;
    _exportedAccounts = export.accounts.length;
    final reqId = _exportRequestId(export.walletId);
    final fragments = controller?.hasWallet == true
        ? Fragmenter().fragment(export.encode(), reqId: reqId)
        : demoAccountExportFrames();
    _frameData = [
      for (final frame in fragments) base64Url.encode(frame.encode()),
    ];
    if (_frameData!.length > 1) {
      _timer = Timer.periodic(_frameInterval, (_) {
        setState(() => _index = (_index + 1) % _frameData!.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = [l10n.allAddresses, 'Ethereum', 'Polygon'];
    final export = _export;
    final realRows = _preview || export == null
        ? _addrs
        : [
            for (final account in export.accounts)
              (
                _colorForCoin(account.coin),
                _coinName(account.coin),
                _shortAddress(account.address),
                account.path,
              ),
          ];
    final visible = _seg == 0
        ? realRows
        : realRows.where((a) => a.$2 == options[_seg]).toList();
    final frames = _frameData;
    if (frames == null || frames.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(
        title: l10n.exportPublicAddress,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: KtPrimaryButton(
        label: l10n.done,
        style: KtButtonStyle.signer,
        onPressed: () => context.go('/home'),
      ),
      children: [
        KtSegmented(
          theme: _t,
          options: options,
          selected: _seg,
          onChanged: (i) => setState(() => _seg = i),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SignerColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // The current frame of the animated export QR (dark style: white
              // modules on the signer surface).
              KtQrCode(data: frames[_index], size: 200, dark: true),
              const SizedBox(height: 14),
              Text(
                l10n.dynamicShard(_index + 1, frames.length),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: SignerColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              ShardProgressBar(
                received: _index + 1,
                total: frames.length,
                color: SignerColors.ok,
                trackColor: SignerColors.border,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.exportQrCaption(_exportedAccounts),
                style: const TextStyle(fontSize: 12, color: SignerColors.text2),
              ),
            ],
          ),
        ),
        _card(
          Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Row(
                  children: [
                    _Dot(visible[i].$1, size: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visible[i].$2,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: SignerColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            visible[i].$4,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: KtFonts.mono,
                              color: Color(0xFF5A616C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      visible[i].$3,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: KtFonts.mono,
                        color: SignerColors.text2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.qr_code,
                      size: 16,
                      color: SignerColors.text2,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
