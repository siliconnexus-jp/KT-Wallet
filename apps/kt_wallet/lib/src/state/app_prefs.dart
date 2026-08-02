import 'dart:async';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'endpoint_policy.dart';

enum AuthMethod { biometrics, password }

typedef PreferencesProvider = Future<SharedPreferences> Function();

/// User preferences from the settings screens: app lock, privacy mode,
/// auto-lock delay, fiat display currency and per-chain RPC endpoint
/// overrides. Persisted via SharedPreferences.
///
/// Reads fail to conservative defaults. Writes are commit-before-publish: a
/// storage error is returned to the UI and can never make a security, privacy,
/// RPC, or display preference look durable when it will vanish on restart.
class AppPrefsController extends ChangeNotifier {
  AppPrefsController({PreferencesProvider? preferencesProvider})
    : _preferencesProvider =
          preferencesProvider ?? SharedPreferences.getInstance;

  final PreferencesProvider _preferencesProvider;
  Future<void> _writes = Future<void>.value();
  static const _keyAppLock = 'prefs.appLock';
  static const _keyPrivacyMode = 'prefs.privacyMode';
  static const _keyAutoLockMinutes = 'prefs.autoLockMinutes';
  static const _keyFiat = 'prefs.fiat';
  static const _keyAuthMethod = 'prefs.authMethod';
  static const _keyHideZeroBalances = 'prefs.assets.hideZero';
  static const _keyFavoriteAssets = 'prefs.assets.favorites';
  static const _keyExternalApprovalScanConsent =
      'prefs.security.externalApprovalScanConsent';

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
  bool _externalApprovalScanConsent = false;

  bool get appLock => _appLock;
  bool get privacyMode => _privacyMode;

  /// Minutes in the background before the app re-locks; 0 = immediately.
  int get autoLockMinutes => _autoLockMinutes;
  String get fiat => _fiat;
  AuthMethod get authMethod => _authMethod;
  bool get hideZeroBalances => _hideZeroBalances;
  Set<String> get favoriteAssets => Set.unmodifiable(_favoriteAssets);
  bool get externalApprovalScanConsent => _externalApprovalScanConsent;
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
  Future<void> load() => _queueWrite(_load);

  Future<void> _load() async {
    try {
      final prefs = await _preferencesProvider();
      final nextAppLock = prefs.getBool(_keyAppLock) ?? _appLock;
      final nextPrivacyMode = prefs.getBool(_keyPrivacyMode) ?? _privacyMode;
      final storedAutoLock = prefs.getInt(_keyAutoLockMinutes);
      final nextAutoLock = autoLockOptions.contains(storedAutoLock)
          ? storedAutoLock!
          : 1;
      final storedFiat = prefs.getString(_keyFiat);
      final nextFiat = fiatOptions.contains(storedFiat) ? storedFiat! : 'USD';
      final nextAuthMethod = prefs.getString(_keyAuthMethod) == 'password'
          ? AuthMethod.password
          : AuthMethod.biometrics;
      final nextHideZeroBalances =
          prefs.getBool(_keyHideZeroBalances) ?? _hideZeroBalances;
      final nextFavoriteAssets = {
        for (final symbol
            in prefs.getStringList(_keyFavoriteAssets) ?? const <String>[])
          symbol.toUpperCase(),
      };
      final nextExternalApprovalScanConsent =
          prefs.getBool(_keyExternalApprovalScanConsent) ?? false;
      final nextRpcOverrides = <Coin, String>{};
      for (final entry in rpcPrefKeys.entries) {
        final url = prefs.getString(entry.value);
        if (url != null && EndpointPolicy.isSafeUrl(url)) {
          nextRpcOverrides[entry.key] = url;
        } else if (url != null && url.isNotEmpty) {
          await prefs.remove(entry.value);
        }
      }
      String? nextGatewayUrl;
      if (prefs.containsKey(gatewayPrefKey)) {
        final gateway = prefs.getString(gatewayPrefKey);
        if (gateway == null || gateway.isEmpty) {
          nextGatewayUrl = null;
        } else if (EndpointPolicy.isSafeUrl(gateway)) {
          nextGatewayUrl = gateway;
        } else {
          nextGatewayUrl = defaultGatewayUrl;
          await prefs.remove(gatewayPrefKey);
        }
      } else {
        nextGatewayUrl = defaultGatewayUrl;
      }

      // Publish one complete, internally consistent snapshot only after every
      // read and legacy-value cleanup above has completed successfully.
      _appLock = nextAppLock;
      _privacyMode = nextPrivacyMode;
      _autoLockMinutes = nextAutoLock;
      _fiat = nextFiat;
      _authMethod = nextAuthMethod;
      _hideZeroBalances = nextHideZeroBalances;
      _favoriteAssets = nextFavoriteAssets;
      _externalApprovalScanConsent = nextExternalApprovalScanConsent;
      _rpcOverrides
        ..clear()
        ..addAll(nextRpcOverrides);
      _gatewayUrl = nextGatewayUrl;
      notifyListeners();
    } catch (_) {
      // No prefs plugin (tests) or read error: keep the defaults.
    }
  }

