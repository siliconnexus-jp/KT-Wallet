// Navigation-only adaptation of liquid_glass_bottom_nav_native 0.2.0.
// Copyright (c) 2026 UjjawalGandhi, SiliconNexus. See package LICENSE (MIT).
import Flutter
import UIKit

public final class NativeWalletTabsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativeWalletTabsFactory(messenger: registrar.messenger()),
      withId: "kt/native_wallet_tabs"
    )
  }
}

final class NativeWalletTabsFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView {
    NativeWalletTabsHost(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }
}

/// UIKit owns hit testing throughout the reserved navigation strip. Do not
/// clip interaction to UITabBar.bounds: the floating controls are managed by
/// the system and need not share the legacy bar's geometry on every iOS.
final class WalletTabsContainer: UIView {
  var windowChanged: (() -> Void)?
  override func didMoveToWindow() {
    super.didMoveToWindow()
    windowChanged?()
  }
}

final class NativeWalletTabsHost: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  let container: WalletTabsContainer
  let controller = UITabBarController()
  private let channel: FlutterMethodChannel
  private var items: [[String: String]] = []
  private var revision = 0
  private var enabled = false
  private var foreground = UIApplication.shared.applicationState != .background
  private var disposed = false
  private var observers: [NSObjectProtocol] = []

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    container = WalletTabsContainer(frame: frame)
    channel = FlutterMethodChannel(name: "kt/native_wallet_tabs/\(viewId)", binaryMessenger: messenger)
    super.init()
    container.backgroundColor = .clear
    container.isOpaque = false
    controller.view.backgroundColor = .clear
    controller.delegate = self
    // Keep this navigation-only controller at the bottom on iPad too. The
    // override is scoped to this child, never the Flutter app or its sheets.
    if #available(iOS 17.0, *) { controller.traitOverrides.horizontalSizeClass = .compact }
    container.windowChanged = { [weak self] in self?.synchronizeParent() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, !self.disposed else { result(nil); return }
      switch call.method {
      case "update":
        guard self.update(call.arguments) else {
          result(FlutterError(code: "invalid_tabs", message: "Invalid navigation configuration", details: nil))
          return
        }
        result(nil)
      case "setEnabled":
        self.enabled = call.arguments as? Bool ?? false
        self.applyVisibility()
        result(nil)
      case "dispose":
        self.dispose()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    _ = update(args)
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
      object: nil, queue: .main) { [weak self] _ in
        self?.foreground = false
        self?.applyVisibility()
      })
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
      object: nil, queue: .main) { [weak self] _ in
        self?.foreground = true
        self?.applyVisibility()
      })
  }

  func view() -> UIView { container }

  @discardableResult
  func update(_ arguments: Any?) -> Bool {
    guard !disposed,
      let params = arguments as? [String: Any],
      let nextItems = params["items"] as? [[String: String]],
      (2...5).contains(nextItems.count),
      nextItems.allSatisfy({ !($0["title"] ?? "").isEmpty && !($0["symbol"] ?? "").isEmpty }),
      let index = params["selectedIndex"] as? Int,
      nextItems.indices.contains(index),
      let nextRevision = params["revision"] as? Int,
      nextRevision >= revision
    else { return false }
    revision = nextRevision
    if nextItems != items {
      var pages = controller.viewControllers ?? []
      if pages.count != nextItems.count {
        pages = nextItems.map { _ in
          let page = UIViewController()
          page.view.backgroundColor = .clear
          return page
        }
        controller.setViewControllers(pages, animated: false)
      }
      for (position, item) in nextItems.enumerated() {
        pages[position].tabBarItem = UITabBarItem(
          title: item["title"],
          image: UIImage(systemName: item["symbol"]!),
          tag: position
        )
        pages[position].tabBarItem.accessibilityIdentifier = "home-tab-\(position)"
      }
      items = nextItems
    }
    // Updating selectedIndex does not invoke the user-selection delegate.
    controller.selectedIndex = index
    let dark = params["dark"] as? Bool ?? false
    controller.overrideUserInterfaceStyle = dark ? .dark : .light
    container.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
    controller.tabBar.tintColor = .systemBlue
    if params["highContrast"] as? Bool == true {
      let opaque = UITabBarAppearance()
      opaque.configureWithOpaqueBackground()
      controller.tabBar.standardAppearance = opaque
      controller.tabBar.scrollEdgeAppearance = opaque
    } else {
      // Restore system defaults: iOS 26 supplies Liquid Glass, old versions
      // supply their own material. UIKit handles Reduce Transparency/Motion.
      let system = UITabBarAppearance()
      system.configureWithDefaultBackground()
      controller.tabBar.standardAppearance = system
      controller.tabBar.scrollEdgeAppearance = nil
    }
    enabled = params["enabled"] as? Bool ?? false
    applyVisibility()
    return true
  }

  func tabBarController(_ tabBarController: UITabBarController,
    didSelect viewController: UIViewController) {
    guard !disposed, enabled, foreground, controller.parent != nil,
      let index = controller.viewControllers?.firstIndex(of: viewController),
      items.indices.contains(index)
    else { return }
    channel.invokeMethod("selected", arguments: ["index": index, "revision": revision])
  }

  private func applyVisibility() {
    let visible = enabled && foreground && !disposed
    container.isHidden = !visible
    container.isUserInteractionEnabled = visible
    container.accessibilityElementsHidden = !visible
  }

  private func synchronizeParent() {
    guard !disposed, container.window != nil else { detach(); return }
    var responder: UIResponder? = container.next
    while let candidate = responder, !(candidate is UIViewController) {
      responder = candidate.next
    }
    guard let parent = responder as? UIViewController,
      parent !== controller, controller.parent !== parent else { return }
    detach()
    parent.addChild(controller)
    let hosted = controller.view!
    hosted.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hosted)
    NSLayoutConstraint.activate([
      hosted.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hosted.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hosted.topAnchor.constraint(equalTo: container.topAnchor),
      hosted.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    controller.didMove(toParent: parent)
  }

  private func detach() {
    if controller.parent != nil { controller.willMove(toParent: nil) }
    controller.viewIfLoaded?.removeFromSuperview()
    controller.removeFromParent()
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    applyVisibility()
    channel.setMethodCallHandler(nil)
    container.windowChanged = nil
    controller.delegate = nil
    detach()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
  }

  deinit { dispose() }
}
