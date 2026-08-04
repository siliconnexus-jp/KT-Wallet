import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';

/// WalletPin (the app-lock PIN fallback): PBKDF2 enrollment round-trip, wrong
/// PIN counting, and the persisted 5-failure doubling lockout — all against
/// the in-memory storage fake (the secure-storage plugin is dead in tests).
void main() {
  // Low iteration count keeps the suite fast; the record stores the count it
  // was hashed with, so the production default (100k) shares every code path.
  WalletPin newPin(
    InMemoryPinStorage storage, {
    int iterations = 1000,
    DateTime Function()? clock,
  }) => WalletPin(storage, iterations: iterations, clock: clock);

  test(
    'enrollment round-trip: set, verify ok, wrong rejected, clear',
    () async {
      final storage = InMemoryPinStorage();
      final pin = newPin(storage);

      expect(await pin.isSet(), isFalse);
      await pin.setPin('123456');
      expect(await pin.isSet(), isTrue);

      // The stored record is a salted hash, never the PIN itself.
      expect(storage.values[WalletPin.pinKey], isNot(contains('123456')));
      expect(storage.values[WalletPin.pinKey], contains('pbkdf2-hmac-sha256'));

      expect((await pin.verify('123456')).isOk, isTrue);
      final wrong = await pin.verify('654321');
      expect(wrong.kind, PinVerdictKind.wrong);
      expect(wrong.failedAttempts, 1);

      // A success resets the counter.
      expect((await pin.verify('123456')).isOk, isTrue);
      expect((await pin.verify('654321')).failedAttempts, 1);

      await pin.clear();
      expect(await pin.isSet(), isFalse);
      expect(storage.values, isEmpty);
    },
  );

  test(
    'the record remembers its iteration count, so defaults can change',
    () async {
      final storage = InMemoryPinStorage();
      await newPin(storage, iterations: 500).setPin('111222');
      // A future app version with a different default still verifies old PINs.
      expect(
        (await newPin(storage, iterations: 2000).verify('111222')).isOk,
        isTrue,
      );
    },
  );

  test('5 failures lock for 30s, doubling each further failure', () async {
    var now = DateTime(2026, 1, 1);
    final storage = InMemoryPinStorage();
    final pin = newPin(storage, clock: () => now);
    await pin.setPin('123456');

    for (var i = 1; i <= 4; i++) {
      final v = await pin.verify('000000');
      expect(v.kind, PinVerdictKind.wrong);
      expect(v.failedAttempts, i);
    }
    final fifth = await pin.verify('000000');
    expect(fifth.isLocked, isTrue);
    expect(fifth.lockRemaining, const Duration(seconds: 30));

    // While locked even the correct PIN is refused (and not hashed).
    now = now.add(const Duration(seconds: 29));
    expect((await pin.verify('123456')).isLocked, isTrue);

    // Lock expired: a 6th wrong attempt doubles the lockout to 60s.
    now = now.add(const Duration(seconds: 2));
    final sixth = await pin.verify('000000');
    expect(sixth.isLocked, isTrue);
    expect(sixth.failedAttempts, 6);
    expect(sixth.lockRemaining, const Duration(seconds: 60));

    // After it passes, the right PIN unlocks and clears the state.
    now = now.add(const Duration(seconds: 61));
    expect((await pin.verify('123456')).isOk, isTrue);
    expect(storage.values.containsKey(WalletPin.pinLockoutKey), isFalse);
  });

  test(
    'lockout survives a "restart" (fresh instance over the same storage)',
    () async {
      var now = DateTime(2026, 1, 1);
      final storage = InMemoryPinStorage();
      final pin = newPin(storage, clock: () => now);
      await pin.setPin('123456');
      for (var i = 0; i < 5; i++) {
        await pin.verify('000000');
      }

      // New WalletPin, same storage: still locked, remaining time honored.
      final restarted = newPin(storage, clock: () => now);
      expect(await restarted.lockRemaining(), const Duration(seconds: 30));
      expect((await restarted.verify('123456')).isLocked, isTrue);

      now = now.add(const Duration(seconds: 31));
      expect(await restarted.lockRemaining(), isNull);
      expect((await restarted.verify('123456')).isOk, isTrue);
    },
  );

  test('re-enrolling clears any pending lockout', () async {
    final storage = InMemoryPinStorage();
    final pin = newPin(storage);
    await pin.setPin('123456');
    for (var i = 0; i < 5; i++) {
      await pin.verify('000000');
    }
    expect(await pin.lockRemaining(), isNotNull);

    await pin.setPin('222333');
    expect(await pin.lockRemaining(), isNull);
    expect((await pin.verify('222333')).isOk, isTrue);
  });

  test('salts are random: identical PINs hash to different records', () async {
    final a = InMemoryPinStorage();
    final b = InMemoryPinStorage();
    await newPin(a).setPin('123456');
    await newPin(b).setPin('123456');
    expect(a.values[WalletPin.pinKey], isNot(b.values[WalletPin.pinKey]));
  });

  test('verify without an enrolled PIN is a programming error', () async {
    expect(
      () => newPin(InMemoryPinStorage()).verify('123456'),
      throwsStateError,
    );
  });

  test('rejects ambiguous or open PIN records before hashing', () async {
    final storage = InMemoryPinStorage();
    final pin = newPin(storage);
    await pin.setPin('123456');
    final valid = storage.values[WalletPin.pinKey]!;

    for (final malformed in [
      valid.replaceFirst('"algo":"pbkdf2-hmac-sha256"', '"algo":"unknown"'),
      valid.replaceFirst('}', ',"memo":"ignored"}'),
      valid.replaceFirst(
        '"iterations":1000',
        '"iterations":1,"iterations":1000',
      ),
      valid.replaceFirst(
        '"iterations":1000',
        '"iterations":1,"itera\\u0074ions":1000',
      ),
      valid.replaceFirst(RegExp(r'"salt":"[^"]+"'), '"salt":"AA=="'),
    ]) {
      storage.values[WalletPin.pinKey] = malformed;
      expect(() => pin.isSet(), throwsA(isA<PinStateCorruptedException>()));
      expect(
        () => pin.verify('123456'),
        throwsA(isA<PinStateCorruptedException>()),
      );
    }
  });

  test(
    'rejects malformed lockout state instead of weakening the gate',
    () async {
      final storage = InMemoryPinStorage();
      final pin = newPin(storage, clock: () => DateTime.utc(2026, 8, 5));
      await pin.setPin('123456');

      for (final malformed in [
        '{"fails":1,"memo":"ignored"}',
        '{"fails":1,"fails":2}',
        '{"fails":65}',
        '{"fails":5}',
        '{"fails":5,"lockedUntil":1786579200000}',
      ]) {
        storage.values[WalletPin.pinLockoutKey] = malformed;
        expect(
          () => pin.lockRemaining(),
          throwsA(isA<PinStateCorruptedException>()),
        );
      }
    },
  );

  test('caps repeated lockout growth without losing persistence', () async {
    final now = DateTime.utc(2026, 8, 5);
    final storage = InMemoryPinStorage();
    final pin = newPin(storage, clock: () => now);
    await pin.setPin('123456');
    storage.values[WalletPin.pinLockoutKey] =
        '{"fails":64,"lockedUntil":${now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch}}';

    final verdict = await pin.verify('000000');
    expect(verdict.isLocked, isTrue);
    expect(verdict.failedAttempts, WalletPin.maxTrackedFailures);
    expect(verdict.lockRemaining, WalletPin.maxLockout);

    final restarted = newPin(storage, clock: () => now);
    expect(await restarted.lockRemaining(), WalletPin.maxLockout);
  });
}