  Future<void> setAppLock(bool value) => _queueWrite(() async {
    if (value == _appLock) return;
    await _persistBool(_keyAppLock, value);
    _appLock = value;
    notifyListeners();
  });

  Future<void> setPrivacyMode(bool value) => _queueWrite(() async {
    if (value == _privacyMode) return;
    await _persistBool(_keyPrivacyMode, value);
    _privacyMode = value;
    notifyListeners();
  });

  Future<void> setAutoLockMinutes(int minutes) => _queueWrite(() async {
    if (!autoLockOptions.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', 'unsupported auto-lock');
    }
    if (minutes == _autoLockMinutes) return;
    final prefs = await _preferencesProvider();
    _requireStored(
      await prefs.setInt(_keyAutoLockMinutes, minutes),
      _keyAutoLockMinutes,
    );
    _autoLockMinutes = minutes;
    notifyListeners();
  });

  Future<void> setFiat(String fiat) => _queueWrite(() async {
    if (!fiatOptions.contains(fiat)) {
      throw ArgumentError.value(fiat, 'fiat', 'unsupported currency');
    }
    if (fiat == _fiat) return;
    final prefs = await _preferencesProvider();
    _requireStored(await prefs.setString(_keyFiat, fiat), _keyFiat);
    _fiat = fiat;
    notifyListeners();
  });

  Future<void> setAuthMethod(AuthMethod method) => _queueWrite(() async {
    if (method == _authMethod) return;
    final prefs = await _preferencesProvider();
    _requireStored(
      await prefs.setString(
        _keyAuthMethod,
        method == AuthMethod.password ? 'password' : 'biometrics',
      ),
      _keyAuthMethod,
    );
    _authMethod = method;
    notifyListeners();
  });

  Future<void> setHideZeroBalances(bool value) => _queueWrite(() async {
    if (value == _hideZeroBalances) return;
    await _persistBool(_keyHideZeroBalances, value);
    _hideZeroBalances = value;
    notifyListeners();
  });

  Future<void> toggleFavoriteAsset(String symbol) => _queueWrite(() async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final next = {..._favoriteAssets};
    if (!next.add(normalized)) next.remove(normalized);
    final prefs = await _preferencesProvider();
    final values = next.toList()..sort();
    _requireStored(
      await prefs.setStringList(_keyFavoriteAssets, values),
      _keyFavoriteAssets,
    );
    _favoriteAssets = next;
    notifyListeners();
  });

  /// Allows the authorization center to send the current wallet's PUBLIC EVM
  /// address and chain id to the Gateway's configured external provider.
  /// Fresh installs are opted out. Turning this off takes effect immediately.
  Future<void> setExternalApprovalScanConsent(bool value) =>
      _queueWrite(() async {
        if (value == _externalApprovalScanConsent) return;
        await _persistBool(_keyExternalApprovalScanConsent, value);
        _externalApprovalScanConsent = value;
        notifyListeners();
      });

  /// Sets (or, with null / blank, clears back to the default) the RPC
  /// endpoint override for [coin].
  Future<void> setRpcOverride(Coin coin, String? url) => _queueWrite(() async {
    final value = url?.trim();
    final normalized = (value == null || value.isEmpty)
        ? null
        : EndpointPolicy.requireSafeUrl(value);
    if (normalized == _rpcOverrides[coin]) return;
    final prefs = await _preferencesProvider();
    final key = rpcPrefKeys[coin]!;
    final stored = normalized == null
        ? await prefs.remove(key)
        : await prefs.setString(key, normalized);
    _requireStored(stored, key);
    if (normalized == null) {
      _rpcOverrides.remove(coin);
    } else {
      _rpcOverrides[coin] = normalized;
    }
    notifyListeners();
  });

  /// Sets the Gateway URL. Null / blank explicitly selects direct mode and is
  /// stored as a blank sentinel so it remains selected after restart.
  Future<void> setGatewayUrl(String? url) => _queueWrite(() async {
    final value = url?.trim();
    final normalized = (value == null || value.isEmpty)
        ? null
        : EndpointPolicy.requireSafeUrl(value);
    if (normalized == _gatewayUrl) return;
    final prefs = await _preferencesProvider();
    _requireStored(
      await prefs.setString(gatewayPrefKey, normalized ?? ''),
      gatewayPrefKey,
    );
    _gatewayUrl = normalized;
    notifyListeners();
  });

  /// Serializes preference mutations so rapid taps cannot let an older write
  /// finish after a newer intent. A failed operation does not poison the
  /// queue: its caller receives the error while later writes still run.
  Future<void> _queueWrite(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.catchError((Object _) {});
    return result;
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = await _preferencesProvider();
    _requireStored(await prefs.setBool(key, value), key);
  }

  static void _requireStored(bool stored, String key) {
    if (!stored) throw StateError('preference write failed: $key');
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
