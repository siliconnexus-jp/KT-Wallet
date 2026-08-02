package com.ktwallet.core_crypto

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.BadPaddingException
import javax.crypto.IllegalBlockSizeException
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM entropy sealing backed by the Android Keystore (StrongBox when
 * available, TEE otherwise). The key is non-exportable and — when [requireAuth]
 * — bound to device credentials, invalidated on new biometric enrollment
 * (detailed-design.md §3.1). Stored blob layout: iv(12) || ciphertext+tag.
 */
class KeystoreManager {
    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS_PREFIX = "kt_entropy_"
        private const val IV_LENGTH = 12
        private const val TAG_LENGTH_BITS = 128
        private const val AUTH_VALIDITY_SECONDS = 30
    }

    private fun alias(walletId: String) = "$KEY_ALIAS_PREFIX$walletId"

    fun exists(walletId: String): Boolean {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return keyStore.containsAlias(alias(requireValidWalletId(walletId)))
    }

    private fun getOrCreateKey(walletId: String, requireAuth: Boolean): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(alias(walletId), null) as? KeyStore.SecretKeyEntry)
            ?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val builder = KeyGenParameterSpec.Builder(
            alias(walletId),
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
        if (requireAuth) {
            builder.setUserAuthenticationRequired(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setUserAuthenticationParameters(
                    AUTH_VALIDITY_SECONDS,
                    KeyProperties.AUTH_BIOMETRIC_STRONG or
                        KeyProperties.AUTH_DEVICE_CREDENTIAL,
                )
            } else {
                @Suppress("DEPRECATION")
                builder.setUserAuthenticationValidityDurationSeconds(
                    AUTH_VALIDITY_SECONDS,
                )
            }
            builder.setInvalidatedByBiometricEnrollment(true)
        }
        runCatching { builder.setIsStrongBoxBacked(true) } // TEE fallback below
        return try {
            generator.init(builder.build())
            generator.generateKey()
        } catch (_: Exception) {
            builder.setIsStrongBoxBacked(false)
            generator.init(builder.build())
            generator.generateKey()
        }
    }

    fun seal(walletId: String, entropy: ByteArray, requireAuth: Boolean): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey(walletId, requireAuth))
        val ciphertext = cipher.doFinal(entropy)
        return cipher.iv + ciphertext
    }

    /** Requires an already-authenticated context on the calling thread when the
     *  key is auth-bound; the BiometricPrompt supplies it. */
    fun open(walletId: String, blob: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = keyStore.getEntry(alias(walletId), null) as? KeyStore.SecretKeyEntry
            ?: throw WalletNotFoundException(walletId)
        val iv = blob.copyOfRange(0, IV_LENGTH)
        val ciphertext = blob.copyOfRange(IV_LENGTH, blob.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            entry.secretKey,
            GCMParameterSpec(TAG_LENGTH_BITS, iv),
        )
        return try {
            cipher.doFinal(ciphertext)
        } catch (_: BadPaddingException) {
            throw StoredWalletCorruptedException()
        } catch (_: IllegalBlockSizeException) {
            throw StoredWalletCorruptedException()
        } finally {
            iv.fill(0)
            ciphertext.fill(0)
        }
    }

    fun deleteKey(walletId: String) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(alias(walletId))) {
            keyStore.deleteEntry(alias(walletId))
        }
    }
}

class WalletNotFoundException(walletId: String) :
    Exception("wallet not found: $walletId")
