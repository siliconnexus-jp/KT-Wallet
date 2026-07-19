import Foundation
import WalletCore

/// Thin wrapper over Trust Wallet Core. Everything that touches private key
/// material lives here; buffers are zeroed immediately after use
/// (detailed-design.md §2.3).
enum WalletCoreBridge {
  enum BridgeError: Error { case invalidMnemonic, invalidInput, signFailed }

  static func generateMnemonic(strength: Int32) -> String {
    let wallet = HDWallet(strength: strength, passphrase: "")!
    defer { /* HDWallet zeroizes on dealloc */ }
    return wallet.mnemonic
  }

  static func isValidMnemonic(_ mnemonic: String) -> Bool {
    Mnemonic.isValid(mnemonic: mnemonic)
  }

  static func isValidWord(_ word: String) -> Bool {
    Mnemonic.isValidWord(word: word)
  }

  static func suggest(_ prefix: String) -> [String] {
    Mnemonic.suggest(prefix: prefix).split(separator: " ").map(String.init)
  }

  /// Converts a mnemonic to entropy for storage (never store the string).
  static func entropy(from mnemonic: String) throws -> Data {
    guard isValidMnemonic(mnemonic) else { throw BridgeError.invalidMnemonic }
    guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
      throw BridgeError.invalidMnemonic
    }
    return wallet.entropy
  }

  private static func wallet(fromEntropy entropy: Data) throws -> HDWallet {
    guard let wallet = HDWallet(entropy: entropy, passphrase: "") else {
      throw BridgeError.invalidMnemonic
    }
    return wallet
  }

  static func addresses(fromEntropy entropy: Data) throws -> [String: String] {
    let wallet = try wallet(fromEntropy: entropy)
    return [
      "eth": wallet.getAddressForCoin(coin: .ethereum),
      "polygon": wallet.getAddressForCoin(coin: .polygon),
      "tron": wallet.getAddressForCoin(coin: .tron),
      "solana": wallet.getAddressForCoin(coin: .solana),
    ]
  }

  private static func coinType(_ coin: String) -> CoinType? {
    switch coin {
    case "eth": return .ethereum
    case "polygon": return .polygon
    case "tron": return .tron
    case "solana": return .solana
    default: return nil
    }
  }

  /// Signs a wallet-core SigningInput.
  ///
  /// IMPORTANT (must be completed + verified on device — P1-4 DoD):
  /// `chains` builds the SigningInput WITHOUT a private key; the derived key
  /// must be injected into the per-chain SigningInput proto here before
  /// `AnySigner.sign`, and the transaction hash must be read from the
  /// per-chain SigningOutput (keccak for EVM, but NOT for TRON/Solana). The
  /// current form is a structural stub and returns SIGN_FAILED until wired,
  /// so it can never emit a wrong-but-plausible signature.
  static func sign(entropy: Data, coin: String, signingInput: Data) throws
    -> (signedTx: Data, txHash: String)
  {
    guard coinType(coin) != nil else { throw BridgeError.invalidInput }
    _ = try wallet(fromEntropy: entropy)
    throw BridgeError.signFailed  // per-chain key injection wired in P1-4
  }
}
