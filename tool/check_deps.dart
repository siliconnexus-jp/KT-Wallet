// Repo-level dependency firewall for cold_signer (todolist.md P0-2).
//
// Usage: dart run tool/check_deps.dart   (from workspace root)
// Exits non-zero on any violation. Wired into CI.

import 'dart:io';

import 'package:test_support/dep_check.dart';
import 'package:test_support/e2e_credentials.dart';

void main() {
  final failures = <String>[];

  final pubspec = File('apps/cold_signer/pubspec.yaml');
  final violations = findWhitelistViolations(pubspec.readAsStringSync());
  if (violations.isNotEmpty) {
    failures.add('cold_signer pubspec has non-whitelisted deps: $violations');
  }

  final libDir = Directory('apps/cold_signer/lib');
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    final bad = findBannedImports(source);
    if (bad.isNotEmpty) {
      failures.add('${entity.path} imports banned libraries: $bad');
    }
    // `dart:io` is allowed (Platform, paths) but its socket types are not.
    final sockets = findBannedSymbols(source);
    if (sockets.isNotEmpty) {
      failures.add('${entity.path} uses network symbols: $sockets');
    }
  }

  // A whitelist listing packages the app no longer uses is how this firewall
  // silently stopped protecting anything before; fail on drift in both
  // directions.
  final stale = findStaleWhitelistEntries(pubspec.readAsStringSync());
  if (stale.isNotEmpty) {
    failures.add('whitelist lists deps cold_signer no longer declares: $stale');
  }

  // Release/profile builds must be provably offline (no INTERNET). The debug
  // manifest is exempt (Flutter hot-reload needs it and never ships).
  for (final variant in ['main', 'profile']) {
    final manifest = File(
      'apps/cold_signer/android/app/src/$variant/AndroidManifest.xml',
    );
    if (manifest.existsSync() &&
        manifestDeclaresInternet(manifest.readAsStringSync())) {
      failures.add('cold_signer $variant AndroidManifest declares INTERNET');
    }
  }

  // The online wallet is the mirror image: it MUST declare INTERNET in the
  // shipping manifest. It shipped without it once, and because debug/profile
  // manifests carry the permission the gap only surfaced in release builds.
  final walletManifest = File(
    'apps/kt_wallet/android/app/src/main/AndroidManifest.xml',
  );
  if (walletManifest.existsSync() &&
      !manifestDeclaresInternet(walletManifest.readAsStringSync())) {
    failures.add('kt_wallet main AndroidManifest is missing INTERNET');
  }

  for (final manifest in [
    walletManifest,
    File('apps/cold_signer/android/app/src/main/AndroidManifest.xml'),
  ]) {
    if (!manifest.existsSync() ||
        !manifestHasFailClosedBackup(manifest.readAsStringSync())) {
      failures.add('${manifest.path} does not fail closed for Android backup');
    }
  }

  // Test-only process markers and constructor overrides must never enable a
  // process-local PIN/vault in profile or release builds. Keep both the
  // environment resolver and the final storage decision behind kDebugMode;
  // checking only one layer would let a future refactor re-open the fallback.
  for (final environmentBoundary in [
    File('apps/kt_wallet/lib/src/state/flutter_test_env.dart'),
    File('apps/cold_signer/lib/src/security/secure_vault.dart'),
  ]) {
    final source = environmentBoundary.existsSync()
        ? environmentBoundary.readAsStringSync()
        : '';
    if (!source.contains(
          "kDebugMode && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')",
        ) ||
        !source.contains('isDebugBuild && !isWeb && markerPresent')) {
      failures.add(
        '${environmentBoundary.path} can trust FLUTTER_TEST outside debug',
      );
    }
  }
  for (final storageBoundary in [
    File('apps/kt_wallet/lib/src/security/wallet_pin.dart'),
    File('apps/cold_signer/lib/src/security/secure_vault.dart'),
  ]) {
    final source = storageBoundary.existsSync()
        ? storageBoundary.readAsStringSync()
        : '';
    if (!source.contains(
      'kDebugMode && (_testEnvironmentOverride ?? isFlutterTestEnv)',
    )) {
      failures.add(
        '${storageBoundary.path} does not compile-time clamp test storage',
      );
    }
  }
  const testMarker = "Platform.environment.containsKey('FLUTTER_TEST')";
  const allowedTestMarkerFiles = {
    'apps/kt_wallet/lib/src/state/flutter_test_env.dart',
    'apps/cold_signer/lib/src/security/secure_vault.dart',
  };
  for (final app in ['apps/kt_wallet/lib', 'apps/cold_signer/lib']) {
    for (final entity in Directory(app).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains(testMarker) &&
          !allowedTestMarkerFiles.contains(entity.path)) {
        failures.add(
          '${entity.path} bypasses the compile-mode test-environment gate',
        );
      }
    }
  }

  for (final entitlements in [
    File('apps/kt_wallet/ios/Runner/Runner.entitlements'),
    File('apps/cold_signer/ios/Runner/Runner.entitlements'),
  ]) {
    final contents = entitlements.existsSync()
        ? entitlements.readAsStringSync()
        : '';
    if (!contents.contains('com.apple.developer.default-data-protection') ||
        !contents.contains('NSFileProtectionComplete')) {
      failures.add(
        '${entitlements.path} does not require complete iOS file protection',
      );
    }
  }

  for (final manifest in [
    File('apps/kt_wallet/ios/Runner/PrivacyInfo.xcprivacy'),
    File('apps/cold_signer/ios/Runner/PrivacyInfo.xcprivacy'),
    File(
      'packages/core_crypto/ios/core_crypto/Sources/core_crypto/PrivacyInfo.xcprivacy',
    ),
  ]) {
    final contents = manifest.existsSync() ? manifest.readAsStringSync() : '';
    if (!privacyManifestDeclaresAppScopedUserDefaults(contents)) {
      failures.add(
        '${manifest.path} is missing the app-scoped UserDefaults CA92.1 declaration',
      );
    }
  }

  final coreCryptoPodspec = File(
    'packages/core_crypto/ios/core_crypto.podspec',
  );
  final coreCryptoPackageSwift = File(
    'packages/core_crypto/ios/core_crypto/Package.swift',
  );
  if (!applePackageMetadataEmbedsPrivacyManifest(
    podspec: coreCryptoPodspec.existsSync()
        ? coreCryptoPodspec.readAsStringSync()
        : '',
    packageSwift: coreCryptoPackageSwift.existsSync()
        ? coreCryptoPackageSwift.readAsStringSync()
        : '',
  )) {
    failures.add(
      'core_crypto Apple package metadata does not safely embed PrivacyInfo.xcprivacy',
    );
  }

  // core_crypto declares Android API 24. The platform only guarantees the
  // PBKDF2WithHmacSHA256 SecretKeyFactory alias from API 26, so reintroducing
  // that otherwise-correct JCA call would make backup create/restore fail on
  // two supported Android releases. The portable implementation must retain
  // the API-23 HmacSHA256 primitive and explicit UTF-8 password bytes.
  final androidPortableBackup = File(
    'packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/PortableBackupCipher.kt',
  );
  final androidPortableSource = androidPortableBackup.existsSync()
      ? androidPortableBackup.readAsStringSync()
      : '';
  if (androidPortableSource.contains(
        'SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")',
      ) ||
      !androidPortableSource.contains('Mac.getInstance("HmacSHA256")') ||
      !androidPortableSource.contains('toByteArray(Charsets.UTF_8)')) {
    failures.add(
      '${androidPortableBackup.path} does not preserve the API-24 portable backup KDF',
    );
  }

  // Direct MethodChannel callers must not be able to crash the iOS process
  // with an unexpected runtime type. `as!` and force-unwrapped HDWallet
  // construction bypass Swift error handling entirely, so keep both out of
  // the native crypto boundary even though the Dart wrapper also validates.
  final appleCoreCryptoSources = Directory(
    'packages/core_crypto/ios/core_crypto/Sources/core_crypto',
  );
  if (!appleCoreCryptoSources.existsSync()) {
    failures.add('${appleCoreCryptoSources.path} is missing');
  } else {
    for (final entity in appleCoreCryptoSources.listSync()) {
      if (entity is! File || !entity.path.endsWith('.swift')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('as!')) {
        failures.add('${entity.path} contains a crashing Swift force cast');
      }
      for (final line in source.split('\n')) {
        if (line.contains('HDWallet(') && line.trimRight().endsWith('!')) {
          failures.add('${entity.path} force-unwraps HDWallet construction');
        }
      }
    }
  }
  final appleCoreCryptoPlugin = File(
    'packages/core_crypto/ios/core_crypto/Sources/core_crypto/CoreCryptoPlugin.swift',
  );
  final appleCoreCryptoPluginSource = appleCoreCryptoPlugin.existsSync()
      ? appleCoreCryptoPlugin.readAsStringSync()
      : '';
  for (final requiredBoundary in [
    'requireMnemonicStrength(a)',
    'requireSuggestionLimit(a)',
    'requireSupportedCoin(a)',
    'requireSigningInput(a)',
    'requireBackupBlob(a)',
    'requireBackupPassword(a)',
    'requireStoredWalletPayloadSize(stored)',
    'requireStoredWalletFlag(first)',
    'requireEntropySize(entropy)',
    'catch NativeArgumentValidationError.invalid',
  ]) {
    if (!appleCoreCryptoPluginSource.contains(requiredBoundary)) {
      failures.add(
        '${appleCoreCryptoPlugin.path} does not preserve native input boundary: '
        '$requiredBoundary',
      );
    }
  }
  final appleNativeArguments = File(
    'packages/core_crypto/ios/core_crypto/Sources/core_crypto/NativeArgumentValidation.swift',
  );
  final appleNativeArgumentsSource = appleNativeArguments.existsSync()
      ? appleNativeArguments.readAsStringSync()
      : '';
  for (final resourceBoundary in [
    'maxMnemonicUTF8Bytes = 512',
    'maxBackupPasswordUTF8Bytes = 4096',
    'maxSigningInputBytes = 1024 * 1024',
    'validBackupBlobSizes: Set<Int> = [60, 68, 76]',
    'supportedCoins: Set<String>',
    'validEntropySizes: Set<Int> = [16, 24, 32]',
    'validStoredWalletPayloadSizes: Set<Int> = [17, 25, 33, 61, 69, 77]',
  ]) {
    if (!appleNativeArgumentsSource.contains(resourceBoundary)) {
      failures.add(
        '${appleNativeArguments.path} does not preserve native resource bounds: '
        '$resourceBoundary',
      );
    }
  }
  final appleKeychainStore = File(
    'packages/core_crypto/ios/core_crypto/Sources/core_crypto/KeychainStore.swift',
  );
  final appleKeychainStoreSource = appleKeychainStore.existsSync()
      ? appleKeychainStore.readAsStringSync()
      : '';
  if (!appleKeychainStoreSource.contains('errSecDuplicateItem') ||
      !appleKeychainStoreSource.contains('StoreError.alreadyExists') ||
      appleKeychainStoreSource.contains('try? delete(walletId: walletId)')) {
    failures.add(
      '${appleKeychainStore.path} does not preserve create-only wallet storage',
    );
  }
  final androidCoreCryptoPlugin = File(
    'packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/CoreCryptoPlugin.kt',
  );
  final androidCoreCryptoPluginSource = androidCoreCryptoPlugin.existsSync()
      ? androidCoreCryptoPlugin.readAsStringSync()
      : '';
  for (final requiredBoundary in [
    'requireMnemonicStrength(call.argument<Any?>("strength"))',
    'requireSuggestionLimit(call.argument<Any?>("limit"))',
    'requireSupportedCoin(call.argument<Any?>("coin"))',
    'requireSigningInput(call.argument<Any?>("signingInput"))',
    'requireBackupBlob(call.argument<Any?>("blob"))',
    'requireBackupPassword(call.argument<Any?>("password"))',
    'requireStoredWalletFlag(stored[0].toInt())',
    'requireEntropySize(entropy)',
    'is InvalidNativeArgumentException -> "INVALID_INPUT"',
  ]) {
    if (!androidCoreCryptoPluginSource.contains(requiredBoundary)) {
      failures.add(
        '${androidCoreCryptoPlugin.path} does not preserve native input boundary: '
        '$requiredBoundary',
      );
    }
  }
  final androidNativeArguments = File(
    'packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/NativeArgumentValidation.kt',
  );
  final androidNativeArgumentsSource = androidNativeArguments.existsSync()
      ? androidNativeArguments.readAsStringSync()
      : '';
  for (final resourceBoundary in [
    'MAX_MNEMONIC_UTF8_BYTES = 512',
    'MAX_BACKUP_PASSWORD_UTF8_BYTES = 4096',
    'MAX_SIGNING_INPUT_BYTES = 1024 * 1024',
    'VALID_BACKUP_BLOB_SIZES = setOf(60, 68, 76)',
    'SUPPORTED_COINS = setOf(',
    'VALID_ENTROPY_SIZES = setOf(16, 24, 32)',
  ]) {
    if (!androidNativeArgumentsSource.contains(resourceBoundary)) {
      failures.add(
        '${androidNativeArguments.path} does not preserve native resource bounds: '
        '$resourceBoundary',
      );
    }
  }
  final androidBlobStore = File(
    'packages/core_crypto/android/src/main/kotlin/com/ktwallet/core_crypto/BlobStore.kt',
  );
  final androidBlobStoreSource = androidBlobStore.existsSync()
      ? androidBlobStore.readAsStringSync()
      : '';
  for (final createOnlyBoundary in [
    'fun writeNew(',
    'WalletAlreadyExistsException()',
    'fd.sync()',
    'temporary.renameTo(destination)',
    'VALID_STORED_BLOB_SIZES',
  ]) {
    if (!androidBlobStoreSource.contains(createOnlyBoundary)) {
      failures.add(
        '${androidBlobStore.path} does not preserve atomic create-only storage: '
        '$createOnlyBoundary',
      );
    }
  }
  for (final createOnlyBoundary in [
    'blobStore.exists(walletId) || keystore.exists(walletId)',
    'blobStore.writeNew(walletId, sealed)',
    'is WalletAlreadyExistsException -> "WALLET_EXISTS"',
  ]) {
    if (!androidCoreCryptoPluginSource.contains(createOnlyBoundary)) {
      failures.add(
        '${androidCoreCryptoPlugin.path} does not preserve create-only storage: '
        '$createOnlyBoundary',
      );
    }
  }

  // The Gradle configuration rejects release+stub today, and the artifact
  // guard must independently reject a future mixed build where the native
  // Wallet Core library is present but the Kotlin fail-closed bridge was
  // compiled. Keep its exact DEX marker part of the repository contract.
  const walletCoreStubMarker =
      'Trust Wallet Core is not linked in this build (walletCore=false)';
  final androidArtifactGuard = File('tool/check_release_artifact.sh');
  final androidArtifactGuardSource = androidArtifactGuard.existsSync()
      ? androidArtifactGuard.readAsStringSync()
      : '';
  if (!androidArtifactGuardSource.contains(walletCoreStubMarker)) {
    failures.add(
      '${androidArtifactGuard.path} does not reject the Wallet Core stub marker',
    );
  }
  final appleArtifactGuard = File('tool/check_apple_release_artifact.sh');
  final appleArtifactGuardSource = appleArtifactGuard.existsSync()
      ? appleArtifactGuard.readAsStringSync()
      : '';
  for (final signedAppleBoundary in [
    '--require-signed',
    'codesign --verify --deep --strict',
    'security cms -D -u 9',
    'certificate leaf = H',
    'DeveloperCertificates.',
    'embedded.mobileprovision',
    'Entitlements.application-identifier',
    'Entitlements.get-task-allow',
    'ProvisionedDevices.0',
    'ProvisionsAllDevices',
    r'Entitlements.com\.apple\.developer\.default-data-protection',
    r'com\.apple\.developer\.team-identifier',
    r'com\.apple\.developer\.default-data-protection',
    'NSFileProtectionComplete',
    'nested Apple code signer does not match the profile',
    'Apple artifact is not signed by a distribution identity',
  ]) {
    if (!appleArtifactGuardSource.contains(signedAppleBoundary)) {
      failures.add(
        '${appleArtifactGuard.path} is missing signed-artifact boundary: '
        '$signedAppleBoundary',
      );
    }
  }
  for (final credentialBoundary in [
    'github_pat_',
    'alch_',
    'xox[baprs]-',
    'sk_(live|test)_',
    'AIza',
    'access[_-]?token',
    'auth[_-]?token',
    'bearer[_-]?token',
    'client[_-]?secret',
    'credential|password|secret|token',
  ]) {
    if (!androidArtifactGuardSource.contains(credentialBoundary)) {
      failures.add(
        '${androidArtifactGuard.path} is missing credential boundary: '
        '$credentialBoundary',
      );
    }
    if (!appleArtifactGuardSource.contains(credentialBoundary)) {
      failures.add(
        '${appleArtifactGuard.path} is missing credential boundary: '
        '$credentialBoundary',
      );
    }
  }
  for (final requiredBundleGuard in [
    '*.aab) artifact_kind="aab"',
    'BundleConfig.pb',
    'android-release-toolchain.lock',
    'read_bundletool_version.dart',
    'producer toolchain version drift',
    'runtime dependency hashes verified',
    'bundletool validates the Android App Bundle',
    'AAB is intentionally unsigned; upload signing pending',
    'jar verified.',
    'incomplete signature metadata',
    'unsafe path or symbolic link',
  ]) {
    if (!androidArtifactGuardSource.contains(requiredBundleGuard)) {
      failures.add(
        '${androidArtifactGuard.path} does not preserve AAB guard: $requiredBundleGuard',
      );
    }
  }
  final androidReleaseToolchain = File('tool/android-release-toolchain.lock');
  final androidReleaseToolchainSource = androidReleaseToolchain.existsSync()
      ? androidReleaseToolchain.readAsStringSync()
      : '';
  final bundletoolVersionLocks = RegExp(
    r'^bundletool\.version=[0-9]+\.[0-9]+\.[0-9]+$',
    multiLine: true,
  ).allMatches(androidReleaseToolchainSource).length;
  final bundletoolHashLocks = RegExp(
    r'^bundletool\.sha256=[0-9a-f]{64}$',
    multiLine: true,
  ).allMatches(androidReleaseToolchainSource).length;
  if (bundletoolVersionLocks != 1 || bundletoolHashLocks != 1) {
    failures.add(
      '${androidReleaseToolchain.path} does not pin bundletool version and SHA-256',
    );
  }
  final bundletoolVersionReader = File('tool/read_bundletool_version.dart');
  final bundletoolVersionReaderSource = bundletoolVersionReader.existsSync()
      ? bundletoolVersionReader.readAsStringSync()
      : '';
  for (final parserBoundary in [
    'const _maxConfigBytes = 1024 * 1024',
    'field.number == 1',
    'field.number == 2',
    'allowMalformed: false',
    'protobuf varint overflow',
  ]) {
    if (!bundletoolVersionReaderSource.contains(parserBoundary)) {
      failures.add(
        '${bundletoolVersionReader.path} does not preserve parser boundary: $parserBoundary',
      );
    }
  }
  final bundletoolReaderTest = File('tool/test_bundletool_version_reader.sh');
  final bundletoolReaderTestSource = bundletoolReaderTest.existsSync()
      ? bundletoolReaderTest.readAsStringSync()
      : '';
  for (final negativeVector in [
    'truncated.pb',
    'duplicate.pb',
    'invalid-utf8.pb',
    'overflow.pb',
    'unsupported-wire.pb',
  ]) {
    if (!bundletoolReaderTestSource.contains(negativeVector)) {
      failures.add(
        '${bundletoolReaderTest.path} does not preserve vector: $negativeVector',
      );
    }
  }
  final dependencyAudit = File('tool/audit_dependencies.sh');
  final dependencyAuditSource = dependencyAudit.existsSync()
      ? dependencyAudit.readAsStringSync()
      : '';
  if (!dependencyAuditSource.contains('test_bundletool_version_reader.sh')) {
    failures.add(
      '${dependencyAudit.path} does not execute the bundletool parser vectors',
    );
  }
  if (!dependencyAuditSource.contains('test_prepare_ios_flutter_build.sh')) {
    failures.add(
      '${dependencyAudit.path} does not execute the stale Flutter target vectors',
    );
  }

  final iosFlutterBuildPreparation = File('tool/prepare_ios_flutter_build.sh');
  final iosFlutterBuildPreparationSource =
      iosFlutterBuildPreparation.existsSync()
      ? iosFlutterBuildPreparation.readAsStringSync()
      : '';
  for (final requiredBoundary in [
    '*/flutter_test_listener.*/listener.dart)',
    'export FLUTTER_TARGET=lib/main.dart',
    'unset DART_DEFINES',
    '[ ! -f "\$kt_generated_target" ]',
  ]) {
    if (!iosFlutterBuildPreparationSource.contains(requiredBoundary)) {
      failures.add(
        '${iosFlutterBuildPreparation.path} does not preserve boundary: '
        '$requiredBoundary',
      );
    }
  }
  const iosBuildPreparationInvocation =
      '. \\"\$SRCROOT/../../../tool/prepare_ios_flutter_build.sh\\"\\n'
      '/bin/sh \\"\$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\\" build';
  for (final app in ['kt_wallet', 'cold_signer']) {
    final project = File('apps/$app/ios/Runner.xcodeproj/project.pbxproj');
    final source = project.existsSync() ? project.readAsStringSync() : '';
    if (!source.contains(iosBuildPreparationInvocation)) {
      failures.add(
        '${project.path} does not sanitize stale Flutter test build settings',
      );
    }
  }
  final iosBuildPreparationTest = File(
    'tool/test_prepare_ios_flutter_build.sh',
  );
  if (!iosBuildPreparationTest.existsSync()) {
    failures.add('${iosBuildPreparationTest.path} is missing');
  } else {
    final result = Process.runSync('bash', [iosBuildPreparationTest.path]);
    if (result.exitCode != 0) {
      failures.add(
        '${iosBuildPreparationTest.path} behavior vectors failed '
        '(exit ${result.exitCode})',
      );
    }
  }

  // mobile_scanner 7.4.0 currently brings JUnit 6.1.2 into its own Android
  // unit-test classpath. These are not release-runtime dependencies, but an
  // unscoped Gradle test must still verify every byte before executing third-
  // party tests. Each value below was checked against Maven Central's official
  // SHA-256 sidecar, a fresh download, and the local Gradle cache on 2026-08-03.
  // Keep this narrow: only the 7 metadata files and 6 JARs the aggregate task
  // actually consumes are trusted.
  const junit612Artifacts = <String, String>{
    'junit-bom-6.1.2.module':
        '59ce085fd5b7e7d2c4b32ba99a3a3e1efff4179919f1e9d66c2de6ee77556478',
    'junit-jupiter-api-6.1.2.jar':
        'e60794b7d94e03c4bca1c0833cfca18762da5eaac0a61b16281cbbb708103e4c',
    'junit-jupiter-api-6.1.2.module':
        '29cf7ab684039d6f20b14b59ec8b7bf9c55f60c5ec94acdc5bbfc952ac653d09',
    'junit-jupiter-engine-6.1.2.jar':
        '57227ce289ed84ab205136997d2e5117f6cc695a16b7e235d59f70cdf33c3d7a',
    'junit-jupiter-engine-6.1.2.module':
        '8a639ab70ba02274bc5dde4f180768c27e30efa41e2d7179ed6af8462c321f6b',
    'junit-platform-commons-6.1.2.jar':
        '204894c039d321743ee11e7d1dc8360170d7c64391fbea1211178a645c33a92a',
    'junit-platform-commons-6.1.2.module':
        '58cad9d89b062df2cfa04decfbc9e6538a454cb57f56b21d62dfc084a9fab1cd',
    'junit-platform-engine-6.1.2.jar':
        '484e90828846ad6b88efe226b6fe014a75941b32b226e914d9a7758802f46f91',
    'junit-platform-engine-6.1.2.module':
        '3111841e3759acb6c96e9573d20c80443a905021a42ace89efede086b3549535',
    'junit-platform-launcher-6.1.2.jar':
        '858197212c1b2acc257c9eec9b450a31923c61c1bc61e66acf0057d57bbe577a',
    'junit-platform-launcher-6.1.2.module':
        'a7770594bda2aca4e0030dbb37ee5066760d719b3e40627ebe52189c50aa49f7',
    'junit-vintage-engine-6.1.2.jar':
        'ba1fe9a190b0a0758b342c964758c952674c1c9ad6f599856b3fcd63f66a4e91',
    'junit-vintage-engine-6.1.2.module':
        '600b160b9436a2d8ed91cc7d6488d8eaf6ae3c81cb101aae512c7b02b2abf987',
  };
  const junitOrigin = 'Maven Central official SHA-256 verified 2026-08-03';
  for (final metadata in [
    File('apps/kt_wallet/android/gradle/verification-metadata.xml'),
    File('apps/cold_signer/android/gradle/verification-metadata.xml'),
  ]) {
    final source = metadata.existsSync() ? metadata.readAsStringSync() : '';
    final issues = findReviewedArtifactPinIssues(
      source,
      junit612Artifacts,
      origin: junitOrigin,
    );
    if (issues.isNotEmpty) {
      failures.add('${metadata.path} JUnit 6.1.2 pin drift: $issues');
    }
  }

  // A cold-cache standalone Signer build reaches metadata variants that are
  // not necessarily requested by the combined wallet build. Keep the exact
  // Maven Central bytes pinned so a future metadata regeneration cannot hide
  // this clean-environment boundary or silently broaden trust.
  const coldSignerColdCacheArtifacts = <String, String>{
    'guava-parent-33.3.1-jre.pom':
        '55441db27e8869dfefe053059bdf478bdc7e95585642bf391f0023345fd56287',
    'kotlin-gradle-plugins-bom-2.2.0.module':
        'babd3c497a2971dfc68e50254ff97065a93a23183e8eda3c398f84f60cec12b2',
    'kotlin-gradle-plugins-bom-2.2.0.pom':
        'd9c45a2f5730e84e9b84fa42c64a1874dcba6668f212c4fe297bea25dc007878',
    'kotlinx-coroutines-bom-1.8.0.pom':
        '1239e9dbe1397cd5971342956b2511bc3ace7b641842e4372a088dcfa8b9ad55',
    'junit-bom-5.10.2.module':
        'de23b114b3e4119a8fe6eb17bed5a3852816698bace67071579d6d927ebb080a',
    'junit-bom-5.11.0-M2.module':
        '86477abcf490d6ca059aa9973cb108d22a506f49d1a5569bb32cc6cbf43c2cce',
  };
  const coldSignerColdCacheOrigin = 'Maven Central SHA-256 verified 2026-08-03';
  final coldSignerMetadata = File(
    'apps/cold_signer/android/gradle/verification-metadata.xml',
  );
  final coldSignerMetadataSource = coldSignerMetadata.existsSync()
      ? coldSignerMetadata.readAsStringSync()
      : '';
  final coldSignerColdCacheIssues = findReviewedArtifactPinIssues(
    coldSignerMetadataSource,
    coldSignerColdCacheArtifacts,
    origin: coldSignerColdCacheOrigin,
  );
  if (coldSignerColdCacheIssues.isNotEmpty) {
    failures.add(
      '${coldSignerMetadata.path} cold-cache pin drift: '
      '$coldSignerColdCacheIssues',
    );
  }

  for (final podfile in [
    File('apps/kt_wallet/ios/Podfile'),
    File('apps/cold_signer/ios/Podfile'),
  ]) {
    final contents = podfile.existsSync() ? podfile.readAsStringSync() : '';
    if (!podfileEnforcesIos13Floor(contents)) {
      failures.add('${podfile.path} does not enforce the iOS 13 Pod floor');
    }
  }

  for (final delegate in [
    File('apps/kt_wallet/ios/Runner/AppDelegate.swift'),
    File('apps/cold_signer/ios/Runner/AppDelegate.swift'),
  ]) {
    final contents = delegate.existsSync() ? delegate.readAsStringSync() : '';
    final excludesPersistentDirectories =
        contents.contains('values.isExcludedFromBackup = true') &&
        contents.contains('.documentDirectory') &&
        contents.contains('.libraryDirectory');
    if (!excludesPersistentDirectories) {
      failures.add(
        '${delegate.path} does not exclude local wallet state from iOS backup',
      );
    }
  }

  // Flutter and native localization are one release contract. Keep all three
  // catalogs structurally aligned and make English the safe fallback for an
  // unsupported device locale.
  for (final app in ['kt_wallet', 'cold_signer']) {
    final appRoot = 'apps/$app';
    final arbIssues = findArbCatalogIssues(
      {
        for (final locale in ['en', 'zh', 'ja'])
          locale: File('$appRoot/lib/l10n/app_$locale.arb').readAsStringSync(),
      },
      sameAsDefaultAllowedKeys: switch (app) {
        'kt_wallet' => const {
          'zh': {'txNonceLabel', 'rpcNotMeasured', 'chainIdLabel'},
          'ja': {
            'appName',
            'walletStateColdSigner',
            'txNonceLabel',
            'rpcNotMeasured',
            'chainIdLabel',
          },
        },
        'cold_signer' => const {
          'zh': {'chainIdLabel'},
          'ja': {'appName', 'checkBluetooth', 'chainIdLabel'},
        },
        _ => const {},
      },
      cjkAsciiPunctuationAllowedKeys: switch (app) {
        'kt_wallet' => const {
          'zh': {'approvalRevokeBody'},
        },
        'cold_signer' => const {
          'zh': {'approvalRevokeSignerNotice', 'unknownContractCallDesc'},
        },
        _ => const {},
      },
    );
    if (arbIssues.isNotEmpty) {
      failures.add('$app ARB localization drift: $arbIssues');
    }

    final brandIssues = findForbiddenLocalizationTermIssues(
      {
        for (final locale in ['en', 'zh', 'ja'])
          locale: File('$appRoot/lib/l10n/app_$locale.arb').readAsStringSync(),
      },
      switch (app) {
        'kt_wallet' => const {
          'en': {'KT Wallet Cold Signer'},
          'zh': {'KT Wallet Cold Signer', 'KT Cold Signer'},
          'ja': {'KT Wallet Cold Signer'},
        },
        'cold_signer' => const {
          'en': {'KT Wallet Cold Signer'},
          'zh': {'KT Wallet Cold Signer', 'KT Cold Signer'},
          'ja': {'KT Wallet Cold Signer'},
        },
        _ => const {},
      },
    );
    if (brandIssues.isNotEmpty) {
      failures.add('$app localized brand drift: $brandIssues');
    }

    final androidIssues = findAndroidStringResourceIssues({
      for (final qualifier in ['values', 'values-zh-rCN', 'values-ja'])
        qualifier: File(
          '$appRoot/android/app/src/main/res/$qualifier/strings.xml',
        ).readAsStringSync(),
    });
    if (androidIssues.isNotEmpty) {
      failures.add('$app Android localization drift: $androidIssues');
    }

    final requiredInfoPlistKeys = <String>{
      'CFBundleDisplayName',
      'CFBundleName',
      'NSCameraUsageDescription',
      'NSFaceIDUsageDescription',
      if (app == 'kt_wallet') 'NSPhotoLibraryAddUsageDescription',
    };
    final iosIssues = findInfoPlistStringsIssues({
      for (final locale in ['en', 'zh-Hans', 'ja'])
        locale: File(
          '$appRoot/ios/Runner/$locale.lproj/InfoPlist.strings',
        ).readAsStringSync(),
    }, requiredKeys: requiredInfoPlistKeys);
    if (iosIssues.isNotEmpty) {
      failures.add('$app iOS localization drift: $iosIssues');
    }
  }

  // Design fixtures are intentionally retained for goldens and the debug
  // screen gallery, but the shipped router must make them unreachable. Keep
  // the boundary as a repository gate as well as widget tests: a future
  // refactor must not silently remove the Debug-only clamp, pending-flow
  // checks, wallet identity checks, or camera simulation clamp.
  final walletRouter = File('apps/kt_wallet/lib/src/app_router.dart');
  final walletRouterSource = walletRouter.existsSync()
      ? walletRouter.readAsStringSync()
      : '';
  for (final productionBoundary in [
    'final effectiveGalleryMode = developerFixturesEnabled && galleryMode;',
    'required WalletController walletController',
    'walletController.pendingMnemonic == null',
    'currentWallet == null',
    "path == '/splash'",
    "path == '/wallet-detail'",
    '!walletController.wallets.any',
  ]) {
    if (!walletRouterSource.contains(productionBoundary)) {
      failures.add(
        '${walletRouter.path} does not preserve production fixture boundary: '
        '$productionBoundary',
      );
    }
  }
  final signerRouter = File('apps/cold_signer/lib/src/signer_router.dart');
  final signerRouterSource = signerRouter.existsSync()
      ? signerRouter.readAsStringSync()
      : '';
  for (final productionBoundary in [
    'SignerOnboardingStage.mnemonicReview',
    'SignerOnboardingStage.pinSetup',
    'SignerOnboardingStage.biometricSetup',
    'SignerOnboardingStage.completed',
    "'/created'",
    'extra is! WalletMetadata',
    'extra.walletId != currentWalletId',
  ]) {
    if (!signerRouterSource.contains(productionBoundary)) {
      failures.add(
        '${signerRouter.path} does not preserve signer onboarding route boundary: '
        '$productionBoundary',
      );
    }
  }
  final signerController = File(
    'apps/cold_signer/lib/src/state/signer_wallet_controller.dart',
  );
  final signerControllerSource = signerController.existsSync()
      ? signerController.readAsStringSync()
      : '';
  for (final productionBoundary in [
    'Future<List<String>>? _beginCreateInFlight',
    'Future<WalletMetadata>? _completeOnboardingInFlight',
    'void markMnemonicVerified(List<String> words)',
    "StateError('a wallet already exists')",
    'SignerOnboardingStage.biometricSetup',
  ]) {
    if (!signerControllerSource.contains(productionBoundary)) {
      failures.add(
        '${signerController.path} does not preserve atomic onboarding boundary: '
        '$productionBoundary',
      );
    }
  }
  final walletCamera = File(
    'apps/kt_wallet/lib/src/screens/camera_screen.dart',
  );
  final walletCameraSource = walletCamera.existsSync()
      ? walletCamera.readAsStringSync()
      : '';
  if (RegExp(
        r'onSimulatedScan:\s*developerFixturesEnabled\s*\?[^:]+:\s*null',
        dotAll: true,
      ).allMatches(walletCameraSource).length <
      2) {
    failures.add(
      '${walletCamera.path} does not clamp both live simulated scanners to Debug',
    );
  }
  if (!walletCameraSource.contains('if (!developerFixturesEnabled) return;') ||
      !walletCameraSource.contains(
        'developerFixturesEnabled\n      ? demoAccountExportFrames()\n      : const []',
      )) {
    failures.add(
      '${walletCamera.path} materializes or executes the account fixture outside Debug',
    );
  }
  final transferScreens = File(
    'apps/kt_wallet/lib/src/screens/transfer_screens.dart',
  );
  final transferScreensSource = transferScreens.existsSync()
      ? transferScreens.readAsStringSync()
      : '';
  if (!RegExp(
    r'onSimulatedTap:\s*developerFixturesEnabled\s*\?[^:]+:\s*null',
    dotAll: true,
  ).hasMatch(transferScreensSource)) {
    failures.add(
      '${transferScreens.path} does not detach simulated signing outside Debug',
    );
  }
  final historyService = File(
    'apps/kt_wallet/lib/src/market/history_service.dart',
  );
  final historyController = File(
    'apps/kt_wallet/lib/src/market/history_controller.dart',
  );
  final historySnapshot = File(
    'apps/kt_wallet/lib/src/market/history_snapshot.dart',
  );
  final historySources = {
    historyService.path: historyService.existsSync()
        ? historyService.readAsStringSync()
        : '',
    historyController.path: historyController.existsSync()
        ? historyController.readAsStringSync()
        : '',
    historySnapshot.path: historySnapshot.existsSync()
        ? historySnapshot.readAsStringSync()
        : '',
  };
  for (final boundary in const {
    'apps/kt_wallet/lib/src/market/history_service.dart': [
      'final String? networkId;',
      'String? networkId,',
      'record.onNetwork(networkId)',
      '_evmExplorerExecutionStatus',
      '_evmTokenTransferExecutionStatus',
      '_isEvmBlockHash',
      "item['hash'] ?? item['transactionHash']",
      "item['traceId'] ?? item['index'] ?? index",
      '_solanaExecutionStatus',
      '_tronContractExecutionStatus',
      '?limit=\$limit&only_confirmed=true',
    ],
    'apps/kt_wallet/lib/src/market/history_controller.dart': [
      'networkId: transaction.networkId',
      'networkId: _activeNetworkId?.call(coin)',
      'typedef _HistoryIdentity',
      'typedef _HistoryEventIdentity',
      '_recordIdentity(ChainTxRecord record)',
      '_recordEventIdentity(ChainTxRecord record)',
      '_transactionIdentity(db.Transaction transaction)',
      'coin == Coin.solana ? hash : hash.toLowerCase()',
      'localTransactionForRecord(ChainTxRecord record)',
      '_resolveRemoteStatuses(Set<ChainTxStatus> statuses)',
      'remoteTransactionStatuses',
      'remoteStatusesByIdentity',
      'remoteIdentities',
    ],
    'apps/kt_wallet/lib/src/market/history_snapshot.dart': [
      "'v': 3",
      "'networkId': record.networkId",
      "value['networkId']",
    ],
  }.entries) {
    for (final marker in boundary.value) {
      if (!(historySources[boundary.key] ?? '').contains(marker)) {
        failures.add(
          '${boundary.key} does not preserve history network identity: $marker',
        );
      }
    }
  }
  for (final failOpen in const [
    "item['isError'] != '1'",
    "item['err'] == null && meta['err'] == null",
    "data['rejected'] != true",
    'var confirmed = true',
  ]) {
    if (historySources[historyService.path]!.contains(failOpen)) {
      failures.add(
        '${historyService.path} treats missing execution evidence as success: '
        '$failOpen',
      );
    }
  }
  final gatewayHistorySources = {
    'backend/gateway/internal/handlers/history.go': File(
      'backend/gateway/internal/handlers/history.go',
    ).readAsStringSync(),
    'backend/gateway/internal/upstream/history.go': File(
      'backend/gateway/internal/upstream/history.go',
    ).readAsStringSync(),
  };
  for (final boundary in const {
    'backend/gateway/internal/handlers/history.go': [
      'EtherscanTokenExecutionStatus(t)',
      't.CanonicalHash()',
      't.CanonicalTraceID()',
    ],
    'backend/gateway/internal/upstream/history.go': [
      'func EtherscanTokenExecutionStatus',
      'BlockNumber',
      'BlockHash',
      'TransactionIndex',
      'Confirmations',
      'TransactionHash',
      'func (t EtherscanInternalTx) CanonicalHash()',
    ],
  }.entries) {
    for (final marker in boundary.value) {
      if (!(gatewayHistorySources[boundary.key] ?? '').contains(marker)) {
        failures.add(
          '${boundary.key} does not preserve indexed EVM history evidence: '
          '$marker',
        );
      }
    }
  }
  for (final marker in [
    '_networkForChainRecord(context, record)',
    'network.chain != chainOf(record.coin)',
    'final url = network == null ? null : explorerTxUrl(network, record.hash)',
  ]) {
    if (!transferScreensSource.contains(marker)) {
      failures.add(
        '${transferScreens.path} guesses a network for chain history: $marker',
      );
    }
  }
  final transactionStatusService = File(
    'apps/kt_wallet/lib/src/market/transaction_status_service.dart',
  );
  final transactionStatusSource = transactionStatusService.existsSync()
      ? transactionStatusService.readAsStringSync()
      : '';
  final marketScope = File('apps/kt_wallet/lib/src/market/market_scope.dart');
  final marketScopeSource = marketScope.existsSync()
      ? marketScope.readAsStringSync()
      : '';
  final gatewayClient = File(
    'apps/kt_wallet/lib/src/market/gateway_client.dart',
  );
  final gatewayClientSource = gatewayClient.existsSync()
      ? gatewayClient.readAsStringSync()
      : '';
  for (final marker in const [
    'TransactionNetworkEndpointResolver',
    'final persistedNetwork = transaction.networkId',
    'network: networkEndpoints == null ? null : persistedNetwork',
  ]) {
    if (!transactionStatusSource.contains(marker)) {
      failures.add(
        '${transactionStatusService.path} can query transaction finality on the active network: $marker',
      );
    }
  }
  for (final marker in const [
    'effectiveTransactionRpcEndpoints',
    'final network = networks.byId(networkId)',
    'if (network == null || network.chain != chain) return null',
  ]) {
    if (!marketScopeSource.contains(marker)) {
      failures.add(
        '${marketScope.path} does not resolve persisted transaction networks safely: $marker',
      );
    }
  }
  for (final marker in const [
    'String? networkOverride',
    'final id = networkOverride ?? _networks(chain)',
    'networkOverride: network',
  ]) {
    if (!gatewayClientSource.contains(marker)) {
      failures.add(
        '${gatewayClient.path} cannot override active network for transaction status: $marker',
      );
    }
  }
  for (final path in const [
    'apps/kt_wallet/lib/src/market/history_scope_host.dart',
    'apps/kt_wallet/lib/src/screens/home_screen.dart',
    'apps/kt_wallet/lib/src/screens/transfer_screens.dart',
  ]) {
    final file = File(path);
    final source = file.existsSync() ? file.readAsStringSync() : '';
    if (!source.contains('effectiveTransactionRpcEndpoints')) {
      failures.add('$path does not wire persisted-network status resolution');
    }
  }
  final historyFinalityController = File(
    'apps/kt_wallet/lib/src/market/history_controller.dart',
  );
  final historyFinalityControllerSource = historyFinalityController.existsSync()
      ? historyFinalityController.readAsStringSync()
      : '';
  for (final marker in const [
    'Future<List<db.Transaction>> _loadPendingTransactions()',
    'static const pendingStatusConcurrency = 4;',
    'await _forEachBounded(',
    'Do not even start a queued network lookup',
    'status = await _statusService.check(transaction);',
    'unknown evidence for this hash',
    '_wallets.localPendingTransactions()',
    'final statusFuture = _refreshPendingStatuses(',
    'pendingTransactions,',
    '_hasPendingTransactions = remainingPending.isNotEmpty',
    'updateTransactionStatusForWallet(',
    'walletId: transaction.walletId',
  ]) {
    if (!historyFinalityControllerSource.contains(marker)) {
      failures.add(
        '${historyFinalityController.path} can pause or mis-scope inactive-network finality: $marker',
      );
    }
  }
  for (final entry in const {
    'apps/kt_wallet/lib/src/market/market_controller.dart': [
      'if (id == null) {\n      _clearWalletState();',
      'void _clearWalletState()',
      'if (_disposed || !_canRefresh()) return;',
      'Supersede their callbacks so',
      '_generation++;',
      '_pricesUsd = null;',
    ],
    'apps/kt_wallet/lib/src/market/history_controller.dart': [
      'if (id == null) {\n      _clearWalletState();',
      'void _clearWalletState()',
      'Wallet/network identity changes are a synchronous privacy boundary.',
      '_generation++;',
      '_localTransactions = const [];',
      '_notices.clear();',
    ],
  }.entries) {
    final source = File(entry.key).readAsStringSync();
    for (final marker in entry.value) {
      if (!source.contains(marker)) {
        failures.add(
          '${entry.key} can retain deleted-wallet data after the final wallet is removed: $marker',
        );
      }
    }
  }
  for (final entry in const {
    'apps/kt_wallet/lib/src/market/market_controller.dart': [
      'display-only acceleration cache',
      'cannot remain on an infinite skeleton',
      "entry.value.status == BalanceStatus.loading\n              ? const BalanceResult.error()",
    ],
    'apps/kt_wallet/lib/src/market/history_controller.dart': [
      'Snapshot state is display-only.',
      'must not permanently latch refresh or',
      "entry.value.status == HistoryStatus.loading\n              ? const HistoryResult.error()",
      '_loadingMore = false;',
      'final (entries, _) = await (historyFuture, statusFuture).wait;',
      '_pollFailureCount++',
      '_schedulePoll(retryAfterFailure: true)',
      '1x/2x/4x/8x delay',
    ],
  }.entries) {
    final source = File(entry.key).readAsStringSync();
    for (final marker in entry.value) {
      if (!source.contains(marker)) {
        failures.add(
          '${entry.key} can latch a failed refresh/finality poll: $marker',
        );
      }
    }
  }
  final historyScopeHost = File(
    'apps/kt_wallet/lib/src/market/history_scope_host.dart',
  );
  final historyScopeHostSource = historyScopeHost.existsSync()
      ? historyScopeHost.readAsStringSync()
      : '';
  for (final marker in const [
    'onEvmNonceObserved: (transaction, nonce)',
    'setTransactionNonceIfAbsentForWallet(',
    'transaction.walletId',
  ]) {
    if (!historyScopeHostSource.contains(marker)) {
      failures.add(
        '${historyScopeHost.path} does not persist observed nonce in the originating wallet: $marker',
      );
    }
  }
  final walletRepository = File(
    'packages/wallet_data/lib/src/repositories.dart',
  );
  final walletRepositorySource = walletRepository.existsSync()
      ? walletRepository.readAsStringSync()
      : '';
  for (final marker in const [
    'Future<List<Transaction>> pendingTransactions()',
    't.hash.isNotNull()',
    'TxStatus.submitted.index',
    'TxStatus.broadcast.index',
    'TxStatus.pending.index',
  ]) {
    if (!walletRepositorySource.contains(marker)) {
      failures.add(
        '${walletRepository.path} lacks a wallet-scoped all-network pending query: $marker',
      );
    }
  }
  final walletController = File(
    'apps/kt_wallet/lib/src/state/wallet_controller.dart',
  );
  final walletControllerSource = walletController.existsSync()
      ? walletController.readAsStringSync()
      : '';
  for (final marker in const [
    'localPendingTransactions()',
    'updateTransactionStatusForWallet(',
    'setTransactionNonceIfAbsentForWallet(',
    'settleEvmTransactionForWallet(',
  ]) {
    if (!walletControllerSource.contains(marker)) {
      failures.add(
        '${walletController.path} can bind an awaited finality write to the selected wallet: $marker',
      );
    }
  }
  final homeScreen = File('apps/kt_wallet/lib/src/screens/home_screen.dart');
  final homeScreenSource = homeScreen.existsSync()
      ? homeScreen.readAsStringSync()
      : '';
  if (!homeScreenSource.contains('localTransactionForRecord(r)')) {
    failures.add(
      '${homeScreen.path} matches history rows to local transactions by hash only',
    );
  }
  final walletMain = File('apps/kt_wallet/lib/main.dart');
  final walletMainSource = walletMain.existsSync()
      ? walletMain.readAsStringSync()
      : '';
  for (final productionBoundary in [
    '_missingProductionController()',
    '!developerFixturesEnabled && controller.allowsTestBypass',
    'walletController: widget.controller',
  ]) {
    if (!walletMainSource.contains(productionBoundary)) {
      failures.add(
        '${walletMain.path} does not preserve production controller boundary: '
        '$productionBoundary',
      );
    }
  }

  // Profile builds are production-like. kReleaseMode is valid only where the
  // app reports its build classification; fixture, Gallery and simulated
  // success gates must depend on the central kDebugMode adapter instead.
  const allowedReleaseModeFiles = {
    'apps/kt_wallet/lib/src/observability/diagnostic_bundle.dart',
    'apps/kt_wallet/lib/src/observability/diagnostic_telemetry.dart',
  };
  for (final appLib in ['apps/kt_wallet/lib', 'apps/cold_signer/lib']) {
    for (final entity in Directory(appLib).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('kReleaseMode') &&
          !allowedReleaseModeFiles.contains(entity.path)) {
        failures.add(
          '${entity.path} treats Profile as a developer-fixture build',
        );
      }
    }
  }
  for (final developerMode in [
    File('apps/kt_wallet/lib/src/state/developer_mode.dart'),
    File('apps/cold_signer/lib/src/developer_mode.dart'),
  ]) {
    final source = developerMode.existsSync()
        ? developerMode.readAsStringSync()
        : '';
    if (!source.contains('developerFixturesEnabled => kDebugMode') ||
        !source.contains('isDebugBuild;')) {
      failures.add(
        '${developerMode.path} does not keep fixtures behind kDebugMode',
      );
    }
  }

  // Public-test readiness includes reviewable package contracts. Fail if a
  // generated Dart/Flutter template is reintroduced in package metadata.
  for (final entity in Directory('packages').listSync(recursive: true)) {
    if (entity is! File) continue;
    final basename = entity.uri.pathSegments.last;
    final isPackageMetadata =
        const {
          'README.md',
          'CHANGELOG.md',
          'pubspec.yaml',
        }.contains(basename) ||
        basename.endsWith('.podspec');
    if (!isPackageMetadata) continue;
    final file = entity;
    final placeholders = findDocumentationPlaceholders(file.readAsStringSync());
    if (placeholders.isNotEmpty) {
      failures.add('${file.path} contains template text: $placeholders');
    }
  }

  // The public status table and release report are safety-relevant evidence:
  // a stale Gateway version can make operators and testers reason about the
  // wrong cache, provider, privacy, or broadcast behavior. Bind every current
  // release marker to the single version declared by production code while
  // allowing older versions to remain in explicitly historical sections.
  final gatewayReleaseVersionIssues = findGatewayReleaseVersionIssues(
    gatewaySource: File(
      'backend/gateway/internal/handlers/gateway.go',
    ).readAsStringSync(),
    backendReadme: File('backend/gateway/README.md').readAsStringSync(),
    rootReadme: File('README.md').readAsStringSync(),
    readinessPlan: File('docs/P0_P1_TRUSTED_WALLET_PLAN.md').readAsStringSync(),
    htmlReport: File(
      'reports/p0-p1-wallet-audit-2026-07-31/index.html',
    ).readAsStringSync(),
  );
  for (final issue in gatewayReleaseVersionIssues) {
    failures.add('Gateway public release version drift: $issue');
  }

  // When a local funded E2E mnemonic exists, use it as a canary and reject any
  // exact disclosure in public text artifacts. Error output contains only the
  // leak category and file path, never the matched secret.
  final localCredential = File(
    'apps/kt_wallet/integration_test/.sepolia-e2e.json',
  );
  String? localMnemonic;
  if (localCredential.existsSync()) {
    final match = RegExp(
      '"$e2eMnemonicKey"\\s*:\\s*"([^"]+)"',
    ).firstMatch(localCredential.readAsStringSync());
    localMnemonic = match?.group(1);
  }
  for (final root in [
    File('README.md'),
    File('BUILDING.md'),
    File('PRIVACY_POLICY.md'),
    File('SECURITY.md'),
    Directory('docs'),
    Directory('reports'),
  ]) {
    final entities = root is File
        ? <FileSystemEntity>[root]
        : root.existsSync()
        ? (root as Directory).listSync(recursive: true)
        : const <FileSystemEntity>[];
    for (final entity in entities) {
      if (entity.path.endsWith('docs/TESTING_LOCAL.md') ||
          entity.path.endsWith('docs/BACKEND_DEPLOY_LOCAL.md')) {
        continue;
      }
      if (entity is! File ||
          !const ['.md', '.html', '.json', '.txt'].any(entity.path.endsWith)) {
        continue;
      }
      final labels = findE2eSecretLeakLabels(
        entity.readAsStringSync(),
        mnemonic: localMnemonic,
      );
      if (labels.isNotEmpty) {
        failures.add('${entity.path} contains sensitive material: $labels');
      }
    }
  }

  // Scan every tracked file plus every non-ignored untracked file that could
  // be committed. GitHub Push Protection scans tests and tooling too, so fake
  // provider fixtures must be assembled at runtime instead of exempting whole
  // test trees. `git ls-files` also keeps funded local credentials and private
  // runbooks out through the shared .gitignore contract.
  final publicFiles = Process.runSync('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  if (publicFiles.exitCode != 0) {
    failures.add('could not enumerate public repository files for secret scan');
  } else {
    final paths =
        '${publicFiles.stdout}'
            .split('\u0000')
            .where((path) => path.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    for (final path in paths) {
      if (!isE2eSecretScanTextPath(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final labels = findE2eSecretLeakLabels(
        file.readAsStringSync(),
        mnemonic: localMnemonic,
      );
      if (labels.isNotEmpty) {
        failures.add('$path contains public credential material: $labels');
      }
    }
  }

  // These local handoff files may contain funded test-key metadata or host
  // deployment details. Keep the policy in the shared .gitignore rather than
  // relying on one workstation's .git/info/exclude.
  final ignoredLocalRunbooks = {
    for (final line in File('.gitignore').readAsLinesSync()) line.trim(),
  };
  for (final path in const [
    'docs/TESTING_LOCAL.md',
    'docs/SIMULATOR_RECOVERY_LOCAL.md',
    'docs/BACKEND_DEPLOY_LOCAL.md',
  ]) {
    if (!ignoredLocalRunbooks.contains(path)) {
      failures.add('$path must remain in the shared .gitignore');
    }
  }

  // A developer may invoke an integration test directly and bypass the CLI
  // preflight. Keep the same freshness check inside every real-key entrypoint.
  final integrationTests = Directory('apps/kt_wallet/integration_test');
  for (final entity in integrationTests.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
    if (!realE2eEntrypointHasCredentialGuard(entity.readAsStringSync())) {
      failures.add(
        '${entity.path} reads the real E2E mnemonic without the batch guard',
      );
    }
  }

  // Real native E2E wallets must not survive a completed test run. Execute
  // the standalone audit here so the same rule is enforced by the repository
  // gate used in CI/release review, not only by a remembered manual command.
  final cleanupAudit = Process.runSync(Platform.resolvedExecutable, [
    'tool/audit_e2e_wallet_cleanup.dart',
  ]);
  if (cleanupAudit.exitCode != 0) {
    final details = '${cleanupAudit.stderr}'.trim();
    failures.add(
      'native E2E wallet cleanup audit failed'
      '${details.isEmpty ? '' : ': $details'}',
    );
  }

  // Gateway/RPC responses may provide data and additive warnings, but never
  // remotely weaken authentication, exact-transaction binding or signature
  // verification. Keep that ownership boundary in the same release gate as
  // the offline dependency firewall and native-key cleanup discipline.
  final remoteBoundaryAudit = Process.runSync(Platform.resolvedExecutable, [
    'tool/audit_remote_security_boundary.dart',
  ]);
  if (remoteBoundaryAudit.exitCode != 0) {
    final details = '${remoteBoundaryAudit.stderr}'.trim();
    failures.add(
      'remote security boundary audit failed'
      '${details.isEmpty ? '' : ': $details'}',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln('check_deps: OK');
    return;
  }
  for (final f in failures) {
    stderr.writeln('check_deps FAIL: $f');
  }
  // main() returning a non-zero int does NOT set the process exit code — must
  // call exit() explicitly or CI would pass despite violations.
  exit(1);
}
