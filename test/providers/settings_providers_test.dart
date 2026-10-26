import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/language_provider.dart';
import 'package:dartscore_app/providers/pace_provider.dart';
import 'package:dartscore_app/providers/tablet_layout_provider.dart';
import 'package:dartscore_app/providers/theme_provider.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Both providers load asynchronously from their constructor, so a test that
/// reads them straight away would see the default rather than what was stored.
Future<T> _loaded<T extends ChangeNotifier>(T provider) async {
  await Future<void>.delayed(Duration.zero);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaceProvider', () {
    tearDown(() => TurnPacing.pace = GamePace.normal);

    test('runs at the normal pace until the user picks one', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = await _loaded(PaceProvider());

      expect(provider.pace, GamePace.normal);
      expect(TurnPacing.pace, GamePace.normal);
      expect(TurnPacing.visitPause, const Duration(seconds: 2));
    });

    test('comes back on the pace the user left it on, and hands it to the games',
        () async {
      SharedPreferences.setMockInitialValues({'game_pace': GamePace.fast.index});

      final provider = await _loaded(PaceProvider());

      expect(provider.pace, GamePace.fast);
      expect(TurnPacing.pace, GamePace.fast);
      expect(TurnPacing.botDartDelay, const Duration(milliseconds: 400));
      expect(TurnPacing.visitPause, const Duration(seconds: 1));
    });

    test('writes a change down and passes it on at once', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(PaceProvider());

      await provider.setPace(GamePace.slow);

      expect(TurnPacing.pace, GamePace.slow);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('game_pace'), GamePace.slow.index);
    });

    test('shrugs off a stored value from a version with other options',
        () async {
      SharedPreferences.setMockInitialValues({'game_pace': 42});

      final provider = await _loaded(PaceProvider());

      expect(provider.pace, GamePace.normal);
    });
  });

  group('ThemeProvider', () {
    test('defaults to B74 dark when no theme was selected', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = await _loaded(ThemeProvider());

      expect(provider.mode, ThemeMode.dark);
    });

    test('comes back on the mode the user left it on', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

      final provider = await _loaded(ThemeProvider());

      expect(provider.mode, ThemeMode.dark);
    });

    test('writes the choice so the next launch reads it', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(ThemeProvider());

      await provider.setMode(ThemeMode.light);

      expect(provider.mode, ThemeMode.light);
      expect(await _loaded(ThemeProvider()).then((p) => p.mode),
          ThemeMode.light);
    });

    test('falls back to B74 dark for an unknown stored theme', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});

      final provider = await _loaded(ThemeProvider());

      expect(provider.mode, ThemeMode.dark);
    });

    test('notifies before it has finished writing', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(ThemeProvider());
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setMode(ThemeMode.dark);

      expect(notifications, 1);
    });
  });

  group('LanguageProvider', () {
    test('follows the system locale when nothing was chosen', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = await _loaded(LanguageProvider());

      expect(provider.languageCode, isNull);
      expect(provider.locale, isNull);
    });

    test('comes back on the language the user left it on', () async {
      SharedPreferences.setMockInitialValues({'language_code': 'de'});

      final provider = await _loaded(LanguageProvider());

      expect(provider.languageCode, 'de');
      expect(provider.locale, const Locale('de'));
    });

    test('writes the choice so the next launch reads it', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(LanguageProvider());

      await provider.setLanguage('en');

      expect(await _loaded(LanguageProvider()).then((p) => p.languageCode),
          'en');
    });

    test('clears the override rather than storing a null language', () async {
      SharedPreferences.setMockInitialValues({'language_code': 'de'});
      final provider = await _loaded(LanguageProvider());

      await provider.setLanguage(null);

      expect(provider.locale, isNull);
      // Stored as absent, not as an empty string: _load reads any stored value
      // straight through, so a leftover would come back as a locale.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language_code'), isNull);
    });
  });

  group('TabletLayoutProvider', () {
    test('keeps the screens and orientations apart', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(TabletLayoutProvider());

      provider.setSplitFraction(SplitPane.game, 0.65, landscape: true);

      expect(provider.splitFraction(SplitPane.game, landscape: true), 0.65);
      expect(provider.splitFraction(SplitPane.game, landscape: false),
          kDefaultSplitFraction);
      // And the other screens are untouched by it.
      expect(provider.splitFraction(SplitPane.history, landscape: true),
          kDefaultSplitFraction);
    });

    test('comes back on the split each orientation was left on', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await _loaded(TabletLayoutProvider());
      first.setSplitFraction(SplitPane.game, 0.65, landscape: true);
      first.setSplitFraction(SplitPane.players, 0.38, landscape: false);
      await first.persistSplitFraction(SplitPane.game, landscape: true);
      await first.persistSplitFraction(SplitPane.players, landscape: false);

      final next = await _loaded(TabletLayoutProvider());

      expect(next.splitFraction(SplitPane.game, landscape: true), 0.65);
      expect(next.splitFraction(SplitPane.players, landscape: false), 0.38);
      expect(next.splitFraction(SplitPane.game, landscape: false),
          kDefaultSplitFraction);
    });

    test('refuses a split that would leave a pane unusable', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await _loaded(TabletLayoutProvider());

      provider.setSplitFraction(SplitPane.game, 0.95, landscape: true);

      expect(provider.splitFraction(SplitPane.game, landscape: true),
          kMaxSplitFraction);
    });
  });
}
