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
    expect(prefs.externalApprovalScanConsent, isFalse);
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

  test('asset visibility and favorites persist across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();

    await prefs.setHideZeroBalances(true);
    await prefs.toggleFavoriteAsset('eth');
    await prefs.toggleFavoriteAsset('USDC');

    final reloaded = AppPrefsController();
    await reloaded.load();
    expect(reloaded.hideZeroBalances, isTrue);
    expect(reloaded.isFavoriteAsset('ETH'), isTrue);
    expect(reloaded.isFavoriteAsset('usdc'), isTrue);

    await reloaded.toggleFavoriteAsset('ETH');
    expect(reloaded.isFavoriteAsset('ETH'), isFalse);
  });

  test(
    'external approval scan is opt-in and persists an explicit choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      expect(prefs.externalApprovalScanConsent, isFalse);

      await prefs.setExternalApprovalScanConsent(true);
      final reloaded = AppPrefsController();
      await reloaded.load();
      expect(reloaded.externalApprovalScanConsent, isTrue);

      await reloaded.setExternalApprovalScanConsent(false);
      final disabled = AppPrefsController();
      await disabled.load();
      expect(disabled.externalApprovalScanConsent, isFalse);
    },
  );

  test(
    'rpc overrides: null by default, round-trip through storage, reset',
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
    },
  );

  test(
    'gateway url: production default, round-trip, blank persists direct mode',
    () async {
      SharedPreferences.setMockInitialValues({});

      final prefs = AppPrefsController();
      expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);

      await prefs.setGatewayUrl('  https://gw.example  ');
      expect(prefs.gatewayUrl, 'https://gw.example'); // trimmed

      // Persists under the documented key and survives a fresh controller.
      final store = await SharedPreferences.getInstance();
      expect(store.getString('gateway.url'), 'https://gw.example');
      final reloaded = AppPrefsController();
      await reloaded.load();
      expect(reloaded.gatewayUrl, 'https://gw.example');

      // Blank (or null) selects direct mode and persists an explicit blank
      // sentinel, distinguishing it from the absent-key production default.
      await prefs.setGatewayUrl('   ');
      expect(prefs.gatewayUrl, isNull);
      expect(store.getString('gateway.url'), '');
      await reloaded.load();
      expect(reloaded.gatewayUrl, isNull);
    },
  );

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

  test(
    'unsafe endpoint setters fail closed without changing preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();

      await expectLater(
        prefs.setGatewayUrl('http://public-rpc.example'),
        throwsFormatException,
      );
      await expectLater(
        prefs.setRpcOverride(Coin.eth, 'https://user:secret@rpc.example'),
        throwsFormatException,
      );

      expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);
      expect(prefs.rpcOverride(Coin.eth), isNull);
      final store = await SharedPreferences.getInstance();
      expect(store.containsKey(AppPrefsController.gatewayPrefKey), isFalse);
      expect(
        store.containsKey(AppPrefsController.rpcPrefKeys[Coin.eth]!),
        isFalse,
      );
    },
  );

  test(
    'load evicts legacy unsafe endpoints and restores safe defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        AppPrefsController.gatewayPrefKey: 'http://public-gateway.example',
        AppPrefsController.rpcPrefKeys[Coin.eth]!: 'javascript:alert(1)',
        AppPrefsController.rpcPrefKeys[Coin.tron]!: 'https://tron.example',
      });
      final prefs = AppPrefsController();
      await prefs.load();

      expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);
      expect(prefs.rpcOverride(Coin.eth), isNull);
      expect(prefs.rpcOverride(Coin.tron), 'https://tron.example');

      final store = await SharedPreferences.getInstance();
      expect(store.containsKey(AppPrefsController.gatewayPrefKey), isFalse);
      expect(
        store.containsKey(AppPrefsController.rpcPrefKeys[Coin.eth]!),
        isFalse,
      );
      expect(
        store.getString(AppPrefsController.rpcPrefKeys[Coin.tron]!),
        'https://tron.example',
      );
    },
  );

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

  test(
    'write failures never publish preferences and do not poison later writes',
    () async {
      final prefs = AppPrefsController(
        preferencesProvider: () async => throw StateError('storage offline'),
      );
      var notified = 0;
      prefs.addListener(() => notified++);

      final writes = <Future<void>>[
        prefs.setAppLock(false),
        prefs.setPrivacyMode(true),
        prefs.setAutoLockMinutes(5),
        prefs.setFiat('JPY'),
        prefs.setAuthMethod(AuthMethod.password),
        prefs.setHideZeroBalances(true),
        prefs.toggleFavoriteAsset('ETH'),
        prefs.setExternalApprovalScanConsent(true),
        prefs.setRpcOverride(Coin.eth, 'https://rpc.example'),
        prefs.setGatewayUrl('https://gateway.example'),
      ];
      for (final write in writes) {
        await expectLater(write, throwsStateError);
      }

      expect(prefs.appLock, isTrue);
      expect(prefs.privacyMode, isFalse);
      expect(prefs.autoLockMinutes, 1);
      expect(prefs.fiat, 'USD');
      expect(prefs.authMethod, AuthMethod.biometrics);
      expect(prefs.hideZeroBalances, isFalse);
      expect(prefs.isFavoriteAsset('ETH'), isFalse);
      expect(prefs.externalApprovalScanConsent, isFalse);
      expect(prefs.rpcOverride(Coin.eth), isNull);
      expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);
      expect(notified, 0);
    },
  );

  test(
    'rapid writes are serialized and the newest intent survives restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();

      await Future.wait([
        prefs.setPrivacyMode(true),
        prefs.setPrivacyMode(false),
        prefs.setPrivacyMode(true),
      ]);
      expect(prefs.privacyMode, isTrue);

      final reloaded = AppPrefsController();
      await reloaded.load();
      expect(reloaded.privacyMode, isTrue);
    },
  );

  test('unsupported enumerated preferences fail closed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();

    await expectLater(prefs.setAutoLockMinutes(99), throwsArgumentError);
    await expectLater(prefs.setFiat('BTC'), throwsArgumentError);
    expect(prefs.autoLockMinutes, 1);
    expect(prefs.fiat, 'USD');
  });

  test('load rejects invalid legacy option values', () async {
    SharedPreferences.setMockInitialValues({
      'prefs.autoLockMinutes': 99,
      'prefs.fiat': 'BTC',
    });
    final prefs = AppPrefsController();
    await prefs.load();

    expect(prefs.autoLockMinutes, 1);
    expect(prefs.fiat, 'USD');
  });
}
