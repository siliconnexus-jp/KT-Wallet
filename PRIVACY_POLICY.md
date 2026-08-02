# KT Wallet Privacy Policy

Last updated: 2026-07-31

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

KT Wallet keeps a bounded set of privacy-minimal reliability samples on the
device: one of twelve fixed operation names, a bounded duration, and whether
the operation succeeded. Exact event times, error messages, stack traces,
device/session identifiers, wallet data and transaction data are not recorded.
The About screen can export a redacted local support package for the user to
review and share.

The About screen also offers a separate, optional **Send anonymous performance
report** action. Nothing is uploaded in the background. Each upload requires a
fresh confirmation and is sent once without automatic retries. It contains
only the app version, platform, broad language (`en`, `zh`, `ja`, or `other`),
build mode, and aggregate count/success/failure/P50/P95 values for the fixed
operation names. It never includes a wallet or device ID, address, balance,
amount, transaction, transaction hash, timestamp, endpoint URL, error text,
stack trace, key, signature, or recovery phrase. The Gateway converts accepted
reports directly into fixed-label counters and does not store the request body
or raw events. Production monitoring currently retains these anonymous
aggregates for at most 7 days or 512 MB, whichever limit is reached first.

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

General, non-sensitive questions can be filed in the public issue tracker.
Suspected vulnerabilities must not be posted publicly. Use the private process
in [SECURITY.md](SECURITY.md). Never include a recovery phrase, private key,
provider credential, complete transaction payload, or unredacted wallet data in
a report.
