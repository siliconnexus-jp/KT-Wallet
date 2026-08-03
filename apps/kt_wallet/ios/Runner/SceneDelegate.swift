import Flutter
import UIKit

internal enum ScenePrivacyEffect: Equatable {
  case none
  case showCover
  case hideCover
}

/// Keeps temporary inactive states (Control Center, permission prompts and
/// system overlays) separate from a real background transition. The cover
/// remains installed while the scene returns through `willEnterForeground`
/// and is removed only once that exact scene is active again.
internal struct ScenePrivacyState {
  private(set) var isProtected = false

  mutating func didEnterBackground() -> ScenePrivacyEffect {
    isProtected = true
    return .showCover
  }

  mutating func willEnterForeground() -> ScenePrivacyEffect {
    .none
  }

  mutating func didBecomeActive() -> ScenePrivacyEffect {
    guard isProtected else { return .none }
    isProtected = false
    return .hideCover
  }
}

class SceneDelegate: FlutterSceneDelegate {
  private var privacyState = ScenePrivacyState()

  override func sceneDidEnterBackground(_ scene: UIScene) {
    if privacyState.didEnterBackground() == .showCover {
      (UIApplication.shared.delegate as? AppDelegate)?.showPrivacyCover()
    }
    super.sceneDidEnterBackground(scene)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    _ = privacyState.willEnterForeground()
    super.sceneWillEnterForeground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    if privacyState.didBecomeActive() == .hideCover {
      (UIApplication.shared.delegate as? AppDelegate)?.hidePrivacyCover()
    }
  }
}
