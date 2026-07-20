package com.ktwallet.core_crypto

/**
 * Fail-closed stub used when the app is built WITHOUT Trust Wallet Core
 * (gradle property `walletCore=false`, the default so the repo builds on
 * Android without the GitHub Packages artifact).
 *
 * Every key operation throws [UnavailableException] so the full 1:1 UI runs on
 * Android today, while it stays IMPOSSIBLE to emit a wrong-but-plausible key,
 * address, or signature. To link the real, audited bridge, build with
 * `-PwalletCore=true` and configure the wallet-core GitHub Packages
 * credentials (see packages/core_crypto/android/build.gradle.kts).
 *
 * The public surface is kept identical to the real [WalletCoreBridge] so
 * [CoreCryptoPlugin] compiles unchanged against either.
 */
object WalletCoreBridge {
    class InvalidMnemonicException : Exception("invalid mnemonic")
    class InvalidInputException : Exception("invalid signing input")
    class SignFailedException : Exception("signing failed")
    class UnavailableException :
        Exception("Trust Wallet Core is not linked in this build (walletCore=false)")

    fun generateMnemonic(strength: Int): String = throw UnavailableException()
    fun isValidMnemonic(mnemonic: String): Boolean = throw UnavailableException()
    fun isValidWord(word: String): Boolean = throw UnavailableException()
    fun suggest(prefix: String): List<String> = throw UnavailableException()
    fun entropyFromMnemonic(mnemonic: String): ByteArray = throw UnavailableException()
    fun addresses(entropy: ByteArray): Map<String, String> = throw UnavailableException()
    fun exportMnemonic(entropy: ByteArray): String = throw UnavailableException()

    data class Signed(val signedTx: ByteArray, val txHash: String)

    fun sign(entropy: ByteArray, coin: String, signingInput: ByteArray): Signed =
        throw UnavailableException()
}
