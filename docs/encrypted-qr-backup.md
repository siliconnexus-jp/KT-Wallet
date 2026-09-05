# Encrypted QR backups

## User flow

- Security settings → Encrypted backup → Encrypted QR.
- Choose a unique password (14–128 Unicode scalar values; existing weak-pattern checks), confirm it, and acknowledge offline guessing / password-loss / folder-sync risks.
- Native `createBackup` requires the existing strong authentication before sealing entropy. Dart receives ciphertext, not the phrase.
- Preview the branded PNG, then explicitly choose a destination in the system Files picker. No automatic upload, clipboard copy, photo-library write, or share action is performed.
- Add wallet → Restore from backup → scan the encrypted QR or choose its PNG/JPEG. Enter the backup password, then use the existing wallet-import path. Existing `.ktbak` restore remains supported.

## Wire format

`KTWALLET:BACKUP:2:` followed by canonical padded base64url of the native portable-v2 sealed bytes.

- Payload: 16-byte random salt || 12-byte random nonce || encrypted entropy || 16-byte GCM tag.
- Existing portable-v2 cryptography: PBKDF2-HMAC-SHA256, 210,000 iterations, AES-256-GCM. This feature does not change the native cipher or silently reinterpret historical backups.
- Only version 2 is accepted from QR; no configurable KDF parameters or legacy fallback. Changing the work factor requires a separately versioned migration.
- Ciphertext transport bounds: 60–512 bytes, at most 704 text characters. QR input is never dispatched as a URL, payment address, or plaintext mnemonic.
- No wallet name, address, balance, device ID, or password appears in the QR transport or image. Branding and instructional text are public decoration, not an authenticity guarantee.

## Image handling

- PNG export has integer-aligned modules, high error correction, and a four-module quiet zone. The logo is outside the QR.
- Image import accepts PNG/JPEG, bounds the selected file at 8 MiB and decoded dimensions at 16 MiPixels / 8192 per side, normalizes the long side to at most 2048 pixels, and decodes locally using the existing scanner.
- Multiple distinct decoded QR payloads, malformed transports, and unsupported versions are rejected before decryption.
- The private temporary normalized image is removed in a `finally` block. Original user-selected files are not altered.
- Wrong password and authenticated-decryption failure share an error; no wallet is imported on failure. Password fields are cleared after successful encryption/decryption.

## Verification

- Codec bounds/version/canonicalization; PNG generation at maximum supported payload.
- UI strength/risk gate, encrypted export/save cancellation, wrong-password import, successful import, and rejection of payment QR codes.
- Android emulator integration test uses a public portable-cipher test vector only: generated PNG → native image recognition → native decryption; wrong password and modified ciphertext are rejected. It never intentionally reads, creates, imports, or deletes a user wallet.
- For future device tests, use a disposable emulator or an explicitly preinstalled test build with a non-downgrading version code. Flutter's automatic install fallback can uninstall an existing app after a version-downgrade error; do not run it against a populated wallet emulator.

Authenticated encryption and cryptographically secure randomness follow the design principles described by [OWASP Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html). An encrypted backup is still an offline password-guessing target; these checks do not make weak or reused passwords safe and are not a substitute for an independent security audit.
