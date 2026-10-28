import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's language override (en/de) and persists it across launches.
/// A null code means the app follows the system locale.
class LanguageProvider extends ChangeNotifier {
  static const _key = 'language_code';

  /// null = follow system, 'en' or 'de' = override
  String? _languageCode;

  /// The selected language code, or null when following the system locale.
  String? get languageCode => _languageCode;

  /// The selected [Locale], or null when following the system locale.
  Locale? get locale => _languageCode != null ? Locale(_languageCode!) : null;

  /// Creates the provider and asynchronously loads the persisted language.
  LanguageProvider() {
    _load();
  }

  /// Reads the saved language code from shared_preferences.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _languageCode = saved; // null if never set
    notifyListeners();
  }

  /// Sets the language override ([code] of null follows the system locale),
  /// notifies listeners, and persists the choice.
  Future<void> setLanguage(String? code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, code);
    }
  }
}
