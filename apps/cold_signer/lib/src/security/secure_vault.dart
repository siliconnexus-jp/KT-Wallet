import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// True inside `flutter test`. MethodChannel plugins are unavailable there:
/// their futures never even complete under the fake-async test zone, so
/// plugin-backed stores must be bypassed up front, not caught after the fact.
bool get isFlutterTestEnv =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

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
/// injecting [InMemoryVaultStorage]) the plugin channel is dead — its futures
/// never complete — so this degrades to a process-local in-memory map and the
/// UI keeps working statelessly instead of hanging. On a real device the
/// plugin is always registered and the fallback never engages.
class SecureVaultStorage implements VaultStorage {
  SecureVaultStorage({FlutterSecureStorage? storage})
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

  factory WalletMetadata.fromJson(Map<String, Object?> json) => WalletMetadata(
    walletId: json['walletId']! as String,
    name: json['name']! as String,
    createdAt: json['createdAt']! as int,
    version: json['version'] as int? ?? 1,
    addresses: ((json['addresses'] as Map?) ?? const {}).cast<String, String>(),
    publicKeys: ((json['publicKeys'] as Map?) ?? const {}).cast<String, String>(),
    biometricEnabled: json['biometricEnabled'] as bool? ?? false,
  );

  final String walletId;
  final String name;

  /// Epoch seconds.
  final int createdAt;
  final int version;
  final Map<String, String> addresses;
  /// Base64-encoded public keys only; private material remains native.
  final Map<String, String> publicKeys;
  final bool biometricEnabled;

  WalletMetadata copyWith({
    Map<String, String>? addresses,
    Map<String, String>? publicKeys,
    bool? biometricEnabled,
  }) => WalletMetadata(
    walletId: walletId,
    name: name,
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

  Future<bool> hasWallet() async => await _storage.read(metadataKey) != null;

  Future<void> storeMetadata(WalletMetadata metadata) async {
    await _storage.write(metadataKey, jsonEncode(metadata.toJson()));
  }

  Future<WalletMetadata?> readMetadata() async {
    final raw = await _storage.read(metadataKey);
    if (raw == null) return null;
    return WalletMetadata.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  Future<void> removeLegacyMnemonic() => _storage.delete(mnemonicKey);

  /// Erases all Dart-side state. Native key material is deleted separately by
  /// `CoreCrypto.deleteWallet` before this method is called.
  Future<void> wipe() async {
    for (final key in const [mnemonicKey, metadataKey, pinKey, pinLockoutKey]) {
      await _storage.delete(key);
    }
  }
}
