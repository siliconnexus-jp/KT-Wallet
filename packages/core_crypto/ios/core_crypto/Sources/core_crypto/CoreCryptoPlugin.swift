import Flutter
import LocalAuthentication
import UIKit
import WalletCore

/// Channel dispatcher for `kt/core_crypto` (detailed-design.md §2.1).
///
/// Every argument is validated again at this native trust boundary before it
/// can reach authentication, Keychain, KDF, or Wallet Core.
public class CoreCryptoPlugin: NSObject, FlutterPlugin {
  private final class PrivateKeySession {
    let walletId: String
    var keys: [String: NSMutableData]
    let expiresAt: Date

    init(walletId: String, keys: [String: Data], expiresAt: Date) {
      self.walletId = walletId
      self.keys = keys.mapValues { NSMutableData(data: $0) }
      self.expiresAt = expiresAt
    }

    func wipe() {
      for value in keys.values where value.length > 0 {
        memset(value.mutableBytes, 0, value.length)
      }
      keys.removeAll(keepingCapacity: false)
    }

    deinit { wipe() }
  }

  private let privateKeySessionLock = NSLock()
  private var privateKeySessions: [String: PrivateKeySession] = [:]
  private let privateKeyViews = NSHashTable<PrivateKeyPlatformView>.weakObjects()

  private static let walletIdMethods: Set<String> = [
    "storeWallet", "walletExists", "deriveAddresses", "derivePublicKeys",
    "signTransaction",
    "exportMnemonic", "beginPrivateKeyExport", "createBackup", "deleteWallet",
    "signTransactionForIntegrationTest", "deleteWalletForIntegrationTest",
  ]

  public override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(clearPrivateKeySessionsForBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    clearPrivateKeySessions()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kt/core_crypto", binaryMessenger: registrar.messenger())
    let plugin = CoreCryptoPlugin()
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(
      PrivateKeyPlatformViewFactory(plugin: plugin),
      withId: "kt/private_key_view")
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
      case "beginPrivateKeyExport":
        try requireExactArgumentKeys(a, ["walletId"])
      case "copyPrivateKey":
        try requireExactArgumentKeys(a, ["sessionId", "coin", "mode"])
      case "endPrivateKeyExport":
        try requireExactArgumentKeys(a, ["sessionId"])
      default:
        break
      }
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

      case "beginPrivateKeyExport":
        result(try await beginPrivateKeyExport(a))

      case "copyPrivateKey":
        result(try await copyPrivateKey(a))

      case "endPrivateKeyExport":
        try endPrivateKeyExport(a)
        result(true)

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

      #if DEBUG
      // Physical-device integration tests must be able to complete without a
      // human satisfying an out-of-process Face ID sheet. These methods still
      // use the real Keychain payload and Wallet Core implementation, and are
      // restricted to the reserved test-wallet namespace. They do not exist
      // in profile/release builds.
      case "signTransactionForIntegrationTest":
        result(try signTransactionForIntegrationTest(a))

      case "deleteWalletForIntegrationTest":
        try deleteWalletForIntegrationTest(a)
        result(true)
      #endif

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

  #if DEBUG
  private func requireIntegrationTestWalletId(_ value: Any?) throws -> String {
    let walletId = try requireValidWalletId(value)
    guard walletId.hasPrefix("kt-e2e-") else {
      throw WalletCoreBridge.BridgeError.invalidInput
    }
    return walletId
  }

  private func signTransactionForIntegrationTest(_ a: [String: Any]) throws -> [String: Any] {
    _ = try requireIntegrationTestWalletId(a["walletId"])
    let coin = try requireSupportedCoin(a)
    let input = try requireSigningInput(a)
    let context = LAContext()
    let signed = try withEntropy(a, context: context) {
      try WalletCoreBridge.sign(entropy: $0, coin: coin, signingInput: input)
    }
    return ["signedTx": FlutterStandardTypedData(bytes: signed.signedTx), "txHash": signed.txHash]
  }

  private func deleteWalletForIntegrationTest(_ a: [String: Any]) throws {
    let walletId = try requireIntegrationTestWalletId(a["walletId"])
    try KeychainStore.delete(walletId: walletId)
  }
  #endif

  private func exportMnemonic(_ a: [String: Any]) async throws -> String {
    let context = try await AuthGate.shared.authenticate(reason: "Reveal recovery phrase")
    return try withEntropy(a, context: context) { entropy in
      guard let wallet = HDWallet(entropy: entropy, passphrase: "") else {
        throw WalletCoreBridge.BridgeError.invalidMnemonic
      }
      return wallet.mnemonic
    }
  }

  private func beginPrivateKeyExport(_ a: [String: Any]) async throws -> String {
    let walletId = try requireValidWalletId(a["walletId"])
    let context = try await AuthGate.shared.authenticate(reason: "View private keys")
    var keys = try withEntropy(a, context: context) {
      try WalletCoreBridge.privateKeys(fromEntropy: $0)
    }
    defer {
      for (name, var value) in keys {
        value.resetBytes(in: 0..<value.count)
        keys[name] = value
      }
      keys.removeAll(keepingCapacity: false)
    }
    let sessionId = UUID().uuidString
    let session = PrivateKeySession(
      walletId: walletId,
      keys: keys,
      expiresAt: Date().addingTimeInterval(5 * 60))
    storePrivateKeySession(session, id: sessionId)
    return sessionId
  }

