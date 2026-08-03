package cc.siliconnexus.ktwallet.coldsigner

/**
 * Separates a temporary system overlay from a real task-background transition.
 *
 * Android may pause an Activity while a permission prompt, notification shade,
 * or another translucent system surface is still showing the app underneath.
 * Those events must not replace the live UI. Home/Recents (`onUserLeaveHint`)
 * and complete loss of visibility (`onStop`) must protect the task snapshot.
 */
internal data class TaskCapturePolicy(
    val windowSecure: Boolean,
    val recentsScreenshotEnabled: Boolean?,
)

internal class TaskPrivacyState {
    private var protectionRequired = false
    private var sensitiveRouteSecure = false

    fun onPause() = Unit

    fun onUserLeaveHint() {
        protectionRequired = true
    }

    fun onStop() {
        protectionRequired = true
    }

    fun onResume() {
        protectionRequired = false
    }

    fun setSensitiveRouteSecure(secure: Boolean) {
        sensitiveRouteSecure = secure
    }

    fun shouldProtect(): Boolean = protectionRequired

    /**
     * Android 13 introduced a task-snapshot API that does not interfere with
     * ordinary foreground screenshots. Older Android versions need a
     * background-only FLAG_SECURE fallback. Route-level FLAG_SECURE always
     * wins, including after the task resumes.
     */
    fun capturePolicy(apiLevel: Int): TaskCapturePolicy =
        if (apiLevel >= ANDROID_13_API) {
            TaskCapturePolicy(
                windowSecure = sensitiveRouteSecure,
                recentsScreenshotEnabled = !protectionRequired,
            )
        } else {
            TaskCapturePolicy(
                windowSecure = sensitiveRouteSecure || protectionRequired,
                recentsScreenshotEnabled = null,
            )
        }

    private companion object {
        const val ANDROID_13_API = 33
    }
}
