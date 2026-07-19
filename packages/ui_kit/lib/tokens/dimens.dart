/// Spacing / radius / typography scale — mirrors the Pencil design system.
abstract final class KtDimens {
  // Screen padding used by both apps (Pencil content wrappers).
  static const pagePaddingWallet = 20.0;
  static const pagePaddingSigner = 24.0;

  // Corner radii.
  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 16.0;
  static const radiusXl = 20.0;

  // Component heights.
  static const buttonHeight = 52.0;

  // Vertical rhythm.
  static const gapXs = 8.0;
  static const gapSm = 12.0;
  static const gapMd = 16.0;
  static const gapLg = 24.0;
}

/// Font family names (bundled at app level).
abstract final class KtFonts {
  static const ui = 'Inter';
  static const mono = 'JetBrains Mono';
}
