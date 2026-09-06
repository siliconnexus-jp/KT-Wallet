package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class AuthenticatedReadTest {
    private class Expired : Exception()

    @Test fun `fresh authentication reads without extra prompt`() {
        var prompts = 0
        var completed = 0
        authenticatedRead({ 42 }, { it is Expired }, { prompts++ }, { completed = it })
        assertEquals(0, prompts)
        assertEquals(42, completed)
    }

    @Test fun `expired authentication retries only after successful provider callback`() {
        var reads = 0
        var prompts = 0
        var completed = 0
        authenticatedRead(
            { if (++reads == 1) throw Expired() else 42 },
            { it is Expired },
            { retry -> prompts++; completed = retry() },
            { completed = it },
        )
        assertEquals(2, reads)
        assertEquals(1, prompts)
        assertEquals(42, completed)
    }

    @Test fun `cancelled prompt never retries or reports a read`() {
        var reads = 0
        var completed = 0
        authenticatedRead<Int>({ reads++; throw Expired() }, { it is Expired }, {}, { completed++ })
        assertEquals(1, reads)
        assertEquals(0, completed)
    }

    @Test fun `corrupt storage is not treated as expired authentication`() {
        var prompts = 0
        assertFailsWith<IllegalStateException> {
            authenticatedRead<Int>({ throw IllegalStateException() }, { it is Expired }, { prompts++ }, {})
        }
        assertEquals(0, prompts)
    }

    @Test fun `a second expiry does not loop or bypass the key`() {
        var prompts = 0
        assertFailsWith<Expired> {
            authenticatedRead<Int>({ throw Expired() }, { it is Expired }, { retry -> prompts++; retry() }, {})
        }
        assertEquals(1, prompts)
    }
}
