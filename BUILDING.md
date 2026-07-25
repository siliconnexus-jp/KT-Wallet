# Building KT Wallet

Two Flutter apps in a pub workspace:

- `apps/kt_wallet` — **the shipping single installer**: first-launch device-mode
  picker (online wallet / offline signer), with the signer embedded via a path
  dependency on `cold_signer`
- `apps/cold_signer` — the air-gapped offline signer, also independently
  buildable as its own app for users who want a dedicated signer install

Both build for **iOS and Android**. All four targets are verified building:

| App | iOS | Android |
|---|---|---|
| kt_wallet | ✅ `flutter build ios --no-codesign` | ✅ `flutter build apk` |
| cold_signer | ✅ `flutter build ios --no-codesign` | ✅ `flutter build apk` |

## Fonts

The design typography — **Inter** (UI) and **JetBrains Mono** (addresses,
hashes, mnemonics) — is bundled under each app's `fonts/` and declared in its
`pubspec.yaml`, so both apps render the Pencil design 1:1 on-device, offline
(important for the air-gapped signer). CJK glyphs fall back to the platform CJK
font (PingFang on iOS, Noto on Android), which is correct — Inter has no CJK.

## Trust Wallet Core (native crypto)

`packages/core_crypto` bridges [Trust Wallet Core](https://github.com/trustwallet/wallet-core)
(audited mnemonic / derivation / signing).

- **iOS** links the `TrustWalletCore` CocoaPods pod — resolves automatically.
- **Android** needs `com.trustwallet:wallet-core`, which Trust Wallet publishes
  **only to GitHub Packages** (authenticated); it is **not** on Maven Central,
  and the GitHub release ships no Android `.aar`.

To keep the repo building on Android without credentials, wallet-core is
**opt-in** on Android via the gradle property `walletCore` (default `false`).
When off, an **API-identical fail-closed stub** is compiled in its place:
key/address/signature operations throw `CRYPTO_UNAVAILABLE`, so no
wrong-but-plausible crypto can be produced. The production app always calls the
native bridge and therefore shows its retryable bootstrap error on a clean
Android install until wallet-core is enabled.

For simulator-only UI acceptance, a deterministic mock may be opted into
explicitly:

```sh
flutter run --dart-define=KT_ALLOW_MOCK_CRYPTO=true
```

Never use that define for release artifacts or real assets.

### Enabling real crypto on Android

1. Create a GitHub personal access token with `read:packages`.
2. Add the GitHub Packages Maven repo with credentials in
   `packages/core_crypto/android/build.gradle.kts` (`allprojects.repositories`):

   ```kotlin
   maven {
       url = uri("https://maven.pkg.github.com/trustwallet/wallet-core")
       credentials {
           username = providers.gradleProperty("gpr.user").get()
           password = providers.gradleProperty("gpr.token").get()
       }
   }
   ```

3. Build with the flag on, e.g. add `walletCore=true` to
   `apps/<app>/android/gradle.properties` (plus `gpr.user` / `gpr.token` in
   `~/.gradle/gradle.properties`), then `flutter build apk`.

iOS is unaffected by this flag.
