package cc.siliconnexus.ktwallet

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TaskPrivacyStateTest {
    @Test
    fun `temporary system overlays do not hide the live app`() {
        val state = TaskPrivacyState()

        state.onPause()

        assertFalse(state.shouldProtect())
    }

    @Test
    fun `leaving the app protects recents until resume`() {
        val state = TaskPrivacyState()

        state.onUserLeaveHint()
        assertTrue(state.shouldProtect())

        state.onResume()
        assertFalse(state.shouldProtect())
    }

    @Test
    fun `involuntary backgrounding is protected at stop`() {
        val state = TaskPrivacyState()

        state.onStop()

        assertTrue(state.shouldProtect())
    }

    @Test
    fun `android 13 disables only recents capture while backgrounded`() {
        val state = TaskPrivacyState()

        assertFalse(state.capturePolicy(33).windowSecure)
        assertTrue(state.capturePolicy(33).recentsScreenshotEnabled!!)

        state.onUserLeaveHint()

        assertFalse(state.capturePolicy(33).windowSecure)
        assertFalse(state.capturePolicy(33).recentsScreenshotEnabled!!)
    }

    @Test
    fun `older android uses background-only secure window fallback`() {
        val state = TaskPrivacyState()

        state.onStop()
        assertTrue(state.capturePolicy(32).windowSecure)
        assertTrue(state.capturePolicy(32).recentsScreenshotEnabled == null)

        state.onResume()
        assertFalse(state.capturePolicy(32).windowSecure)
    }

    @Test
    fun `sensitive route stays secure across task resume`() {
        val state = TaskPrivacyState()
        state.setSensitiveRouteSecure(true)
        state.onStop()
        state.onResume()

        assertTrue(state.capturePolicy(32).windowSecure)
        assertTrue(state.capturePolicy(33).windowSecure)
        assertTrue(state.capturePolicy(33).recentsScreenshotEnabled!!)
    }
}
