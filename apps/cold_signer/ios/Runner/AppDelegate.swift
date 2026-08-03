import Flutter
import LocalAuthentication
import MetricKit
import Network
import UIKit

internal func selectPrivacyHostWindow(
  from windows: [UIWindow],
  fallback: UIWindow?
) -> UIWindow? {
  windows.first(where: \.isKeyWindow)
    ?? windows.first(where: { !$0.isHidden && $0.windowLevel == .normal })
    ?? windows.first
    ?? fallback
}

/// Pure tri-state policy shared by the native probe and XCTest. Only an
/// explicitly unsatisfied path proves the signer has no active default route.
struct DeviceSecurityClassifier {
  static func network(_ status: NWPath.Status) -> String {
    switch status {
    case .satisfied:
      return "unsafe"
    case .unsatisfied:
      return "safe"
    case .requiresConnection:
      return "unknown"
    @unknown default:
      return "unknown"
    }
  }
}

/// Makes the asynchronous NWPath callback and timeout race safe. Flutter must
/// receive exactly one result even if the monitor calls back after timeout.
final class OneShotDeviceSecurityResult {
  private let lock = NSLock()
  private var completed = false
  private let completion: ([String: String]) -> Void

  init(completion: @escaping ([String: String]) -> Void) {
    self.completion = completion
  }

