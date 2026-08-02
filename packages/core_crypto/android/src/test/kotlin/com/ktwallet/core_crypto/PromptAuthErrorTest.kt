package com.ktwallet.core_crypto

import androidx.biometric.BiometricPrompt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

class PromptAuthErrorTest {
    @Test
    fun `missing enrollment is unavailable, not a failed credential`() {
        assertEquals(
            PromptAuthDisposition.UNAVAILABLE,
            classifyPromptAuthError(BiometricPrompt.ERROR_NO_BIOMETRICS),
        )
        assertEquals(
            PromptAuthDisposition.UNAVAILABLE,
            classifyPromptAuthError(BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL),
        )
    }

    @Test
    fun `hardware and provider errors are unavailable`() {
        assertEquals(
            PromptAuthDisposition.UNAVAILABLE,
            classifyPromptAuthError(BiometricPrompt.ERROR_HW_NOT_PRESENT),
        )
        assertEquals(
            PromptAuthDisposition.UNAVAILABLE,
            classifyPromptAuthError(BiometricPrompt.ERROR_HW_UNAVAILABLE),
        )
        assertEquals(
            PromptAuthDisposition.UNAVAILABLE,
            classifyPromptAuthError(BiometricPrompt.ERROR_TIMEOUT),
        )
    }

    @Test
    fun `user and system cancellation stay non hostile`() {
        assertEquals(
            PromptAuthDisposition.CANCELLED,
            classifyPromptAuthError(BiometricPrompt.ERROR_USER_CANCELED),
        )
        assertEquals(
            PromptAuthDisposition.CANCELLED,
            classifyPromptAuthError(BiometricPrompt.ERROR_CANCELED),
        )
    }

    @Test
    fun `operating system lockout remains distinct`() {
        assertEquals(
            PromptAuthDisposition.SYSTEM_LOCKED,
            classifyPromptAuthError(BiometricPrompt.ERROR_LOCKOUT),
        )
        assertEquals(
            PromptAuthDisposition.SYSTEM_LOCKED,
            classifyPromptAuthError(BiometricPrompt.ERROR_LOCKOUT_PERMANENT),
        )
    }

    @Test
    fun `prompt startup failure completes through exactly one error callback`() {
        val expected = IllegalStateException("fragment state saved")
        var callbacks = 0
        var received: Exception? = null

        runPromptStart(
            start = { throw expected },
            onError = {
                callbacks += 1
                received = it
            },
        )

        assertEquals(1, callbacks)
        assertSame(expected, received)
    }

    @Test
    fun `successful prompt startup does not call error callback`() {
        var started = false
        var callbacks = 0

        runPromptStart(
            start = { started = true },
            onError = { callbacks += 1 },
        )

        assertEquals(true, started)
        assertEquals(0, callbacks)
    }
}
