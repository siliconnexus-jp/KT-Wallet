import CommonCrypto
import CryptoKit
import Foundation

/// Optional Cold Signer second encryption layer: the app password is stretched
/// with a memory/CPU-hard-ish KDF and used to AES-GCM seal the entropy *before*
/// it enters the Keychain (detailed-design.md §2.2, §3.3). Both layers must
/// pass to recover the entropy. Layout: salt(16) || gcmSealed.
enum EntropyCipher {
  enum CipherError: Error { case rngFailed, kdfFailed, sealFailed, openFailed }

  private static let saltLength = 16
  /// PBKDF2 is used as the concrete stretching KDF available in the iOS SDK
  /// with no extra dependency. Target is Argon2id (matching Android); swap
  /// `deriveKey` once a vetted Swift Argon2 is vendored. This is a real
  /// password-stretching KDF — never HKDF.
  private static let pbkdf2Rounds: UInt32 = 210_000

  static func seal(entropy: Data, password: String) throws -> Data {
    var salt = Data(count: saltLength)
    let status = salt.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
    }
    guard status == errSecSuccess else { throw CipherError.rngFailed }

    let key = try deriveKey(password: password, salt: salt)
    let sealed = try AES.GCM.seal(entropy, using: key)
    guard let combined = sealed.combined else { throw CipherError.sealFailed }
    return salt + combined
  }

  static func open(sealed: Data, password: String) throws -> Data {
    guard sealed.count > saltLength else { throw CipherError.openFailed }
    let salt = Data(sealed.prefix(saltLength))
    let key = try deriveKey(password: password, salt: salt)
    do {
      let box = try AES.GCM.SealedBox(combined: sealed.suffix(from: saltLength))
      return try AES.GCM.open(box, using: key)
    } catch {
      throw CipherError.openFailed
    }
  }

  private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
    let pwData = Array(password.utf8)
    var derived = [UInt8](repeating: 0, count: 32)
    let result = salt.withUnsafeBytes { saltPtr in
      CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        password, pwData.count,
        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        pbkdf2Rounds,
        &derived, derived.count
      )
    }
    guard result == kCCSuccess else { throw CipherError.kdfFailed }
    let key = SymmetricKey(data: Data(derived))
    derived.resetBytes(in: 0..<derived.count)
    return key
  }
}

private extension Array where Element == UInt8 {
  mutating func resetBytes(in range: Range<Int>) {
    for i in range { self[i] = 0 }
  }
}
