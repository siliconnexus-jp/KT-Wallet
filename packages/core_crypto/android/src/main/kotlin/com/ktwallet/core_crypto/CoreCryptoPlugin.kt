package com.ktwallet.core_crypto

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import android.os.Build
import android.os.PersistableBundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.TextView
import androidx.annotation.NonNull
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.Executor
import java.security.MessageDigest

/**
 * Channel dispatcher for `kt/core_crypto` (detailed-design.md §2.1). Auth-bound
 * operations run a BiometricPrompt before the Keystore read; sensitive byte
 * arrays are zeroed after use.
 */
class CoreCryptoPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    ComponentCallbacks2 {
    private lateinit var channel: MethodChannel
    private val keystore = KeystoreManager()
    private val cipher = EntropyCipher()
    private val portableBackupCipher = PortableBackupCipher()
    private lateinit var authGate: AuthGate
    private lateinit var applicationContext: Context
    private var activity: FragmentActivity? = null
    private lateinit var blobStore: BlobStore
    private val walletStorageLock = Any()
    private val privateKeySessionLock = Any()
    private val privateKeySessions = mutableMapOf<String, PrivateKeySession>()
    private val privateKeyViews = mutableListOf<WeakReference<PrivateKeyPlatformView>>()
    private val clipboardHandler = Handler(Looper.getMainLooper())

    private data class PrivateKeySession(
        val walletId: String,
        val keys: MutableMap<String, ByteArray>,
        val expiresAtMs: Long,
    )

