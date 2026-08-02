package com.ktwallet.core_crypto

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Device test because Argon2Kt loads its Android JNI library at runtime. */
@RunWith(AndroidJUnit4::class)
class LegacyBackupCompatibilityInstrumentedTest {
    @Test
    fun testPortableUnicodeVectorMatchesOnAndroidRuntime() {
        val entropy = ByteArray(32) { it.toByte() }
        val salt = ByteArray(16) { it.toByte() }
        val nonce = ByteArray(12) { (it + 16).toByte() }
        val cipher = PortableBackupCipher()

        val sealed = cipher.sealWithParameters(
            entropy = entropy,
            password = "Correct horse 電池🔐",
            salt = salt,
            nonce = nonce,
        )

        assertEquals(
            "000102030405060708090a0b0c0d0e0f" +
                "101112131415161718191a1b" +
                "364a29004ca61dca69b29ce63afbfa7315822fc380f858634e289bbb5b33dd43" +
                "bf50be31944b5e4d9f6bbd81f23c53bc",
            sealed.toHex(),
        )
        assertTrue(entropy.contentEquals(cipher.open(sealed, "Correct horse 電池🔐")))

        sealed.fill(0)
        entropy.fill(0)
        salt.fill(0)
        nonce.fill(0)
    }

    @Test
    fun testActualHistoricalAndroidPayloadRemainsRestorable() {
        val entropy = ByteArray(32) { it.toByte() }
        val password = "legacy Android backup"
        val legacyCipher = EntropyCipher()
        val legacyBlob = legacyCipher.seal(entropy, password)
        val portableCipher = PortableBackupCipher()

        val opened = openBackupPayload(
            formatVersion = 1,
            portableOpen = { portableCipher.open(legacyBlob, password) },
            legacyOpen = { legacyCipher.open(legacyBlob, password) },
        )

        assertTrue(entropy.contentEquals(opened))
        opened.fill(0)
        entropy.fill(0)
        legacyBlob.fill(0)
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
