import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyCover: UIView?
  private var screenSecurityChannel: FlutterMethodChannel?

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

  @objc private func willResignActive() {
    showPrivacyCover()
  }

  @objc private func didBecomeActive() {
    hidePrivacyCover()
  }

  private func showPrivacyCover() {
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
    let text = localizedProtectionText()
    let title = protectionLabel("KT Wallet", size: 26, weight: .bold, color: .white)
    let active = protectionLabel("⚖  \(text.active)", size: 18, weight: .semibold, color: .white)
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

  private func hidePrivacyCover() {
    if privacyCover == nil {
      showPrivacyCover()
    }
    privacyCover?.isHidden = true
  }

  private func activeWindow() -> UIWindow? {
    if let appWindow = window { return appWindow }
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
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
      return ("天秤保护已启动", "您的钱包内容已隐藏")
    }
    if language.hasPrefix("ja") {
      return ("Libra 保護が有効です", "ウォレットの内容は非表示です")
    }
    return ("Libra Protection is active", "Your wallet content is hidden")
  }

  private func appIcon() -> UIImage? {
    let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
    let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
    let files = primary?["CFBundleIconFiles"] as? [String]
    return files?.last.flatMap(UIImage.init(named:))
      ?? UIImage(systemName: "shield.lefthalf.filled")
  }
}
