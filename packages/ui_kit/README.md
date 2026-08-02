# ui_kit

Shared Flutter presentation primitives for KT Wallet and KT Cold Signer. It
contains the wallet/signer palettes, navigation and card scaffolds, accessible
buttons and dialogs, QR rendering, shard progress, and screen-security overlay.

```dart
import 'package:ui_kit/ui_kit.dart';

KtPrimaryButton(
  label: 'Continue',
  onPressed: submit,
);
```

`KtDeviceChrome` separates design-gallery chrome from real OS status bars.
`ScreenSecurityGuard` receives native screenshot/lifecycle events and presents
localized privacy UI; platform code remains responsible for task-switcher
coverage and Android secure-window policy.

## UI contract

- interactive controls retain platform minimum touch targets and semantics;
- dialogs use `KtDialog`/`KtConfirmDialog` so spacing, focus, destructive
  actions, and reduced-motion behavior stay consistent;
- wallet and signer colors are intentionally separate; do not hardcode a
  third palette in app screens;
- QR data is supplied by the caller and is never logged or persisted here.

Run `flutter test`; golden updates require visual review at normal and 200%
text scale. Licensed under MPL-2.0; see `LICENSE`.
