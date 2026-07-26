# KT Wallet Privacy Policy

Last updated: 2026-07-26

KT Wallet is a self-custody wallet. Recovery phrases and private keys are
processed on the user's device and are not uploaded by KT Wallet. The app does
not operate an advertising SDK, does not track users across apps or websites,
and does not sell personal information.

## Data processed on the device

- Wallet names, public addresses, enabled assets, preferences and transaction
  state are stored locally.
- Recovery phrases and signing keys are held by the native `core_crypto`
  storage protected by the operating system keystore/keychain. The Cold Signer
  does not store a complete phrase in Dart preferences or Flutter secure
  storage.
- PIN verifiers, authentication settings, lockout state and non-secret signing
  records are stored locally.
- Camera frames used for QR scanning are processed in memory and are not saved
  by KT Wallet.
- Screenshot notifications contain only an event signal; KT Wallet does not
  read or retain the screenshot.

## Network requests

Online Wallet mode sends public wallet addresses, transaction payloads and RPC
queries to the RPC, explorer or optional gateway endpoints selected in the app.
Those independent services may observe the IP address and request contents and
apply their own privacy policies. Offline Signer mode is intended for an
air-gapped device and blocks signing when a network connection is detected.

## Permissions

- Camera: scan pairing and transaction QR codes.
- Biometrics/device authentication: protect wallet access and every signing
  operation. Biometric templates remain under operating-system control.
- Network state: report whether the Cold Signer is actually offline.
- Android screen-capture detection: show a security warning on supported
  Android versions. The standalone Cold Signer also uses `FLAG_SECURE`.

## Deletion

Deleting a wallet removes its native key, wallet metadata, PIN/authentication
configuration and signing records associated with that Cold Signer wallet.
Deleting the app removes remaining local app data according to the operating
system's normal uninstall behavior.

Questions and security reports can be filed at
https://github.com/siliconnexus-jp/KT-Wallet/issues.
