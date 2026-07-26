import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../transfer/frame_scan.dart';
import '../wallets/pairing_airgap.dart';
import '../widgets/scan_viewfinder.dart';

/// Shared full-screen dark camera. With a camera available at runtime the
/// viewfinder card hosts a live scanner and every decoded QR string is
/// reported through [onScanned]; without one (emulator without a camera,
/// permission denied, widget tests) it falls back to the tappable simulated
/// viewfinder and [onSimulatedScan] keeps driving the demo capture loop.
class KtCameraScreen extends StatelessWidget {
  const KtCameraScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.onClose,
    this.onSimulatedScan,
    this.onScanned,
    this.availability,
  });
  final String title, hint;
  final VoidCallback onClose;
  final VoidCallback? onSimulatedScan;

  /// One decoded QR string per camera detection (consecutive duplicates are
  /// already filtered); null keeps the screen purely simulated.
  final ValueChanged<String>? onScanned;

  /// Camera probe override for tests; defaults to the process-wide instance.
  final CameraAvailability? availability;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SignerColors.bg,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          const KtStatusBar(theme: AppTheme.signer),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: KtNavBar(
              title: title,
              theme: AppTheme.signer,
              leading: Icons.close,
              onBack: onClose,
            ),
          ),
          const SizedBox(height: 24),
          ScanViewfinder(
            height: 400,
            frameColor: SignerColors.blue,
            onSimulatedTap: onSimulatedScan,
            onScanned: onScanned,
            availability: availability,
          ),
          const SizedBox(height: 24),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Returns the address a scanned QR string carries if it validates on any
/// supported chain (normalized when the validator provides one), else null.
/// Pure so the scanned-string plumbing is unit-testable without a camera.
String? scannedAddressCandidate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  for (final chain in Chain.values) {
    final check = Addresses.validate(chain, text);
    if (check.isValid) return check.normalized ?? text;
  }
  return null;
}

/// Address scanner pushed from the transfer screen ('/scan-address'; not part
/// of the gallery registry). A real scan that passes any-chain validation —
/// or the simulated tap — pops with the address.
class ScanAddressScreen extends StatefulWidget {
  const ScanAddressScreen({super.key, this.availability});

  /// Demo TRON address returned by the mock scan (passes base58check).
  static const demoAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D';

  final CameraAvailability? availability;

  @override
  State<ScanAddressScreen> createState() => _ScanAddressScreenState();
}

class _ScanAddressScreenState extends State<ScanAddressScreen> {
  bool _popped = false;

  void _pop(String address) {
    if (_popped) return; // A frame may deliver several detections; pop once.
    _popped = true;
    context.pop(address);
  }

  void _onScanned(String raw) {
    final address = scannedAddressCandidate(raw);
    // Non-address QR content is ignored silently; the camera keeps scanning.
    if (address != null) _pop(address);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtCameraScreen(
      title: l10n.scanAddressTitle,
      hint: l10n.scanAddressHint,
      onClose: () => Navigator.of(context).maybePop(),
      onSimulatedScan: () => _pop(ScanAddressScreen.demoAddress),
      onScanned: _onScanned,
      availability: widget.availability,
    );
  }
}

/// Live '/scan-account' route (W12 with a real camera behind it).
///
/// The gallery/golden registry keeps building the original design-snapshot
/// `ScanAccountScreen` (wallet_screens.dart, untouched here); the router
/// serves this widget instead so real scans work. Fallback rendering and the
/// simulated tap loop are identical to the snapshot: each tap "captures" the
/// next demo pairing frame, while camera detections feed scanned strings —
/// one base64url AirgapFrame each — into the same real aggregation path
/// (wire bytes → AirgapFrame.decode → FrameAggregator → AccountExport).
class ScanAccountCameraScreen extends StatefulWidget {
  const ScanAccountCameraScreen({super.key, this.availability});

  final CameraAvailability? availability;

  @override
  State<ScanAccountCameraScreen> createState() =>
      _ScanAccountCameraScreenState();
}

class _ScanAccountCameraScreenState extends State<ScanAccountCameraScreen> {
  /// The frame set the signer's C10 export QR is "displaying" (demo taps).
  late final List<AirgapFrame> _frames = demoAccountExportFrames();
  final _session = QrFrameScanSession();
  int _received = 0;
  bool _navigated = false;

  void _afterFrame(BuildContext context) {
    setState(() => _received = _session.progress.received);
    final payload = _session.payload;
    if (payload == null || _navigated) return;
    final AirgapPayload decoded;
    try {
      decoded = AirgapPayload.decode(payload);
    } on Object {
      // Assembled bytes that aren't a valid payload: silent anomaly, rescan.
      _session.reset();
      setState(() => _received = 0);
      return;
    }
    if (decoded is AccountExport && context.mounted) {
      _navigated = true;
      context.pushReplacement('/import-confirm', extra: decoded);
    }
  }

  void _onSimulatedScan(BuildContext context) {
    // Same simulated capture as the design snapshot: the next demo frame goes
    // through its wire encoding into the aggregator.
    final wire = _frames[_received % _frames.length].encode();
    _session.aggregator.addFrame(AirgapFrame.decode(wire));
    _afterFrame(context);
  }

  void _onScanned(String raw) {
    _session.add(raw); // Invalid strings count silently as anomalies.
    _afterFrame(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _received == 0
        ? ''
        : ' · $_received / ${_session.progress.total == 0 ? _frames.length : _session.progress.total}';
    return KtCameraScreen(
      title: l10n.scanAccountQr,
      hint: '${l10n.scanAccountHint}$progress',
      onClose: () => Navigator.of(context).maybePop(),
      onSimulatedScan: () => _onSimulatedScan(context),
      onScanned: _onScanned,
      availability: widget.availability,
    );
  }
}
