## 0.0.1

- Made native wallet storage create-only, with typed duplicate rejection,
  atomic Android ciphertext commits, and Keystore failure compensation.
- Added pre-authentication native size bounds for mnemonics, signing inputs,
  KDF/backup passwords and backup blobs, plus an exact supported-coin allowlist.
- Closed the device-local wallet envelope schema and reject unknown headers,
  invalid entropy lengths, malformed GCM payloads and oversized private blobs.
- Native BIP-39 wallet creation/import, device-bound key storage, public
  address and public-key derivation for eight chains.
- Authenticated Wallet Core signing, mnemonic export, encrypted backup, and
  wallet deletion APIs for Android and iOS.
