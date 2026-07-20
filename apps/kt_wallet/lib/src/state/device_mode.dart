import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The role this physical device plays: the online watch/hot wallet or the
/// air-gapped offline signer. Chosen once on first launch and persisted.
enum DeviceMode { wallet, signer }

/// Persisted device-mode choice. `null` means "not chosen yet" — the app shows
/// the first-launch mode picker until a mode is set.
///
/// All persistence is best-effort and guarded: in widget tests (where the
/// SharedPreferences plugin isn't registered) reads/writes fail silently and
/// the in-memory choice still applies. Tests can inject an initial mode.
class DeviceModeController extends ChangeNotifier {
  DeviceModeController({DeviceMode? initial}) : _mode = initial;

  static const _prefsKey = 'device.mode';

  DeviceMode? _mode;

  /// The chosen mode, or `null` while the picker should be shown.
  DeviceMode? get mode => _mode;

  /// Loads the persisted mode (if any). Safe to call before `runApp`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = switch (prefs.getString(_prefsKey)) {
        'wallet' => DeviceMode.wallet,
        'signer' => DeviceMode.signer,
        _ => null,
      };
      if (mode != null && mode != _mode) {
        _mode = mode;
        notifyListeners();
      }
    } catch (_) {
      // No prefs plugin (tests) or read error: stay on the picker.
    }
  }

  /// Sets the mode and persists it.
  Future<void> setMode(DeviceMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode == DeviceMode.wallet ? 'wallet' : 'signer');
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  /// Clears the choice and returns to the picker on next build.
  Future<void> clear() async {
    if (_mode == null) return;
    _mode = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }
}
