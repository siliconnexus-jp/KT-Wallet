package cc.siliconnexus.ktwallet.coldsigner

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Bundle
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private var privacyCover: View? = null
    private var securityChannel: MethodChannel? = null
    private var screenCaptureCallback: Activity.ScreenCaptureCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The standalone signer is always displaying secrets (mnemonics, the
        // signing QR loop), so FLAG_SECURE is set unconditionally: no
        // screenshots, no screen recording, blanked recents preview.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        securityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kt/screen_security"
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && intent.getBooleanExtra("kt_test_screenshot", false)) {
            securityChannel?.invokeMethod("screenshotTaken", null)
        }
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback = Activity.ScreenCaptureCallback {
                securityChannel?.invokeMethod("screenshotTaken", null)
            }
            screenCaptureCallback = callback
            registerScreenCaptureCallback(mainExecutor, callback)
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            screenCaptureCallback?.let(::unregisterScreenCaptureCallback)
            screenCaptureCallback = null
        }
        super.onStop()
    }

    override fun onPause() {
        showPrivacyCover()
        super.onPause()
    }

    override fun onUserLeaveHint() {
        // Fires before onPause for Home/Recents navigation, early enough for
        // Android's task snapshot compositor to capture the cover.
        showPrivacyCover()
        super.onUserLeaveHint()
    }

    override fun onResume() {
        super.onResume()
        hidePrivacyCover()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        if (!hasFocus) showPrivacyCover()
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !isFinishing) hidePrivacyCover()
    }

    private fun showPrivacyCover() {
        if (privacyCover != null) return
        val density = resources.displayMetrics.density
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((32 * density).toInt(), 0, (32 * density).toInt(), 0)
            setBackgroundColor(Color.rgb(8, 12, 24))
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            contentDescription = getString(R.string.privacy_protection_active)
            addView(ImageView(context).apply {
                setImageResource(R.mipmap.ic_launcher)
            }, LinearLayout.LayoutParams((88 * density).toInt(), (88 * density).toInt()))
            addView(privacyText(getString(R.string.privacy_app_name), 26f, true).apply {
                setPadding(0, (24 * density).toInt(), 0, 0)
            })
            addView(privacyText("⚖  ${getString(R.string.privacy_protection_active)}", 18f, true).apply {
                setPadding(0, (14 * density).toInt(), 0, 0)
            })
            addView(privacyText(getString(R.string.privacy_content_hidden), 14f, false).apply {
                setPadding(0, (8 * density).toInt(), 0, 0)
            })
        }
        privacyCover = content
        addContentView(content, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
        content.bringToFront()
    }

    private fun privacyText(value: String, size: Float, bold: Boolean) =
        TextView(this).apply {
            text = value
            textSize = size
            gravity = Gravity.CENTER
            setTextColor(if (size == 14f) Color.rgb(170, 178, 198) else Color.WHITE)
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

    private fun hidePrivacyCover() {
        privacyCover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        privacyCover = null
    }
}
