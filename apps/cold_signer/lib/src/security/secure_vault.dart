import 'dart:convert';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'strict_local_json.dart';

/// Public signer metadata or deletion recovery state exists but is not valid
/// under the closed local schema. Startup must remain blocked.
class VaultStateCorruptedException implements Exception {
  const VaultStateCorruptedException();

  @override
  String toString() => 'VaultStateCorruptedException';
}

/// True inside `flutter test`. MethodChannel plugins are unavailable there:
/// their futures never even complete under the fake-async test zone, so
/// plugin-backed stores must be bypassed up front, not caught after the fact.
/// Release and profile builds reject the process marker at the compile-time
/// boundary; an environment variable can never enable an in-memory vault in a
/// distributed app.
bool get isFlutterTestEnv =>
    kDebugMode && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

@visibleForTesting
bool resolveFlutterTestFallback({
  required bool isDebugBuild,
  required bool isWeb,
  required bool markerPresent,
}) => isDebugBuild && !isWeb && markerPresent;

/// Minimal string key-value contract over the platform secure store
/// (iOS Keychain / Android Keystore-backed EncryptedSharedPreferences).
///
/// Kept as an interface so everything above it — [SecureVault], PinLock, the
/// wallet controller — is testable: MethodChannel plugins are unavailable in
/// widget tests, so ALL tests run against [InMemoryVaultStorage] instead of
/// the real [SecureVaultStorage].
abstract class VaultStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production storage: flutter_secure_storage (Keychain / Keystore).
///
/// Under `flutter test` (widget tests that pump the real app without
/// injecting [InMemoryVaultStorage]) the plugin channel is dead, so tests use
/// a process-local map. Every non-test environment fails closed: a missing or
/// broken platform plugin is propagated to the caller and can never turn PIN
/// or wallet metadata into silently ephemeral state.
class SecureVaultStorage implements VaultStorage {
  SecureVaultStorage({FlutterSecureStorage? storage})
    : this._(storage ?? const FlutterSecureStorage(), null);

  @visibleForTesting
  SecureVaultStorage.withTestEnvironment({
    FlutterSecureStorage? storage,
    required bool isTestEnvironment,
  }) : this._(storage ?? const FlutterSecureStorage(), isTestEnvironment);

  SecureVaultStorage._(this._storage, this._testEnvironmentOverride);

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
class InMemoryVaultStorage implements VaultStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Non-secret wallet descriptor stored alongside the mnemonic.
class WalletMetadata {
  const WalletMetadata({
    required this.walletId,
    required this.name,
    required this.createdAt,
    this.version = 2,
    this.addresses = const {},
    this.publicKeys = const {},
    this.biometricEnabled = false,
  });

  factory WalletMetadata.fromJson(Map<String, Object?> json) {
    try {
      const allowed = {
        'walletId',
        'name',
        'createdAt',
        'version',
        'addresses',
        'publicKeys',
        'biometricEnabled',
      };
      const legacyRequired = {'walletId', 'name', 'createdAt'};
      const currentRequired = allowed;
      if (json.keys.any((key) => !allowed.contains(key)) ||
          legacyRequired.any((key) => !json.containsKey(key))) {
        throw const VaultStateCorruptedException();
      }
      final version = json.containsKey('version') ? json['version'] : 1;
      if (version is! int || (version != 1 && version != 2)) {
        throw const VaultStateCorruptedException();
      }
      if (version == 2 &&
          currentRequired.any((key) => !json.containsKey(key))) {
        throw const VaultStateCorruptedException();
      }
      final metadata = WalletMetadata(
        walletId: json['walletId']! as String,
        name: json['name']! as String,
        createdAt: json['createdAt']! as int,
        version: version,
        addresses: json.containsKey('addresses')
            ? _decodeStringMap(json['addresses'])
            : const {},
        publicKeys: json.containsKey('publicKeys')
            ? _decodeStringMap(json['publicKeys'])
            : const {},
        biometricEnabled: json.containsKey('biometricEnabled')
            ? json['biometricEnabled'] as bool
            : false,
      );
      metadata.validate();
      return metadata;
    } on VaultStateCorruptedException {
      rethrow;
    } on Object {
      throw const VaultStateCorruptedException();
    }
  }

  static const supportedChainKeys = {
    'eth',
    'polygon',
    'base',
    'arbitrum',
    'avalanche',
    'bnb',
    'tron',
    'solana',
  };
  static const maxNameRunes = 80;
  static const maxCreatedAt = 4102444800; // 2100-01-01 UTC.

  static final _unsafeNameCharacters = RegExp(
    r'[\x00-\x1f\x7f\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]',
  );
  static final _nonAsciiAddressCharacters = RegExp(r'[^\x21-\x7e]');

  final String walletId;
  final String name;

  /// Epoch seconds.
  final int createdAt;
  final int version;
  final Map<String, String> addresses;

  /// Base64-encoded public keys only; private material remains native.
  final Map<String, String> publicKeys;
  final bool biometricEnabled;