  private func copyPrivateKey(_ a: [String: Any]) async throws -> [String: String] {
    let sessionId = try requirePrivateKeySessionId(a)
    let coin = try requireSupportedCoin(a)
    let mode = try requirePrivateKeyCopyMode(a)
    let family = try privateKeyFamily(coin)
    var key = try privateKeyData(sessionId: sessionId, family: family)
    defer { key.resetBytes(in: 0..<key.count) }
    var encoded = try WalletCoreBridge.encodePrivateKey(key, coin: coin)
    guard encoded.count > 6 else { throw NativeArgumentValidationError.invalid }
    let suffix = mode == "safe" ? String(encoded.suffix(6)) : ""
    let clipboardValue = mode == "safe" ? String(encoded.dropLast(6)) : encoded
    await MainActor.run {
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": clipboardValue]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(60),
        ])
    }
    encoded = ""
    return ["suffix": suffix]
  }

  private func endPrivateKeyExport(_ a: [String: Any]) throws {
    let sessionId = try requirePrivateKeySessionId(a)
    privateKeySessionLock.lock()
    privateKeySessions.removeValue(forKey: sessionId)?.wipe()
    privateKeySessionLock.unlock()
  }

  private func storePrivateKeySession(_ session: PrivateKeySession, id: String) {
    privateKeySessionLock.lock()
    clearExpiredPrivateKeySessionsLocked()
    let previous = privateKeySessions.filter { $0.value.walletId == session.walletId }.map(\.key)
    for sessionId in previous {
      privateKeySessions.removeValue(forKey: sessionId)?.wipe()
    }
    privateKeySessions[id] = session
    privateKeySessionLock.unlock()
  }

  private func privateKeyData(sessionId: String, family: String) throws -> Data {
    privateKeySessionLock.lock()
    defer { privateKeySessionLock.unlock() }
    clearExpiredPrivateKeySessionsLocked()
    guard let stored = privateKeySessions[sessionId]?.keys[family] else {
      throw NativeArgumentValidationError.invalid
    }
    return Data(bytes: stored.bytes, count: stored.length)
  }

  fileprivate func privateKeyText(_ arguments: Any?) throws -> String {
    guard let a = arguments as? [String: Any],
          Set(a.keys) == Set(["sessionId", "coin"])
    else { throw NativeArgumentValidationError.invalid }
    let sessionId = try requirePrivateKeySessionId(a)
    let coin = try requireSupportedCoin(a)
    let family = try privateKeyFamily(coin)
    var key = try privateKeyData(sessionId: sessionId, family: family)
    defer { key.resetBytes(in: 0..<key.count) }
    return try WalletCoreBridge.encodePrivateKey(key, coin: coin)
  }

  fileprivate func registerPrivateKeyView(_ view: PrivateKeyPlatformView) {
    privateKeyViews.add(view)
  }

  private func privateKeyFamily(_ coin: String) throws -> String {
    switch coin {
    case "eth", "polygon", "base", "arbitrum", "avalanche", "bnb": return "evm"
    case "tron": return "tron"
    case "solana": return "solana"
    default: throw NativeArgumentValidationError.invalid
    }
  }

  private func clearExpiredPrivateKeySessionsLocked() {
    let expired = privateKeySessions.filter { $0.value.expiresAt <= Date() }.map(\.key)
    for sessionId in expired {
      privateKeySessions.removeValue(forKey: sessionId)?.wipe()
    }
  }

  private func clearPrivateKeySessions() {
    privateKeySessionLock.lock()
    for session in privateKeySessions.values { session.wipe() }
    privateKeySessions.removeAll(keepingCapacity: false)
    privateKeySessionLock.unlock()
    let views = privateKeyViews.allObjects
    DispatchQueue.main.async {
      for view in views { view.conceal() }
    }
  }

  @objc private func clearPrivateKeySessionsForBackground() {
    clearPrivateKeySessions()
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

fileprivate final class PrivateKeyPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: CoreCryptoPlugin?

  init(plugin: CoreCryptoPlugin) {
    self.plugin = plugin
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let text = try? plugin?.privateKeyText(args)
    let view = PrivateKeyPlatformView(frame: frame, text: text ?? "")
    plugin?.registerPrivateKeyView(view)
    return view
  }
}

fileprivate final class PrivateKeyPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let label: UITextView
  private var concealTimer: Timer?

  init(frame: CGRect, text: String) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    label = UITextView(frame: container.bounds)
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    label.backgroundColor = .clear
    label.text = text
    label.textColor = .label
    label.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
    label.textAlignment = .center
    label.isEditable = false
    label.isSelectable = false
    label.isScrollEnabled = false
    label.textContainerInset = UIEdgeInsets(top: 38, left: 22, bottom: 20, right: 22)
    container.addSubview(label)
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(conceal),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureStateChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil)
    concealTimer = Timer.scheduledTimer(
      timeInterval: 60,
      target: self,
      selector: #selector(conceal),
      userInfo: nil,
      repeats: false)
    captureStateChanged()
  }

  deinit {
    concealTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
    conceal()
  }

  func view() -> UIView { container }

  @objc fileprivate func conceal() {
    label.text = nil
  }

  @objc private func captureStateChanged() {
    if UIScreen.main.isCaptured { conceal() }
  }
}
