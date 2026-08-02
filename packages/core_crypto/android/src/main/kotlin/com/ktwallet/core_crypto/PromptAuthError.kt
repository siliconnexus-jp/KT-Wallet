package com.ktwallet.core_crypto

import androidx.biometric.BiometricPrompt

/**
 * A BiometricPrompt terminal error is not automatically a bad credential.
 *
 * Missing hardware, missing enrollment, provider timeouts and system lockout
 * are device/runtime states. Counting them in KT Wallet's persisted failure
 * ladder can lock an innocent user out without a single wrong credential.
 */
internal enum class PromptAuthDisposition {
    CANCELLED,
    UNAVAILABLE,
    SYSTEM_LOCKED,
}

internal fun classifyPromptAuthError(code: Int): PromptAuthDisposition = when (code) {
    BiometricPrompt.ERROR_USER_CANCELED,
    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
    BiometricPrompt.ERROR_CANCELED -> PromptAuthDisposition.CANCELLED

    BiometricPrompt.ERROR_LOCKOUT,
    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> PromptAuthDisposition.SYSTEM_LOCKED

    // Every remaining documented terminal error describes hardware,
    // enrollment, credential setup, timeout, capacity, vendor or security
    // state. Biometric mismatches arrive through onAuthenticationFailed(),
    // not this callback, and Android applies its own retry/lockout policy.
    else -> PromptAuthDisposition.UNAVAILABLE
}

/** Converts synchronous prompt construction/start failures into a terminal
 * callback so the Flutter MethodChannel cannot be left unresolved. */
internal fun runPromptStart(
    start: () -> Unit,
    onError: (Exception) -> Unit,
) {
    try {
        start()
    } catch (error: Exception) {
        onError(error)
    }
}
