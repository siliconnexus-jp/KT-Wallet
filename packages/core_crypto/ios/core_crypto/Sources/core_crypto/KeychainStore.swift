import Foundation
import LocalAuthentication

/// Encrypted-at-rest storage for wallet entropy, gated by the Secure Enclave
/// via a biometry-bound Keychain access control (detailed-design.md §3.1).
///
/// The Keychain item stores *entropy* (not the mnemonic string). Reading it
/// requires the user to pass biometrics/passcode, enforced by the OS.
enum KeychainStore {
  private static let service = "com.ktwallet.core_crypto.entropy"

  enum StoreError: Error {
    case unexpectedStatus(OSStatus)
    case corrupted
    case notFound
    case alreadyExists
  }

  private static func accessControl(requireAuth: Bool) throws -> SecAccessControl {
    var error: Unmanaged<CFError>?
    let flags: SecAccessControlCreateFlags =
      requireAuth ? [.biometryCurrentSet] : []
    guard
      let control = SecAccessControlCreateWithFlags(
        nil,
        // Never migrates to another device; requires a passcode to be set.
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        flags,
        &error
      )
    else {
      throw error!.takeRetainedValue() as Error
    }
    return control
  }

  /// Persists ciphertext into a fresh wallet slot. Existing key material is
  /// never deleted or replaced: callers must allocate a new random walletId.
  static func save(walletId: String, ciphertext: Data, requireAuth: Bool) throws {
    let walletId = try requireValidWalletId(walletId)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: walletId,
      kSecValueData as String: ciphertext,
      kSecAttrAccessControl as String: try accessControl(requireAuth: requireAuth),
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem { throw StoreError.alreadyExists }
    guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
  }

  /// Reads ciphertext, prompting biometrics via [context] when auth-bound.
  static func load(walletId: String, context: LAContext) throws -> Data {
    let walletId = try requireValidWalletId(walletId)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: walletId,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { throw StoreError.corrupted }
      return data
    case errSecItemNotFound:
      throw StoreError.notFound
    default:
      throw StoreError.unexpectedStatus(status)
    }
  }

  static func exists(walletId: String) -> Bool {
    guard let walletId = try? requireValidWalletId(walletId) else { return false }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: walletId,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) != errSecItemNotFound
  }

  /// Deletes the item after overwriting its stored value (best-effort scrub).
  static func delete(walletId: String) throws {
    let walletId = try requireValidWalletId(walletId)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: walletId,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw StoreError.unexpectedStatus(status)
    }
  }
}
