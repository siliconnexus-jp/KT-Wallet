import Flutter
import LocalAuthentication
import UIKit
import WalletCore

/// Channel dispatcher for `kt/core_crypto` (detailed-design.md §2.1).
///
/// The Dart side already validated arguments; here we only decode, route to
/// the native components, and translate errors into the shared error codes.
public class CoreCryptoPlugin: NSObject, FlutterPlugin {
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
      switch call.method {
      case "generateMnemonic":
        let strength = Int32(a["strength"] as? Int ?? 128)
        result(WalletCoreBridge.generateMnemonic(strength: strength))

      case "validateMnemonic":
        result(WalletCoreBridge.isValidMnemonic(a["mnemonic"] as? String ?? ""))

      case "validateWord":
        result(WalletCoreBridge.isValidWord(a["word"] as? String ?? ""))

      case "suggestWords":
        result(WalletCoreBridge.suggest(a["prefix"] as? String ?? ""))

      case "storeWallet":
        try storeWallet(a)
        result(true)

      case "deriveAddresses":
        result(try deriveAddresses(a))

      case "derivePublicKeys":
        result(try derivePublicKeys(a))

      case "signTransaction":
        result(try await signTransaction(a))

      case "exportMnemonic":
        result(try await exportMnemonic(a))

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
    } catch KeychainStore.StoreError.corrupted {
      result(FlutterError(code: "STORE_CORRUPTED", message: nil, details: nil))
    } catch EntropyCipher.CipherError.openFailed {
      result(FlutterError(code: "STORE_CORRUPTED", message: "kdf layer failed", details: nil))
    } catch {
      result(FlutterError(code: "SIGN_FAILED", message: "\(error)", details: nil))
    }
  }

  // MARK: - operations

  private func storeWallet(_ a: [String: Any]) throws {
    let walletId = a["walletId"] as! String
    let mnemonic = a["mnemonic"] as! String
    let requireAuth = a["requireAuth"] as? Bool ?? true
    var entropy = try WalletCoreBridge.entropy(from: mnemonic)
    defer { entropy.resetBytes(in: 0..<entropy.count) }

    // Blob header: first byte flags whether the KDF layer is present, so reads
    // can fail closed when the password is missing (enforces invariant 5 at the
    // native layer instead of trusting the caller).
    let usesKdf = (a["kdfPassword"] as? String).map { !$0.isEmpty } ?? false
    var body: Data
    if usesKdf {
      body = try EntropyCipher.seal(
        entropy: entropy, password: a["kdfPassword"] as! String)
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
    let walletId = a["walletId"] as! String
    var stored = try KeychainStore.load(walletId: walletId, context: context)
    defer { stored.resetBytes(in: 0..<stored.count) }
    guard let flag = stored.first else { throw KeychainStore.StoreError.corrupted }
    let payload = stored.dropFirst()

    let password = a["kdfPassword"] as? String
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
    let context = try await AuthGate.shared.authenticate(reason: "Authorize transaction signing")
    let coin = a["coin"] as! String
    let input = (a["signingInput"] as! FlutterStandardTypedData).data
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

  private func deleteWallet(_ a: [String: Any]) async throws {
    _ = try await AuthGate.shared.authenticate(reason: "Confirm wallet deletion")
    try KeychainStore.delete(walletId: a["walletId"] as! String)
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
