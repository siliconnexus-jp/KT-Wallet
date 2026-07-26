package com.ktwallet.core_crypto

import com.google.protobuf.ByteString
import wallet.core.java.AnySigner
import wallet.core.jni.CoinType
import wallet.core.jni.Curve
import wallet.core.jni.Base58
import wallet.core.jni.HDWallet
import wallet.core.jni.Hash
import wallet.core.jni.Mnemonic
import wallet.core.jni.proto.Ethereum

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
        "base", "arbitrum", "avalanche" -> CoinType.ETHEREUM
        "tron" -> CoinType.TRON
        "solana" -> CoinType.SOLANA
        else -> throw InvalidInputException()
    }

    fun addresses(entropy: ByteArray): Map<String, String> {
        val wallet = HDWallet(entropy, "")
        return mapOf(
            "eth" to wallet.getAddressForCoin(CoinType.ETHEREUM),
            "polygon" to wallet.getAddressForCoin(CoinType.POLYGON),
            "base" to wallet.getAddressForCoin(CoinType.ETHEREUM),
            "arbitrum" to wallet.getAddressForCoin(CoinType.ETHEREUM),
            "avalanche" to wallet.getAddressForCoin(CoinType.ETHEREUM),
            "tron" to wallet.getAddressForCoin(CoinType.TRON),
            "solana" to wallet.getAddressForCoin(CoinType.SOLANA),
        )
    }

    fun publicKeys(entropy: ByteArray): Map<String, ByteArray> {
        val wallet = HDWallet(entropy, "")
        val evm = wallet.getKeyForCoin(CoinType.ETHEREUM)
            .getPublicKeySecp256k1(false).data()
        val tron = wallet.getKeyForCoin(CoinType.TRON)
            .getPublicKeySecp256k1(false).data()
        val solana = wallet.getKeyForCoin(CoinType.SOLANA)
            .getPublicKeyEd25519().data()
        return mapOf(
            "eth" to evm,
            "polygon" to evm,
            "base" to evm,
            "arbitrum" to evm,
            "avalanche" to evm,
            "tron" to tron,
            "solana" to solana,
        )
    }

    fun exportMnemonic(entropy: ByteArray): String = HDWallet(entropy, "").mnemonic()

    data class Signed(val signedTx: ByteArray, val txHash: String)

    fun sign(entropy: ByteArray, coin: String, signingInput: ByteArray): Signed {
        val type = coinType(coin)
        if (type == CoinType.TRON) return signTron(entropy, signingInput)
        if (type == CoinType.SOLANA) return signSolana(entropy, signingInput)
        if (type != CoinType.ETHEREUM && type != CoinType.POLYGON) throw SignFailedException()
        val tx = decodeEip1559(signingInput)
        val key = HDWallet(entropy, "").getKeyForCoin(type)
        val keyBytes = key.data()
        try {
            val transaction = Ethereum.Transaction.newBuilder()
            if (tx.data.isEmpty()) {
                transaction.transfer = Ethereum.Transaction.Transfer.newBuilder()
                    .setAmount(ByteString.copyFrom(tx.value))
                    .build()
            } else {
                transaction.contractGeneric =
                    Ethereum.Transaction.ContractGeneric.newBuilder()
                        .setAmount(ByteString.copyFrom(tx.value))
                        .setData(ByteString.copyFrom(tx.data))
                        .build()
            }
            val input = Ethereum.SigningInput.newBuilder()
                .setChainId(ByteString.copyFrom(tx.chainId))
                .setNonce(ByteString.copyFrom(tx.nonce))
                .setTxMode(Ethereum.TransactionMode.Enveloped)
                .setMaxInclusionFeePerGas(ByteString.copyFrom(tx.maxPriorityFeePerGas))
                .setMaxFeePerGas(ByteString.copyFrom(tx.maxFeePerGas))
                .setGasLimit(ByteString.copyFrom(tx.gasLimit))
                .setToAddress("0x${tx.to.toHex()}")
                .setTransaction(transaction)
                .setPrivateKey(ByteString.copyFrom(keyBytes))
                .build()
            val output = AnySigner.sign(
                input,
                type,
                Ethereum.SigningOutput.parser(),
            )
            if (output.errorValue != 0 || output.encoded.isEmpty) {
                throw SignFailedException()
            }
            val encoded = output.encoded.toByteArray()
            return Signed(encoded, "0x${Hash.keccak256(encoded).toHex()}")
        } catch (e: SignFailedException) {
            throw e
        } catch (_: Exception) {
            throw SignFailedException()
        } finally {
            keyBytes.fill(0)
        }
    }

    /** Signs canonical TRON Transaction.raw bytes and emits broadcasthex JSON. */
    private fun signTron(entropy: ByteArray, rawData: ByteArray): Signed {
        if (rawData.isEmpty()) throw InvalidInputException()
        val key = HDWallet(entropy, "").getKeyForCoin(CoinType.TRON)
        val keyBytes = key.data()
        try {
            val txIdBytes = Hash.sha256(rawData)
            val signature = key.sign(txIdBytes, Curve.SECP256K1)
            if (signature.size != 65) throw SignFailedException()
            val txId = txIdBytes.toHex()
            val json =
                """{"raw_data_hex":"${rawData.toHex()}","signature":["${signature.toHex()}"],"txID":"$txId"}"""
                    .toByteArray(Charsets.UTF_8)
            return Signed(json, txId)
        } catch (e: SignFailedException) {
            throw e
        } catch (_: Exception) {
            throw SignFailedException()
        } finally {
            keyBytes.fill(0)
        }
    }

    /** Signs a legacy Solana message and emits the canonical wire transaction. */
    private fun signSolana(entropy: ByteArray, message: ByteArray): Signed {
        if (message.isEmpty()) throw InvalidInputException()
        val key = HDWallet(entropy, "").getKeyForCoin(CoinType.SOLANA)
        val keyBytes = key.data()
        try {
            val signature = key.sign(message, Curve.ED25519)
            if (signature.size != 64) throw SignFailedException()
            val encoded = byteArrayOf(1) + signature + message
            return Signed(encoded, Base58.encodeNoCheck(signature))
        } catch (e: SignFailedException) {
            throw e
        } catch (_: Exception) {
            throw SignFailedException()
        } finally {
            keyBytes.fill(0)
        }
    }

    private data class Eip1559Fields(
        val chainId: ByteArray,
        val nonce: ByteArray,
        val maxPriorityFeePerGas: ByteArray,
        val maxFeePerGas: ByteArray,
        val gasLimit: ByteArray,
        val to: ByteArray,
        val value: ByteArray,
        val data: ByteArray,
    )

    private data class RlpItem(
        val bytes: ByteArray,
        val isList: Boolean,
        val next: Int,
    )

    /** Decodes the exact unsigned type-2 envelope emitted by `chains`. */
    private fun decodeEip1559(input: ByteArray): Eip1559Fields {
        if (input.size < 3 || input[0] != 0x02.toByte()) {
            throw InvalidInputException()
        }
        val outer = readRlp(input, 1)
        if (!outer.isList || outer.next != input.size) throw InvalidInputException()
        val fields = mutableListOf<RlpItem>()
        var offset = 0
        while (offset < outer.bytes.size) {
            val item = readRlp(outer.bytes, offset)
            fields += item
            offset = item.next
        }
        if (fields.size != 9 || fields.take(8).any { it.isList }) {
            throw InvalidInputException()
        }
        // V1 only permits an empty access list.
        if (!fields[8].isList || fields[8].bytes.isNotEmpty()) {
            throw InvalidInputException()
        }
        val to = fields[5].bytes
        if (to.size != 20) throw InvalidInputException()
        return Eip1559Fields(
            fields[0].bytes,
            fields[1].bytes,
            fields[2].bytes,
            fields[3].bytes,
            fields[4].bytes,
            to,
            fields[6].bytes,
            fields[7].bytes,
        )
    }

    private fun readRlp(source: ByteArray, start: Int): RlpItem {
        if (start !in source.indices) throw InvalidInputException()
        val prefix = source[start].toInt() and 0xff
        return when {
            prefix <= 0x7f -> RlpItem(byteArrayOf(source[start]), false, start + 1)
            prefix <= 0xb7 -> sliceRlp(source, start, prefix - 0x80, 1, false)
            prefix <= 0xbf -> {
                val sizeBytes = prefix - 0xb7
                sliceRlp(source, start, readLength(source, start + 1, sizeBytes),
                    1 + sizeBytes, false)
            }
            prefix <= 0xf7 -> sliceRlp(source, start, prefix - 0xc0, 1, true)
            else -> {
                val sizeBytes = prefix - 0xf7
                sliceRlp(source, start, readLength(source, start + 1, sizeBytes),
                    1 + sizeBytes, true)
            }
        }
    }

    private fun sliceRlp(
        source: ByteArray,
        start: Int,
        length: Int,
        header: Int,
        isList: Boolean,
    ): RlpItem {
        val from = start + header
        val end = from + length
        if (length < 0 || from < 0 || end < from || end > source.size) {
            throw InvalidInputException()
        }
        return RlpItem(source.copyOfRange(from, end), isList, end)
    }

    private fun readLength(source: ByteArray, start: Int, count: Int): Int {
        if (count !in 1..4 || start + count > source.size || source[start] == 0.toByte()) {
            throw InvalidInputException()
        }
        var value = 0
        repeat(count) { value = (value shl 8) or (source[start + it].toInt() and 0xff) }
        return value
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
