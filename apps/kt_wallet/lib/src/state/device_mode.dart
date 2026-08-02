import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The role this physical device plays: the online watch/hot wallet or the
/// air-gapped offline signer. Chosen once on first launch and persisted.
enum DeviceMode { wallet, signer }

typedef DeviceModePreferencesProvider = Future<SharedPreferences> Function();

/// Persisted device-mode choice. `null` means "not chosen yet" — the app shows
/// the first-launch mode picker until a mode is set.
///
/// Reads fail closed to the current state. Mutations are serialized and commit
/// before publish: a mode is never shown as selected (or cleared) unless the
/// same choice is durable across restart. Tests can inject an initial mode and
/// preferences provider.
class DeviceModeController extends ChangeNotifier {
  DeviceModeController({
    DeviceMode? initial,
    DeviceModePreferencesProvider? preferencesProvider,
  }) : _mode = initial,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  static const _prefsKey = 'device.mode';

  final DeviceModePreferencesProvider _preferencesProvider;
  Future<void> _operations = Future<void>.value();
  DeviceMode? _mode;

  /// The chosen mode, or `null` while the picker should be shown.
  DeviceMode? get mode => _mode;

  /// Loads the persisted mode (if any). Safe to call before `runApp`.
  Future<void> load() => _queue(_load);

  Future<void> _load() async {
    try {
      final prefs = await _preferencesProvider();
      final stored = prefs.getString(_prefsKey);
      final mode = switch (stored) {
        'wallet' => DeviceMode.wallet,
        'signer' => DeviceMode.signer,
        _ => null,
      };
      if (stored != null && mode == null) {
        final removed = await prefs.remove(_prefsKey);
        if (!removed) throw StateError('device mode cleanup failed');
      }
      if (mode != _mode) {
        _mode = mode;
        notifyListeners();
      }
    } catch (_) {
      // No prefs plugin (tests) or read error: stay on the picker.
    }
  }

  /// Persists and then publishes the selected mode.
  Future<void> setMode(DeviceMode mode) => _queue(() async {
    if (mode == _mode) return;
    final prefs = await _preferencesProvider();
    final stored = await prefs.setString(
      _prefsKey,
      mode == DeviceMode.wallet ? 'wallet' : 'signer',
    );
    if (!stored) throw StateError('device mode write failed');
    _mode = mode;
    notifyListeners();
  });

  /// Persists removal and then returns to the picker.
  Future<void> clear() => _queue(() async {
    if (_mode == null) return;
    final prefs = await _preferencesProvider();
    final removed = await prefs.remove(_prefsKey);
    if (!removed) throw StateError('device mode removal failed');
    _mode = null;
    notifyListeners();
  });

  Future<T> _queue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
