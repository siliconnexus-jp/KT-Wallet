/// Facts about this build that the UI shows the user.
///
/// [version] is duplicated from pubspec.yaml rather than read through
/// package_info_plus: a whole platform plugin for one string on one screen is
/// not a trade this app makes. The duplication is the cost, so a test asserts
/// the two agree — see `about_test.dart`.
abstract final class AppInfo {
  static const version = '1.0.0';

  /// The public repository. Shown on the about screen because a wallet asking
  /// to hold someone's keys should be able to say where its code is.
  static const repositoryUrl = 'https://github.com/siliconnexus-jp/KT-Wallet';
}
