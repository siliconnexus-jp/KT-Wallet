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

To keep local Debug and UI-test builds working on Android without credentials,
wallet-core is **opt-in** via the Gradle property `walletCore` (default `false`).
When off, an **API-identical fail-closed stub** is compiled in its place:
key/address/signature operations throw `CRYPTO_UNAVAILABLE`, so no
wrong-but-plausible crypto can be produced. Android **Release builds now fail
at configuration time** when Wallet Core is disabled, so a non-functional
signer APK cannot be mistaken for a publishable artifact.

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

3. Build with the flag on, e.g. add `walletCore=true` to the ignored
   `apps/<app>/android/local.properties` (with `gpr.user` / `gpr.token` there),
   or put all three values in `~/.gradle/gradle.properties`, then run
   `flutter build apk`. Inside this monorepo the Cold Signer may reuse the
   ignored KT Wallet local properties, so credentials never need to be copied
   into tracked files.

iOS is unaffected by this flag.

## Dependency integrity and vulnerability gate

All three Android projects include the official Gradle 9.1.0 wrapper scripts
and JAR. `gradle-wrapper.properties` pins the official distribution SHA-256 and
enables URL validation. Both applications also keep two complementary files:

- `android/app/gradle.lockfile` pins the exact production
  `releaseRuntimeClasspath` versions.
- `android/gradle/verification-metadata.xml` pins SHA-256 values for every
  Maven artifact and metadata file used by the build.

Do not hand-edit the production runtime lock or broadly regenerate verification
metadata without review. After an intentional runtime dependency update,
regenerate the release lock and integrity baseline from the standard Flutter
release state, then review the diff before accepting it:

```sh
flutter build apk --release
(cd android && ./gradlew :app:dependencies \
  --configuration releaseRuntimeClasspath --write-locks)
(cd android && ./gradlew :app:assembleRelease \
  --write-verification-metadata sha256)
```

Run the repository gate afterwards:

```sh
tool/audit_dependencies.sh
```

Build/test-only artifacts discovered by strict verification use a narrower
procedure. Do not accept them with a blanket metadata generation command.
Compare the artifact against its publisher's official SHA-256 sidecar, a fresh
download, and the Gradle cache; add only the requested artifact entries to both
applications; then extend `tool/check_deps.dart` so the exact reviewed artifact
set, hashes, origins, cardinality, and absence of trust expansion are enforced.
JUnit 6.1.2 used by `mobile_scanner` tests currently follows this procedure for
7 Gradle module metadata files and 6 JARs. Verify the aggregate Android test
graphs as well as the repository gate:

```sh
(cd apps/kt_wallet/android && ./gradlew testDebugUnitTest --offline)
(cd apps/cold_signer/android && ./gradlew testDebugUnitTest --offline)
dart run tool/check_deps.dart
```

The gate scans the actual Android Release runtime locks rather than treating
AGP/Flutter test and lint classpaths as APK code. The full verification metadata
still integrity-pins those build tools. CocoaPods does not currently have a
native OSV extractor here, so iOS combines checked-in `Podfile.lock`
versions/spec checksums and `pod install --deployment` with exact upstream tag
resolution, pinned source-archive checksums, and OSV exact-commit queries. The
SQLite native-assets release tag/source hashes and final Apple runtime are also
checked. These gates cover the current known dependency set; they are not a
claim of complete iOS vulnerability coverage or an external security audit.

Debug, Profile, and Release each use a dedicated Flutter xcconfig that includes
the matching `Pods-Runner.*.xcconfig`. In particular, do not point Runner's
Profile configuration back to `Release.xcconfig`: that silently skips
CocoaPods' Profile-specific settings and makes `pod install` report an invalid
base configuration. The Apple dependency audit enforces the Profile include,
the production `FLUTTER_TARGET`, and the Xcode project reference.

## Release identity and signing

The shipping app uses `cc.siliconnexus.ktwallet` on Android and iOS. Its
launcher name is **KT Wallet** on both platforms. The independently installable
Cold Signer uses `cc.siliconnexus.ktwallet.coldsigner`.

Android release builds of **both** apps are deliberately **not** signed with
the debug key — whose password is the public string `android`, so anyone could
otherwise sign a look-alike update of the app that holds the seed. Each app
reads its own four values from the environment only:

```sh
# apps/kt_wallet
export KT_RELEASE_STORE_FILE=/absolute/path/to/kt-wallet-release.jks
export KT_RELEASE_STORE_PASSWORD='...'
export KT_RELEASE_KEY_ALIAS='...'
export KT_RELEASE_KEY_PASSWORD='...'

# apps/cold_signer (separate keystore — separate trust anchor)
export KT_SIGNER_RELEASE_STORE_FILE=/absolute/path/to/kt-signer-release.jks
export KT_SIGNER_RELEASE_STORE_PASSWORD='...'
export KT_SIGNER_RELEASE_KEY_ALIAS='...'
export KT_SIGNER_RELEASE_KEY_PASSWORD='...'

flutter build appbundle --release
```

Both builds fail closed: without all four values the release build type gets no
signing config at all, so Gradle emits an unsigned artifact rather than a
falsely publishable debug-signed one. Do not commit either keystore or its
passwords.

After building, verify the exact APK or App Bundle that will leave the build
machine. The same guard checks all three ABIs, the real Wallet Core bridge,
SQLite, final merged manifest and permissions, exported components, production
markers, local E2E canaries, credential patterns, archive paths and signing
identity:

```sh
tool/check_release_artifact.sh \
  apps/kt_wallet/build/app/outputs/flutter-apk/app-release.apk
tool/check_release_artifact.sh \
  apps/kt_wallet/build/app/outputs/bundle/release/app-release.aab
tool/check_release_artifact.sh \
  apps/cold_signer/build/app/outputs/flutter-apk/app-release.apk
tool/check_release_artifact.sh \
  apps/cold_signer/build/app/outputs/bundle/release/app-release.aab
```

For AAB input, the guard strictly parses the producer version from
`BundleConfig.pb` and requires it to match
`tool/android-release-toolchain.lock`. The selected `bundletool` JAR must match
both that lock's SHA-256 and the app's Gradle verification metadata; every
runtime JAR used to execute it is also checked against the same metadata. The
guard then validates the bundle container and reads the final base-module
protobuf manifest. Do not update the release-toolchain lock merely to make a
new build pass: review the AGP change, both verification-metadata diffs, fresh
AAB hashes and all positive/negative guard evidence together.

An unsigned result is reported explicitly as signing pending: it is valid
evidence for source/artifact review, but it is **not** uploadable or
distributable until the correct upload key is applied and the guard is rerun.

For iOS, select the SiliconNexus Apple team and the App Store provisioning
profile in Xcode, then archive `apps/kt_wallet/ios/Runner.xcworkspace`.
Signing identities and provisioning profiles remain local/CI secrets.

## Apple export compliance

Both iOS apps currently declare `ITSAppUsesNonExemptEncryption` as `NO`, matching
the accepted NyxNet iOS release configuration. The apps use standard
cryptographic primitives for blockchain transaction signatures and operating
system facilities for secure storage and HTTPS; they do not implement
proprietary encryption algorithms.

Do not add an empty `ITSEncryptionExportComplianceCode`: App Store Connect
rejects an empty value as an invalid code. If the app's cryptographic use or
distribution classification changes and Apple requires documentation, complete
the App Encryption Documentation flow separately for each app, then add only
the app-specific code Apple issues after approval.
