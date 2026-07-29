package cc.siliconnexus.ktwallet.coldsigner

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/** Snapshot-safe protection page placed at the top of a backgrounded task. */
class PrivacyActivity : Activity() {
    private val createdAt = SystemClock.elapsedRealtime()
    private var wasFocused = false
    private var lostFocus = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(8, 12, 24)
        window.navigationBarColor = Color.rgb(8, 12, 24)
        setContentView(buildProtectionPage())
        Handler(Looper.getMainLooper()).postDelayed({
            if (hasWindowFocus() && !isFinishing) {
                finish()
                overridePendingTransition(0, 0)
            }
        }, 1500)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && lostFocus) {
            finish()
            overridePendingTransition(0, 0)
            return
        }
        if (hasFocus) wasFocused = true
        if (!hasFocus && wasFocused) lostFocus = true
    }

    override fun onResume() {
        super.onResume()
        if (SystemClock.elapsedRealtime() - createdAt > 500) {
            finish()
            overridePendingTransition(0, 0)
        }
    }

    private fun buildProtectionPage(): View {
        val density = resources.displayMetrics.density
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((32 * density).toInt(), 0, (32 * density).toInt(), 0)
            setBackgroundColor(Color.rgb(8, 12, 24))
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            contentDescription = getString(R.string.privacy_protection_active)
            addView(
                ImageView(context).apply { setImageResource(R.mipmap.ic_launcher) },
                LinearLayout.LayoutParams((88 * density).toInt(), (88 * density).toInt())
            )
            addView(label(getString(R.string.privacy_app_name), 26f, true).apply {
                setPadding(0, (24 * density).toInt(), 0, 0)
            })
            addView(label(getString(R.string.privacy_protection_active), 18f, true).apply {
                setPadding(0, (14 * density).toInt(), 0, 0)
            })
            addView(label(getString(R.string.privacy_content_hidden), 14f, false).apply {
                setPadding(0, (8 * density).toInt(), 0, 0)
            })
        }
    }

    private fun label(value: String, size: Float, bold: Boolean) =
        TextView(this).apply {
            text = value
            textSize = size
            gravity = Gravity.CENTER
            setTextColor(if (size == 14f) Color.rgb(170, 178, 198) else Color.WHITE)
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
}
