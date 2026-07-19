package com.ktwallet.core_crypto

import android.content.Context
import java.io.File

/**
 * Persists the Keystore-sealed entropy blob. The blob is already AES-GCM
 * ciphertext produced by a non-exportable Keystore key, so the file itself
 * never contains plaintext key material (detailed-design.md §3.1). No mnemonic
 * or seed ever reaches this store.
 */
class BlobStore(context: Context) {
    private val dir = File(context.filesDir, "kt_entropy").apply { mkdirs() }

    private fun file(walletId: String) = File(dir, "$walletId.blob")

    fun write(walletId: String, blob: ByteArray) {
        file(walletId).writeBytes(blob)
    }

    fun read(walletId: String): ByteArray {
        val f = file(walletId)
        if (!f.exists()) throw WalletNotFoundException(walletId)
        return f.readBytes()
    }

    fun exists(walletId: String): Boolean = file(walletId).exists()

    /** Overwrites with zeros before deleting (best-effort scrub of ciphertext). */
    fun delete(walletId: String) {
        val f = file(walletId)
        if (f.exists()) {
            runCatching { f.writeBytes(ByteArray(f.length().toInt())) }
            f.delete()
        }
    }
}
