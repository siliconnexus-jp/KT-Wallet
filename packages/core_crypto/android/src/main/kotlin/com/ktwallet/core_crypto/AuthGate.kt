package com.ktwallet.core_crypto

/** Persistence for the lockout counter so a process restart cannot reset it. */
interface AuthGateStore {
    var failCount: Int
    var lockedUntilMillis: Long
}

/** In-memory store for unit tests. */
class InMemoryAuthGateStore : AuthGateStore {
    override var failCount: Int = 0
    override var lockedUntilMillis: Long = 0
}

/**
 * Failure-lockout ladder (detailed-design.md §2.4). State is held in an
 * injected [AuthGateStore] so it survives process death in production
 * (SharedPreferences-backed) and stays deterministic in tests. The clock is
 * injectable for the same reason.
 */
class AuthGate(
    private val store: AuthGateStore = InMemoryAuthGateStore(),
    private val clockMillis: () -> Long = System::currentTimeMillis,
) {
    val failCount: Int get() = store.failCount

    class LockedException(val cooldownSec: Int) : Exception("auth locked")
    class FailedException : Exception("auth failed")

    fun cooldownFor(fails: Int): Int = when {
        fails >= 15 -> 900
        fails >= 10 -> 300
        fails >= 5 -> 60
        else -> 0
    }

    fun remainingCooldownSec(): Int {
        val remaining = ((store.lockedUntilMillis - clockMillis()) / 1000).toInt()
        return if (remaining > 0) remaining else 0
    }

    /** Call before a protected operation. Throws if cooling down. */
    fun ensureNotLocked() {
        val remaining = remainingCooldownSec()
        if (remaining > 0) throw LockedException(remaining)
    }

    fun onSuccess() {
        store.failCount = 0
        store.lockedUntilMillis = 0
    }

    /** Register a failed attempt; throws Locked or Failed accordingly. */
    fun onFailure() {
        store.failCount += 1
        val cd = cooldownFor(store.failCount)
        if (cd > 0) {
            store.lockedUntilMillis = clockMillis() + cd * 1000L
            throw LockedException(cd)
        }
        throw FailedException()
    }

    fun state(): Map<String, Any> {
        val remaining = remainingCooldownSec()
        return mapOf(
            "locked" to (remaining > 0),
            "failCount" to store.failCount,
            "cooldownSec" to remaining,
        )
    }
}
