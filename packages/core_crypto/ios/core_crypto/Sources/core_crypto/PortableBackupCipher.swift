import CommonCrypto
import CryptoKit
import Foundation

/// Cross-platform KT backup payload cipher.
///
/// Layout: salt(16) || nonce(12) || ciphertext || GCM tag(16). This is kept
/// separate from EntropyCipher, whose device-local storage KDF may evolve
/// independently and must never silently change the portable file format.
enum PortableBackupCipher {
  enum CipherError: Error { case rngFailed, invalidInput, kdfFailed, sealFailed, openFailed }

  static let saltLength = 16
  static let nonceLength = 12
  static let tagLength = 16
  static let pbkdf2Rounds: UInt32 = 210_000

  static func seal(entropy: Data, password: String) throws -> Data {
    guard !entropy.isEmpty, !password.isEmpty else { throw CipherError.invalidInput }
    var salt = Data(count: saltLength)
    var nonce = Data(count: nonceLength)
    guard salt.withUnsafeMutableBytes({
      SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
    }) == errSecSuccess,
      nonce.withUnsafeMutableBytes({
        SecRandomCopyBytes(kSecRandomDefault, nonceLength, $0.baseAddress!)
      }) == errSecSuccess
    else { throw CipherError.rngFailed }
    return try seal(entropy: entropy, password: password, salt: salt, nonce: nonce)
  }

  /// Deterministic entry used only by native interoperability tests.
  static func seal(
    entropy: Data,
    password: String,
    salt: Data,
    nonce: Data
  ) throws -> Data {
    guard !entropy.isEmpty, !password.isEmpty,
      salt.count == saltLength, nonce.count == nonceLength
    else { throw CipherError.invalidInput }
    let key = try deriveKey(password: password, salt: salt)
    let gcmNonce: AES.GCM.Nonce
    do {
      gcmNonce = try AES.GCM.Nonce(data: nonce)
    } catch {
      throw CipherError.sealFailed
    }
    let sealed = try AES.GCM.seal(entropy, using: key, nonce: gcmNonce)
    guard let combined = sealed.combined else { throw CipherError.sealFailed }
    return salt + combined
  }

  static func open(sealed: Data, password: String) throws -> Data {
    guard sealed.count > saltLength + nonceLength + tagLength, !password.isEmpty else {
      throw CipherError.openFailed
    }
    let salt = Data(sealed.prefix(saltLength))
    let key: SymmetricKey
    do {
      key = try deriveKey(password: password, salt: salt)
    } catch {
      throw CipherError.openFailed
    }
    do {
      let box = try AES.GCM.SealedBox(combined: sealed.suffix(from: saltLength))
      return try AES.GCM.open(box, using: key)
    } catch {
      throw CipherError.openFailed
    }
  }

  private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
    var passwordBytes = Array(password.utf8)
    var derived = [UInt8](repeating: 0, count: 32)
    defer {
      for index in passwordBytes.indices { passwordBytes[index] = 0 }
      for index in derived.indices { derived[index] = 0 }
    }
    let result = passwordBytes.withUnsafeBytes { passwordPtr in
      salt.withUnsafeBytes { saltPtr in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          passwordPtr.bindMemory(to: Int8.self).baseAddress,
          passwordBytes.count,
          saltPtr.bindMemory(to: UInt8.self).baseAddress,
          salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          pbkdf2Rounds,
          &derived,
          derived.count
        )
      }
    }
    guard result == kCCSuccess else { throw CipherError.kdfFailed }
    return SymmetricKey(data: Data(derived))
  }
}
