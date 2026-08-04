import 'dart:convert';
import 'dart:math';

import 'package:cold_signer/src/security/pin_lock.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';

/// PIN hashing + lockout over the in-memory fake vault storage (MethodChannel
/// plugins are unavailable in tests). Iteration counts are lowered for test
/// speed; the stored record carries its own count so this is behavior-safe.
void main() {
  // Movable clock shared by lock/verify.
  var now = DateTime.utc(2026, 7, 21, 12);

  PinLock lock(InMemoryVaultStorage storage) =>
      PinLock(storage, iterations: 500, random: Random(7), clock: () => now);

  setUp(() => now = DateTime.utc(2026, 7, 21, 12));

  test('known PBKDF2-HMAC-SHA256 vector (RFC 6070 adapted to SHA-256)', () {
    // Published SHA-256 vector for P="password", S="salt", c=1, dkLen=32.
    final dk = pbkdf2Sha256(
      password: utf8.encode('password'),
      salt: utf8.encode('salt'),
      iterations: 1,
    );
    expect(
      dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
  });

  test(
    'hash roundtrip: enrolled PIN verifies, storage holds only a hash',
    () async {
      final storage = InMemoryVaultStorage();
      final pin = lock(storage);
      expect(await pin.isSet(), isFalse);

      await pin.setPin('123456');
      expect(await pin.isSet(), isTrue);
      // Never the raw PIN in storage — a salted PBKDF2 record.
      final raw = storage.values[SecureVault.pinKey]!;
      expect(raw.contains('123456'), isFalse);
      final record = (jsonDecode(raw) as Map).cast<String, Object?>();
      expect(record['algo'], 'pbkdf2-hmac-sha256');
      expect(
        base64Decode(record['salt']! as String).length,
        PinLock.saltLength,
      );
      expect(record['iterations'], 500);

      expect((await pin.verify('123456')).isOk, isTrue);
    },
  );

  test('wrong PIN is refused and bumps the persisted failure count', () async {
    final storage = InMemoryVaultStorage();
    final pin = lock(storage);
    await pin.setPin('123456');

    final verdict = await pin.verify('654321');
    expect(verdict.kind, PinVerdictKind.wrong);
    expect(verdict.failedAttempts, 1);
    // A success afterwards clears the counter.
    expect((await pin.verify('123456')).isOk, isTrue);
    expect(storage.values[SecureVault.pinLockoutKey], isNull);
  });

  test(
    '5 failures lock for 30s; further failures double the lockout',
    () async {
      final storage = InMemoryVaultStorage();
      final pin = lock(storage);
      await pin.setPin('123456');

      for (var i = 1; i <= 4; i++) {
        final v = await pin.verify('000000');
        expect(v.kind, PinVerdictKind.wrong);
        expect(v.failedAttempts, i);
      }
      // 5th failure engages the 30s lock.
      final fifth = await pin.verify('000000');
      expect(fifth.kind, PinVerdictKind.locked);
      expect(fifth.lockRemaining, const Duration(seconds: 30));

      // While locked even the CORRECT pin is refused (and not hashed).
      now = now.add(const Duration(seconds: 29));
      expect((await pin.verify('123456')).isLocked, isTrue);

      // Lock expired → next failure doubles: 60s.
      now = now.add(const Duration(seconds: 2));
      final sixth = await pin.verify('000000');
      expect(sixth.kind, PinVerdictKind.locked);
      expect(sixth.failedAttempts, 6);
      expect(sixth.lockRemaining, const Duration(seconds: 60));

      // And doubles again: 120s.
      now = now.add(const Duration(seconds: 61));
      final seventh = await pin.verify('000000');
      expect(seventh.lockRemaining, const Duration(seconds: 120));

      // After the lock passes, the correct PIN unlocks and resets everything.
      now = now.add(const Duration(seconds: 121));
      expect((await pin.verify('123456')).isOk, isTrue);
      final again = await pin.verify('000000');
      expect(again.kind, PinVerdictKind.wrong);
      expect(again.failedAttempts, 1);
    },
  );

  test(
    'lockout persists across a restart (new PinLock, same storage)',
    () async {
      final storage = InMemoryVaultStorage();
      final pin = lock(storage);
      await pin.setPin('123456');
      for (var i = 0; i < 5; i++) {
        await pin.verify('000000');
      }

      // "Restart": a brand-new PinLock over the same persisted storage.
      final reopened = lock(storage);
      final verdict = await reopened.verify('123456');
      expect(
        verdict.isLocked,
        isTrue,
        reason: 'restart must not reset the lockout',
      );
      expect(await reopened.lockRemaining(), const Duration(seconds: 30));

      now = now.add(const Duration(seconds: 31));
      expect((await reopened.verify('123456')).isOk, isTrue);
    },
  );

  test('setPin clears any previous lockout and re-salts', () async {
    final storage = InMemoryVaultStorage();
    final pin = lock(storage);
    await pin.setPin('123456');
    for (var i = 0; i < 5; i++) {
      await pin.verify('000000');
    }
    await pin.setPin('222222');
    expect(storage.values[SecureVault.pinLockoutKey], isNull);
    expect((await pin.verify('222222')).isOk, isTrue);
    expect((await pin.verify('123456')).kind, PinVerdictKind.wrong);
  });

  test('verify without an enrolled PIN throws', () async {
    final pin = lock(InMemoryVaultStorage());
    expect(() => pin.verify('123456'), throwsStateError);
  });

  test('rejects ambiguous or open PIN records before hashing', () async {
    final storage = InMemoryVaultStorage();
    final pin = lock(storage);
    await pin.setPin('123456');
    final valid = storage.values[SecureVault.pinKey]!;

    for (final malformed in [
      valid.replaceFirst('"algo":"pbkdf2-hmac-sha256"', '"algo":"unknown"'),
      valid.replaceFirst('}', ',"memo":"ignored"}'),
      valid.replaceFirst('"iterations":500', '"iterations":1,"iterations":500'),
      valid.replaceFirst(
        '"iterations":500',
        '"iterations":1,"itera\\u0074ions":500',
      ),
      valid.replaceFirst(RegExp(r'"salt":"[^"]+"'), '"salt":"AA=="'),
    ]) {
      storage.values[SecureVault.pinKey] = malformed;
      expect(() => pin.isSet(), throwsA(isA<PinStateCorruptedException>()));
      expect(
        () => pin.verify('123456'),
        throwsA(isA<PinStateCorruptedException>()),
      );
    }
  });

  test(
    'rejects malformed lockout state instead of weakening signing',
    () async {
      final storage = InMemoryVaultStorage();
      final pin = lock(storage);
      await pin.setPin('123456');

      for (final malformed in [
        '{"fails":1,"memo":"ignored"}',
        '{"fails":1,"fails":2}',
        '{"fails":65}',
        '{"fails":5}',
        '{"fails":5,"lockedUntil":1786579200000}',
      ]) {
        storage.values[SecureVault.pinLockoutKey] = malformed;
        expect(
          () => pin.lockRemaining(),
          throwsA(isA<PinStateCorruptedException>()),
        );
      }
    },
  );

  test('caps repeated lockout growth without losing persistence', () async {
    final storage = InMemoryVaultStorage();
    final pin = lock(storage);
    await pin.setPin('123456');
    storage.values[SecureVault.pinLockoutKey] =
        '{"fails":64,"lockedUntil":${now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch}}';

    final verdict = await pin.verify('000000');
    expect(verdict.isLocked, isTrue);
    expect(verdict.failedAttempts, PinLock.maxTrackedFailures);
    expect(verdict.lockRemaining, PinLock.maxLockout);

    final reopened = lock(storage);
    expect(await reopened.lockRemaining(), PinLock.maxLockout);
  });

  test('rejects oversized persisted PIN state before JSON parsing', () async {
    final storage = InMemoryVaultStorage()
      ..values[SecureVault.pinKey] = ' ' * 4097;
    final pin = lock(storage);

    expect(() => pin.isSet(), throwsA(isA<PinStateCorruptedException>()));
  });
}
