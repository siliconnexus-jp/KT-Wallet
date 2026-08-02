package com.ktwallet.core_crypto

/**
 * Optional host hook for apps that protect their task snapshot with a native
 * privacy Activity.
 *
 * Android may deliver `onUserLeaveHint()` while BiometricPrompt owns the
 * foreground window. A host that starts its privacy Activity at that moment
 * steals the FragmentActivity from BiometricPrompt and the crypto operation
 * never receives its result. Implementations use these callbacks only to
 * suppress that internal transition; they must not bypass authentication.
 */
interface CoreCryptoAuthLifecycleHost {
    fun onCoreCryptoAuthStarted()
    fun onCoreCryptoAuthFinished()
}
