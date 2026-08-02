package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class NativeArgumentValidationTest {
    @Test
    fun acceptsExactMethodChannelTypesAndStrengths() {
        assertEquals("value", requireNativeString("value"))
        assertEquals("optional", optionalNativeString("optional"))
        assertNull(optionalNativeString(null))
        assertContentEquals(byteArrayOf(1, 2), requireNativeBytes(byteArrayOf(1, 2)))
        assertEquals(7, requireNativeInt(7))
        assertEquals(true, optionalNativeBoolean(true, false))
        assertEquals(false, optionalNativeBoolean(null, false))
        listOf(128, 192, 256).forEach { assertEquals(it, requireMnemonicStrength(it)) }
        assertEquals(1, requireSuggestionLimit(1))
        assertEquals(20, requireSuggestionLimit(20))
        assertEquals("eth", requireSupportedCoin("eth"))
        assertContentEquals(byteArrayOf(1), requireSigningInput(byteArrayOf(1)))
        assertContentEquals(ByteArray(60), requireBackupBlob(ByteArray(60)))
        assertEquals("password", requireBackupPassword("password"))
        assertEquals("123456", optionalKdfPassword("123456"))
        assertEquals(0, requireStoredWalletFlag(0))
        assertEquals(1, requireStoredWalletFlag(1))
        assertContentEquals(ByteArray(16), requireEntropySize(ByteArray(16)))
    }

    @Test
    fun rejectsWrongTypesAndUnsupportedStrengths() {
        val invalidCalls = listOf<() -> Unit>(
            { requireNativeString(null) },
            { requireNativeString(7) },
            { optionalNativeString(false) },
            { requireNativeBytes("bytes") },
            { requireNativeInt(true) },
            { optionalNativeBoolean("true", false) },
            { requireMnemonicStrength(129) },
            { requireMnemonicStrength("128") },
            { requireSuggestionLimit(0) },
            { requireSuggestionLimit(21) },
            { requireMnemonicText("") },
            { requireMnemonicText("x".repeat(MAX_MNEMONIC_UTF8_BYTES + 1)) },
            { requireWordText("x".repeat(MAX_WORD_UTF8_BYTES + 1)) },
            { requireSupportedCoin("bitcoin") },
            { requireSigningInput(ByteArray(0)) },
            { requireSigningInput(ByteArray(MAX_SIGNING_INPUT_BYTES + 1)) },
            { requireBackupBlob(ByteArray(59)) },
            { requireBackupBlob(ByteArray(61)) },
            { requireBackupPassword("") },
            { requireBackupPassword("x".repeat(MAX_BACKUP_PASSWORD_UTF8_BYTES + 1)) },
            { optionalKdfPassword("x".repeat(MAX_KDF_PASSWORD_UTF8_BYTES + 1)) },
        )
        invalidCalls.forEach { call ->
            assertFailsWith<InvalidNativeArgumentException> { call() }
        }
        listOf(-1, 2, 255).forEach { flag ->
            assertFailsWith<StoredWalletCorruptedException> {
                requireStoredWalletFlag(flag)
            }
        }
        listOf(0, 15, 17, 23, 25, 31, 33).forEach { size ->
            assertFailsWith<StoredWalletCorruptedException> {
                requireEntropySize(ByteArray(size))
            }
        }
    }
}
