import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef LocalePreferencesProvider = Future<SharedPreferences> Function();

/// App language preference. `null` means "follow the system locale"; a concrete
/// [Locale] is a manual override chosen in Settings. The choice is persisted
/// (SharedPreferences) so it survives restarts.
///
/// Reads fail closed to the current language. Mutations are serialized and
/// commit before publish so the visible language always matches what a restart
/// will restore.
class LocaleController extends ChangeNotifier {
  LocaleController({
    Locale? initial,
    LocalePreferencesProvider? preferencesProvider,
  }) : _locale = initial,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  static const _prefsKey = 'app_locale';
  static const supportedLanguageCodes = {'en', 'zh', 'ja'};

  final LocalePreferencesProvider _preferencesProvider;
  Future<void> _operations = Future<void>.value();
  Locale? _locale;

  /// The manual override, or `null` to follow the system locale.
  Locale? get locale => _locale;

  /// Loads the persisted override (if any). Safe to call before `runApp`.
  Future<void> load() => _queue(_load);

  Future<void> _load() async {
    try {
      final prefs = await _preferencesProvider();
      final code = prefs.getString(_prefsKey);
      if (code == null) return;
      final next = supportedLanguageCodes.contains(code) ? Locale(code) : null;
      if (next == null) {
        final removed = await prefs.remove(_prefsKey);
        if (!removed) throw StateError('locale cleanup failed');
      }
      if (next?.languageCode != _locale?.languageCode) {
        _locale = next;
        notifyListeners();
      }
    } catch (_) {
      // No prefs plugin (tests) or read error: follow the system locale.
    }
  }

  /// Persists and then publishes the override (`null` = follow system).
  Future<void> setLocale(Locale? locale) => _queue(() async {
    final code = locale?.languageCode;
    if (code != null && !supportedLanguageCodes.contains(code)) {
      throw ArgumentError.value(locale, 'locale', 'unsupported language');
    }
    if (code == _locale?.languageCode) return;
    final prefs = await _preferencesProvider();
    final stored = locale == null
        ? await prefs.remove(_prefsKey)
        : await prefs.setString(_prefsKey, code!);
    if (!stored) throw StateError('locale write failed');
    _locale = locale == null ? null : Locale(code!);
    notifyListeners();
  });

  Future<T> _queue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

/// Exposes the app-wide [LocaleController] to the widget tree (e.g. the Settings
/// language picker) and rebuilds dependents when the language changes.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The live controller, or a shared "follow system" fallback when a screen is
  /// rendered standalone (the gallery index and golden tests). Real navigation
  /// always runs under a [LocaleScope].
  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    return scope?.notifier ?? _fallback;
  }

  static final LocaleController _fallback = LocaleController();
}
