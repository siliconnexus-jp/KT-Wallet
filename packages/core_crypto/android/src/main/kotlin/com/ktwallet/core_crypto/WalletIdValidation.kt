package com.ktwallet.core_crypto

internal class InvalidWalletIdException : Exception("invalid wallet id")

private val walletIdPattern = Regex("^[A-Za-z0-9_-]{1,64}$")

/**
 * Native trust-boundary validation for identifiers used as Keystore aliases
 * and entropy-blob file names. Dart performs the same check, but native code
 * must remain safe when invoked directly through a MethodChannel or test host.
 */
internal fun requireValidWalletId(value: Any?): String {
    val walletId = value as? String ?: throw InvalidWalletIdException()
    if (!walletIdPattern.matches(walletId)) throw InvalidWalletIdException()
    return walletId
}
