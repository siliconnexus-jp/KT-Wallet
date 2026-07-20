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
