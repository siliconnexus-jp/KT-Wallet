import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthMethod { biometrics, password }

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
  static const _keyAuthMethod = 'prefs.authMethod';
  static const _keyHideZeroBalances = 'prefs.assets.hideZero';
  static const _keyFavoriteAssets = 'prefs.assets.favorites';

  /// Production Gateway used when the user has not chosen an override.
  static const defaultGatewayUrl = 'https://gateway.kt-wallet.com';

  /// Storage key for the KT gateway URL. An absent key selects
  /// [defaultGatewayUrl]; an explicitly stored blank value selects direct
  /// mode so that opting out survives an app restart.
  static const gatewayPrefKey = 'gateway.url';

  /// Storage keys for the per-chain RPC endpoint overrides. No stored value
  /// (null) means "use the built-in default endpoint".
  static const rpcPrefKeys = {
    Coin.eth: 'rpc.eth',
    Coin.polygon: 'rpc.polygon',
    Coin.base: 'rpc.base',
    Coin.arbitrum: 'rpc.arbitrum',
    Coin.avalanche: 'rpc.avalanche',
    Coin.bnb: 'rpc.bnb',
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
  AuthMethod _authMethod = AuthMethod.biometrics;
  bool _hideZeroBalances = false;
  Set<String> _favoriteAssets = const {};

  bool get appLock => _appLock;
  bool get privacyMode => _privacyMode;

  /// Minutes in the background before the app re-locks; 0 = immediately.
  int get autoLockMinutes => _autoLockMinutes;
  String get fiat => _fiat;
  AuthMethod get authMethod => _authMethod;
  bool get hideZeroBalances => _hideZeroBalances;
  Set<String> get favoriteAssets => Set.unmodifiable(_favoriteAssets);
  bool isFavoriteAsset(String symbol) =>
      _favoriteAssets.contains(symbol.toUpperCase());

  final Map<Coin, String> _rpcOverrides = {};

  /// The user's RPC endpoint override for [coin], or null when the built-in
  /// default applies (callers resolve the effective URL themselves).
  String? rpcOverride(Coin coin) => _rpcOverrides[coin];

  String? _gatewayUrl = defaultGatewayUrl;

  /// The configured KT gateway URL, or null when the user selected direct
  /// mode. Fresh installs use [defaultGatewayUrl].
  String? get gatewayUrl => _gatewayUrl;

  /// Loads persisted values (if any). Safe to call lazily from a screen.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _appLock = prefs.getBool(_keyAppLock) ?? _appLock;
      _privacyMode = prefs.getBool(_keyPrivacyMode) ?? _privacyMode;
      _autoLockMinutes = prefs.getInt(_keyAutoLockMinutes) ?? _autoLockMinutes;
      _fiat = prefs.getString(_keyFiat) ?? _fiat;
      _authMethod = prefs.getString(_keyAuthMethod) == 'password'
          ? AuthMethod.password
          : AuthMethod.biometrics;
      _hideZeroBalances =
          prefs.getBool(_keyHideZeroBalances) ?? _hideZeroBalances;
      _favoriteAssets = {
        for (final symbol
            in prefs.getStringList(_keyFavoriteAssets) ?? const <String>[])
          symbol.toUpperCase(),
      };
      for (final entry in rpcPrefKeys.entries) {
        final url = prefs.getString(entry.value);
        if (url != null && url.isNotEmpty) {
          _rpcOverrides[entry.key] = url;
        } else {
          _rpcOverrides.remove(entry.key);
        }
      }
      if (prefs.containsKey(gatewayPrefKey)) {
        final gateway = prefs.getString(gatewayPrefKey);
        _gatewayUrl = (gateway == null || gateway.isEmpty) ? null : gateway;
      } else {
        _gatewayUrl = defaultGatewayUrl;
      }
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

  Future<void> setAuthMethod(AuthMethod method) async {
    if (method == _authMethod) return;
    _authMethod = method;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyAuthMethod,
        method == AuthMethod.password ? 'password' : 'biometrics',
      );
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  Future<void> setHideZeroBalances(bool value) async {
    if (value == _hideZeroBalances) return;
    _hideZeroBalances = value;
    notifyListeners();
    await _persistBool(_keyHideZeroBalances, value);
  }

  Future<void> toggleFavoriteAsset(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final next = {..._favoriteAssets};
    if (!next.add(normalized)) next.remove(normalized);
    _favoriteAssets = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = next.toList()..sort();
      await prefs.setStringList(_keyFavoriteAssets, values);
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

  /// Sets the Gateway URL. Null / blank explicitly selects direct mode and is
  /// stored as a blank sentinel so it remains selected after restart.
  Future<void> setGatewayUrl(String? url) async {
    final value = url?.trim();
    final normalized = (value == null || value.isEmpty) ? null : value;
    if (normalized == _gatewayUrl) return;
    _gatewayUrl = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(gatewayPrefKey, normalized ?? '');
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