  void validate() {
    try {
      CoreCryptoValidation.checkWalletId(walletId);
      if (name.isEmpty ||
          name != name.trim() ||
          name.runes.length > maxNameRunes ||
          _unsafeNameCharacters.hasMatch(name) ||
          createdAt < 0 ||
          createdAt > maxCreatedAt ||
          (version != 1 && version != 2)) {
        throw const VaultStateCorruptedException();
      }
      _validateAddressMap(addresses);
      _validatePublicKeyMap(publicKeys);
    } on VaultStateCorruptedException {
      rethrow;
    } on Object {
      throw const VaultStateCorruptedException();
    }
  }

  WalletMetadata copyWith({
    String? name,
    Map<String, String>? addresses,
    Map<String, String>? publicKeys,
    bool? biometricEnabled,
  }) => WalletMetadata(
    walletId: walletId,
    name: name ?? this.name,
    createdAt: createdAt,
    version: version,
    addresses: addresses ?? this.addresses,
    publicKeys: publicKeys ?? this.publicKeys,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
  );

  Map<String, Object?> toJson() => {
    'walletId': walletId,
    'name': name,
    'createdAt': createdAt,
    'version': version,
    'addresses': addresses,
    'publicKeys': publicKeys,
    'biometricEnabled': biometricEnabled,
  };

  static Map<String, String> _decodeStringMap(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.values.any((entry) => entry is! String)) {
      throw const VaultStateCorruptedException();
    }
    return Map.unmodifiable(value.cast<String, String>());
  }

  static void _validateAddressMap(Map<String, String> addresses) {
    for (final entry in addresses.entries) {
      if (!supportedChainKeys.contains(entry.key) ||
          entry.value.isEmpty ||
          entry.value.length > 128 ||
          _nonAsciiAddressCharacters.hasMatch(entry.value)) {
        throw const VaultStateCorruptedException();
      }
    }
  }

  static void _validatePublicKeyMap(Map<String, String> publicKeys) {
    for (final entry in publicKeys.entries) {
      if (!supportedChainKeys.contains(entry.key)) {
        throw const VaultStateCorruptedException();
      }
      final decoded = base64Decode(entry.value);
      if (base64Encode(decoded) != entry.value) {
        throw const VaultStateCorruptedException();
      }
      if (entry.key == 'solana') {
        if (decoded.length != 32) {
          throw const VaultStateCorruptedException();
        }
      } else if (decoded.length != 65 || decoded.first != 4) {
        throw const VaultStateCorruptedException();
      }
    }
  }
}

/// The signer's non-secret descriptor store.
///
/// Mnemonic entropy is owned exclusively by `core_crypto`'s native Keychain /
/// Keystore implementation. This Dart store contains only versioned public
/// metadata, the app PIN verifier and its durable lockout state.
class SecureVault {
  SecureVault(this._storage);

  final VaultStorage _storage;

  /// Storage keys. `signer.pin` / `signer.pin_lockout` are written by PinLock
  /// but listed here so [wipe] erases everything the signer ever persists.
  /// Legacy key used by pre-native builds. It is never written again and is
  /// deleted on load/wipe so an upgrade cannot leave a Dart mnemonic behind.
  static const mnemonicKey = 'signer.mnemonic';
  static const metadataKey = 'signer.wallet_meta';
  static const pinKey = 'signer.pin';
  static const pinLockoutKey = 'signer.pin_lockout';
  static const deletionPendingKey = 'signer.wallet_delete_pending.v1';
  static const maxMetadataChars = 16384;

  Future<bool> hasWallet() async => await readMetadata() != null;

  Future<void> storeMetadata(WalletMetadata metadata) async {
    metadata.validate();
    await _storage.write(metadataKey, jsonEncode(metadata.toJson()));
  }

  Future<WalletMetadata?> readMetadata() async {
    final raw = await _storage.read(metadataKey);
    if (raw == null) return null;
    try {
      final decoded = decodeStrictLocalJson(raw, maxChars: maxMetadataChars);
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const VaultStateCorruptedException();
      }
      return WalletMetadata.fromJson(decoded.cast<String, Object?>());
    } on VaultStateCorruptedException {
      rethrow;
    } on Object {
      throw const VaultStateCorruptedException();
    }
  }

  Future<void> removeLegacyMnemonic() => _storage.delete(mnemonicKey);

  Future<void> markDeletionPending(String walletId) async {
    _validateWalletId(walletId);
    await _storage.write(deletionPendingKey, walletId);
  }

  Future<String?> pendingDeletionWalletId() async {
    final walletId = await _storage.read(deletionPendingKey);
    if (walletId == null) return null;
    _validateWalletId(walletId);
    return walletId;
  }

  static void _validateWalletId(String walletId) {
    try {
      CoreCryptoValidation.checkWalletId(walletId);
    } on Object {
      throw const VaultStateCorruptedException();
    }
  }

  /// Erases all Dart-side state. Native key material is deleted separately by
  /// `CoreCrypto.deleteWallet` before this method is called.
  Future<void> wipe({bool keepDeletionMarker = false}) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final key in const [mnemonicKey, metadataKey, pinKey, pinLockoutKey]) {
      try {
        await _storage.delete(key);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    // The marker is the crash-recovery anchor. Remove it last and only after
    // every primary state key was erased and any external record cleanup has
    // succeeded. Otherwise startup must retry instead of resurrecting a
    // metadata row whose native key has already gone.
    if (firstError == null && !keepDeletionMarker) {
      try {
        await _storage.delete(deletionPendingKey);
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