    private val walletIdMethods = setOf(
        "storeWallet",
        "walletExists",
        "deriveAddresses",
        "derivePublicKeys",
        "signTransaction",
        "exportMnemonic",
        "beginPrivateKeyExport",
        "createBackup",
        "deleteWallet",
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "kt/core_crypto")
        blobStore = BlobStore(binding.applicationContext)
        authGate = AuthGate(PrefsAuthGateStore(binding.applicationContext))
        applicationContext = binding.applicationContext
        applicationContext.registerComponentCallbacks(this)
        binding.platformViewRegistry.registerViewFactory(
            "kt/private_key_view",
            PrivateKeyPlatformViewFactory(this),
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        clearPrivateKeySessions()
        applicationContext.unregisterComponentCallbacks(this)
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivity() {
        clearPrivateKeySessions()
        activity = null
    }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "beginPrivateKeyExport" ->
                    requireExactArgumentKeys(call.arguments, setOf("walletId"))
                "copyPrivateKey" ->
                    requireExactArgumentKeys(
                        call.arguments,
                        setOf("sessionId", "coin", "mode"),
                    )
                "endPrivateKeyExport" ->
                    requireExactArgumentKeys(call.arguments, setOf("sessionId"))
            }
            // Validate before any BiometricPrompt or filesystem/Keychain work.
            // The Dart API checks too, but the native MethodChannel is a trust
            // boundary and must not accept path separators or arbitrary IDs.
            if (call.method in walletIdMethods) {
                requireValidWalletId(call.argument<Any?>("walletId"))
            }
            when (call.method) {
                "generateMnemonic" ->
                    result.success(
                        WalletCoreBridge.generateMnemonic(
                            requireMnemonicStrength(call.argument<Any?>("strength")),
                        ),
                    )
                "validateMnemonic" ->
                    result.success(
                        WalletCoreBridge.isValidMnemonic(
                            requireMnemonicText(call.argument<Any?>("mnemonic")),
                        ),
                    )
                "validateWord" ->
                    result.success(
                        WalletCoreBridge.isValidWord(
                            requireWordText(call.argument<Any?>("word")),
                        ),
                    )
                "suggestWords" -> {
                    val prefix = requireSuggestionPrefix(call.argument<Any?>("prefix"))
                    val limit = requireSuggestionLimit(call.argument<Any?>("limit"))
                    result.success(
                        if (prefix.isBlank()) emptyList()
                        else WalletCoreBridge.suggest(prefix).take(limit),
                    )
                }
                // Prompts before writing, and iOS does not — a platform
                // requirement, not a policy difference, so do NOT "align" them.
                // The Keystore key is created with
                // setUserAuthenticationRequired(true), so the ENCRYPT operation
                // at store time already needs a fresh authentication. iOS's
                // Keychain applies its access control to reads only, so writing
                // there is silent. What matters is identical on both:
                // exportMnemonic / signTransaction / deleteWallet always
                // authenticate.
                "storeWallet" -> {
                    val mnemonic = requireMnemonicText(call.argument<Any?>("mnemonic"))
                    if (!WalletCoreBridge.isValidMnemonic(mnemonic)) {
                        throw WalletCoreBridge.InvalidMnemonicException()
                    }
                    optionalKdfPassword(call.argument<Any?>("kdfPassword"))
                    if (optionalNativeBoolean(call.argument<Any?>("requireAuth"), true)) {
                        promptThen(result, "Protect wallet") {
                            storeWallet(call)
                            true
                        }
                    } else {
                        storeWallet(call)
                        result.success(true)
                    }
                }
                // Check both halves of Android's native wallet record without
                // opening the auth-bound Keystore key or showing a prompt.
                "walletExists" -> {
                    val walletId = requireValidWalletId(call.argument<Any?>("walletId"))
                    result.success(
                        synchronized(walletStorageLock) {
                            blobStore.exists(walletId) && keystore.exists(walletId)
                        },
                    )
                }
                "deriveAddresses" -> result.success(deriveAddresses(call))
                "derivePublicKeys" -> result.success(derivePublicKeys(call))
                "signTransaction" -> signTransaction(call, result)
                "exportMnemonic" -> exportMnemonic(call, result)
                "beginPrivateKeyExport" -> beginPrivateKeyExport(call, result)
                "copyPrivateKey" -> result.success(copyPrivateKey(call))
                "endPrivateKeyExport" -> {
                    endPrivateKeyExport(call)
                    result.success(true)
                }
                // Same secret as exportMnemonic, same prompt. The difference is
                // only where it goes: a file the user carries off the device
                // rather than the screen.
                "createBackup" -> createBackup(call, result)
                "readBackup" -> result.success(readBackup(call))
                "deleteWallet" -> deleteWallet(call, result)
                "getAuthState" -> result.success(authGate.state())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Neither logs nor the channel receive exception text: native
            // crypto failures may carry wallet/transaction context.
            result.error(mapError(e), null, errorDetails(e))
        }
    }

    // ---- operations --------------------------------------------------------

    private fun storeWallet(call: MethodCall) {
        val walletId = requireValidWalletId(call.argument<Any?>("walletId"))
        val mnemonic = requireMnemonicText(call.argument<Any?>("mnemonic"))
        val requireAuth = optionalNativeBoolean(call.argument<Any?>("requireAuth"), true)
        val entropy = WalletCoreBridge.entropyFromMnemonic(mnemonic)
        val password = optionalKdfPassword(call.argument<Any?>("kdfPassword"))
        val usesKdf = !password.isNullOrEmpty()
        var inner: ByteArray = entropy
        try {
            // Header byte flags KDF presence so reads fail closed without the
            // password (enforces invariant 5 at the native layer).
            inner = if (usesKdf) {
                cipher.seal(entropy, requireNotNull(password))
            } else {
                entropy
            }
            val withHeader = byteArrayOf(if (usesKdf) 1 else 0) + inner
            try {
                synchronized(walletStorageLock) {
                    if (blobStore.exists(walletId) || keystore.exists(walletId)) {
                        throw WalletAlreadyExistsException()
                    }
                    try {
                        val sealed = keystore.seal(walletId, withHeader, requireAuth)
                        try {
                            blobStore.writeNew(walletId, sealed)
                        } finally {
                            sealed.fill(0)
                        }
                    } catch (e: Exception) {
                        // Creating a Keystore key and its ciphertext file cannot be
                        // one OS transaction. If the file commit fails, remove the
                        // newly-created key so no stale authentication policy can
                        // be reused by a later wallet with this id.
                        runCatching { keystore.deleteKey(walletId) }
                        throw e
                    }
                }
            } finally {
                withHeader.fill(0)
            }
        } finally {
            entropy.fill(0)
            if (inner !== entropy) inner.fill(0)
        }
    }

    private fun withEntropy(call: MethodCall, block: (ByteArray) -> Unit) {
        val walletId = requireValidWalletId(call.argument<Any?>("walletId"))
        // Auth-bound Keystore reads succeed because promptThen() already ran a
        // BiometricPrompt on this thread; non-auth-bound wallets read directly.
        val stored = keystore.open(walletId, blobStore.read(walletId))
        if (stored.isEmpty()) throw EntropyCipher.OpenFailedException()
        val flag = try {
            requireStoredWalletFlag(stored[0].toInt())
        } catch (e: Exception) {
            stored.fill(0)
            throw e
        }
        val payload = stored.copyOfRange(1, stored.size)
        val password = optionalKdfPassword(call.argument<Any?>("kdfPassword"))
        if (flag == 1 && password.isNullOrEmpty()) {
            stored.fill(0); payload.fill(0)
            throw EntropyCipher.OpenFailedException() // KDF wallet, no password
        }
        var entropy = payload
        try {
            entropy = if (flag == 1) cipher.open(payload, password!!) else payload
            requireEntropySize(entropy)
            block(entropy)
        } finally {
            stored.fill(0)
            entropy.fill(0)
            if (entropy !== payload) payload.fill(0)
        }
    }

    private fun deriveAddresses(call: MethodCall): Map<String, String> {
        var out: Map<String, String> = emptyMap()
        withEntropy(call) { out = WalletCoreBridge.addresses(it) }
        return out
    }

    private fun derivePublicKeys(call: MethodCall): Map<String, ByteArray> {
        var out: Map<String, ByteArray> = emptyMap()
        withEntropy(call) { out = WalletCoreBridge.publicKeys(it) }
        return out
    }

    private fun signTransaction(call: MethodCall, result: Result) {
        // Decode before opening the system prompt: malformed callers must not
        // make the user authenticate for an operation that can never run.
        val coin = requireSupportedCoin(call.argument<Any?>("coin"))
        val input = requireSigningInput(call.argument<Any?>("signingInput"))
        promptThen(result, "Authorize transaction signing") {
            var signed: WalletCoreBridge.Signed? = null
            withEntropy(call) { signed = WalletCoreBridge.sign(it, coin, input) }
            val completed = requireNotNull(signed)
            mapOf("signedTx" to completed.signedTx, "txHash" to completed.txHash)
        }
    }

    private fun exportMnemonic(call: MethodCall, result: Result) {
        promptThen(result, "Reveal recovery phrase") {
            var mnemonic = ""
            withEntropy(call) { mnemonic = WalletCoreBridge.exportMnemonic(it) }
            mnemonic
        }
    }

    private fun beginPrivateKeyExport(call: MethodCall, result: Result) {
        promptThen(result, "View private keys") {
            val walletId = requireValidWalletId(call.argument<Any?>("walletId"))
            var keys = emptyMap<String, ByteArray>()
            withEntropy(call) { keys = WalletCoreBridge.privateKeys(it) }
            val owned = keys.mapValuesTo(mutableMapOf()) { (_, key) -> key.copyOf() }
            keys.values.forEach { it.fill(0) }
            val sessionId = UUID.randomUUID().toString()
            synchronized(privateKeySessionLock) {
                clearExpiredPrivateKeySessionsLocked()
                val previous = privateKeySessions.filterValues {
                    it.walletId == walletId
                }.keys.toList()
                previous.forEach { privateKeySessions.remove(it)?.wipe() }
                privateKeySessions[sessionId] = PrivateKeySession(
                    walletId = walletId,
                    keys = owned,
                    expiresAtMs = SystemClock.elapsedRealtime() + 5 * 60 * 1000L,
                )
            }
            sessionId
        }
    }

    private fun copyPrivateKey(call: MethodCall): Map<String, String> {
        val sessionId = requirePrivateKeySessionId(call.argument<Any?>("sessionId"))
        val coin = requireSupportedCoin(call.argument<Any?>("coin"))
        val mode = requirePrivateKeyCopyMode(call.argument<Any?>("mode"))
        val family = privateKeyFamily(coin)
        val key = synchronized(privateKeySessionLock) {
            clearExpiredPrivateKeySessionsLocked()
            privateKeySessions[sessionId]?.keys?.get(family)?.copyOf()
                ?: throw InvalidNativeArgumentException()
        }
        var encoded = ""
        try {
            encoded = WalletCoreBridge.encodePrivateKey(key, coin)
            if (encoded.length <= 6) throw InvalidNativeArgumentException()
            val suffix = if (mode == "safe") encoded.takeLast(6) else ""
            val clipboardText = if (mode == "safe") encoded.dropLast(6) else encoded
            writeSensitiveClipboard(clipboardText)
            return mapOf("suffix" to suffix)
        } finally {
            key.fill(0)
            encoded = ""
        }
    }

    private fun endPrivateKeyExport(call: MethodCall) {
        val sessionId = requirePrivateKeySessionId(call.argument<Any?>("sessionId"))
        synchronized(privateKeySessionLock) {
            privateKeySessions.remove(sessionId)?.wipe()
        }
    }

    private fun privateKeyFamily(coin: String): String = when (coin) {
        "eth", "polygon", "base", "arbitrum", "avalanche", "bnb" -> "evm"
        "tron" -> "tron"
        "solana" -> "solana"
        else -> throw InvalidNativeArgumentException()
    }

    internal fun privateKeyText(arguments: Any?): String {
        val values = arguments as? Map<*, *> ?: throw InvalidNativeArgumentException()
        if (values.keys != setOf("sessionId", "coin")) {
            throw InvalidNativeArgumentException()
        }
        val sessionId = requirePrivateKeySessionId(values["sessionId"])
        val coin = requireSupportedCoin(values["coin"])
        val family = privateKeyFamily(coin)
        val key = synchronized(privateKeySessionLock) {
            clearExpiredPrivateKeySessionsLocked()
            privateKeySessions[sessionId]?.keys?.get(family)?.copyOf()
                ?: throw InvalidNativeArgumentException()
        }
        return try {
            WalletCoreBridge.encodePrivateKey(key, coin)
        } finally {
            key.fill(0)
        }
    }

    internal fun registerPrivateKeyView(view: PrivateKeyPlatformView) {
        synchronized(privateKeyViews) {
            privateKeyViews.removeAll { it.get() == null }
            privateKeyViews += WeakReference(view)
        }
    }

    private fun writeSensitiveClipboard(value: String) {
        val manager = applicationContext.getSystemService(Context.CLIPBOARD_SERVICE)
            as ClipboardManager
        val clip = ClipData.newPlainText("", value)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }
        manager.setPrimaryClip(clip)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        clipboardHandler.postDelayed({
            try {
                val current = manager.primaryClip
                    ?.getItemAt(0)
                    ?.coerceToText(applicationContext)
                    ?.toString()
                    ?: return@postDelayed
                val currentDigest = MessageDigest.getInstance("SHA-256")
                    .digest(current.toByteArray(Charsets.UTF_8))
                try {
                    if (currentDigest.contentEquals(digest)) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            manager.clearPrimaryClip()
                        } else {
                            manager.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                    }
                } finally {
                    currentDigest.fill(0)
                }
            } finally {
                digest.fill(0)
            }
        }, 60_000L)
    }

    private fun PrivateKeySession.wipe() {
        keys.values.forEach { it.fill(0) }
        keys.clear()
    }

    private fun clearExpiredPrivateKeySessionsLocked() {
        val now = SystemClock.elapsedRealtime()
        val expired = privateKeySessions.filterValues { it.expiresAtMs <= now }.keys
        expired.forEach { privateKeySessions.remove(it)?.wipe() }
    }

    private fun clearPrivateKeySessions() {
        synchronized(privateKeySessionLock) {
            privateKeySessions.values.forEach { it.wipe() }
            privateKeySessions.clear()
        }
        val views = synchronized(privateKeyViews) {
            privateKeyViews.mapNotNull { it.get() }.also { privateKeyViews.clear() }
        }
        clipboardHandler.post { views.forEach { it.conceal() } }
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            clearPrivateKeySessions()
        }
    }

    override fun onLowMemory() = clearPrivateKeySessions()

    override fun onConfigurationChanged(newConfig: Configuration) = Unit

    /** Re-seals the stored entropy under the user's backup password. Note this
     *  re-seals rather than copying the stored blob: that blob is wrapped in a
     *  Keystore key that never leaves this device, and its optional KDF layer
     *  may use a different password. */
    private fun createBackup(call: MethodCall, result: Result) {
        val password = requireBackupPassword(call.argument<Any?>("password"))
        promptThen(result, "Create an encrypted backup") {
            var sealed = ByteArray(0)
            withEntropy(call) { sealed = portableBackupCipher.seal(it, password) }
            sealed
        }
    }

    /** Opens a backup blob. No BiometricPrompt: the file already left the
     *  device, so the password is the whole gate, and a device prompt would
     *  only inconvenience the owner restoring onto a phone they just set up. */
    private fun readBackup(call: MethodCall): String {
        val blob = requireBackupBlob(call.argument<Any?>("blob"))
        val password = requireBackupPassword(call.argument<Any?>("password"))
        val formatVersion = requireNativeInt(call.argument<Any?>("formatVersion"))
        val entropy = openBackupPayload(
            formatVersion = formatVersion,
            portableOpen = { portableBackupCipher.open(blob, password) },
            legacyOpen = { cipher.open(blob, password) },
        )
        try {
            return WalletCoreBridge.exportMnemonic(entropy)
        } finally {
            entropy.fill(0)
        }
    }

    private fun deleteWallet(call: MethodCall, result: Result) {
        promptThen(result, "Confirm wallet deletion") {
            val walletId = requireValidWalletId(call.argument<Any?>("walletId"))
            synchronized(privateKeySessionLock) {
                val owned = privateKeySessions.filterValues {
                    it.walletId == walletId
                }.keys.toList()
                owned.forEach { privateKeySessions.remove(it)?.wipe() }
            }
            blobStore.delete(walletId)
            keystore.deleteKey(walletId)
            true
        }
    }

    /** Runs a biometric prompt, then [action] on success.
     *
     * Terminal provider/device errors never feed the persisted failure
     * ladder: no hardware, no enrollment, timeout and system lockout do not
     * prove that the user supplied a wrong credential.
     */
    private fun promptThen(result: Result, reason: String, action: () -> Any) {
        val act = activity
        if (act == null) { result.error("SIGN_FAILED", null, null); return }
        try {
            authGate.ensureNotLocked()
        } catch (e: AuthGate.LockedException) {
            result.error("AUTH_LOCKED", null, mapOf("cooldownSec" to e.cooldownSec)); return
        }
        val lifecycleHost = act as? CoreCryptoAuthLifecycleHost
        var lifecycleFinished = false
        fun finishLifecycle() {
            if (lifecycleFinished) return
            lifecycleFinished = true
            runCatching { lifecycleHost?.onCoreCryptoAuthFinished() }
        }
        runCatching { lifecycleHost?.onCoreCryptoAuthStarted() }
        val executor: Executor = act.mainExecutor
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                finishLifecycle()
                authGate.onSuccess()
                try {
                    result.success(action())
                } catch (e: Exception) {
                    result.error(mapError(e), null, errorDetails(e))
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                finishLifecycle()
                when (classifyPromptAuthError(code)) {
                    PromptAuthDisposition.CANCELLED ->
                        result.error("AUTH_CANCELLED", null, null)
                    PromptAuthDisposition.SYSTEM_LOCKED ->
                        result.error(
                            "AUTH_LOCKED",
                            null,
                            mapOf("cooldownSec" to 0, "systemLockout" to true),
                        )
                    PromptAuthDisposition.UNAVAILABLE ->
                        result.error(
                            "AUTH_UNAVAILABLE",
                            null,
                            mapOf("nativeCode" to code),
                        )
                }
            }

            override fun onAuthenticationFailed() {
                // BiometricPrompt keeps the prompt open and the OS owns
                // retry/lockout. There is no terminal result to send yet.
            }
        }
        runPromptStart(start = {
            val prompt = BiometricPrompt(act, executor, callback)
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(reason)
                    .setAllowedAuthenticators(
                        androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                    )
                    .build(),
            )
        }, onError = { e ->
            finishLifecycle()
            // Fragment state, a missing provider Activity, or vendor prompt
            // setup failures must complete the MethodChannel exactly once.
            // Throwing here leaves Dart waiting forever and can strand a
            // signing request after the user already confirmed its details.
            result.error(
                "AUTH_UNAVAILABLE",
                null,
                null,
            )
        })
    }

    private fun mapError(e: Exception): String = when (e) {
        is WalletCoreBridge.InvalidMnemonicException -> "INVALID_MNEMONIC"
        is WalletCoreBridge.InvalidInputException -> "INVALID_INPUT"
        is WalletCoreBridge.SignFailedException -> "SIGN_FAILED"
        is WalletCoreBridge.UnavailableException -> "CRYPTO_UNAVAILABLE"
        is WalletNotFoundException -> "WALLET_NOT_FOUND"
        is WalletAlreadyExistsException -> "WALLET_EXISTS"
        is WalletStorageException -> "SIGN_FAILED"
        is StoredWalletCorruptedException -> "STORE_CORRUPTED"
        is EntropyCipher.OpenFailedException -> "STORE_CORRUPTED"
        is PortableBackupCipher.OpenFailedException -> "STORE_CORRUPTED"
        is BackupFormatVersionException -> "INVALID_INPUT"
        is InvalidWalletIdException -> "INVALID_INPUT"
        is InvalidNativeArgumentException -> "INVALID_INPUT"
        is android.security.keystore.KeyPermanentlyInvalidatedException ->
            "BIOMETRY_CHANGED"
        else -> "SIGN_FAILED"
    }

    private fun errorDetails(e: Exception): Any? =
        if (e is AuthGate.LockedException) mapOf("cooldownSec" to e.cooldownSec) else null
}

