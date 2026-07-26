import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/flutter_test_env.dart';

/// The wallet app's own PIN (the app-lock fallback when biometrics are
/// unavailable or fail). Mirrors cold_signer's PinLock/SecureVault design but
/// stays independent of it — the two apps' security stacks share no code.

/// Minimal string key-value contract over the platform secure store
/// (iOS Keychain / Android Keystore-backed EncryptedSharedPreferences).
///
/// Kept as an interface so [WalletPin] and everything above it is testable:
/// MethodChannel plugins are unavailable in widget tests, so ALL tests run
/// against [InMemoryPinStorage] instead of the real [SecurePinStorage].
abstract class PinStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production storage: flutter_secure_storage (Keychain / Keystore).
///
/// Under `flutter test` (widget tests that pump the real app without
/// injecting [InMemoryPinStorage]) the plugin channel is dead — its futures
/// never complete — so this degrades to a process-local in-memory map and the
/// UI keeps working statelessly instead of hanging. On a real device the
/// plugin is always registered and the fallback never engages.
class SecurePinStorage implements PinStorage {
  SecurePinStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Plugin-less fallback (see class doc). Static so every default-constructed
  /// instance in one process shares it, like the real backing store would.
  static final Map<String, String> _pluginlessFallback = {};

  @override
  Future<String?> read(String key) async {
    if (isFlutterTestEnv) return _pluginlessFallback[key];
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return _pluginlessFallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (isFlutterTestEnv) {
      _pluginlessFallback[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      _pluginlessFallback[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    if (isFlutterTestEnv) {
      _pluginlessFallback.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      _pluginlessFallback.remove(key);
    }
  }
}

/// In-memory fake for tests.
class InMemoryPinStorage implements PinStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// PBKDF2-HMAC-SHA256 (RFC 2898). package:crypto has no PBKDF2, so the loop
/// is implemented here over its HMAC primitive.
Uint8List pbkdf2Sha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int length = 32,
}) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
  final hmac = Hmac(sha256, password);
  final blockCount = (length / 32).ceil();
  final out = BytesBuilder(copy: false);
  for (var block = 1; block <= blockCount; block++) {
    // U1 = HMAC(password, salt || INT_32_BE(block))
    var u = hmac.convert([
      ...salt,
      block >> 24,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

/// Outcome of a PIN verification attempt.
enum PinVerdictKind { ok, wrong, locked }

class PinVerdict {
  const PinVerdict._(this.kind, {this.failedAttempts = 0, this.lockRemaining});

  const PinVerdict.ok() : this._(PinVerdictKind.ok);
  const PinVerdict.wrong(int failedAttempts)
    : this._(PinVerdictKind.wrong, failedAttempts: failedAttempts);
  const PinVerdict.locked(Duration remaining, int failedAttempts)
    : this._(
        PinVerdictKind.locked,
        failedAttempts: failedAttempts,
        lockRemaining: remaining,
      );

  final PinVerdictKind kind;

  /// Consecutive failures so far (0 after a success).
  final int failedAttempts;

  /// How long until the next attempt is allowed; only set when [kind] is
  /// [PinVerdictKind.locked].
  final Duration? lockRemaining;

  bool get isOk => kind == PinVerdictKind.ok;
  bool get isLocked => kind == PinVerdictKind.locked;
}

/// The wallet's app PIN: PBKDF2-HMAC-SHA256 hash in secure storage, with a
/// persisted failed-attempt counter and doubling lockout.
///
/// Parameters (defaults): 100 000 iterations, 16-byte Random.secure salt,
/// 32-byte derived key. After [lockoutThreshold] (5) consecutive failures the
/// lock engages for [baseLockout] (30 s) and doubles on every further failure
/// (30 s → 60 s → 120 s → …). Both the counter and the lock deadline are
/// persisted, so restarting the app does NOT reset the lockout.
class WalletPin {
  WalletPin(
    this._storage, {
    this.iterations = 100000,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _now = clock ?? DateTime.now;

  /// Process-wide default (real secure storage), swappable in tests — same
  /// pattern as [BiometricAuth.instance].
  static WalletPin instance = WalletPin(SecurePinStorage());

  final PinStorage _storage;

  /// PBKDF2 iteration count. The stored record remembers the count it was
  /// hashed with, so changing this default never invalidates existing PINs.
  final int iterations;

  final Random _random;
  final DateTime Function() _now;

  /// Storage keys ("wallet." prefix: distinct from cold_signer's "signer."
  /// keys even when both apps share one installer / one keychain).
  static const pinKey = 'wallet.pin';
  static const pinLockoutKey = 'wallet.pin_lockout';

  static const saltLength = 16;
  static const lockoutThreshold = 5;
  static const baseLockout = Duration(seconds: 30);

  /// Whether a PIN has been enrolled.
  Future<bool> isSet() async => await _storage.read(pinKey) != null;

  /// Enrolls (or replaces) the PIN and clears any lockout state.
  Future<void> setPin(String pin) async {
    final salt = Uint8List.fromList(
      List.generate(saltLength, (_) => _random.nextInt(256)),
    );
    final hash = pbkdf2Sha256(
      password: utf8.encode(pin),
      salt: salt,
      iterations: iterations,
    );
    await _storage.write(
      pinKey,
      jsonEncode({
        'algo': 'pbkdf2-hmac-sha256',
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'iterations': iterations,
      }),
    );
    await _storage.delete(pinLockoutKey);
  }

  /// Removes the PIN and its lockout state.
  Future<void> clear() async {
    await _storage.delete(pinKey);
    await _storage.delete(pinLockoutKey);
  }

  /// Verifies [pin]. Refuses without hashing while locked out; on a wrong PIN
  /// bumps the persisted failure counter (engaging/extending the lock); on
  /// success resets it.
  Future<PinVerdict> verify(String pin) async {
    final raw = await _storage.read(pinKey);
    if (raw == null) throw StateError('no PIN set');
    final record = (jsonDecode(raw) as Map).cast<String, Object?>();

    final lockout = await _readLockout();
    final fails = lockout.$1;
    final lockedUntil = lockout.$2;
    final now = _now();
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      return PinVerdict.locked(lockedUntil.difference(now), fails);
    }

    final hash = pbkdf2Sha256(
      password: utf8.encode(pin),
      salt: base64Decode(record['salt']! as String),
      iterations: record['iterations']! as int,
    );
    if (_constantTimeEquals(hash, base64Decode(record['hash']! as String))) {
      await _storage.delete(pinLockoutKey);
      return const PinVerdict.ok();
    }

    final newFails = fails + 1;
    DateTime? until;
    if (newFails >= lockoutThreshold) {
      // 5th failure → 30s; each further failure doubles the lock.
      final factor = 1 << (newFails - lockoutThreshold);
      until = now.add(baseLockout * factor);
    }
    await _storage.write(
      pinLockoutKey,
      jsonEncode({
        'fails': newFails,
        if (until != null) 'lockedUntil': until.millisecondsSinceEpoch,
      }),
    );
    return until == null
        ? PinVerdict.wrong(newFails)
        : PinVerdict.locked(until.difference(now), newFails);
  }

  /// The currently pending lockout, if any (for pre-flight UI checks).
  Future<Duration?> lockRemaining() async {
    final (_, until) = await _readLockout();
    if (until == null) return null;
    final left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  Future<(int, DateTime?)> _readLockout() async {
    final raw = await _storage.read(pinLockoutKey);
    if (raw == null) return (0, null);
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    final untilMs = json['lockedUntil'] as int?;
    return (
      json['fails']! as int,
      untilMs == null ? null : DateTime.fromMillisecondsSinceEpoch(untilMs),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
