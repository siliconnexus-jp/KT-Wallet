import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves [AppPrefsController] round-trips every preference through
/// SharedPreferences: values written by one instance are loaded by a fresh one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults: app lock on, privacy off, 1 min auto-lock, USD', () {
    final prefs = AppPrefsController();
    expect(prefs.appLock, isTrue);
    expect(prefs.privacyMode, isFalse);
    expect(prefs.autoLockMinutes, 1);
    expect(prefs.fiat, 'USD');
  });

  test('load() on empty storage keeps the defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    expect(prefs.appLock, isTrue);
    expect(prefs.privacyMode, isFalse);
    expect(prefs.autoLockMinutes, 1);
    expect(prefs.fiat, 'USD');
  });

  test('setters persist and a fresh controller loads them back', () async {
    SharedPreferences.setMockInitialValues({});

    final prefs = AppPrefsController();
    await prefs.setAppLock(false);
    await prefs.setPrivacyMode(true);
    await prefs.setAutoLockMinutes(5);
    await prefs.setFiat('JPY');

    final reloaded = AppPrefsController();
    await reloaded.load();
    expect(reloaded.appLock, isFalse);
    expect(reloaded.privacyMode, isTrue);
    expect(reloaded.autoLockMinutes, 5);
    expect(reloaded.fiat, 'JPY');
  });

  test('rpc overrides: null by default, round-trip through storage, reset',
      () async {
    SharedPreferences.setMockInitialValues({});

    final prefs = AppPrefsController();
    for (final coin in Coin.values) {
      expect(prefs.rpcOverride(coin), isNull, reason: '$coin');
    }

    await prefs.setRpcOverride(Coin.eth, 'https://my-eth-node.example');
    await prefs.setRpcOverride(Coin.tron, '  https://my-tron.example  ');

    // Persists under the documented keys (trimmed).
    final store = await SharedPreferences.getInstance();
    expect(store.getString('rpc.eth'), 'https://my-eth-node.example');
    expect(store.getString('rpc.tron'), 'https://my-tron.example');
    expect(store.getString('rpc.polygon'), isNull);

    // A fresh controller loads them back; untouched chains stay default.
    final reloaded = AppPrefsController();
    await reloaded.load();
    expect(reloaded.rpcOverride(Coin.eth), 'https://my-eth-node.example');
    expect(reloaded.rpcOverride(Coin.tron), 'https://my-tron.example');
    expect(reloaded.rpcOverride(Coin.polygon), isNull);
    expect(reloaded.rpcOverride(Coin.solana), isNull);

    // Reset: null clears the override and removes the stored key; a blank
    // string means the same thing.
    await prefs.setRpcOverride(Coin.eth, null);
    await prefs.setRpcOverride(Coin.tron, '   ');
    expect(prefs.rpcOverride(Coin.eth), isNull);
    expect(prefs.rpcOverride(Coin.tron), isNull);
    expect(store.getString('rpc.eth'), isNull);
    expect(store.getString('rpc.tron'), isNull);

    // load() drops overrides that were removed from storage.
    await reloaded.load();
    expect(reloaded.rpcOverride(Coin.eth), isNull);
    expect(reloaded.rpcOverride(Coin.tron), isNull);
  });

  test('gateway url: null by default, round-trip, blank clears to direct',
      () async {
    SharedPreferences.setMockInitialValues({});

    final prefs = AppPrefsController();
    expect(prefs.gatewayUrl, isNull); // direct mode is the default

    await prefs.setGatewayUrl('  https://gw.example  ');
    expect(prefs.gatewayUrl, 'https://gw.example'); // trimmed

    // Persists under the documented key and survives a fresh controller.
    final store = await SharedPreferences.getInstance();
    expect(store.getString('gateway.url'), 'https://gw.example');
    final reloaded = AppPrefsController();
    await reloaded.load();
    expect(reloaded.gatewayUrl, 'https://gw.example');

    // Blank (or null) clears back to direct mode and removes the stored key.
    await prefs.setGatewayUrl('   ');
    expect(prefs.gatewayUrl, isNull);
    expect(store.getString('gateway.url'), isNull);
    await reloaded.load();
    expect(reloaded.gatewayUrl, isNull);
  });

  test('setGatewayUrl notifies once per actual change', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    var notified = 0;
    prefs.addListener(() => notified++);
    await prefs.setGatewayUrl('https://gw.example');
    await prefs.setGatewayUrl('https://gw.example'); // no-op
    await prefs.setGatewayUrl(null);
    await prefs.setGatewayUrl('  '); // already direct: no-op
    expect(notified, 2);
  });

  test('setRpcOverride notifies once per actual change', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    var notified = 0;
    prefs.addListener(() => notified++);
    await prefs.setRpcOverride(Coin.eth, 'https://a.example');
    await prefs.setRpcOverride(Coin.eth, 'https://a.example'); // no-op
    await prefs.setRpcOverride(Coin.polygon, null); // already default: no-op
    expect(notified, 1);
  });

  test('setters notify listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    var notified = 0;
    prefs.addListener(() => notified++);
    await prefs.setFiat('CNY');
    await prefs.setFiat('CNY'); // no-op: same value
    expect(notified, 1);
    expect(prefs.fiat, 'CNY');
  });
}
