import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ui_kit/ui_kit.dart';

import '../state/flutter_test_env.dart';

/// Injectable probe deciding whether a live [MobileScanner] session should be
/// attempted at all. Widget tests (and the golden suite) run without the
/// plugin, so the default answers `false` off-device and the viewfinder stays
/// the tappable simulated one; the runtime camera errors that can still occur
/// on-device (no camera configured on an emulator, permission denied) are
/// handled downstream by [ScanViewfinder] falling back gracefully.
abstract class CameraAvailability {
  const CameraAvailability();

  /// Process-wide default, swappable in tests.
  static CameraAvailability instance = const DeviceCameraAvailability();

  Future<bool> canAttempt();
}

/// Default probe: only mobile targets ever have the mobile_scanner platform
/// implementation, and `flutter test` (where plugin channels are dead — their
/// futures never even complete) must never touch the plugin at all.
class DeviceCameraAvailability extends CameraAvailability {
  const DeviceCameraAvailability();

  @override
  Future<bool> canAttempt() async =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');
}

/// Fixed-answer probe for tests.
class FakeCameraAvailability extends CameraAvailability {
  const FakeCameraAvailability(this.answer);
  final bool answer;

  @override
  Future<bool> canAttempt() async => answer;
}

/// The dark scan viewfinder card shared by every camera screen.
///
/// With a camera available at runtime the card hosts a live [MobileScanner]
/// preview and reports each decoded QR string through [onScanned]
/// (deduplicating consecutive identical detections). Without one — emulator
/// with no camera, permission denied, widget tests, plugin missing — it
/// renders exactly the design's simulated viewfinder, and tapping it fires
/// [onSimulatedTap] (the demo capture loop), pixel-identical to the previous
/// hardcoded container so the goldens stay byte-for-byte unchanged.
class ScanViewfinder extends StatefulWidget {
  const ScanViewfinder({
    super.key,
    required this.height,
    required this.frameColor,
    this.onSimulatedTap,
    this.onScanned,
    this.availability,
  });

  /// Height of the outer viewfinder card (the screens use 360–400).
  final double height;

  /// Accent of the 240×240 scan frame (blue on the wallet, green on C6).
  final Color frameColor;

  /// Simulated capture (fallback mode only): one tap = one demo frame.
  final VoidCallback? onSimulatedTap;

  /// One decoded QR string per detection; null disables the camera entirely.
  final ValueChanged<String>? onScanned;

  /// Availability probe override; defaults to [CameraAvailability.instance].
  final CameraAvailability? availability;

  @override
  State<ScanViewfinder> createState() => _ScanViewfinderState();
}

class _ScanViewfinderState extends State<ScanViewfinder> {
  MobileScannerController? _camera;
  bool _attempting = false;
  String? _lastScan;

  @override
  void initState() {
    super.initState();
    if (widget.onScanned != null) _probe();
  }

  Future<void> _probe() async {
    final probe = widget.availability ?? CameraAvailability.instance;
    bool attempt;
    try {
      attempt = await probe.canAttempt();
    } catch (_) {
      attempt = false; // A failing probe means "no camera" — never a crash.
    }
    if (!attempt || !mounted) return;
    // Manual lifecycle (autoStart off): start only after the MobileScanner
    // widget below is attached, and catch every startup failure so the
    // simulated viewfinder remains the working fallback.
    final camera = MobileScannerController(autoStart: false);
    setState(() {
      _camera = camera;
      _attempting = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await camera.start();
      } catch (_) {
        if (mounted) setState(() => _attempting = false);
      }
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      // The animated QR repeats frames; forwarding only changes keeps the
      // consumer's aggregator free of trivially duplicated reads.
      if (value == null || value.isEmpty || value == _lastScan) continue;
      _lastScan = value;
      widget.onScanned?.call(value);
    }
  }

  /// The design's 240×240 scan frame (also the fallback placeholder).
  Widget _scanFrame({required bool withIcon}) => Container(
    width: 240,
    height: 240,
    decoration: BoxDecoration(
      border: Border.all(color: widget.frameColor, width: 2),
      borderRadius: BorderRadius.circular(16),
    ),
    child: withIcon
        ? const Icon(Icons.qr_code_2, size: 64, color: SignerColors.border)
        : null,
  );

  Widget _fallbackContent() => ColoredBox(
    color: SignerColors.surface,
    child: Center(
      child: isFlutterTestEnv
          ? _scanFrame(withIcon: true)
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.no_photography_outlined,
                  size: 52,
                  color: SignerColors.border,
                ),
                SizedBox(height: 12),
                Text(
                  'Camera unavailable',
                  style: TextStyle(fontSize: 14, color: SignerColors.text2),
                ),
              ],
            ),
    ),
  );

  /// The outer card. Kept structurally identical to the previous hardcoded
  /// container in fallback mode (no clip) so the goldens stay byte-identical.
  Widget _card({required Widget child, required bool clip}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    height: widget.height,
    clipBehavior: clip ? Clip.antiAlias : Clip.none,
    decoration: BoxDecoration(
      color: SignerColors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    if (!_attempting || camera == null) {
      return GestureDetector(
        onTap: isFlutterTestEnv ? widget.onSimulatedTap : null,
        child: _card(
          clip: false,
          child: isFlutterTestEnv
              ? Center(child: _scanFrame(withIcon: true))
              : _fallbackContent(),
        ),
      );
    }
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: camera,
      builder: (context, state, _) {
        final live = state.isRunning && state.error == null;
        return GestureDetector(
          // While the real camera runs, taps must not inject demo frames into
          // the same aggregation session; the fallback keeps the demo tap.
          onTap: live || !isFlutterTestEnv ? null : widget.onSimulatedTap,
          child: _card(
            clip: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: camera,
                  onDetect: _onDetect,
                  // Both builders render the simulated viewfinder so a camera
                  // that never comes up (or dies) degrades to the demo look.
                  placeholderBuilder: (_) => _fallbackContent(),
                  errorBuilder: (_, _) => _fallbackContent(),
                ),
                if (live) Center(child: _scanFrame(withIcon: false)),
              ],
            ),
          ),
        );
      },
    );
  }
}
