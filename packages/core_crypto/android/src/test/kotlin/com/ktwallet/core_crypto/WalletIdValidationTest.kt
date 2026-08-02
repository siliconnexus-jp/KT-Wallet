package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class WalletIdValidationTest {
    @Test
    fun acceptsLegacyAndRandomUrlSafeIds() {
        val values = listOf(
            "daily",
            "WLT-3E8A91",
            "w_AAAAAAAAAAAAAAAAAAAAAAAA",
            "a_b-C9",
            "x".repeat(64),
        )
        values.forEach { assertEquals(it, requireValidWalletId(it)) }
    }

    @Test
    fun rejectsPathTraversalUnicodeMissingAndOversizedIds() {
        val values: List<Any?> = listOf(
            null,
            7,
            "",
            "../wallet",
            "wallet/child",
            "wallet.child",
            "wallet id",
            "钱包",
            "x".repeat(65),
        )
        values.forEach {
            assertFailsWith<InvalidWalletIdException> {
                requireValidWalletId(it)
            }
        }
    }
}
