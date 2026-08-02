package com.ktwallet.core_crypto

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFailsWith

class BlobStoreTest {
    @Test
    fun createOnlyWriteNeverReplacesExistingCiphertext() {
        val root = Files.createTempDirectory("kt-wallet-blob-store").toFile()
        try {
            val store = BlobStore(root)
            val original = ByteArray(45) { it.toByte() }
            store.writeNew("wallet_A", original)

            assertFailsWith<WalletAlreadyExistsException> {
                store.writeNew("wallet_A", ByteArray(45) { 9 })
            }
            assertContentEquals(original, store.read("wallet_A"))

            root.resolve("wallet_B.blob").writeBytes(ByteArray(44))
            assertFailsWith<StoredWalletCorruptedException> {
                store.read("wallet_B")
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
