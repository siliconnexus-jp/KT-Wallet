package cc.siliconnexus.ktwallet.coldsigner

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
        now += 500
        assertFalse(guard.suppressesTaskPrivacyTransition())
    }
}
