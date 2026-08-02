package cc.siliconnexus.ktwallet

import android.os.SystemClock

/** Keeps the task privacy Activity away from an active system-auth window. */
internal class SystemAuthPrivacyGuard(
    private val clock: () -> Long = SystemClock::elapsedRealtime,
    private val dismissalGraceMs: Long = 1_500,
) {
    private var activeCount = 0
    private var suppressUntil = 0L

    @Synchronized
    fun started() {
        activeCount += 1
    }

    @Synchronized
    fun finished() {
        if (activeCount > 0) activeCount -= 1
        suppressUntil = maxOf(suppressUntil, clock() + dismissalGraceMs)
    }

    @Synchronized
    fun suppressesPrivacyActivity(): Boolean =
        activeCount > 0 || clock() < suppressUntil
}
