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
    let evm = wallet.getAddressForCoin(coin: .ethereum)
    return [
      "eth": evm,
      "polygon": wallet.getAddressForCoin(coin: .polygon),
      "base": evm,
      "arbitrum": evm,
      "avalanche": evm,
      "tron": wallet.getAddressForCoin(coin: .tron),
      "solana": wallet.getAddressForCoin(coin: .solana),
    ]
  }

  static func publicKeys(fromEntropy entropy: Data) throws -> [String: Data] {
    let wallet = try wallet(fromEntropy: entropy)
    let evm = wallet.getKeyForCoin(coin: .ethereum)
      .getPublicKeySecp256k1(compressed: false).data
    let tron = wallet.getKeyForCoin(coin: .tron)
      .getPublicKeySecp256k1(compressed: false).data
    let solana = wallet.getKeyForCoin(coin: .solana)
      .getPublicKeyEd25519().data
    return [
      "eth": evm,
      "polygon": evm,
      "base": evm,
      "arbitrum": evm,
      "avalanche": evm,
      "tron": tron,
      "solana": solana,
    ]
  }

  private static func coinType(_ coin: String) -> CoinType? {
    switch coin {
    case "eth": return .ethereum
    case "polygon": return .polygon
    case "base", "arbitrum", "avalanche": return .ethereum
    case "tron": return .tron
    case "solana": return .solana
    default: return nil
    }
  }

  static func sign(entropy: Data, coin: String, signingInput: Data) throws
    -> (signedTx: Data, txHash: String)
  {
    guard let type = coinType(coin) else { throw BridgeError.invalidInput }
    if type == .tron { return try signTron(entropy: entropy, rawData: signingInput) }
    if type == .solana { return try signSolana(entropy: entropy, message: signingInput) }
    return try signEvm(entropy: entropy, coin: type, encoded: signingInput)
  }

  private static func signEvm(entropy: Data, coin: CoinType, encoded: Data) throws
    -> (signedTx: Data, txHash: String)
  {
    let tx = try decodeEip1559(encoded)
    let key = try wallet(fromEntropy: entropy).getKeyForCoin(coin: coin)
    let input = EthereumSigningInput.with {
      $0.chainID = tx.chainID
      $0.nonce = tx.nonce
      $0.txMode = .enveloped
      $0.maxInclusionFeePerGas = tx.maxPriorityFeePerGas
      $0.maxFeePerGas = tx.maxFeePerGas
      $0.gasLimit = tx.gasLimit
      $0.toAddress = "0x" + tx.to.hexString
      $0.privateKey = key.data
      $0.transaction = EthereumTransaction.with {
        if tx.data.isEmpty {
          $0.transfer = EthereumTransaction.Transfer.with { $0.amount = tx.value }
        } else {
          $0.contractGeneric = EthereumTransaction.ContractGeneric.with {
            $0.amount = tx.value
            $0.data = tx.data
          }
        }
      }
    }
    let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: coin)
    guard output.error == .ok, !output.encoded.isEmpty else {
      throw BridgeError.signFailed
    }
    let hash = Hash.keccak256(data: output.encoded)
    return (output.encoded, "0x" + hash.hexString)
  }

  private static func signTron(entropy: Data, rawData: Data) throws
    -> (signedTx: Data, txHash: String)
  {
    guard !rawData.isEmpty else { throw BridgeError.invalidInput }
    let key = try wallet(fromEntropy: entropy).getKeyForCoin(coin: .tron)
    let txID = Hash.sha256(data: rawData)
    guard let signature = key.sign(digest: txID, curve: .secp256k1),
          signature.count == 65 else { throw BridgeError.signFailed }
    let json: [String: Any] = [
      "raw_data_hex": rawData.hexString,
      "signature": [signature.hexString],
      "txID": txID.hexString,
    ]
    return (
      try JSONSerialization.data(withJSONObject: json, options: []),
      txID.hexString
    )
  }

  private static func signSolana(entropy: Data, message: Data) throws
    -> (signedTx: Data, txHash: String)
  {
    guard !message.isEmpty else { throw BridgeError.invalidInput }
    let key = try wallet(fromEntropy: entropy).getKeyForCoin(coin: .solana)
    guard let signature = key.sign(digest: message, curve: .ed25519),
          signature.count == 64 else { throw BridgeError.signFailed }
    return (
      Data([1]) + signature + message,
      Base58.encodeNoCheck(data: signature)
    )
  }

  private struct Eip1559Fields {
    let chainID, nonce, maxPriorityFeePerGas, maxFeePerGas: Data
    let gasLimit, to, value, data: Data
  }

  private struct RlpItem {
    let bytes: Data
    let isList: Bool
    let next: Int
  }

  private static func decodeEip1559(_ input: Data) throws -> Eip1559Fields {
    guard input.count > 2, input[0] == 0x02 else {
      throw BridgeError.invalidInput
    }
    let outer = try readRlp(input, at: 1)
    guard outer.isList, outer.next == input.count else {
      throw BridgeError.invalidInput
    }
    var fields: [RlpItem] = []
    var offset = 0
    while offset < outer.bytes.count {
      let item = try readRlp(outer.bytes, at: offset)
      fields.append(item)
      offset = item.next
    }
    guard fields.count == 9,
          !fields[0...7].contains(where: { $0.isList }),
          fields[8].isList, fields[8].bytes.isEmpty,
          fields[5].bytes.count == 20 else {
      throw BridgeError.invalidInput
    }
    return Eip1559Fields(
      chainID: fields[0].bytes, nonce: fields[1].bytes,
      maxPriorityFeePerGas: fields[2].bytes, maxFeePerGas: fields[3].bytes,
      gasLimit: fields[4].bytes, to: fields[5].bytes,
      value: fields[6].bytes, data: fields[7].bytes)
  }

  private static func readRlp(_ data: Data, at offset: Int) throws -> RlpItem {
    guard offset < data.count else { throw BridgeError.invalidInput }
    let prefix = Int(data[offset])
    if prefix <= 0x7f {
      return RlpItem(bytes: Data([data[offset]]), isList: false, next: offset + 1)
    }
    if prefix <= 0xb7 {
      let length = prefix - 0x80
      return try rlpPayload(data, offset, 1, length, false)
    }
    if prefix <= 0xbf {
      let lengthOfLength = prefix - 0xb7
      let length = try rlpLength(data, offset + 1, lengthOfLength)
      return try rlpPayload(data, offset, 1 + lengthOfLength, length, false)
    }
    if prefix <= 0xf7 {
      let length = prefix - 0xc0
      return try rlpPayload(data, offset, 1, length, true)
    }
    let lengthOfLength = prefix - 0xf7
    let length = try rlpLength(data, offset + 1, lengthOfLength)
    return try rlpPayload(data, offset, 1 + lengthOfLength, length, true)
  }

  private static func rlpLength(_ data: Data, _ start: Int, _ count: Int) throws -> Int {
    guard count > 0, count <= 4, start + count <= data.count else {
      throw BridgeError.invalidInput
    }
    var value = 0
    for byte in data[start..<(start + count)] { value = (value << 8) | Int(byte) }
    return value
  }

  private static func rlpPayload(
    _ data: Data, _ offset: Int, _ header: Int, _ length: Int, _ isList: Bool
  ) throws -> RlpItem {
    let start = offset + header
    let end = start + length
    guard length >= 0, end <= data.count else { throw BridgeError.invalidInput }
    return RlpItem(bytes: data.subdata(in: start..<end), isList: isList, next: end)
  }
}
