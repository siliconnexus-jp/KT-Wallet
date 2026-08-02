import Flutter
import Foundation

enum NativeArgumentValidationError: Error {
  case invalid
}

let maxMnemonicUTF8Bytes = 512
let maxWordUTF8Bytes = 64
let maxKDFPasswordUTF8Bytes = 1024
let maxBackupPasswordUTF8Bytes = 4096
let maxSigningInputBytes = 1024 * 1024
let validBackupBlobSizes: Set<Int> = [60, 68, 76]
let supportedCoins: Set<String> = [
  "eth", "polygon", "base", "arbitrum", "avalanche", "bnb", "tron", "solana",
]
let validEntropySizes: Set<Int> = [16, 24, 32]
let validStoredWalletPayloadSizes: Set<Int> = [17, 25, 33, 61, 69, 77]

/// MethodChannel is a native trust boundary. Reject malformed direct calls
/// before authentication, Keychain, KDF, Wallet Core, or force casts.
func requireStringArgument(_ arguments: [String: Any], _ name: String) throws -> String {
  guard let value = arguments[name] as? String else {
    throw NativeArgumentValidationError.invalid
  }
  return value
}

func optionalStringArgument(_ arguments: [String: Any], _ name: String) throws -> String? {
  guard let raw = arguments[name], !(raw is NSNull) else { return nil }
  guard let value = raw as? String else { throw NativeArgumentValidationError.invalid }
  return value
}

func requireDataArgument(_ arguments: [String: Any], _ name: String) throws -> Data {
  guard let value = arguments[name] as? FlutterStandardTypedData else {
    throw NativeArgumentValidationError.invalid
  }
  return value.data
}

func requireIntArgument(_ arguments: [String: Any], _ name: String) throws -> Int {
  guard let value = arguments[name] as? Int else {
    throw NativeArgumentValidationError.invalid
  }
  return value
}

func optionalBoolArgument(
  _ arguments: [String: Any], _ name: String, default defaultValue: Bool
) throws -> Bool {
  guard let raw = arguments[name], !(raw is NSNull) else { return defaultValue }
  guard let value = raw as? Bool else { throw NativeArgumentValidationError.invalid }
  return value
}

func requireMnemonicStrength(_ arguments: [String: Any]) throws -> Int32 {
  let strength = try requireIntArgument(arguments, "strength")
  guard strength == 128 || strength == 192 || strength == 256 else {
    throw NativeArgumentValidationError.invalid
  }
  return Int32(strength)
}

func requireSuggestionLimit(_ arguments: [String: Any]) throws -> Int {
  let limit = try requireIntArgument(arguments, "limit")
  guard (1...20).contains(limit) else { throw NativeArgumentValidationError.invalid }
  return limit
}

private func requireUTF8Bounded(
  _ arguments: [String: Any], _ name: String, maxBytes: Int, allowBlank: Bool
) throws -> String {
  let value = try requireStringArgument(arguments, name)
  if !allowBlank && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw NativeArgumentValidationError.invalid
  }
  guard value.utf8.count <= maxBytes else { throw NativeArgumentValidationError.invalid }
  return value
}

func requireMnemonicText(_ arguments: [String: Any]) throws -> String {
  try requireUTF8Bounded(
    arguments, "mnemonic", maxBytes: maxMnemonicUTF8Bytes, allowBlank: false)
}

func requireWordText(_ arguments: [String: Any]) throws -> String {
  try requireUTF8Bounded(arguments, "word", maxBytes: maxWordUTF8Bytes, allowBlank: true)
}

func requireSuggestionPrefix(_ arguments: [String: Any]) throws -> String {
  try requireUTF8Bounded(arguments, "prefix", maxBytes: maxWordUTF8Bytes, allowBlank: true)
}

func optionalKDFPassword(_ arguments: [String: Any]) throws -> String? {
  guard let password = try optionalStringArgument(arguments, "kdfPassword") else { return nil }
  if password.isEmpty { return password }
  guard password.utf8.count <= maxKDFPasswordUTF8Bytes else {
    throw NativeArgumentValidationError.invalid
  }
  return password
}

func requireBackupPassword(_ arguments: [String: Any]) throws -> String {
  try requireUTF8Bounded(
    arguments, "password", maxBytes: maxBackupPasswordUTF8Bytes, allowBlank: false)
}

func requireSupportedCoin(_ arguments: [String: Any]) throws -> String {
  let coin = try requireStringArgument(arguments, "coin")
  guard supportedCoins.contains(coin) else { throw NativeArgumentValidationError.invalid }
  return coin
}

func requireSigningInput(_ arguments: [String: Any]) throws -> Data {
  let input = try requireDataArgument(arguments, "signingInput")
  guard !input.isEmpty, input.count <= maxSigningInputBytes else {
    throw NativeArgumentValidationError.invalid
  }
  return input
}

func requireBackupBlob(_ arguments: [String: Any]) throws -> Data {
  let blob = try requireDataArgument(arguments, "blob")
  guard validBackupBlobSizes.contains(blob.count) else {
    throw NativeArgumentValidationError.invalid
  }
  return blob
}

func requireStoredWalletFlag(_ flag: UInt8) throws -> UInt8 {
  guard flag == 0 || flag == 1 else { throw KeychainStore.StoreError.corrupted }
  return flag
}

func requireStoredWalletPayloadSize(_ payload: Data) throws -> Data {
  guard validStoredWalletPayloadSizes.contains(payload.count) else {
    throw KeychainStore.StoreError.corrupted
  }
  return payload
}

func requireEntropySize(_ entropy: Data) throws -> Data {
  guard validEntropySizes.contains(entropy.count) else {
    throw KeychainStore.StoreError.corrupted
  }
  return entropy
}
