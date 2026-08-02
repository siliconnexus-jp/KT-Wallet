package com.ktwallet.core_crypto

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cross-platform KT backup payload cipher.
 *
 * Layout: salt(16) || nonce(12) || ciphertext || GCM tag(16). The password is
 * PBKDF2-HMAC-SHA256/210000 over UTF-8 bytes into 32 bytes.
 * Keep this separate from [EntropyCipher]: that Argon2id layer protects
 * device-local Cold Signer storage and is intentionally not a portable file
 * format.
 */
internal class PortableBackupCipher(
    private val random: SecureRandom = SecureRandom(),
) {
    companion object {
        internal const val SALT_LENGTH = 16
        internal const val NONCE_LENGTH = 12
        internal const val TAG_BITS = 128
        internal const val PBKDF2_ROUNDS = 210_000
        internal const val KEY_BITS = 256
    }

    internal class OpenFailedException : Exception("portable backup open failed")

    fun seal(entropy: ByteArray, password: String): ByteArray {
        require(entropy.isNotEmpty())
        require(password.isNotEmpty())
        val salt = ByteArray(SALT_LENGTH).also(random::nextBytes)
        val nonce = ByteArray(NONCE_LENGTH).also(random::nextBytes)
        return try {
            sealWithParameters(entropy, password, salt, nonce)
        } finally {
            salt.fill(0)
            nonce.fill(0)
        }
    }

    internal fun sealWithParameters(
        entropy: ByteArray,
        password: String,
        salt: ByteArray,
        nonce: ByteArray,
    ): ByteArray {
        require(entropy.isNotEmpty())
        require(password.isNotEmpty())
        require(salt.size == SALT_LENGTH)
        require(nonce.size == NONCE_LENGTH)
        val saltCopy = salt.copyOf()
        val nonceCopy = nonce.copyOf()
        val key = deriveKey(password, saltCopy)
        var ciphertext = ByteArray(0)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.ENCRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, nonceCopy),
            )
            ciphertext = cipher.doFinal(entropy)
            saltCopy + nonceCopy + ciphertext
        } finally {
            key.fill(0)
            saltCopy.fill(0)
            nonceCopy.fill(0)
            ciphertext.fill(0)
        }
    }

    fun open(blob: ByteArray, password: String): ByteArray {
        if (blob.size <= SALT_LENGTH + NONCE_LENGTH + TAG_BITS / 8 || password.isEmpty()) {
            throw OpenFailedException()
        }
        val salt = blob.copyOfRange(0, SALT_LENGTH)
        val nonce = blob.copyOfRange(SALT_LENGTH, SALT_LENGTH + NONCE_LENGTH)
        val ciphertext = blob.copyOfRange(SALT_LENGTH + NONCE_LENGTH, blob.size)
        val key = try {
            deriveKey(password, salt)
        } catch (_: Exception) {
            throw OpenFailedException()
        }
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, nonce),
            )
            cipher.doFinal(ciphertext)
        } catch (_: Exception) {
            throw OpenFailedException()
        } finally {
            key.fill(0)
            salt.fill(0)
            nonce.fill(0)
            ciphertext.fill(0)
        }
    }

    internal fun deriveKey(password: String, salt: ByteArray): ByteArray {
        require(salt.size == SALT_LENGTH)
        val passwordBytes = password.toByteArray(Charsets.UTF_8)
        val blockInput = ByteArray(salt.size + 4)
        salt.copyInto(blockInput)
        // PBKDF2 block indices are unsigned 32-bit, big-endian values. The
        // requested 32-byte key is exactly one HMAC-SHA256 block.
        blockInput[blockInput.lastIndex] = 1
        var u = ByteArray(0)
        var next = ByteArray(0)
        var derived = ByteArray(0)
        var completed = false
        return try {
            // Android only guarantees SecretKeyFactory's
            // PBKDF2WithHmacSHA256 alias from API 26. HmacSHA256 itself is
            // guaranteed from API 23, so perform the RFC 8018 loop directly
            // to keep this package's declared minSdk 24 honest without
            // changing the portable file format.
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(passwordBytes, "HmacSHA256"))
            u = mac.doFinal(blockInput)
            check(u.size * 8 == KEY_BITS)
            derived = u.copyOf()
            next = ByteArray(u.size)
            repeat(PBKDF2_ROUNDS - 1) {
                mac.update(u)
                mac.doFinal(next, 0)
                for (index in derived.indices) {
                    derived[index] =
                        (derived[index].toInt() xor next[index].toInt()).toByte()
                }
                u.fill(0)
                val previous = u
                u = next
                next = previous
            }
            completed = true
            derived
        } finally {
            passwordBytes.fill(0)
            blockInput.fill(0)
            u.fill(0)
            next.fill(0)
            if (!completed) derived.fill(0)
        }
    }
}
