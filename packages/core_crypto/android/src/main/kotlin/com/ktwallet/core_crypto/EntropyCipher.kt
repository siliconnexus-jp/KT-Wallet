package com.ktwallet.core_crypto

import com.lambdapioneer.argon2kt.Argon2Kt
import com.lambdapioneer.argon2kt.Argon2Mode
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cold Signer second encryption layer (detailed-design.md §3.3): the app
 * password is stretched with Argon2id and used to AES-GCM seal the entropy
 * before it enters the Keystore layer. Blob: salt(16) || iv(12) || ct+tag.
 */
class EntropyCipher(private val argon2: Argon2Kt = Argon2Kt()) {
    companion object {
        private const val SALT_LEN = 16
        private const val IV_LEN = 12
        private const val TAG_BITS = 128
        private const val MEM_KIB = 65536 // 64 MB
        private const val ITERATIONS = 3
        private const val PARALLELISM = 4
    }

    class OpenFailedException : Exception("kdf layer open failed")

    private fun deriveKey(password: String, salt: ByteArray): ByteArray {
        val hash = argon2.hash(
            mode = Argon2Mode.ARGON2_ID,
            password = password.toByteArray(Charsets.UTF_8),
            salt = salt,
            tCostInIterations = ITERATIONS,
            mCostInKibibyte = MEM_KIB,
            parallelism = PARALLELISM,
            hashLengthInBytes = 32,
        )
        return hash.rawHashAsByteArray()
    }

    fun seal(entropy: ByteArray, password: String): ByteArray {
        val salt = ByteArray(SALT_LEN).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(password, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        val ct = cipher.doFinal(entropy)
        key.fill(0)
        return salt + cipher.iv + ct
    }

    fun open(blob: ByteArray, password: String): ByteArray {
        if (blob.size <= SALT_LEN + IV_LEN) throw OpenFailedException()
        val salt = blob.copyOfRange(0, SALT_LEN)
        val iv = blob.copyOfRange(SALT_LEN, SALT_LEN + IV_LEN)
        val ct = blob.copyOfRange(SALT_LEN + IV_LEN, blob.size)
        val key = deriveKey(password, salt)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, iv),
            )
            cipher.doFinal(ct)
        } catch (_: Exception) {
            throw OpenFailedException()
        } finally {
            key.fill(0)
        }
    }
}
