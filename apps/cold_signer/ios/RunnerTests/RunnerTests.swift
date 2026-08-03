import Flutter
import Network
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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

  func testDeviceNetworkClassificationIsFailClosed() {
    XCTAssertEqual(DeviceSecurityClassifier.network(.satisfied), "unsafe")
    XCTAssertEqual(DeviceSecurityClassifier.network(.unsatisfied), "safe")
    XCTAssertEqual(DeviceSecurityClassifier.network(.requiresConnection), "unknown")
  }

  func testDeviceSecurityResultCompletesExactlyOnce() {
    var delivered: [[String: String]] = []
    let result = OneShotDeviceSecurityResult { delivered.append($0) }

    XCTAssertTrue(result.finish(["network": "unknown"]))
    XCTAssertFalse(result.finish(["network": "unsafe"]))
    XCTAssertEqual(delivered, [["network": "unknown"]])
  }

  func testNativeIncidentStoreIsBoundedAndPrivacyMinimal() throws {
    let suite = "kt-signer-native-observability-tests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = NativeIncidentStore(defaults: defaults)

    store.record("private-exception-message")
    for index in 0..<40 {
      store.record(index.isMultiple(of: 2) ? "fatal" : "anr")
    }

    let payload = store.pendingPayload()
    XCTAssertEqual(payload.keys.sorted(), ["events", "schemaVersion"])
    let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
    XCTAssertEqual(events.count, 32)
    XCTAssertTrue(events.allSatisfy { Set($0.keys) == ["id", "kind"] })
    XCTAssertFalse(String(describing: payload).contains("private-exception-message"))

    let throughID = try XCTUnwrap((events.last?["id"] as? NSNumber)?.int64Value)
    XCTAssertTrue(store.acknowledge(throughID: throughID))
    XCTAssertEqual((store.pendingPayload()["events"] as? [[String: Any]])?.count, 0)
  }
}
