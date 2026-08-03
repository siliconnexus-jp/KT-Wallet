package cc.siliconnexus.ktwallet.coldsigner

import android.os.SystemClock

/** Prevents a biometric prompt transition from being mistaken for app exit. */
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
    fun suppressesTaskPrivacyTransition(): Boolean =
        activeCount > 0 || clock() < suppressUntil
}
