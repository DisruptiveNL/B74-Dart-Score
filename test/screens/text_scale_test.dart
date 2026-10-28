import 'package:dartscore_app/providers/donation_provider.dart';
import 'package:dartscore_app/providers/language_provider.dart';
import 'package:dartscore_app/providers/pace_provider.dart';
import 'package:dartscore_app/providers/text_scale_provider.dart';
import 'package:dartscore_app/providers/theme_provider.dart';
import 'package:dartscore_app/screens/settings_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';

/// A 10.9 inch tablet held upright, and a phone.
const _tablet = Size(820, 1180);
const _phone = Size(390, 844);

void main() {
  group('the text size the reader sets', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Renders the settings screen at [size] with a text scale provider of its
    /// own, and hands that provider back so a test can read what the screen did
    /// to it.
    Future<TextScaleProvider> pumpSettings(
      WidgetTester tester, {
      required Size size,
    }) async {
      final scale = TextScaleProvider();
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TextScaleProvider>.value(value: scale),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider(create: (_) => DonationProvider()),
            ChangeNotifierProvider(create: (_) => PaceProvider()),
          ],
          child: testApp(const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return scale;
    }

    testWidgets('is offered on a tablet and nowhere else', (tester) async {
      await pumpSettings(tester, size: _tablet);
      expect(find.byType(Slider), findsOneWidget);

      await pumpSettings(tester, size: _phone);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('starts at the size the system asks for', (tester) async {
      final scale = await pumpSettings(tester, size: _tablet);

      expect(scale.factor, kDefaultTextScale);
      expect(find.text('100 %'), findsOneWidget);
    });

    testWidgets('follows the slider and offers the way back', (tester) async {
      final scale = await pumpSettings(tester, size: _tablet);
      // No way back while the size is the one the app starts at.
      expect(find.widgetWithText(TextButton, 'Standard'), findsNothing);

      await tester.drag(find.byType(Slider), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(scale.factor, kMaxTextScale);

      await tester.tap(find.widgetWithText(TextButton, 'Standard'));
      await tester.pumpAndSettle();
      expect(scale.factor, kDefaultTextScale);
    });

    test('keeps the factor inside the range it offers', () async {
      final scale = TextScaleProvider();

      await scale.setFactor(9);
      expect(scale.factor, kMaxTextScale);

      await scale.setFactor(0);
      expect(scale.factor, kMinTextScale);
    });

    test('reads back the size that was written', () async {
      SharedPreferences.setMockInitialValues({});
      await TextScaleProvider().setFactor(1.2);

      final reloaded = TextScaleProvider();
      // The load runs off the constructor, so the value lands one microtask
      // later rather than by the time the constructor returns.
      await Future<void>.delayed(Duration.zero);

      expect(reloaded.factor, 1.2);
    });

    testWidgets('multiplies the text of a subtree by what it is given', (
      tester,
    ) async {
      /// The height one line of text takes at [factor].
      Future<double> lineHeight(double factor) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TextScaleBy(
              factor: factor,
              child: const Center(child: Text('501')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getRect(find.text('501')).height;
      }

      final plain = await lineHeight(1.0);
      final larger = await lineHeight(1.4);

      expect(larger, greaterThan(plain));
    });
  });
}