internal class PrivateKeyPlatformViewFactory(
    private val plugin: CoreCryptoPlugin,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val text = runCatching { plugin.privateKeyText(args) }.getOrDefault("")
        return PrivateKeyPlatformView(context, text).also(plugin::registerPrivateKeyView)
    }
}

internal class PrivateKeyPlatformView(
    context: Context,
    private var secret: String,
) : PlatformView {
    private val handler = Handler(Looper.getMainLooper())
    private val label = TextView(context).apply {
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setTextColor(android.graphics.Color.BLACK)
        typeface = Typeface.MONOSPACE
        textSize = 15f
        gravity = Gravity.CENTER
        setPadding(22, 30, 22, 20)
        setTextIsSelectable(false)
        text = secret
    }
    private val concealTask = Runnable { conceal() }

    init {
        handler.postDelayed(concealTask, 60_000L)
    }

    override fun getView(): View = label

    override fun dispose() {
        handler.removeCallbacks(concealTask)
        conceal()
    }

    fun conceal() {
        secret = ""
        label.text = ""
    }
}

internal class BackupFormatVersionException : Exception("unsupported backup format")

/**
 * Opens one backup payload without weakening the new portable format.
 *
 * Only legacy v1 may fall back to Android's historical Argon2id payload. A v2
 * file never incurs that 64 MiB KDF and can never be silently reinterpreted as
 * a different format after authentication fails.
 */
internal fun openBackupPayload(
    formatVersion: Int,
    portableOpen: () -> ByteArray,
    legacyOpen: () -> ByteArray,
): ByteArray = when (formatVersion) {
    2 -> portableOpen()
    1 -> try {
        portableOpen()
    } catch (_: PortableBackupCipher.OpenFailedException) {
        legacyOpen()
    }
    else -> throw BackupFormatVersionException()
}
