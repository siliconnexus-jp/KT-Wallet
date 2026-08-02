package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class PortableBackupCipherTest {
    private val cipher = PortableBackupCipher()
    private val password = "Correct horse 電池🔐"
    private val salt = ByteArray(16) { it.toByte() }
    private val nonce = ByteArray(12) { (it + 16).toByte() }
    private val entropy = ByteArray(32) { it.toByte() }

    @Test
    fun `PBKDF2 key matches the independent UTF-8 test vector`() {
        assertEquals(
            "735fa3e610dae2d574d074ec8c0e4288209270c4f0ba8b8364dc27d1a76cfbf1",
            cipher.deriveKey(password, salt).toHex(),
        )
    }

    @Test
    fun `portable payload matches the independent AES-GCM test vector`() {
        val sealed = cipher.sealWithParameters(entropy, password, salt, nonce)
        assertEquals(
            "000102030405060708090a0b0c0d0e0f" +
                "101112131415161718191a1b" +
                "364a29004ca61dca69b29ce63afbfa7315822fc380f858634e289bbb5b33dd43" +
                "bf50be31944b5e4d9f6bbd81f23c53bc",
            sealed.toHex(),
        )
        assertContentEquals(entropy, cipher.open(sealed, password))
    }

    @Test
    fun `wrong password truncated and tampered payloads fail closed`() {
        val sealed = cipher.sealWithParameters(entropy, password, salt, nonce)
        assertFailsWith<PortableBackupCipher.OpenFailedException> {
            cipher.open(sealed, "wrong password")
        }
        assertFailsWith<PortableBackupCipher.OpenFailedException> {
            cipher.open(sealed.copyOf(44), password)
        }
        val tampered = sealed.copyOf().also {
            it[it.lastIndex] = (it.last().toInt() xor 1).toByte()
        }
        assertFailsWith<PortableBackupCipher.OpenFailedException> {
            cipher.open(tampered, password)
        }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
