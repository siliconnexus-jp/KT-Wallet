# Native wallet tabs

KT Wallet's locally maintained, navigation-only adaptation of
[`liquid_glass_bottom_nav_native` 0.2.0](https://pub.dev/packages/liquid_glass_bottom_nav_native/versions/0.2.0)
by UjjawalGandhi, MIT licensed. Upstream archive SHA-256:
`f6e21a87c31b4f62e07a26ad889432777256e650f25a5dcd3c5cce7f2f916dfd`.

This is not a drop-in replacement for upstream's full API. Search, action
tabs, icon buttons and menus are deliberately omitted. The native channel
contains only navigation labels, SF Symbol names, selection and appearance;
it never receives accounts, addresses, balances, credentials or signing data.

## Integration

- A real `UITabBarController` is contained in the Flutter platform view.
  Flutter retains ownership of pages, routes and wallet state (one engine).
- Build using Xcode 26+ for iOS 26 Liquid Glass. iOS 15+ remains supported
  using the system's classic tab bar, not a simulated glass shader.
- Non-iOS platforms render the required Flutter fallback. No new permissions,
  network clients, analytics or third-party runtime dependencies.
- Selected index, localized labels, appearance and enabled state synchronize
  after creation. Updates carry a revision to reject delayed native taps.
- The reserved navigation strip is opaque to Flutter hit testing and eagerly
  forwards touches to UIKit. Visual translucency must not allow tappable asset
  rows underneath to win the gesture arena. Native hit testing is left to
  UIKit rather than clipped to legacy `UITabBar.bounds` geometry.
- Route changes and backgrounding disable/hide the bar; native containment
  is detached on window removal and disposal. The containing app's lock gate
  must continue replacing protected content, not merely painting over it.
- UIKit owns accessibility, Dynamic Type, Reduce Motion and Reduce
  Transparency. Flutter's high-contrast preference also reaches UIKit.
- Reserve `NativeWalletTabs.extentFor(context)` beneath scrollable content.
  Do not wrap the native bar in another blur or a bottom SafeArea.

Tests cover the Dart bridge and fallback. Native containment, selection and
appearance tests are included in the online app's RunnerTests target.

## Verification (2026-09-06)

- Online Flutter suite: 1844 passed, 11 skipped; bridge suite: 7 passed.
- The touch regression places a tappable Flutter asset surface under the bar
  and verifies UIKit receives touch-down immediately, with no underlying tap
  or rejected native gesture. It fails with the original translucent bridge.
- After installing the touch fix, the user confirmed that the wallet's native
  tabs switch pages correctly on the iOS simulator.
- iOS native tests cover containment/repeated reattachment, selection events,
  stale revisions, language/appearance updates and inactive-state protection.
- Online iOS simulator and Android debug builds succeed; deployment target
  remains iOS 15. No iOS 15 runtime is installed locally, so older-system
  appearance still needs a device smoke test.
- A separate no-wallet-data preview on iOS 26.2 verified the native glass,
  Chinese/Japanese label updates, light/dark appearance, sheet/detail hiding
  and restoration of selection after returning. The existing wallet remained
  behind its biometric lock; no authentication settings were changed.
- The repository-wide `tool/check_deps.dart` currently fails existing exact
  source-marker assertions (wallet fixture/history/snapshot/database and
  gateway release/response markers). None of those assertions or underlying
  behaviors were changed by this tab adaptation; this is not a clean full
  repository security-audit result.
