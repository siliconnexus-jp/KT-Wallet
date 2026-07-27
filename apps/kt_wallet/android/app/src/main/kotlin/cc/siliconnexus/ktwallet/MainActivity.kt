package cc.siliconnexus.ktwallet

import android.app.Activity
import android.app.KeyguardManager
import android.bluetooth.BluetoothAdapter
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.annotation.RequiresApi
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
    private var secureScreenEnabled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android may snapshot a task before a newly-added overlay completes
        // its first render pass. API 33+ provides the only race-free contract:
        // opt out of system Recents screenshots entirely. The in-window brand
        // cover remains for Home, overlays and older Android releases.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart toggles FLAG_SECURE around the embedded signer mode: signer
        // content (mnemonics, signing QRs) must not appear in screenshots or
        // the recents switcher, while normal wallet mode stays shareable.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kt/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.arguments as? Boolean ?: false
                        secureScreenEnabled = secure
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Saves a generated image (the receive card) into the photo library.
        // MediaStore on API 29+ needs no permission at all; older releases
        // would need WRITE_EXTERNAL_STORAGE, which is not worth requesting for
        // this — Dart falls back to the share sheet on UNSUPPORTED.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kt/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error("UNSUPPORTED", "Requires Android 10+", null)
                            return@setMethodCallHandler
                        }
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "kt-wallet"
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID", "No image bytes", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToPictures(bytes, name))
                        } catch (e: Exception) {
                            result.error("FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        securityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kt/screen_security"
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kt/device_security"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getState") {
                result.success(deviceSecurityState())
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Emulator-only acceptance hook. It is compiled out of release builds;
        // production events come exclusively from ScreenCaptureCallback.
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
            addView(privacyText(getString(R.string.privacy_protection_active), 18f, true).apply {
                setPadding(0, (14 * density).toInt(), 0, 0)
            })
            addView(privacyText(getString(R.string.privacy_content_hidden), 14f, false).apply {
                setPadding(0, (8 * density).toInt(), 0, 0)
            })
        }
        privacyCover = content
        addContentView(
            content,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        content.bringToFront()
    }

    /**
     * Inserts a PNG into Pictures/KT Wallet via MediaStore. IS_PENDING hides
     * the row until the bytes are flushed, so a crash mid-write cannot leave a
     * truncated image in the user's gallery.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveToPictures(bytes: ByteArray, name: String): Boolean {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/KT Wallet"
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
        ) ?: return false
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return false
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return true
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

    private fun deviceSecurityState(): Map<String, String> {
        val connectivity =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = connectivity.activeNetwork?.let(
            connectivity::getNetworkCapabilities
        )
        val connected = capabilities?.hasCapability(
            NetworkCapabilities.NET_CAPABILITY_INTERNET
        ) == true
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val airplaneEnabled = Settings.Global.getInt(
            contentResolver,
            Settings.Global.AIRPLANE_MODE_ON,
            0
        ) == 1
        val bluetooth = try {
            BluetoothAdapter.getDefaultAdapter()?.isEnabled?.let {
                if (it) "unsafe" else "safe"
            } ?: "unknown"
        } catch (_: SecurityException) {
            "unknown"
        }
        val biometric = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val manager = getSystemService(
                android.hardware.biometrics.BiometricManager::class.java
            )
            @Suppress("DEPRECATION")
            if (manager?.canAuthenticate() ==
                android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS
            ) "safe" else "unsafe"
        } else {
            "unknown"
        }
        return mapOf(
            "network" to if (connected) "unsafe" else "safe",
            "airplane" to if (airplaneEnabled) "safe" else "unsafe",
            "bluetooth" to bluetooth,
            "passcode" to if (keyguard.isDeviceSecure) "safe" else "unsafe",
            "biometric" to biometric,
            "screenCapture" to if (secureScreenEnabled) "safe" else "unknown",
            "integrity" to if (hasRootEvidence()) "unsafe" else "unknown"
        )
    }

    private fun hasRootEvidence(): Boolean {
        if (Build.TAGS.orEmpty().contains("test-keys")) return true
        return listOf(
            "/system/app/Superuser.apk",
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su"
        ).any { java.io.File(it).exists() }
    }
}
