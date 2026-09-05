package com.ktwallet.core_crypto

/** Deliberately narrow: only the online wallet or offline signer's debug build on an Android
 * SDK emulator may use a separate, non-auth-bound TEST vault. Unknown devices
 * and all production/profile builds retain normal authentication. */
internal fun useEmulatorTestVault(
    debugBuild: Boolean,
    buildType: String,
    debuggableApp: Boolean,
    packageName: String,
    hardware: String,
    model: String,
    fingerprint: String,
): Boolean = debugBuild && buildType == "debug" && debuggableApp &&
    packageName in setOf("cc.siliconnexus.ktwallet", "cc.siliconnexus.ktwallet.coldsigner") &&
    hardware in setOf("ranchu", "goldfish") &&
    (model.startsWith("sdk_gphone") || model.startsWith("Android SDK built for")) &&
    (fingerprint.startsWith("google/sdk_gphone") || fingerprint.startsWith("generic/"))
