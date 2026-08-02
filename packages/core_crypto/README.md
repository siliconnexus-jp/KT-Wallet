# core_crypto

Flutter platform plugin that owns KT Wallet key creation, device-bound storage,
public derivation, strong authentication, backup encryption, and native Wallet
Core signing on Android and iOS.

```dart
import 'package:core_crypto/core_crypto.dart';

final crypto = MethodChannelCoreCrypto();
final mnemonic = await crypto.generateMnemonic();
await crypto.storeWallet(
  walletId: 'random-wallet-id',
  mnemonic: mnemonic,
  requireAuth: true,
);
final addresses = await crypto.deriveAddresses('random-wallet-id');
```

Supported `Coin` values are Ethereum, Polygon, Base, Arbitrum, Avalanche,
BNB Smart Chain, TRON, and Solana. `signTransaction` accepts a chain-specific
Wallet Core signing input and returns only the signed bytes and public hash.

## Security boundary

- Mnemonics cross the Dart/native boundary only during create, import, or an
  explicitly authenticated export flow. Callers must discard their Dart
  reference immediately after storage.
- Production apps use the native implementation. `MockCoreCrypto` is exported
  only by `package:core_crypto/testing.dart` and is forbidden in release
  artifacts by repository gates.
- Android uses device-bound encrypted storage and native authentication; iOS
  uses a device-only Keychain accessibility class. The host apps additionally
  disable or exclude platform backups.
- Native wallet slots are create-only. A repeated `walletId` returns
  `WalletAlreadyExistsException` and never replaces the existing Keychain/
  Keystore material or changes its authentication policy. Android fsyncs a
  temporary ciphertext file and renames it within the private app directory;
  a failed file commit compensates the newly-created Keystore key.
- The native MethodChannel independently bounds every crypto-sized payload
  before authentication: BIP-39 text, KDF/backup passwords, signing input
  (1 MiB), and the exact 60/68/76-byte backup payload shapes. Coin names use
  the eight-chain allowlist. Unsupported or oversized requests return
  `InvalidInputException` without opening system authentication or a KDF.
- Device-local encrypted wallet envelopes are closed schemas: only header
  versions `0/1`, BIP-39 entropy sizes 16/24/32, and the corresponding bounded
  ciphertext sizes are accepted. Unknown headers, truncated/oversized private
  files, bad GCM tags, or invalid plaintext lengths return
  `StoreCorruptedException` and never reach Wallet Core.
- `createBackup` writes the portable backup-v2 payload used by both platforms:
  PBKDF2-HMAC-SHA256 (210,000 rounds, UTF-8 password, 16-byte salt) followed by
  AES-256-GCM (12-byte nonce and 16-byte tag). The native payload layout is
  `salt || nonce || ciphertext || tag`; the Dart envelope authenticates its
  exact version and metadata before asking native code to decrypt it. Losing
  the password is intentionally unrecoverable.
- Android executes PBKDF2 from the platform `HmacSHA256` primitive instead of
  the API-26-only `PBKDF2WithHmacSHA256` `SecretKeyFactory` alias. This keeps
  the exact same bytes as iOS while honoring the package's Android API 24
  minimum.
- `readBackup` requires an explicit `BackupCipherFormat`. Portable v2 never
  falls back to another KDF. Android can additionally restore legacy v1 files:
  it tries the documented portable PBKDF2 format first and only then the former
  Android Argon2id payload. Device-local mnemonic storage continues to use its
  separate device-bound cipher and is not changed by the backup format.
- A legacy Android v1 Argon2id file is not directly portable to iOS. Restore it
  on Android and immediately export a new v2 backup before moving platforms.
- New backups require a 14–128 Unicode-scalar passphrase and reject common,
  sequential, low-diversity, or short-period repeated patterns. This is an
  offline-guessing floor, not a password-strength guarantee. Restore does not
  apply the new policy, so historical files with shorter passwords remain
  openable.

Run `flutter test` for the Dart channel contract. Android also has native
Gradle tests. `tool/test_portable_backup_swift.sh` directly compiles and runs
the production Swift backup cipher against the same Unicode byte vector used
by Android; iOS host behavior is additionally verified through the application
build and integration tests because Wallet Core is supplied by the
Flutter/CocoaPods build.

Licensed under MPL-2.0; see `LICENSE`.
