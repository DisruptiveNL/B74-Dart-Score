import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/donation_provider.dart';
import 'package:dartscore_app/providers/language_provider.dart';
import 'package:dartscore_app/providers/pace_provider.dart';
import 'package:dartscore_app/providers/text_scale_provider.dart';
import 'package:dartscore_app/providers/theme_provider.dart';
import 'package:dartscore_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';

void main() {
  group('the game pace row', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => TurnPacing.pace = GamePace.normal);

    Future<PaceProvider> pumpSettings(WidgetTester tester) async {
      final pace = PaceProvider();
      usePhoneSurface(tester, size: const Size(400, 1200));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PaceProvider>.value(value: pace),
            ChangeNotifierProvider(create: (_) => TextScaleProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider(create: (_) => DonationProvider()),
          ],
          child: testApp(const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return pace;
    }

    testWidgets('keeps what it does behind an info icon until asked', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('Game pace'), findsOneWidget);
      expect(
        find.textContaining('how quickly a computer opponent throws'),
        findsNothing,
      );

      await tester.tap(find.byTooltip('What it does'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('how quickly a computer opponent throws'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('What it does'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('how quickly a computer opponent throws'),
        findsNothing,
      );
    });

    testWidgets('offers the three paces and hands the pick to the games', (
      tester,
    ) async {
      final pace = await pumpSettings(tester);

      await tester.tap(find.text('Game pace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slow').last);
      await tester.pumpAndSettle();

      expect(pace.pace, GamePace.slow);
      expect(TurnPacing.pace, GamePace.slow);
      expect(
        find.text('Slow'),
        findsOneWidget,
        reason: 'the row now shows the pick',
      );
    });
  });
}