  @discardableResult
  func finish(_ state: [String: String]) -> Bool {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return false
    }
    completed = true
    lock.unlock()
    completion(state)
    return true
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyCover: UIView?
  private var screenSecurityChannel: FlutterMethodChannel?
  private let nativeIncidentStore = NativeIncidentStore()
  private var nativeMetricSubscriber: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The anti-replay database and signer metadata are meaningful only beside
    // the device-bound Keychain item. Never let system backup migrate one
    // without the other; recovery uses the separately controlled phrase.
    excludeLocalStateFromSystemBackup()
    if #available(iOS 14.0, *) {
      let subscriber = NativeMetricSubscriber(store: nativeIncidentStore)
      nativeMetricSubscriber = subscriber
      MXMetricManager.shared.add(subscriber)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    // iOS cannot block a screenshot, but it CAN tell us the screen is being
    // recorded or mirrored — and that one IS preventable: Dart obscures the
    // sensitive screen for as long as the capture lasts.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Exclude every persistent local-state directory from all app-data backup.
  /// Paths and errors are intentionally not logged.
  @discardableResult
  func excludeLocalStateFromSystemBackup(
    fileManager: FileManager = .default
  ) -> Bool {
    let directories: [FileManager.SearchPathDirectory] = [
      .documentDirectory,
      .libraryDirectory,
    ]
    var protectedEveryDirectory = true
    for directory in directories {
      guard var url = fileManager.urls(for: directory, in: .userDomainMask).first else {
        protectedEveryDirectory = false
        continue
      }
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
      } catch {
        protectedEveryDirectory = false
      }
    }
    return protectedEveryDirectory
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenSecurity") {
      let nativeObservabilityChannel = FlutterMethodChannel(
        name: "kt/native_observability",
        binaryMessenger: registrar.messenger()
      )
      nativeObservabilityChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return result(FlutterMethodNotImplemented) }
        switch call.method {
        case "pendingIncidents":
          result(self.nativeIncidentStore.pendingPayload())
        case "ackIncidents":
          let args = call.arguments as? [String: Any]
          guard let throughID = (args?["throughId"] as? NSNumber)?.int64Value,
            self.nativeIncidentStore.acknowledge(throughID: throughID)
          else {
            result(FlutterError(code: "INVALID", message: "Invalid acknowledgement", details: nil))
            return
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      screenSecurityChannel = FlutterMethodChannel(
        name: "kt/screen_security",
        binaryMessenger: registrar.messenger()
      )
      screenCaptureChanged()
      let deviceSecurityChannel = FlutterMethodChannel(
        name: "kt/device_security",
        binaryMessenger: registrar.messenger()
      )
      deviceSecurityChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getState" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.deviceSecurityState(result)
      }
    }
  }

  @objc private func screenshotTaken() {
    screenSecurityChannel?.invokeMethod("screenshotTaken", arguments: nil)
  }

  @objc private func screenCaptureChanged() {
    screenSecurityChannel?.invokeMethod(
      "screenCaptureChanged",
      arguments: UIScreen.main.isCaptured
    )
  }

  func showPrivacyCover(in scene: UIScene? = nil) {
    if let cover = privacyCover {
      cover.isHidden = false
      cover.superview?.bringSubviewToFront(cover)
      CATransaction.flush()
      return
    }
    guard let hostWindow = activeWindow(in: scene) else { return }
    let cover = UIView(frame: hostWindow.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor(red: 8/255, green: 12/255, blue: 24/255, alpha: 1)
    cover.accessibilityLabel = localizedProtectionText().active
    let icon = UIImageView(image: appIcon())
    icon.contentMode = .scaleAspectFit
    icon.layer.cornerRadius = 20
    icon.clipsToBounds = true
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 88),
      icon.heightAnchor.constraint(equalToConstant: 88),
    ])
    let text = localizedProtectionText()
    let title = protectionLabel("KT Cold Signer", size: 26, weight: .bold, color: .white)
    // No glyph here: the "⚖" that used to prefix this line was the scales of
    // Libra, left over from the old brand, and it sat directly above the app
    // icon that already identifies the app.
    let active = protectionLabel(text.active, size: 18, weight: .semibold, color: .white)
    let hidden = protectionLabel(
      text.hidden, size: 14, weight: .regular,
      color: UIColor(red: 170/255, green: 178/255, blue: 198/255, alpha: 1)
    )
    let stack = UIStackView(arrangedSubviews: [icon, title, active, hidden])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 12
    stack.setCustomSpacing(24, after: icon)
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -32),
    ])
    hostWindow.addSubview(cover)
    hostWindow.bringSubviewToFront(cover)
    cover.setNeedsLayout()
    cover.layoutIfNeeded()
    hostWindow.setNeedsLayout()
    hostWindow.layoutIfNeeded()
    CATransaction.flush()
    privacyCover = cover
  }

  func hidePrivacyCover() {
    if privacyCover == nil {
      showPrivacyCover()
    }
    privacyCover?.isHidden = true
  }

  private func activeWindow(in scene: UIScene? = nil) -> UIWindow? {
    let scopedWindows = (scene as? UIWindowScene)?.windows ?? []
    if !scopedWindows.isEmpty {
      return selectPrivacyHostWindow(from: scopedWindows, fallback: window)
    }
    let connectedWindows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    return selectPrivacyHostWindow(from: connectedWindows, fallback: window)
  }

  private func protectionLabel(
    _ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor
  ) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }

  private func localizedProtectionText() -> (active: String, hidden: String) {
    let language = Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("zh") {
      return ("KT冷钱包保护已启动", "您的钱包内容已隐藏")
    }
    if language.hasPrefix("ja") {
      return ("KT Cold Signer 保護が有効です", "ウォレットの内容は非表示です")
    }
    return ("KT Cold Signer Protection is active", "Your wallet content is hidden")
  }

  private func appIcon() -> UIImage? {
    let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
    let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
    let files = primary?["CFBundleIconFiles"] as? [String]
    return files?.last.flatMap(UIImage.init(named:))
      ?? UIImage(systemName: "shield.lefthalf.filled")
  }

  private func deviceSecurityState(_ result: @escaping FlutterResult) {
    let auth = LAContext()
    var authError: NSError?
    let passcode = auth.canEvaluatePolicy(
      .deviceOwnerAuthentication,
      error: &authError
    ) ? "safe" : "unsafe"
    let biometricContext = LAContext()
    var biometricError: NSError?
    let biometric = biometricContext.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &biometricError
    ) ? "safe" : "unsafe"

    var baseState: [String: String] = [
      // iOS exposes neither radio state without invasive private APIs.
      "airplane": "unknown",
      "bluetooth": "unknown",
      "passcode": passcode,
      "biometric": biometric,
      "screenCapture": UIScreen.main.isCaptured ? "unsafe" : "safe",
      "integrity": self.hasJailbreakEvidence() ? "unsafe" : "unknown",
    ]
    let once = OneShotDeviceSecurityResult { state in
      DispatchQueue.main.async {
        result(state)
      }
    }
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "cc.siliconnexus.ktwallet.device-security")
    monitor.pathUpdateHandler = { path in
      monitor.cancel()
      baseState["network"] = DeviceSecurityClassifier.network(path.status)
      once.finish(baseState)
    }
    monitor.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 2) {
      monitor.cancel()
      baseState["network"] = "unknown"
      once.finish(baseState)
    }
  }

  private func hasJailbreakEvidence() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
      ]
      if suspiciousPaths.contains(where: FileManager.default.fileExists(atPath:)) {
        return true
      }
      let probe = "/private/ktwallet-\(UUID().uuidString)"
      do {
        try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: probe)
        return true
      } catch {
        return false
      }
    #endif
  }
}

