package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class BackupFormatSelectionTest {
    @Test
    fun `v2 uses portable cipher and never falls back`() {
        var legacyCalls = 0
        assertFailsWith<PortableBackupCipher.OpenFailedException> {
            openBackupPayload(
                formatVersion = 2,
                portableOpen = { throw PortableBackupCipher.OpenFailedException() },
                legacyOpen = {
                    legacyCalls++
                    byteArrayOf(9)
                },
            )
        }
        assertEquals(0, legacyCalls)
    }

    @Test
    fun `v1 prefers portable cipher for historical iOS-compatible files`() {
        var legacyCalls = 0
        val opened = openBackupPayload(
            formatVersion = 1,
            portableOpen = { byteArrayOf(1, 2) },
            legacyOpen = {
                legacyCalls++
                byteArrayOf(9)
            },
        )
        assertContentEquals(byteArrayOf(1, 2), opened)
        assertEquals(0, legacyCalls)
    }

    @Test
    fun `v1 falls back to historical Android Argon2 payload`() {
        var legacyCalls = 0
        val opened = openBackupPayload(
            formatVersion = 1,
            portableOpen = { throw PortableBackupCipher.OpenFailedException() },
            legacyOpen = {
                legacyCalls++
                byteArrayOf(7, 8)
            },
        )
        assertContentEquals(byteArrayOf(7, 8), opened)
        assertEquals(1, legacyCalls)
    }

    @Test
    fun `unknown version fails before either KDF runs`() {
        var portableCalls = 0
        var legacyCalls = 0
        assertFailsWith<BackupFormatVersionException> {
            openBackupPayload(
                formatVersion = 3,
                portableOpen = {
                    portableCalls++
                    byteArrayOf()
                },
                legacyOpen = {
                    legacyCalls++
                    byteArrayOf()
                },
            )
        }
        assertEquals(0, portableCalls)
        assertEquals(0, legacyCalls)
    }
}
