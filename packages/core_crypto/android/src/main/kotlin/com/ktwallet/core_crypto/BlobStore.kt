package com.ktwallet.core_crypto

import android.content.Context
import java.io.File

/**
 * Persists the Keystore-sealed entropy blob. The blob is already AES-GCM
 * ciphertext produced by a non-exportable Keystore key, so the file itself
 * never contains plaintext key material (detailed-design.md §3.1). No mnemonic
 * or seed ever reaches this store.
 */
class BlobStore internal constructor(private val dir: File) {
    companion object {
        // Keystore AES-GCM: iv(12) + (header(1) + entropy(16/24/32) + tag(16)),
        // or header + device-KDF(salt16 + iv12 + entropy + tag16).
        internal val VALID_STORED_BLOB_SIZES = setOf(45L, 53L, 61L, 89L, 97L, 105L)
    }
    constructor(context: Context) : this(File(context.filesDir, "kt_entropy"))

    init {
        if (!dir.exists() && !dir.mkdirs()) throw WalletStorageException()
        if (!dir.isDirectory) throw WalletStorageException()
    }

    private fun file(walletId: String): File {
        val safeWalletId = requireValidWalletId(walletId)
        return File(dir, "$safeWalletId.blob")
    }

    /** Creates a new ciphertext file without ever replacing an existing
     * wallet. The temporary file is fsynced and renamed within the same
     * directory, so a crash cannot expose a partially-written destination. */
    @Synchronized
    fun writeNew(walletId: String, blob: ByteArray) {
        if (blob.size.toLong() !in VALID_STORED_BLOB_SIZES) {
            throw StoredWalletCorruptedException()
        }
        val destination = file(walletId)
        if (destination.exists()) throw WalletAlreadyExistsException()
        val temporary = File.createTempFile(".pending-", ".blob", dir)
        try {
            temporary.outputStream().use { output ->
                output.write(blob)
                output.flush()
                output.fd.sync()
            }
            // The synchronized create-only check is repeated immediately
            // before rename. Never use a move primitive that replaces files.
            if (destination.exists()) throw WalletAlreadyExistsException()
            if (!temporary.renameTo(destination)) throw WalletStorageException()
        } finally {
            if (temporary.exists()) {
                runCatching { temporary.writeBytes(ByteArray(temporary.length().toInt())) }
                temporary.delete()
            }
        }
    }

    fun read(walletId: String): ByteArray {
        val f = file(walletId)
        if (!f.exists()) throw WalletNotFoundException(walletId)
        if (f.length() !in VALID_STORED_BLOB_SIZES) {
            throw StoredWalletCorruptedException()
        }
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

class WalletAlreadyExistsException : Exception("wallet already exists")
class WalletStorageException : Exception("wallet storage failed")
class StoredWalletCorruptedException : Exception("stored wallet corrupted")