internal struct NativeIncident: Equatable {
  let id: Int64
  let kind: String
}

internal final class NativeIncidentStore {
  private static let eventsKey = "kt.native-observability.v1.events"
  private static let nextIDKey = "kt.native-observability.v1.next-id"
  private static let maxEvents = 32
  private let defaults: UserDefaults
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func record(_ kind: String) {
    guard kind == "fatal" || kind == "anr" else { return }
    lock.lock()
    defer { lock.unlock() }
    let nextID = max(
      1,
      (defaults.object(forKey: Self.nextIDKey) as? NSNumber)?.int64Value ?? 1
    )
    let bounded = (decode(defaults.string(forKey: Self.eventsKey))
      + [NativeIncident(id: nextID, kind: kind)]).suffix(Self.maxEvents)
    defaults.set(nextID + 1, forKey: Self.nextIDKey)
    defaults.set(encode(Array(bounded)), forKey: Self.eventsKey)
  }

  func pendingPayload() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return [
      "schemaVersion": 1,
      "events": decode(defaults.string(forKey: Self.eventsKey)).map {
        ["id": $0.id, "kind": $0.kind]
      },
    ]
  }

  @discardableResult
  func acknowledge(throughID: Int64) -> Bool {
    guard throughID > 0 else { return false }
    lock.lock()
    defer { lock.unlock() }
    let remaining = decode(defaults.string(forKey: Self.eventsKey))
      .filter { $0.id > throughID }
    defaults.set(encode(remaining), forKey: Self.eventsKey)
    return true
  }

  private func encode(_ events: [NativeIncident]) -> String {
    events.map { "\($0.id):\($0.kind)" }.joined(separator: ",")
  }

  private func decode(_ encoded: String?) -> [NativeIncident] {
    guard let encoded, !encoded.isEmpty else { return [] }
    return Array(encoded.split(separator: ",").compactMap { row in
      let parts = row.split(separator: ":")
      guard parts.count == 2, let id = Int64(parts[0]), id > 0 else { return nil }
      let kind = String(parts[1])
      guard kind == "fatal" || kind == "anr" else { return nil }
      return NativeIncident(id: id, kind: kind)
    }.sorted { $0.id < $1.id }.suffix(Self.maxEvents))
  }
}

@available(iOS 14.0, *)
internal final class NativeMetricSubscriber: NSObject, MXMetricManagerSubscriber {
  private let store: NativeIncidentStore

  init(store: NativeIncidentStore) {
    self.store = store
  }

  func didReceive(_ payloads: [MXMetricPayload]) {}

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      payload.crashDiagnostics?.forEach { _ in store.record("fatal") }
      payload.hangDiagnostics?.forEach { _ in store.record("anr") }
    }
  }
}
