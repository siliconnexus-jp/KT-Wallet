package cc.siliconnexus.ktwallet.coldsigner

import android.app.Activity
import android.app.ActivityManager
import android.app.KeyguardManager
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.ConnectivityManager
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.ktwallet.core_crypto.CoreCryptoAuthLifecycleHost
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity(), CoreCryptoAuthLifecycleHost {
    private var privacyCover: View? = null
    private var securityChannel: MethodChannel? = null
    private var screenCaptureCallback: Activity.ScreenCaptureCallback? = null
    private lateinit var nativeIncidentStore: NativeIncidentStore
    private lateinit var nativeAnrWatchdog: NativeAnrWatchdog
    private val systemAuthPrivacyGuard = SystemAuthPrivacyGuard()
    private val taskPrivacyState = TaskPrivacyState()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nativeIncidentStore = NativeIncidentStore(applicationContext)
        NativeFatalObserver(nativeIncidentStore).install()
        nativeAnrWatchdog = NativeAnrWatchdog(nativeIncidentStore)
        // Screenshots are intentionally allowed. Android 14+ reports a
        // successful capture through ScreenCaptureCallback so Flutter can
        // warn the user. Mnemonic routes independently enable FLAG_SECURE
        // before rendering, so their pixels never enter the saved screenshot.
        configureTaskAppearance()
        applyScreenCapturePolicy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kt/native_observability"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pendingIncidents" -> result.success(nativeIncidentStore.pendingPayload())
                "ackIncidents" -> {
                    val throughId = call.argument<Number>("throughId")?.toLong()
                    if (throughId == null || !nativeIncidentStore.acknowledge(throughId)) {
                        result.error("INVALID", "Invalid acknowledgement", null)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kt/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.arguments as? Boolean ?: false
                        taskPrivacyState.setSensitiveRouteSecure(secure)
                        applyScreenCapturePolicy()
                        result.success(null)
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
            "kt/system_auth_visibility"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "started" -> {
                    systemAuthPrivacyGuard.started()
                    result.success(null)
                }
                "finished" -> {
                    systemAuthPrivacyGuard.finished()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
        taskPrivacyState.onStop()
        showPrivacyCover()
        configureTaskAppearance()
        applyScreenCapturePolicy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            screenCaptureCallback?.let(::unregisterScreenCaptureCallback)
            screenCaptureCallback = null
        }
        super.onStop()
    }

    override fun onPause() {
        taskPrivacyState.onPause()
        nativeAnrWatchdog.setForeground(false)
        super.onPause()
    }

    override fun onUserLeaveHint() {
        if (systemAuthPrivacyGuard.suppressesTaskPrivacyTransition()) {
            super.onUserLeaveHint()
            return
        }
        // Install the cover in this window. Starting a second Activity after
        // the task has begun leaving can miss Android's snapshot deadline and
        // make Recents reuse the sensitive pre-cover frame.
        taskPrivacyState.onUserLeaveHint()
        showPrivacyCover()
        configureTaskAppearance()
        applyScreenCapturePolicy()
        super.onUserLeaveHint()
    }

    override fun onResume() {
        super.onResume()
        taskPrivacyState.onResume()
        applyScreenCapturePolicy()
        nativeAnrWatchdog.setForeground(true)
        hidePrivacyCover()
    }

    override fun onDestroy() {
        nativeAnrWatchdog.stop()
        super.onDestroy()
    }

    override fun onCoreCryptoAuthStarted() {
        systemAuthPrivacyGuard.started()
    }

    override fun onCoreCryptoAuthFinished() {
        systemAuthPrivacyGuard.finished()
    }

    private fun applyScreenCapturePolicy() {
        val policy = taskPrivacyState.capturePolicy(Build.VERSION.SDK_INT)
        if (policy.windowSecure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(policy.recentsScreenshotEnabled == true)
        }
    }

    @Suppress("DEPRECATION")
    private fun configureTaskAppearance() {
        val brand = Color.rgb(8, 12, 24)
        val description = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityManager.TaskDescription.Builder()
                .setLabel(getString(R.string.app_name))
                .setIcon(R.mipmap.ic_launcher)
                .setPrimaryColor(brand)
                .setBackgroundColor(brand)
                .setStatusBarColor(brand)
                .setNavigationBarColor(brand)
                .build()
        } else {
            ActivityManager.TaskDescription(
                getString(R.string.app_name),
                R.mipmap.ic_launcher,
                brand,
            )
        }
        setTaskDescription(description)
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

    private fun deviceSecurityState(): Map<String, String> {
        val connectivity =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivity.activeNetwork
        val capabilities = network?.let(connectivity::getNetworkCapabilities)

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
            // An offline signer treats ANY active network as connected. A
            // local-only Wi-Fi/VPN/captive path is not green merely because it
            // lacks NET_CAPABILITY_INTERNET. If Android cannot resolve the
            // capabilities for an active handle, the honest answer is unknown.
            "network" to DeviceSecurityClassifier.network(
                activeNetworkPresent = network != null,
                capabilitiesAvailable = capabilities != null
            ),
            "airplane" to if (airplaneEnabled) "safe" else "unsafe",
            "bluetooth" to bluetooth,
            "passcode" to if (keyguard.isDeviceSecure) "safe" else "unsafe",
            "biometric" to biometric,
            // Android has no reliable recording-state probe here. A
            // post-screenshot callback is not evidence that recording is off.
            "screenCapture" to "unknown",
            "integrity" to DeviceSecurityClassifier.integrity(hasRootEvidence())
        )
    }

    private fun hasRootEvidence(): Boolean {
        val tags = Build.TAGS.orEmpty()
        if (tags.contains("test-keys")) return true
        val paths = listOf(
            "/system/app/Superuser.apk",
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su"
        )
        return paths.any { java.io.File(it).exists() }
    }
}
