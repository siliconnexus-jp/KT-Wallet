package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EmulatorAuthPolicyTest {
    private fun policy(
        debug: Boolean = true,
        buildType: String = "debug",
        debuggable: Boolean = true,
        pkg: String = "cc.siliconnexus.ktwallet",
        hardware: String = "ranchu",
        model: String = "sdk_gphone64_arm64",
        fingerprint: String = "google/sdk_gphone64_arm64/emu64a:15/test",
    ) = useEmulatorTestVault(debug, buildType, debuggable, pkg, hardware, model, fingerprint)

    @Test fun `debug Android SDK emulator defaults to test vault`() {
        assertTrue(policy())
        assertTrue(policy(hardware = "goldfish", model = "Android SDK built for x86", fingerprint = "generic/sdk/test"))
    }

    @Test fun `release and profile cannot bypass even on emulator`() {
        // Flutter's profile library reports DEBUG=true, so build type must
        // also be checked rather than trusting DEBUG alone.
        assertFalse(policy(buildType = "profile"))
        assertFalse(policy(buildType = "release"))
        assertFalse(policy(buildType = "unknown"))
        assertFalse(policy(debug = false))
        assertFalse(policy(debuggable = false))
        assertFalse(policy(debug = false, debuggable = false))
    }

    @Test fun `real or unrecognized hardware never bypasses`() {
        assertFalse(policy(hardware = "tensor", model = "Pixel 9", fingerprint = "google/tokay/test"))
        assertFalse(policy(hardware = "tensor"))
        assertFalse(policy(model = "Pixel 9"))
        assertFalse(policy(fingerprint = "unknown"))
        assertFalse(policy(hardware = "", model = "", fingerprint = ""))
    }

    @Test fun `offline signer and other hosts never bypass`() {
        assertFalse(policy(pkg = "cc.siliconnexus.ktwallet.coldsigner"))
        assertFalse(policy(pkg = "example.app"))
    }
}
