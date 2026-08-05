import Flutter
import LocalAuthentication
import UIKit
import WalletCore

/// Channel dispatcher for `kt/core_crypto` (detailed-design.md §2.1).
///
/// Every argument is validated again at this native trust boundary before it
/// can reach authentication, Keychain, KDF, or Wallet Core.
public class CoreCryptoPlugin: NSObject, FlutterPlugin {
  private static let walletIdMethods: Set<String> = [
    "storeWallet", "walletExists", "deriveAddresses", "derivePublicKeys",
    "signTransaction",
    "exportMnemonic", "createBackup", "deleteWallet",
  ]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kt/core_crypto", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CoreCryptoPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { await self.dispatch(call, result) }
  }

  private func args(_ call: FlutterMethodCall) -> [String: Any] {
    (call.arguments as? [String: Any]) ?? [:]
  }

  private func dispatch(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) async {
    let a = args(call)
    do {
      // Reject malformed identifiers before authentication or native storage.
      // The Dart wrapper validates too; the MethodChannel remains its own
      // trust boundary and must be safe when invoked directly.
      if Self.walletIdMethods.contains(call.method) {
        _ = try requireValidWalletId(a["walletId"])
      }
      switch call.method {
      case "generateMnemonic":
        result(try WalletCoreBridge.generateMnemonic(strength: requireMnemonicStrength(a)))

      case "validateMnemonic":
        result(WalletCoreBridge.isValidMnemonic(try requireMnemonicText(a)))

      case "validateWord":
        result(WalletCoreBridge.isValidWord(try requireWordText(a)))

      case "suggestWords":
        let prefix = try requireSuggestionPrefix(a)
        let limit = try requireSuggestionLimit(a)
        result(prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? [] : Array(WalletCoreBridge.suggest(prefix).prefix(limit)))

      // No AuthGate here, and Android has one — a platform requirement, not a
      // policy difference, so do NOT "align" them. The Keychain access control
      // set by storeWallet gates READS; writing a freshly generated secret in
      // a flow the user is already driving needs no separate prompt. Android's
      // Keystore key is auth-bound at USE time, so its encrypt-on-store must
      // authenticate. What matters is identical on both: exportMnemonic /
      // signTransaction / deleteWallet always authenticate.
      case "storeWallet":
        try storeWallet(a)
        result(true)

      // Presence checks must never open the auth-bound item: startup uses
      // this to detect a missing native wallet before showing AppLockGate.
      case "walletExists":
        result(try KeychainStore.exists(walletId: requireValidWalletId(a["walletId"])))

      case "deriveAddresses":
        result(try deriveAddresses(a))

      case "derivePublicKeys":
        result(try derivePublicKeys(a))

      case "signTransaction":
        result(try await signTransaction(a))

      case "exportMnemonic":
        result(try await exportMnemonic(a))

      // Same secret as exportMnemonic, same auth. The difference is only where
      // it goes — a file the user carries off the device instead of the screen.
      case "createBackup":
        result(FlutterStandardTypedData(bytes: try await createBackup(a)))

      case "readBackup":
        result(try readBackup(a))

      case "deleteWallet":
        try await deleteWallet(a)
        result(true)

      case "getAuthState":
        result(AuthGate.shared.state)

      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let e as AuthGate.GateError {
      result(FlutterError(code: e.code, message: nil, details: ["cooldownSec": e.cooldownSec]))
    } catch let e as WalletCoreBridge.BridgeError {
      result(bridgeError(e))
    } catch KeychainStore.StoreError.notFound {
      result(FlutterError(code: "WALLET_NOT_FOUND", message: nil, details: nil))
    } catch KeychainStore.StoreError.alreadyExists {
      result(FlutterError(code: "WALLET_EXISTS", message: nil, details: nil))
    } catch KeychainStore.StoreError.corrupted {
      result(FlutterError(code: "STORE_CORRUPTED", message: nil, details: nil))
    } catch EntropyCipher.CipherError.openFailed {
      result(FlutterError(code: "STORE_CORRUPTED", message: nil, details: nil))
    } catch PortableBackupCipher.CipherError.openFailed {
      result(FlutterError(code: "STORE_CORRUPTED", message: nil, details: nil))
    } catch WalletIdValidationError.invalid {
      result(FlutterError(code: "INVALID_INPUT", message: nil, details: nil))
    } catch NativeArgumentValidationError.invalid {
      result(FlutterError(code: "INVALID_INPUT", message: nil, details: nil))
    } catch {
      // Never forward raw native exception text. Wallet Core, Keychain and
      // filesystem errors may contain wallet identifiers or operation data.
      result(FlutterError(code: "SIGN_FAILED", message: nil, details: nil))
    }
  }

  // MARK: - operations

  private func storeWallet(_ a: [String: Any]) throws {
    let walletId = try requireValidWalletId(a["walletId"])
    let mnemonic = try requireMnemonicText(a)
    let requireAuth = try optionalBoolArgument(a, "requireAuth", default: true)
    var entropy = try WalletCoreBridge.entropy(from: mnemonic)
    defer { entropy.resetBytes(in: 0..<entropy.count) }

    // Blob header: first byte flags whether the KDF layer is present, so reads
    // can fail closed when the password is missing (enforces invariant 5 at the
    // native layer instead of trusting the caller).
    let kdfPassword = try optionalKDFPassword(a)
    let usesKdf = kdfPassword.map { !$0.isEmpty } ?? false
    var body: Data
    if usesKdf {
      body = try EntropyCipher.seal(
        entropy: entropy, password: kdfPassword!)
    } else {
      body = entropy
    }
    defer { body.resetBytes(in: 0..<body.count) }
    var ciphertext = Data([usesKdf ? 0x01 : 0x00]) + body
    defer { ciphertext.resetBytes(in: 0..<ciphertext.count) }
    try KeychainStore.save(
      walletId: walletId, ciphertext: ciphertext, requireAuth: requireAuth)
  }

  private func withEntropy<T>(
    _ a: [String: Any], context: LAContext, _ body: (Data) throws -> T
  ) throws -> T {
    let walletId = try requireValidWalletId(a["walletId"])
    var stored = try KeychainStore.load(walletId: walletId, context: context)
    defer { stored.resetBytes(in: 0..<stored.count) }
    _ = try requireStoredWalletPayloadSize(stored)
    guard let first = stored.first else { throw KeychainStore.StoreError.corrupted }
    let flag = try requireStoredWalletFlag(first)
    let payload = stored.dropFirst()

    let password = try optionalKDFPassword(a)
    let hasPassword = password.map { !$0.isEmpty } ?? false
    if flag == 0x01 && !hasPassword {
      // KDF-sealed wallet read without its password: fail closed.
      throw KeychainStore.StoreError.corrupted
    }
    var entropy: Data
    if flag == 0x01 {
      entropy = try EntropyCipher.open(sealed: Data(payload), password: password!)
    } else {
      entropy = Data(payload)
    }
    defer { entropy.resetBytes(in: 0..<entropy.count) }
    _ = try requireEntropySize(entropy)
    return try body(entropy)
  }

  /// Derivation does not require auth if the item wasn't stored auth-bound;
  /// a skip-UI context is used so watch-only derivation stays frictionless.
  private func deriveAddresses(_ a: [String: Any]) throws -> [String: String] {
    let context = LAContext()
    context.interactionNotAllowed = false
    return try withEntropy(a, context: context) {
      try WalletCoreBridge.addresses(fromEntropy: $0)
    }
  }

  private func derivePublicKeys(_ a: [String: Any]) throws -> [String: FlutterStandardTypedData] {
    let context = LAContext()
    context.interactionNotAllowed = false
    return try withEntropy(a, context: context) { entropy in
      try WalletCoreBridge.publicKeys(fromEntropy: entropy).mapValues {
        FlutterStandardTypedData(bytes: $0)
      }
    }
  }

  private func signTransaction(_ a: [String: Any]) async throws -> [String: Any] {
    let coin = try requireSupportedCoin(a)
    let input = try requireSigningInput(a)
    let context = try await AuthGate.shared.authenticate(reason: "Authorize transaction signing")
    let signed = try withEntropy(a, context: context) {
      try WalletCoreBridge.sign(entropy: $0, coin: coin, signingInput: input)
    }
    return ["signedTx": FlutterStandardTypedData(bytes: signed.signedTx), "txHash": signed.txHash]
  }

  private func exportMnemonic(_ a: [String: Any]) async throws -> String {
    let context = try await AuthGate.shared.authenticate(reason: "Reveal recovery phrase")
    return try withEntropy(a, context: context) { entropy in
      guard let wallet = HDWallet(entropy: entropy, passphrase: "") else {
        throw WalletCoreBridge.BridgeError.invalidMnemonic
      }
      return wallet.mnemonic
    }
  }

  /// Seals the stored entropy under the user's backup password. Note this
  /// re-seals rather than copying the Keychain blob: that blob may carry the
  /// KDF layer under a *different* password, and a backup nobody can open is
  /// worse than no backup.
  private func createBackup(_ a: [String: Any]) async throws -> Data {
    let password = try requireBackupPassword(a)
    let context = try await AuthGate.shared.authenticate(reason: "Create an encrypted backup")
    return try withEntropy(a, context: context) { entropy in
      try PortableBackupCipher.seal(entropy: entropy, password: password)
    }
  }

  /// Opens a backup blob. No AuthGate: the file already left the device, so
  /// the password is the whole gate, and a device prompt here would only
  /// inconvenience the owner restoring onto a phone they just set up.
  private func readBackup(_ a: [String: Any]) throws -> String {
    let blob = try requireBackupBlob(a)
    let password = try requireBackupPassword(a)
    let formatVersion = try requireIntArgument(a, "formatVersion")
    guard formatVersion == 1 || formatVersion == 2
    else { throw WalletCoreBridge.BridgeError.invalidInput }
    // Both historical iOS v1 and portable v2 use this PBKDF2 format. The
    // Argon2 fallback is Android-only because no released iOS build wrote it.
    var entropy = try PortableBackupCipher.open(sealed: blob, password: password)
    defer { entropy.resetBytes(in: 0..<entropy.count) }
    guard let wallet = HDWallet(entropy: entropy, passphrase: "") else {
      throw WalletCoreBridge.BridgeError.invalidMnemonic
    }
    return wallet.mnemonic
  }

  private func deleteWallet(_ a: [String: Any]) async throws {
    _ = try await AuthGate.shared.authenticate(reason: "Confirm wallet deletion")
    try KeychainStore.delete(walletId: requireValidWalletId(a["walletId"]))
  }

  private func bridgeError(_ e: WalletCoreBridge.BridgeError) -> FlutterError {
    switch e {
    case .invalidMnemonic:
      return FlutterError(code: "INVALID_MNEMONIC", message: nil, details: nil)
    case .invalidInput:
      return FlutterError(code: "INVALID_INPUT", message: nil, details: nil)
    case .signFailed:
      return FlutterError(code: "SIGN_FAILED", message: nil, details: nil)
    }
  }
}
