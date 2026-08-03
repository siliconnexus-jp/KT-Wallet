package cc.siliconnexus.ktwallet

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemAuthPrivacyGuardTest {
    @Test
    fun suppressesDuringPromptAndDismissalAnimationOnly() {
        var now = 1_000L
        val guard = SystemAuthPrivacyGuard(clock = { now }, dismissalGraceMs = 500)

        assertFalse(guard.suppressesTaskPrivacyTransition())
        guard.started()
        assertTrue(guard.suppressesTaskPrivacyTransition())
        guard.finished()
        assertTrue(guard.suppressesTaskPrivacyTransition())
        now += 499
        assertTrue(guard.suppressesTaskPrivacyTransition())
        now += 1
        assertFalse(guard.suppressesTaskPrivacyTransition())
    }

    @Test
    fun nestedPromptsDoNotReleaseSuppressionEarly() {
        var now = 0L
        val guard = SystemAuthPrivacyGuard(clock = { now }, dismissalGraceMs = 10)
        guard.started()
        guard.started()
        guard.finished()
        now += 20
        assertTrue(guard.suppressesTaskPrivacyTransition())
        guard.finished()
        now += 10
        assertFalse(guard.suppressesTaskPrivacyTransition())
    }
}
