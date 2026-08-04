import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../rpc/json_rpc_envelope.dart' show decodeJsonWithoutDuplicateKeys;
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

/// The enrolled PIN or lockout record exists but cannot be interpreted under
/// KT Wallet's closed security schema. Callers must keep authentication
/// locked; deleting or silently replacing the record would weaken the gate.
class PinStateCorruptedException implements Exception {
  const PinStateCorruptedException();

  @override
  String toString() => 'PinStateCorruptedException';
}

/// Production storage: flutter_secure_storage (Keychain / Keystore).
///
/// Under `flutter test` (widget tests that pump the real app without
/// injecting [InMemoryPinStorage]) the plugin channel is dead, so tests use a
/// process-local map. Every non-test environment fails closed: a missing or
/// broken platform plugin is propagated to the caller and can never turn the
/// PIN or its lockout counter into silently ephemeral state.
class SecurePinStorage implements PinStorage {
  SecurePinStorage({FlutterSecureStorage? storage})
    : this._(storage ?? const FlutterSecureStorage(), null);

  @visibleForTesting
  SecurePinStorage.withTestEnvironment({
    FlutterSecureStorage? storage,
    required bool isTestEnvironment,
  }) : this._(storage ?? const FlutterSecureStorage(), isTestEnvironment);

  SecurePinStorage._(this._storage, this._testEnvironmentOverride);

  final FlutterSecureStorage _storage;
  final bool? _testEnvironmentOverride;

  bool get _useTestFallback =>
      kDebugMode && (_testEnvironmentOverride ?? isFlutterTestEnv);

  /// Plugin-less fallback (see class doc). Static so every default-constructed
  /// instance in one process shares it, like the real backing store would.
  static final Map<String, String> _pluginlessFallback = {};

  @override
  Future<String?> read(String key) async {
    if (_useTestFallback) return _pluginlessFallback[key];
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (_useTestFallback) {
      _pluginlessFallback[key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    if (_useTestFallback) {
      _pluginlessFallback.remove(key);
      return;
    }
    await _storage.delete(key: key);
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
  static const hashLength = 32;
  static const maxStoredRecordChars = 4096;
  static const maxStoredIterations = 1000000;
  static const lockoutThreshold = 5;
  static const maxTrackedFailures = 64;
  static const baseLockout = Duration(seconds: 30);
  static const maxLockout = Duration(hours: 24);
  static const maxPersistedLockout = Duration(days: 7);

  /// Whether a PIN has been enrolled.
  Future<bool> isSet() async {
    final raw = await _storage.read(pinKey);
    if (raw == null) return false;
    _decodePinRecord(raw);
    return true;
  }

  /// Enrolls (or replaces) the PIN and clears any lockout state.
  Future<void> setPin(String pin) async {
    if (!_isSixDigitPin(pin)) {
      throw ArgumentError.value(pin.length, 'pin', 'must be exactly 6 digits');
    }
    if (iterations < 1 || iterations > maxStoredIterations) {
      throw ArgumentError.value(iterations, 'iterations');
    }
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
    if (!_isSixDigitPin(pin)) {
      throw ArgumentError.value(pin.length, 'pin', 'must be exactly 6 digits');
    }
    final raw = await _storage.read(pinKey);
    if (raw == null) throw StateError('no PIN set');
    final record = _decodePinRecord(raw);

    final lockout = await _readLockout();
    final fails = lockout.$1;
    final lockedUntil = lockout.$2;
    final now = _now();
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      return PinVerdict.locked(lockedUntil.difference(now), fails);
    }

    final hash = pbkdf2Sha256(
      password: utf8.encode(pin),
      salt: record.salt,
      iterations: record.iterations,
    );
    if (_constantTimeEquals(hash, record.hash)) {
      await _storage.delete(pinLockoutKey);
      return const PinVerdict.ok();
    }

    final newFails = min(fails + 1, maxTrackedFailures);
    DateTime? until;
    if (newFails >= lockoutThreshold) {
      // 5th failure → 30s; subsequent failures double up to a 24-hour hard
      // cap. The bounded loop cannot allocate an attacker-sized BigInt even
      // if persisted storage is corrupted.
      until = now.add(_lockoutDuration(newFails));
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
    final json = _decodeExactObject(
      raw,
      allowed: const {'fails', 'lockedUntil'},
      required: const {'fails'},
    );
    final fails = json['fails'];
    if (fails is! int || fails < 1 || fails > maxTrackedFailures) {
      throw const PinStateCorruptedException();
    }
    final untilMs = json['lockedUntil'];
    if (fails < lockoutThreshold) {
      if (untilMs != null || json.containsKey('lockedUntil')) {
        throw const PinStateCorruptedException();
      }
      return (fails, null);
    }
    if (untilMs is! int || untilMs < 0) {
      throw const PinStateCorruptedException();
    }
    final latest = _now().add(maxPersistedLockout).millisecondsSinceEpoch;
    if (untilMs > latest) throw const PinStateCorruptedException();
    final until = DateTime.fromMillisecondsSinceEpoch(untilMs);
    return (fails, until);
  }

  ({Uint8List salt, Uint8List hash, int iterations}) _decodePinRecord(
    String raw,
  ) {
    final record = _decodeExactObject(
      raw,
      allowed: const {'algo', 'salt', 'hash', 'iterations'},
      required: const {'algo', 'salt', 'hash', 'iterations'},
    );
    final storedIterations = record['iterations'];
    if (record['algo'] != 'pbkdf2-hmac-sha256' ||
        storedIterations is! int ||
        storedIterations < 1 ||
        storedIterations > maxStoredIterations) {
      throw const PinStateCorruptedException();
    }
    final salt = _decodeCanonicalBase64(record['salt'], saltLength);
    final hash = _decodeCanonicalBase64(record['hash'], hashLength);
    return (salt: salt, hash: hash, iterations: storedIterations);
  }

  static Map<String, Object?> _decodeExactObject(
    String raw, {
    required Set<String> allowed,
    required Set<String> required,
  }) {
    try {
      if (raw.length > maxStoredRecordChars) {
        throw const PinStateCorruptedException();
      }
      final decoded = decodeJsonWithoutDuplicateKeys(raw);
      if (decoded is! Map ||
          decoded.keys.any((key) => key is! String || !allowed.contains(key)) ||
          required.any((key) => !decoded.containsKey(key))) {
        throw const PinStateCorruptedException();
      }
      return decoded.cast<String, Object?>();
    } on PinStateCorruptedException {
      rethrow;
    } on Object {
      throw const PinStateCorruptedException();
    }
  }

  static Uint8List _decodeCanonicalBase64(Object? value, int length) {
    if (value is! String) throw const PinStateCorruptedException();
    try {
      final bytes = base64Decode(value);
      if (bytes.length != length || base64Encode(bytes) != value) {
        throw const PinStateCorruptedException();
      }
      return Uint8List.fromList(bytes);
    } on PinStateCorruptedException {
      rethrow;
    } on Object {
      throw const PinStateCorruptedException();
    }
  }

  static Duration _lockoutDuration(int failedAttempts) {
    var seconds = baseLockout.inSeconds;
    final maxSeconds = maxLockout.inSeconds;
    for (var i = lockoutThreshold; i < failedAttempts; i++) {
      seconds = min(seconds * 2, maxSeconds);
      if (seconds == maxSeconds) break;
    }
    return Duration(seconds: seconds);
  }

  static bool _isSixDigitPin(String pin) =>
      pin.length == 6 &&
      pin.codeUnits.every((code) => code >= 48 && code <= 57);

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
