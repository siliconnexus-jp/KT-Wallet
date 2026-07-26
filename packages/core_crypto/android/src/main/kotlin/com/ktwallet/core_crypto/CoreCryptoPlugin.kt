package com.ktwallet.core_crypto

import android.util.Log
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
import java.util.concurrent.Executor

/**
 * Channel dispatcher for `kt/core_crypto` (detailed-design.md §2.1). Auth-bound
 * operations run a BiometricPrompt before the Keystore read; sensitive byte
 * arrays are zeroed after use.
 */
class CoreCryptoPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val keystore = KeystoreManager()
    private val cipher = EntropyCipher()
    private lateinit var authGate: AuthGate
    private var activity: FragmentActivity? = null
    private lateinit var blobStore: BlobStore

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "kt/core_crypto")
        blobStore = BlobStore(binding.applicationContext)
        authGate = AuthGate(PrefsAuthGateStore(binding.applicationContext))
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivity() { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "generateMnemonic" ->
                    result.success(WalletCoreBridge.generateMnemonic(call.arg("strength", 128)))
                "validateMnemonic" ->
                    result.success(WalletCoreBridge.isValidMnemonic(call.arg("mnemonic", "")))
                "validateWord" ->
                    result.success(WalletCoreBridge.isValidWord(call.arg("word", "")))
                "suggestWords" ->
                    result.success(WalletCoreBridge.suggest(call.arg("prefix", "")))
                "storeWallet" -> {
                    if (call.arg("requireAuth", true)) {
                        promptThen(result, "Protect wallet") {
                            storeWallet(call)
                            true
                        }
                    } else {
                        storeWallet(call)
                        result.success(true)
                    }
                }
                "deriveAddresses" -> result.success(deriveAddresses(call))
                "signTransaction" -> signTransaction(call, result)
                "exportMnemonic" -> exportMnemonic(call, result)
                "deleteWallet" -> deleteWallet(call, result)
                "getAuthState" -> result.success(authGate.state())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Never forward raw exception text (may carry library internals).
            Log.e("KtCoreCrypto", "${call.method} failed: ${e.javaClass.name}")
            result.error(mapError(e), null, errorDetails(e))
        }
    }

    // ---- operations --------------------------------------------------------

    private fun storeWallet(call: MethodCall) {
        val walletId = call.arg<String>("walletId", "")
        val mnemonic = call.arg<String>("mnemonic", "")
        val requireAuth = call.arg("requireAuth", true)
        val entropy = WalletCoreBridge.entropyFromMnemonic(mnemonic)
        val password = call.argOrNull<String>("kdfPassword")
        val usesKdf = !password.isNullOrEmpty()
        var inner: ByteArray = entropy
        try {
            // Header byte flags KDF presence so reads fail closed without the
            // password (enforces invariant 5 at the native layer).
            inner = if (usesKdf) cipher.seal(entropy, password!!) else entropy
            val withHeader = byteArrayOf(if (usesKdf) 1 else 0) + inner
            val sealed = keystore.seal(walletId, withHeader, requireAuth)
            withHeader.fill(0)
            blobStore.write(walletId, sealed)
        } finally {
            entropy.fill(0)
            if (inner !== entropy) inner.fill(0)
        }
    }

    private fun withEntropy(call: MethodCall, block: (ByteArray) -> Unit) {
        val walletId = call.arg<String>("walletId", "")
        // Auth-bound Keystore reads succeed because promptThen() already ran a
        // BiometricPrompt on this thread; non-auth-bound wallets read directly.
        val stored = keystore.open(walletId, blobStore.read(walletId))
        if (stored.isEmpty()) throw EntropyCipher.OpenFailedException()
        val flag = stored[0].toInt()
        val payload = stored.copyOfRange(1, stored.size)
        val password = call.argOrNull<String>("kdfPassword")
        if (flag == 1 && password.isNullOrEmpty()) {
            stored.fill(0); payload.fill(0)
            throw EntropyCipher.OpenFailedException() // KDF wallet, no password
        }
        var entropy = payload
        try {
            entropy = if (flag == 1) cipher.open(payload, password!!) else payload
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

    private fun signTransaction(call: MethodCall, result: Result) {
        promptThen(result, "Authorize transaction signing") {
            val coin = call.arg<String>("coin", "")
            val input = call.arg<ByteArray>("signingInput", ByteArray(0))
            var signed: WalletCoreBridge.Signed? = null
            withEntropy(call) { signed = WalletCoreBridge.sign(it, coin, input) }
            mapOf("signedTx" to signed!!.signedTx, "txHash" to signed!!.txHash)
        }
    }

    private fun exportMnemonic(call: MethodCall, result: Result) {
        promptThen(result, "Reveal recovery phrase") {
            var mnemonic = ""
            withEntropy(call) { mnemonic = WalletCoreBridge.exportMnemonic(it) }
            mnemonic
        }
    }

    private fun deleteWallet(call: MethodCall, result: Result) {
        promptThen(result, "Confirm wallet deletion") {
            val walletId = call.arg<String>("walletId", "")
            blobStore.delete(walletId)
            keystore.deleteKey(walletId)
            true
        }
    }

    /** Runs a biometric prompt, then [action] on success. Failures feed the
     *  AuthGate ladder and surface AUTH_* error codes. */
    private fun promptThen(result: Result, reason: String, action: () -> Any) {
        val act = activity
        if (act == null) { result.error("SIGN_FAILED", "no activity", null); return }
        try {
            authGate.ensureNotLocked()
        } catch (e: AuthGate.LockedException) {
            result.error("AUTH_LOCKED", null, mapOf("cooldownSec" to e.cooldownSec)); return
        }
        val executor: Executor = act.mainExecutor
        val prompt = BiometricPrompt(
            act, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                    authGate.onSuccess()
                    try {
                        result.success(action())
                    } catch (e: Exception) {
                        result.error(mapError(e), e.message, errorDetails(e))
                    }
                }

                override fun onAuthenticationError(code: Int, msg: CharSequence) {
                    if (code == BiometricPrompt.ERROR_USER_CANCELED ||
                        code == BiometricPrompt.ERROR_NEGATIVE_BUTTON
                    ) {
                        result.error("AUTH_CANCELLED", null, null); return
                    }
                    try {
                        authGate.onFailure()
                    } catch (e: AuthGate.LockedException) {
                        result.error("AUTH_LOCKED", null, mapOf("cooldownSec" to e.cooldownSec)); return
                    } catch (_: AuthGate.FailedException) {
                    }
                    result.error("AUTH_FAILED", null, null)
                }

                override fun onAuthenticationFailed() { /* biometric mismatch, retry */ }
            },
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(reason)
                .setAllowedAuthenticators(
                    androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                )
                .build(),
        )
    }

    private fun mapError(e: Exception): String = when (e) {
        is WalletCoreBridge.InvalidMnemonicException -> "INVALID_MNEMONIC"
        is WalletCoreBridge.InvalidInputException -> "INVALID_INPUT"
        is WalletCoreBridge.SignFailedException -> "SIGN_FAILED"
        is WalletCoreBridge.UnavailableException -> "CRYPTO_UNAVAILABLE"
        is WalletNotFoundException -> "WALLET_NOT_FOUND"
        is EntropyCipher.OpenFailedException -> "STORE_CORRUPTED"
        is android.security.keystore.KeyPermanentlyInvalidatedException ->
            "BIOMETRY_CHANGED"
        else -> "SIGN_FAILED"
    }

    private fun errorDetails(e: Exception): Any? =
        if (e is AuthGate.LockedException) mapOf("cooldownSec" to e.cooldownSec) else null
}

// ---- MethodCall helpers ---------------------------------------------------

private fun <T> MethodCall.arg(name: String, default: T): T =
    (argument<T>(name)) ?: default

private fun <T> MethodCall.argOrNull(name: String): T? = argument<T>(name)
