package com.ktwallet.core_crypto

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pure-JVM verification of the lockout ladder (detailed-design.md §2.4). No
 * Android framework needed — the clock is injected. Mirrors the Dart mock
 * ladder tests in core_crypto_test.dart.
 */
class AuthGateTest {
    private var now = 0L
    private fun gate() = AuthGate(InMemoryAuthGateStore()) { now }

    @Test
    fun `lockout survives via injected store (process-restart simulation)`() {
        val store = InMemoryAuthGateStore()
        repeat(4) { runCatching { AuthGate(store) { now }.onFailure() } }
        runCatching { AuthGate(store) { now }.onFailure() } // 5th → lock
        // A fresh gate over the same store still sees the lock.
        val restarted = AuthGate(store) { now }
        assertEquals(5, restarted.failCount)
        assertTrue(restarted.state()["locked"] as Boolean)
    }

    @Test
    fun `cooldown ladder maps fail count to 0-60-300-900`() {
        val g = gate()
        assertEquals(0, g.cooldownFor(4))
        assertEquals(60, g.cooldownFor(5))
        assertEquals(60, g.cooldownFor(9))
        assertEquals(300, g.cooldownFor(10))
        assertEquals(900, g.cooldownFor(15))
        assertEquals(900, g.cooldownFor(999))
    }

    @Test
    fun `first four failures throw Failed, fifth locks for 60s`() {
        val g = gate()
        repeat(4) { assertFailsWith<AuthGate.FailedException> { g.onFailure() } }
        val locked = assertFailsWith<AuthGate.LockedException> { g.onFailure() }
        assertEquals(60, locked.cooldownSec)
        assertTrue(g.state()["locked"] as Boolean)
        assertEquals(5, g.state()["failCount"])
    }

    @Test
    fun `ensureNotLocked throws during cooldown with countdown`() {
        val g = gate()
        repeat(4) { runCatching { g.onFailure() } }
        runCatching { g.onFailure() } // locks 60s
        now += 30_000
        val e = assertFailsWith<AuthGate.LockedException> { g.ensureNotLocked() }
        assertEquals(30, e.cooldownSec)
    }

    @Test
    fun `ladder escalates 60 to 300 to 900 across cooldowns`() {
        val g = gate()
        fun failPastCooldown() { now += 3_600_000; runCatching { g.onFailure() } }
        repeat(5) { failPastCooldown() }
        assertEquals(60, g.state()["cooldownSec"])
        repeat(5) { failPastCooldown() }
        assertEquals(300, g.state()["cooldownSec"])
        repeat(5) { failPastCooldown() }
        assertEquals(900, g.state()["cooldownSec"])
    }

    @Test
    fun `success resets counter and unlocks`() {
        val g = gate()
        repeat(3) { runCatching { g.onFailure() } }
        assertEquals(3, g.failCount)
        g.onSuccess()
        assertEquals(0, g.failCount)
        assertFalse(g.state()["locked"] as Boolean)
    }
}
