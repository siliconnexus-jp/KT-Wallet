import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language preference. `null` means "follow the system locale"; a concrete
/// [Locale] is a manual override chosen in Settings. The choice is persisted
/// (SharedPreferences) so it survives restarts.
///
/// All persistence is best-effort and guarded: in widget tests (where the
/// SharedPreferences plugin isn't registered) reads/writes fail silently and
/// the controller simply follows the system locale.
class LocaleController extends ChangeNotifier {
  LocaleController({Locale? initial}) : _locale = initial;

  static const _prefsKey = 'app_locale';

  Locale? _locale;

  /// The manual override, or `null` to follow the system locale.
  Locale? get locale => _locale;

  /// Loads the persisted override (if any). Safe to call before `runApp`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code != null && code.isNotEmpty) {
        _locale = Locale(code);
        notifyListeners();
      }
    } catch (_) {
      // No prefs plugin (tests) or read error: follow the system locale.
    }
  }

  /// Sets the override (`null` = follow system) and persists it.
  Future<void> setLocale(Locale? locale) async {
    if (locale?.languageCode == _locale?.languageCode) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, locale.languageCode);
      }
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }
}

/// Exposes the app-wide [LocaleController] to the widget tree (e.g. the Settings
/// language picker) and rebuilds dependents when the language changes.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({super.key, required LocaleController controller, required super.child}) : super(notifier: controller);

  /// The live controller, or a shared "follow system" fallback when a screen is
  /// rendered standalone (the gallery index and golden tests). Real navigation
  /// always runs under a [LocaleScope].
  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    return scope?.notifier ?? _fallback;
  }

  static final LocaleController _fallback = LocaleController();
}
