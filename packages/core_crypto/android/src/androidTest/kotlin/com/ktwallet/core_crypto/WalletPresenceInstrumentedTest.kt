package com.ktwallet.core_crypto

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WalletPresenceInstrumentedTest {
    @Test
    fun presenceCheckDoesNotDecryptStoredWallet() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val walletId = "presence_${System.nanoTime()}"
        val blobStore = BlobStore(context)
        val keystore = KeystoreManager()

        try {
            // Production seals a one-byte format flag followed by entropy.
            val blob = keystore.seal(walletId, ByteArray(33) { it.toByte() }, false)
            blobStore.writeNew(walletId, blob)

            assertTrue(blobStore.exists(walletId))
            assertTrue(keystore.exists(walletId))
            assertFalse(blobStore.exists("missing_$walletId"))
            assertFalse(keystore.exists("missing_$walletId"))
        } finally {
            blobStore.delete(walletId)
            keystore.deleteKey(walletId)
        }
    }
}
