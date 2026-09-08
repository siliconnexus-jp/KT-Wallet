package com.ktwallet.core_crypto

import java.math.BigInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EvmNetworkPolicyTest {
    @Test fun bindsAllKnownNetworksAndRejectsOfflineUnknowns() {
        val pairs = mapOf(1L to "eth",11155111L to "eth",137L to "polygon",80002L to "polygon",
          8453L to "base",84532L to "base",42161L to "arbitrum",421614L to "arbitrum",
          43114L to "avalanche",43113L to "avalanche",56L to "bnb",97L to "bnb")
        for ((id, expected) in pairs) for (coin in pairs.values.toSet()) {
            assertEquals(expected == coin, EvmNetworkPolicy.allows(coin, BigInteger.valueOf(id).toByteArray(), false))
        }
        assertFalse(EvmNetworkPolicy.allows("bnb", byteArrayOf(1), true))
        assertFalse(EvmNetworkPolicy.allows("eth", byteArrayOf(127), false))
        assertTrue(EvmNetworkPolicy.allows("eth", byteArrayOf(127), true))
        assertFalse(EvmNetworkPolicy.allows("eth", byteArrayOf(0), true))
    }
}
