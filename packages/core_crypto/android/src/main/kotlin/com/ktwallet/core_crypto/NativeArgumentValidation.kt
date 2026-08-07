package com.ktwallet.core_crypto

internal class InvalidNativeArgumentException : Exception("invalid native argument")

internal const val MAX_MNEMONIC_UTF8_BYTES = 512
internal const val MAX_WORD_UTF8_BYTES = 64
internal const val MAX_KDF_PASSWORD_UTF8_BYTES = 1024
internal const val MAX_BACKUP_PASSWORD_UTF8_BYTES = 4096
internal const val MAX_SIGNING_INPUT_BYTES = 1024 * 1024
internal val VALID_BACKUP_BLOB_SIZES = setOf(60, 68, 76)
internal val SUPPORTED_COINS = setOf(
    "eth", "polygon", "base", "arbitrum", "avalanche", "bnb", "tron", "solana",
)
internal val VALID_ENTROPY_SIZES = setOf(16, 24, 32)
internal val PRIVATE_KEY_COPY_MODES = setOf("safe", "full")

internal fun requireExactArgumentKeys(arguments: Any?, expected: Set<String>) {
    val values = arguments as? Map<*, *> ?: throw InvalidNativeArgumentException()
    if (values.keys != expected) throw InvalidNativeArgumentException()
}

/**
 * MethodChannel is a native trust boundary. These helpers deliberately accept
 * [Any] so malformed direct calls are rejected before JNI, Keystore, KDF, or
 * authentication work instead of being coerced to defaults.
 */
internal fun requireNativeString(value: Any?): String =
    value as? String ?: throw InvalidNativeArgumentException()

internal fun optionalNativeString(value: Any?): String? = when (value) {
    null -> null
    is String -> value
    else -> throw InvalidNativeArgumentException()
}

internal fun requireNativeBytes(value: Any?): ByteArray =
    value as? ByteArray ?: throw InvalidNativeArgumentException()

internal fun requireNativeInt(value: Any?): Int =
    value as? Int ?: throw InvalidNativeArgumentException()

internal fun optionalNativeBoolean(value: Any?, default: Boolean): Boolean = when (value) {
    null -> default
    is Boolean -> value
    else -> throw InvalidNativeArgumentException()
}

internal fun requireMnemonicStrength(value: Any?): Int {
    val strength = requireNativeInt(value)
    if (strength !in setOf(128, 192, 256)) throw InvalidNativeArgumentException()
    return strength
}

internal fun requireSuggestionLimit(value: Any?): Int {
    val limit = requireNativeInt(value)
    if (limit !in 1..20) throw InvalidNativeArgumentException()
    return limit
}

private fun requireUtf8Bounded(value: Any?, maxBytes: Int, allowBlank: Boolean): String {
    val text = requireNativeString(value)
    if (!allowBlank && text.isBlank()) throw InvalidNativeArgumentException()
    val bytes = text.toByteArray(Charsets.UTF_8)
    return try {
        if (bytes.size > maxBytes) throw InvalidNativeArgumentException()
        text
    } finally {
        bytes.fill(0)
    }
}

internal fun requireMnemonicText(value: Any?): String =
    requireUtf8Bounded(value, MAX_MNEMONIC_UTF8_BYTES, allowBlank = false)

internal fun requireWordText(value: Any?): String =
    requireUtf8Bounded(value, MAX_WORD_UTF8_BYTES, allowBlank = true)

internal fun requireSuggestionPrefix(value: Any?): String =
    requireUtf8Bounded(value, MAX_WORD_UTF8_BYTES, allowBlank = true)

internal fun optionalKdfPassword(value: Any?): String? {
    val password = optionalNativeString(value) ?: return null
    if (password.isEmpty()) return password
    return requireUtf8Bounded(password, MAX_KDF_PASSWORD_UTF8_BYTES, allowBlank = false)
}

internal fun requireBackupPassword(value: Any?): String =
    requireUtf8Bounded(value, MAX_BACKUP_PASSWORD_UTF8_BYTES, allowBlank = false)

internal fun requireSupportedCoin(value: Any?): String {
    val coin = requireNativeString(value)
    if (coin !in SUPPORTED_COINS) throw InvalidNativeArgumentException()
    return coin
}

internal fun requirePrivateKeySessionId(value: Any?): String {
    val sessionId = requireNativeString(value)
    if (!Regex("^[A-Za-z0-9_-]{1,80}$").matches(sessionId)) {
        throw InvalidNativeArgumentException()
    }
    return sessionId
}

internal fun requirePrivateKeyCopyMode(value: Any?): String {
    val mode = requireNativeString(value)
    if (mode !in PRIVATE_KEY_COPY_MODES) throw InvalidNativeArgumentException()
    return mode
}

internal fun requireSigningInput(value: Any?): ByteArray {
    val input = requireNativeBytes(value)
    if (input.isEmpty() || input.size > MAX_SIGNING_INPUT_BYTES) {
        throw InvalidNativeArgumentException()
    }
    return input
}

internal fun requireBackupBlob(value: Any?): ByteArray {
    val blob = requireNativeBytes(value)
    if (blob.size !in VALID_BACKUP_BLOB_SIZES) throw InvalidNativeArgumentException()
    return blob
}

internal fun requireStoredWalletFlag(flag: Int): Int {
    if (flag != 0 && flag != 1) throw StoredWalletCorruptedException()
    return flag
}

internal fun requireEntropySize(entropy: ByteArray): ByteArray {
    if (entropy.size !in VALID_ENTROPY_SIZES) throw StoredWalletCorruptedException()
    return entropy
}
