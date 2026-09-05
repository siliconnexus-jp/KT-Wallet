import Flutter
import LocalAuthentication
import UIKit
import XCTest
@testable import core_crypto
@testable import native_wallet_tabs
@testable import Runner

private final class TabsTestMessenger: NSObject, FlutterBinaryMessenger {
  var sent: [FlutterMethodCall] = []
  func send(onChannel channel: String, message: Data?) {
    if let message { sent.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message)) }
  }
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(nil)
  }
  func setMessageHandlerOnChannel(_ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

class RunnerTests: XCTestCase {

  private func tabsConfiguration(index: Int = 0, title: String = "钱包", revision: Int = 1,
    enabled: Bool = true, dark: Bool = false) -> [String: Any] {
    ["items": [
      ["title": title, "symbol": "wallet.pass"],
      ["title": "活动", "symbol": "clock.arrow.circlepath"],
      ["title": "设置", "symbol": "gearshape"]
    ], "selectedIndex": index, "revision": revision, "enabled": enabled,
      "dark": dark, "highContrast": false]
  }

  @MainActor
  func testNativeTabsSyncSelectionLanguageAppearanceAndRejectOldRevisions() {
    let host = NativeWalletTabsHost(frame: CGRect(x: 0, y: 0, width: 390, height: 114),
      viewId: 901, args: tabsConfiguration(), messenger: TabsTestMessenger())
    defer { host.dispose() }
    let originalPages = host.controller.viewControllers!
    XCTAssertEqual(originalPages.count, 3)
    XCTAssertTrue(host.update(tabsConfiguration(index: 2, title: "Wallet", revision: 2, dark: true)))
    XCTAssertEqual(host.controller.selectedIndex, 2)
    XCTAssertEqual(host.controller.viewControllers?.first?.tabBarItem.title, "Wallet")
    XCTAssertTrue(host.controller.viewControllers!.first === originalPages.first)
    XCTAssertEqual(host.controller.overrideUserInterfaceStyle, .dark)
    XCTAssertFalse(host.update(tabsConfiguration(index: 0, revision: 1)))
    XCTAssertFalse(host.update(tabsConfiguration(index: 9, revision: 3)))
    XCTAssertEqual(host.controller.selectedIndex, 2)
    XCTAssertTrue(host.update(tabsConfiguration(revision: 3, enabled: false)))
    XCTAssertTrue(host.container.isHidden)
    XCTAssertFalse(host.container.isUserInteractionEnabled)
  }

  @MainActor
  func testNativeTabsContainmentDetachesAndDoesNotAccumulateOnReattachment() {
    let messenger = TabsTestMessenger()
    let host = NativeWalletTabsHost(frame: CGRect(x: 0, y: 730, width: 390, height: 114),
      viewId: 902, args: tabsConfiguration(), messenger: messenger)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let parent = UIViewController()
    window.rootViewController = parent
    window.isHidden = false
    defer { window.isHidden = true; host.dispose() }
    for _ in 0..<5 {
      parent.view.addSubview(host.view())
      parent.view.layoutIfNeeded()
      XCTAssertTrue(host.controller.parent === parent)
      XCTAssertEqual(parent.children.count, 1)
      host.view().removeFromSuperview()
      XCTAssertNil(host.controller.parent)
      XCTAssertEqual(parent.children.count, 0)
    }
    parent.view.addSubview(host.view())
    host.tabBarController(host.controller, didSelect: host.controller.viewControllers![1])
    XCTAssertEqual(messenger.sent.count, 1)
    XCTAssertEqual(messenger.sent.first?.method, "selected")
    XCTAssertEqual(messenger.sent.first?.arguments as? [String: Int], ["index": 1, "revision": 1])
    XCTAssertTrue(host.update(tabsConfiguration(revision: 2, enabled: false)))
    host.tabBarController(host.controller, didSelect: host.controller.viewControllers![2])
    XCTAssertEqual(messenger.sent.count, 1)
    host.dispose()
    host.dispose()
    XCTAssertNil(host.controller.parent)
    XCTAssertEqual(parent.children.count, 0)
    XCTAssertNil(host.container.hitTest(.zero, with: nil))
  }

  @MainActor
  func testNativeTabsHideImmediatelyDuringAuthenticationOrBackgroundTransition() {
    let host = NativeWalletTabsHost(frame: .zero, viewId: 903,
      args: tabsConfiguration(), messenger: TabsTestMessenger())
    defer { host.dispose() }
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertTrue(host.container.isHidden)
    XCTAssertTrue(host.container.accessibilityElementsHidden)
    XCTAssertFalse(host.container.isUserInteractionEnabled)
  }

  @MainActor
  func testPrivacyWindowSelectorUsesVisibleNonKeyBackgroundWindow() {
    let backgroundWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    backgroundWindow.isHidden = false

    XCTAssertTrue(
      selectPrivacyHostWindow(from: [backgroundWindow], fallback: nil) === backgroundWindow
    )
  }

  @MainActor
  func testPrivacyWindowSelectorUsesFallbackWhenSceneHasNoWindows() {
    let fallbackWindow = UIWindow(frame: .zero)

    XCTAssertTrue(selectPrivacyHostWindow(from: [], fallback: fallbackWindow) === fallbackWindow)
  }

  func testScenePrivacyIgnoresTemporaryInactiveTransitions() {
    var state = ScenePrivacyState()

    XCTAssertEqual(state.didBecomeActive(), .none)
    XCTAssertFalse(state.isProtected)
  }

  func testScenePrivacyStaysCoveredUntilTheSceneIsActive() {
    var state = ScenePrivacyState()

    XCTAssertEqual(state.didEnterBackground(), .showCover)
    XCTAssertTrue(state.isProtected)
    XCTAssertEqual(state.willEnterForeground(), .none)
    XCTAssertTrue(state.isProtected)
    XCTAssertEqual(state.didBecomeActive(), .hideCover)
    XCTAssertFalse(state.isProtected)
  }

  func testScenePrivacyRepeatedBackgroundCallbacksRemainFailClosed() {
    var state = ScenePrivacyState()

    XCTAssertEqual(state.didEnterBackground(), .showCover)
    XCTAssertEqual(state.didEnterBackground(), .showCover)
    XCTAssertTrue(state.isProtected)
  }

  func testNativeWalletIdValidationRejectsPathTraversal() throws {
    for value in ["daily", "WLT-3E8A91", "w_AAAAAAAAAAAAAAAAAAAAAAAA", "a_b-C9"] {
      XCTAssertEqual(try requireValidWalletId(value), value)
    }

    let invalid: [Any?] = [
      nil, 7, "", "../wallet", "wallet/child", "wallet.child", "wallet id",
      "钱包", String(repeating: "x", count: 65),
    ]
    for value in invalid {
      XCTAssertThrowsError(try requireValidWalletId(value))
    }
  }

  func testNativeArgumentsRejectWrongTypesBeforeCryptoOrAuthentication() throws {
    let bytes = FlutterStandardTypedData(bytes: Data([1, 2, 3]))
    XCTAssertEqual(try requireStringArgument(["value": "safe"], "value"), "safe")
    XCTAssertEqual(try requireDataArgument(["value": bytes], "value"), Data([1, 2, 3]))
    XCTAssertEqual(try requireMnemonicStrength(["strength": 128]), 128)
    XCTAssertEqual(try requireSuggestionLimit(["limit": 20]), 20)
    XCTAssertEqual(try requireSupportedCoin(["coin": "solana"]), "solana")
    XCTAssertEqual(
      try requirePrivateKeySessionId(["sessionId": "session_01-A"]), "session_01-A")
    XCTAssertEqual(try requirePrivateKeyCopyMode(["mode": "safe"]), "safe")
    XCTAssertEqual(try requirePrivateKeyCopyMode(["mode": "full"]), "full")
    XCTAssertNoThrow(try requireExactArgumentKeys(
      ["sessionId": "session_1", "coin": "eth", "mode": "safe"],
      ["sessionId", "coin", "mode"]))
    XCTAssertThrowsError(try requireExactArgumentKeys(
      ["sessionId": "session_1", "coin": "eth", "mode": "safe", "extra": true],
      ["sessionId", "coin", "mode"]))
    XCTAssertEqual(
      try requireSigningInput([
        "signingInput": FlutterStandardTypedData(bytes: Data([1])),
      ]), Data([1]))
    XCTAssertEqual(
      try requireBackupBlob(["blob": FlutterStandardTypedData(bytes: Data(count: 60))]).count,
      60)
    XCTAssertEqual(try requireStoredWalletFlag(0), 0)
    XCTAssertEqual(try requireStoredWalletFlag(1), 1)
    XCTAssertEqual(try requireEntropySize(Data(count: 32)).count, 32)
    XCTAssertEqual(try requireStoredWalletPayloadSize(Data(count: 77)).count, 77)
    XCTAssertNil(try optionalStringArgument(["value": NSNull()], "value"))
    XCTAssertTrue(try optionalBoolArgument([:], "value", default: true))

    let invalid: [() throws -> Void] = [
      { _ = try requireStringArgument([:], "value") },
      { _ = try requireStringArgument(["value": 7], "value") },
      { _ = try optionalStringArgument(["value": false], "value") },
      { _ = try requireDataArgument(["value": "bytes"], "value") },
      { _ = try requireIntArgument(["value": true], "value") },
      { _ = try optionalBoolArgument(["value": "true"], "value", default: false) },
      { _ = try requireMnemonicStrength(["strength": 129]) },
      { _ = try requireSuggestionLimit(["limit": 0]) },
      { _ = try requireSuggestionLimit(["limit": 21]) },
      { _ = try requireMnemonicText(["mnemonic": ""]) },
      { _ = try requireMnemonicText(["mnemonic": String(repeating: "x", count: 513)]) },
      { _ = try requireWordText(["word": String(repeating: "x", count: 65)]) },
      { _ = try requireSupportedCoin(["coin": "bitcoin"]) },
      { _ = try requirePrivateKeySessionId(["sessionId": "../session"]) },
      { _ = try requirePrivateKeySessionId(["sessionId": ""]) },
      { _ = try requirePrivateKeyCopyMode(["mode": "partial"]) },
      {
        _ = try requireSigningInput([
          "signingInput": FlutterStandardTypedData(bytes: Data()),
        ])
      },
      {
        _ = try requireSigningInput([
          "signingInput": FlutterStandardTypedData(bytes: Data(count: maxSigningInputBytes + 1)),
        ])
      },
      {
        _ = try requireBackupBlob([
          "blob": FlutterStandardTypedData(bytes: Data(count: 59)),
        ])
      },
      { _ = try requireBackupPassword(["password": ""]) },
      {
        _ = try optionalKDFPassword([
          "kdfPassword": String(repeating: "x", count: maxKDFPasswordUTF8Bytes + 1),
        ])
      },
      { _ = try WalletCoreBridge.generateMnemonic(strength: 129) },
    ]
    for call in invalid { XCTAssertThrowsError(try call()) }
    for flag in [UInt8(2), UInt8(255)] {
      XCTAssertThrowsError(try requireStoredWalletFlag(flag))
    }
    for size in [0, 15, 17, 23, 25, 31, 33] {
      XCTAssertThrowsError(try requireEntropySize(Data(count: size)))
    }
    for size in [0, 16, 18, 60, 62, 76, 78, 4096] {
      XCTAssertThrowsError(try requireStoredWalletPayloadSize(Data(count: size)))
    }
  }

  func testPrivateKeyExportEncodingIsBoundedAndChainSpecific() throws {
    let mnemonic =
      "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    var entropy = try WalletCoreBridge.entropy(from: mnemonic)
    defer { entropy.resetBytes(in: 0..<entropy.count) }
    var keys = try WalletCoreBridge.privateKeys(fromEntropy: entropy)
    defer {
      for (name, var value) in keys {
        value.resetBytes(in: 0..<value.count)
        keys[name] = value
      }
    }

    XCTAssertEqual(keys["evm"]?.count, 32)
    XCTAssertEqual(keys["tron"]?.count, 32)
    XCTAssertEqual(keys["solana"]?.count, 32)
    XCTAssertEqual(
      try WalletCoreBridge.encodePrivateKey(keys["evm"]!, coin: "eth").count,
      64)
    XCTAssertEqual(
      try WalletCoreBridge.encodePrivateKey(keys["tron"]!, coin: "tron").count,
      64)
    XCTAssertTrue(
      (43...44).contains(
        try WalletCoreBridge.encodePrivateKey(keys["solana"]!, coin: "solana").count))
    XCTAssertThrowsError(
      try WalletCoreBridge.encodePrivateKey(keys["evm"]!, coin: "bitcoin"))
  }

  func testKeychainWalletSlotIsCreateOnly() throws {
    let walletID = "duplicate_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
    defer { try? KeychainStore.delete(walletId: walletID) }
    let original = Data([0x00, 0x01, 0x02])
    try KeychainStore.save(
      walletId: walletID, ciphertext: original, requireAuth: false)

    XCTAssertThrowsError(
      try KeychainStore.save(
        walletId: walletID, ciphertext: Data([0x09]), requireAuth: false)
    ) { error in
      guard case KeychainStore.StoreError.alreadyExists = error else {
        return XCTFail("unexpected error category")
      }
    }
    XCTAssertEqual(
      try KeychainStore.load(walletId: walletID, context: LAContext()), original)
  }

  func testKeychainPresenceCheckDoesNotOpenAuthBoundWallet() throws {
    let walletID = "presence_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
    defer { try? KeychainStore.delete(walletId: walletID) }

    try KeychainStore.save(
      walletId: walletID,
      ciphertext: Data([0x00, 0x01, 0x02]),
      requireAuth: true
    )

    XCTAssertTrue(try KeychainStore.exists(walletId: walletID))
    XCTAssertFalse(try KeychainStore.exists(walletId: "missing_\(UUID().uuidString)"))
  }

  func testPortableBackupCipherMatchesCrossPlatformVector() throws {
    let entropy = Data((0x00...0x1F).map(UInt8.init))
    let salt = Data((0x00...0x0F).map(UInt8.init))
    let nonce = Data((0x10...0x1B).map(UInt8.init))
    let password = "Correct horse 電池🔐"

    let sealed = try PortableBackupCipher.seal(
      entropy: entropy,
      password: password,
      salt: salt,
      nonce: nonce
    )
    XCTAssertEqual(
      sealed.map { String(format: "%02x", $0) }.joined(),
      "000102030405060708090a0b0c0d0e0f101112131415161718191a1b" +
        "364a29004ca61dca69b29ce63afbfa7315822fc380f858634e289bbb" +
        "5b33dd43bf50be31944b5e4d9f6bbd81f23c53bc"
    )
    XCTAssertEqual(
      try PortableBackupCipher.open(sealed: sealed, password: password),
      entropy
    )
    XCTAssertThrowsError(
      try PortableBackupCipher.open(sealed: sealed, password: "wrong password")
    )
  }

  func testSelectedBackupReadIsStrictlyBounded() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("kt-wallet-bounded-read-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }

    let exact = Data((0..<32).map(UInt8.init))
    try exact.write(to: url)
    XCTAssertEqual(try readPickedFileBounded(at: url, maxBytes: 32), exact)

    try Data(repeating: 0xA5, count: 33).write(to: url)
    XCTAssertThrowsError(try readPickedFileBounded(at: url, maxBytes: 32)) { error in
      guard case PickedFileReadError.tooLarge = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testNativeIncidentStoreIsBoundedAndPrivacyMinimal() throws {
    let suite = "kt-wallet-native-observability-tests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = NativeIncidentStore(defaults: defaults)

    store.record("private-exception-message")
    for index in 0..<40 {
      store.record(index.isMultiple(of: 2) ? "fatal" : "anr")
    }

    let payload = store.pendingPayload()
    XCTAssertEqual(payload.keys.sorted(), ["events", "schemaVersion"])
    XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
    let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
    XCTAssertEqual(events.count, 32)
    XCTAssertTrue(events.allSatisfy { Set($0.keys) == ["id", "kind"] })
    XCTAssertFalse(String(describing: payload).contains("private-exception-message"))

    let throughID = try XCTUnwrap((events[15]["id"] as? NSNumber)?.int64Value)
    XCTAssertTrue(store.acknowledge(throughID: throughID))
    let remaining = try XCTUnwrap(store.pendingPayload()["events"] as? [[String: Any]])
    XCTAssertEqual(remaining.count, 16)
    XCTAssertFalse(store.acknowledge(throughID: 0))
  }
}
