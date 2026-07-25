package com.ktwallet.core_crypto

import wallet.core.jni.CoinType
import wallet.core.jni.HDWallet
import wallet.core.jni.Hash
import wallet.core.jni.Mnemonic
import wallet.core.jni.AnySigner

/**
 * Trust Wallet Core wrapper. All private-key handling lives here; sensitive
 * byte arrays are zeroed after use (detailed-design.md §2.3).
 */
object WalletCoreBridge {
    init {
        System.loadLibrary("TrustWalletCore")
    }

    class InvalidMnemonicException : Exception("invalid mnemonic")
    class InvalidInputException : Exception("invalid signing input")
    class SignFailedException : Exception("signing failed")
    // Kept in the common bridge surface so CoreCryptoPlugin can map the
    // fail-closed build without conditional source code.
    class UnavailableException : Exception("Trust Wallet Core is unavailable")

    fun generateMnemonic(strength: Int): String {
        val wallet = HDWallet(strength, "")
        return wallet.mnemonic()
    }

    fun isValidMnemonic(mnemonic: String): Boolean = Mnemonic.isValid(mnemonic)
    fun isValidWord(word: String): Boolean = Mnemonic.isValidWord(word)
    fun suggest(prefix: String): List<String> =
        Mnemonic.suggest(prefix).split(" ").filter { it.isNotEmpty() }

    fun entropyFromMnemonic(mnemonic: String): ByteArray {
        if (!isValidMnemonic(mnemonic)) throw InvalidMnemonicException()
        return HDWallet(mnemonic, "").entropy()
    }

    private fun coinType(coin: String): CoinType = when (coin) {
        "eth" -> CoinType.ETHEREUM
        "polygon" -> CoinType.POLYGON
        "tron" -> CoinType.TRON
        "solana" -> CoinType.SOLANA
        else -> throw InvalidInputException()
    }

    fun addresses(entropy: ByteArray): Map<String, String> {
        val wallet = HDWallet(entropy, "")
        return mapOf(
            "eth" to wallet.getAddressForCoin(CoinType.ETHEREUM),
            "polygon" to wallet.getAddressForCoin(CoinType.POLYGON),
            "tron" to wallet.getAddressForCoin(CoinType.TRON),
            "solana" to wallet.getAddressForCoin(CoinType.SOLANA),
        )
    }

    fun exportMnemonic(entropy: ByteArray): String = HDWallet(entropy, "").mnemonic()

    data class Signed(val signedTx: ByteArray, val txHash: String)

    /**
     * IMPORTANT (must be completed + verified on device — P1-4 DoD):
     * `chains` builds the SigningInput WITHOUT a private key; the derived key
     * must be injected into the per-chain SigningInput proto here before
     * [AnySigner.sign], and the tx hash read from the per-chain SigningOutput
     * (keccak for EVM, NOT for TRON/Solana). Structural stub until wired, so it
     * can never emit a wrong-but-plausible signature.
     */
    fun sign(entropy: ByteArray, coin: String, signingInput: ByteArray): Signed {
        coinType(coin) // validates coin
        HDWallet(entropy, "") // validates entropy
        throw SignFailedException() // per-chain key injection wired in P1-4
    }
}
