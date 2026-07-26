import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences from the settings screens: app lock, privacy mode,
/// auto-lock delay, fiat display currency and per-chain RPC endpoint
/// overrides. Persisted via SharedPreferences.
///
/// All persistence is best-effort and guarded (same style as
/// [LocaleController]): in widget tests without the SharedPreferences plugin,
/// reads/writes fail silently and the in-memory values still apply.
class AppPrefsController extends ChangeNotifier {
  static const _keyAppLock = 'prefs.appLock';
  static const _keyPrivacyMode = 'prefs.privacyMode';
  static const _keyAutoLockMinutes = 'prefs.autoLockMinutes';
  static const _keyFiat = 'prefs.fiat';

  /// Storage key for the optional KT gateway URL. No stored value (null)
  /// means "direct mode": every chain query goes straight to the nodes.
  static const gatewayPrefKey = 'gateway.url';

  /// Storage keys for the per-chain RPC endpoint overrides. No stored value
  /// (null) means "use the built-in default endpoint".
  static const rpcPrefKeys = {
    Coin.eth: 'rpc.eth',
    Coin.polygon: 'rpc.polygon',
    Coin.base: 'rpc.base',
    Coin.arbitrum: 'rpc.arbitrum',
    Coin.avalanche: 'rpc.avalanche',
    Coin.tron: 'rpc.tron',
    Coin.solana: 'rpc.solana',
  };

  /// Fiat currencies offered by the picker.
  static const fiatOptions = ['USD', 'CNY', 'JPY'];

  /// Auto-lock choices in minutes; 0 means "immediately".
  static const autoLockOptions = [0, 1, 5];

  bool _appLock = true;
  bool _privacyMode = false;
  int _autoLockMinutes = 1;
  String _fiat = 'USD';

  bool get appLock => _appLock;
  bool get privacyMode => _privacyMode;

  /// Minutes in the background before the app re-locks; 0 = immediately.
  int get autoLockMinutes => _autoLockMinutes;
  String get fiat => _fiat;

  final Map<Coin, String> _rpcOverrides = {};

  /// The user's RPC endpoint override for [coin], or null when the built-in
  /// default applies (callers resolve the effective URL themselves).
  String? rpcOverride(Coin coin) => _rpcOverrides[coin];

  String? _gatewayUrl;

  /// The configured KT gateway URL, or null in direct mode (the default).
  /// The gateway is strictly optional: a null/blank value keeps every chain
  /// query on today's direct node paths.
  String? get gatewayUrl => _gatewayUrl;

  /// Loads persisted values (if any). Safe to call lazily from a screen.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _appLock = prefs.getBool(_keyAppLock) ?? _appLock;
      _privacyMode = prefs.getBool(_keyPrivacyMode) ?? _privacyMode;
      _autoLockMinutes = prefs.getInt(_keyAutoLockMinutes) ?? _autoLockMinutes;
      _fiat = prefs.getString(_keyFiat) ?? _fiat;
      for (final entry in rpcPrefKeys.entries) {
        final url = prefs.getString(entry.value);
        if (url != null && url.isNotEmpty) {
          _rpcOverrides[entry.key] = url;
        } else {
          _rpcOverrides.remove(entry.key);
        }
      }
      final gateway = prefs.getString(gatewayPrefKey);
      _gatewayUrl = (gateway == null || gateway.isEmpty) ? null : gateway;
      notifyListeners();
    } catch (_) {
      // No prefs plugin (tests) or read error: keep the defaults.
    }
  }

  Future<void> setAppLock(bool value) async {
    if (value == _appLock) return;
    _appLock = value;
    notifyListeners();
    await _persistBool(_keyAppLock, value);
  }

  Future<void> setPrivacyMode(bool value) async {
    if (value == _privacyMode) return;
    _privacyMode = value;
    notifyListeners();
    await _persistBool(_keyPrivacyMode, value);
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    if (minutes == _autoLockMinutes) return;
    _autoLockMinutes = minutes;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyAutoLockMinutes, minutes);
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  Future<void> setFiat(String fiat) async {
    if (fiat == _fiat) return;
    _fiat = fiat;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFiat, fiat);
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  /// Sets (or, with null / blank, clears back to the default) the RPC
  /// endpoint override for [coin].
  Future<void> setRpcOverride(Coin coin, String? url) async {
    final value = url?.trim();
    final normalized = (value == null || value.isEmpty) ? null : value;
    if (normalized == _rpcOverrides[coin]) return;
    if (normalized == null) {
      _rpcOverrides.remove(coin);
    } else {
      _rpcOverrides[coin] = normalized;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = rpcPrefKeys[coin]!;
      if (normalized == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, normalized);
      }
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  /// Sets (or, with null / blank, clears back to direct mode) the optional
  /// KT gateway URL.
  Future<void> setGatewayUrl(String? url) async {
    final value = url?.trim();
    final normalized = (value == null || value.isEmpty) ? null : value;
    if (normalized == _gatewayUrl) return;
    _gatewayUrl = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (normalized == null) {
        await prefs.remove(gatewayPrefKey);
      } else {
        await prefs.setString(gatewayPrefKey, normalized);
      }
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  Future<void> _persistBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }
}

/// Provides the app-wide [AppPrefsController] and rebuilds dependents when it
/// notifies. Like [MarketScope] there is deliberately NO fallback: screens
/// rendered without a scope (gallery / goldens / plain widget tests) get null
/// from [maybeOf] and keep their scope-absent demo behavior byte-for-byte.
class AppPrefsScope extends InheritedNotifier<AppPrefsController> {
  const AppPrefsScope({
    super.key,
    required AppPrefsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The shared controller, or null when no scope is mounted (demo rendering).
  /// Registers a dependency — rebuilds the caller on preference changes.
  static AppPrefsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPrefsScope>()?.notifier;
}
