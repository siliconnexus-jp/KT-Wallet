import Flutter
import LocalAuthentication
import Network
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyCover: UIView?

  /// Overlay copy pushed from Dart. `localizedProtectionText()` resolves
  /// against the SYSTEM language, which ignores an in-app language override;
  /// these win once Dart has spoken (nil until then, on a cold start).
  private var pushedPrivacyStrings: (appName: String, active: String, hidden: String)?
  private var screenSecurityChannel: FlutterMethodChannel?
  private var privacyProtectionRequired = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenSecurity") {
      screenSecurityChannel = FlutterMethodChannel(
        name: "kt/screen_security",
        binaryMessenger: registrar.messenger()
      )
      screenCaptureChanged()
      let secureScreenChannel = FlutterMethodChannel(
        name: "kt/secure_screen",
        binaryMessenger: registrar.messenger()
      )
      secureScreenChannel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "setPrivacyStrings":
          let args = call.arguments as? [String: Any] ?? [:]
          if let appName = args["appName"] as? String,
            let active = args["active"] as? String,
            let hidden = args["hidden"] as? String
          {
            let next = (appName: appName, active: active, hidden: hidden)
            let changed =
              self?.pushedPrivacyStrings.map {
                $0.appName != next.appName || $0.active != next.active || $0.hidden != next.hidden
              } ?? true
            if changed {
              self?.pushedPrivacyStrings = next
              self?.rebuildPrivacyCover()
            }
          }
          result(nil)
        case "setSecure":
          // iOS has no FLAG_SECURE equivalent; the Dart side documents this
          // as an honest no-op here.
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

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

      // Saves a generated image (the receive card) to the photo library.
      let mediaChannel = FlutterMethodChannel(
        name: "kt/media",
        binaryMessenger: registrar.messenger()
      )
      mediaChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "saveImage" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let data = (args["bytes"] as? FlutterStandardTypedData)?.data,
          let image = UIImage(data: data)
        else {
          result(FlutterError(code: "INVALID", message: "No image bytes", details: nil))
          return
        }
        self?.saveToPhotoLibrary(image, result: result)
      }

      // Encrypted wallet backups in and out via the system document picker —
      // which is how the user reaches iCloud Drive without this app holding an
      // iCloud entitlement or a CloudKit container.
      let filesChannel = FlutterMethodChannel(
        name: "kt/files",
        binaryMessenger: registrar.messenger()
      )
      filesChannel.setMethodCallHandler { [weak self] call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "saveFile":
          guard
            let name = args["name"] as? String,
            let data = (args["bytes"] as? FlutterStandardTypedData)?.data
          else {
            result(FlutterError(code: "INVALID", message: "No file bytes", details: nil))
            return
          }
          self?.presentSavePicker(name: name, data: data, result: result)
        case "pickFile":
          let extensions = args["extensions"] as? [String] ?? []
          self?.presentOpenPicker(extensions: extensions, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // MARK: - document picker

  /// Held for the lifetime of a presented picker: UIDocumentPickerViewController
  /// keeps only a weak delegate, so without this the coordinator deallocates
  /// the moment this method returns and the callback never fires.
  private var documentCoordinator: DocumentPickerCoordinator?

  private func topViewController() -> UIViewController? {
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func presentSavePicker(name: String, data: Data, result: @escaping FlutterResult) {
    guard let host = topViewController() else {
      result(FlutterError(code: "FAILED", message: "No window", details: nil))
      return
    }
    // The picker exports an existing file, so stage it in tmp first. It is
    // already encrypted, and it is removed once the picker is done with it.
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    do {
      try data.write(to: staged, options: .atomic)
    } catch {
      result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [staged], asCopy: true)
    let coordinator = DocumentPickerCoordinator { [weak self] urls in
      try? FileManager.default.removeItem(at: staged)
      self?.documentCoordinator = nil
      guard let saved = urls.first else {
        result(["cancelled": true])
        return
      }
      // Two path components ("iCloud Drive/KT Wallet") read as a place; the
      // full sandbox path does not.
      let location = saved.deletingLastPathComponent().pathComponents.suffix(2).joined(
        separator: "/")
      result(["cancelled": false, "location": location])
    }
    picker.delegate = coordinator
    documentCoordinator = coordinator
    host.present(picker, animated: true)
  }

  private func presentOpenPicker(extensions: [String], result: @escaping FlutterResult) {
    guard let host = topViewController() else {
      result(FlutterError(code: "FAILED", message: "No window", details: nil))
      return
    }
    // A backup carries a private extension, so there is no system UTType for
    // it; `.data` keeps every file selectable and the format check happens in
    // Dart, which can explain the mismatch far better than a greyed-out row.
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
    let coordinator = DocumentPickerCoordinator { [weak self] urls in
      self?.documentCoordinator = nil
      guard let picked = urls.first else {
        result(["cancelled": true])
        return
      }
      // asCopy: true hands us a tmp copy we already own, so no security-scoped
      // access dance is needed.
      guard let data = try? Data(contentsOf: picked) else {
        result(FlutterError(code: "FAILED", message: "Could not read the file", details: nil))
        return
      }
      result([
        "cancelled": false,
        "name": picked.lastPathComponent,
        "bytes": FlutterStandardTypedData(bytes: data),
      ])
    }
    picker.delegate = coordinator
    documentCoordinator = coordinator
    host.present(picker, animated: true)
  }

  /// Asks for add-only access where iOS offers it (14+), which is the
  /// narrowest scope for an app that never reads the user's library.
  private func saveToPhotoLibrary(_ image: UIImage, result: @escaping FlutterResult) {
    let granted: (PHAuthorizationStatus) -> Void = { [weak self] status in
      // `.limited` only exists on iOS 14+, where it also counts as granted for
      // an add-only request.
      var allowed = status == .authorized
      if #available(iOS 14, *) { allowed = allowed || status == .limited }
      guard allowed else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "PERMISSION_DENIED",
              message: "Photo library access was declined",
              details: nil))
        }
        return
      }
      self?.writeAsset(image, result: result)
    }
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: granted)
    } else {
      PHPhotoLibrary.requestAuthorization(granted)
    }
  }

  private func writeAsset(_ image: UIImage, result: @escaping FlutterResult) {
    PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAsset(from: image)
    } completionHandler: { saved, error in
      DispatchQueue.main.async {
        if saved {
          result(true)
        } else {
          result(
            FlutterError(
              code: "FAILED", message: error?.localizedDescription, details: nil))
        }
      }
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    showPrivacyCover()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyCover()
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

  @objc private func willResignActive() {
    showPrivacyCover()
  }

  @objc private func didBecomeActive() {
    hidePrivacyCover()
  }

  /// Throws away the cached cover so the next show rebuilds it.
  private func discardPrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  private func rebuildPrivacyCover() {
    let keepProtected =
      privacyProtectionRequired || privacyCover?.isHidden == false
      || UIApplication.shared.applicationState != .active
    discardPrivacyCover()
    if keepProtected {
      privacyProtectionRequired = true
      presentPrivacyCover()
    }
  }

  func showPrivacyCover() {
    privacyProtectionRequired = true
    presentPrivacyCover()
  }

  private func presentPrivacyCover() {
    if let cover = privacyCover {
      cover.isHidden = false
      cover.superview?.bringSubviewToFront(cover)
      CATransaction.flush()
      return
    }
    guard let hostWindow = activeWindow() else { return }
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

    let title = protectionLabel(
      pushedPrivacyStrings?.appName ?? "KT Wallet", size: 26, weight: .bold, color: .white)
    let text = localizedProtectionText()
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
    privacyProtectionRequired = false
    if privacyCover == nil {
      presentPrivacyCover()
    }
    privacyCover?.isHidden = true
  }

  private func activeWindow() -> UIWindow? {
    let sceneWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return sceneWindow ?? window
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
    if let pushed = pushedPrivacyStrings {
      return (pushed.active, pushed.hidden)
    }
    let language = Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("zh") {
      return ("KT 钱包保护已启动", "您的钱包内容已隐藏")
    }
    if language.hasPrefix("ja") {
      return ("KT Wallet 保護が有効です", "ウォレットの内容は非表示です")
    }
    return ("KT Wallet Protection is active", "Your wallet content is hidden")
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
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "cc.siliconnexus.ktwallet.device-security")
    monitor.pathUpdateHandler = { path in
      monitor.cancel()
      let state: [String: String] = [
        "network": path.status == .satisfied ? "unsafe" : "safe",
        "airplane": "unknown",
        "bluetooth": "unknown",
        "passcode": passcode,
        "biometric": biometric,
        "screenCapture": UIScreen.main.isCaptured ? "unsafe" : "safe",
        "integrity": self.hasJailbreakEvidence() ? "unsafe" : "unknown",
      ]
      DispatchQueue.main.async { result(state) }
    }
    monitor.start(queue: queue)
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

/// Bridges `UIDocumentPickerViewController`'s delegate callbacks to one
/// closure. Both "picked" and "cancelled" must land exactly once, or the Dart
/// future hangs forever behind a dismissed sheet.
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
  private var finish: (([URL]) -> Void)?

  init(onFinish: @escaping ([URL]) -> Void) {
    self.finish = onFinish
  }

  private func complete(_ urls: [URL]) {
    let callback = finish
    finish = nil
    callback?(urls)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    complete(urls)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    complete([])
  }
}
