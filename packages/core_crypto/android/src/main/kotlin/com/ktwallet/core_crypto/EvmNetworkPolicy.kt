package com.ktwallet.core_crypto

import java.math.BigInteger

internal object EvmNetworkPolicy {
    private val domains = mapOf(
        1L to "eth", 11155111L to "eth", 137L to "polygon", 80002L to "polygon",
        8453L to "base", 84532L to "base", 42161L to "arbitrum", 421614L to "arbitrum",
        43114L to "avalanche", 43113L to "avalanche", 56L to "bnb", 97L to "bnb",
    )
    fun allows(coin: String, raw: ByteArray, allowUnknown: Boolean): Boolean {
        if (raw.isEmpty()) return false
        val id = BigInteger(1, raw)
        if (id.signum() <= 0) return false
        val expected = if (id.bitLength() <= 63) domains[id.toLong()] else null
        return if (expected == null) allowUnknown else expected == coin
    }
}
