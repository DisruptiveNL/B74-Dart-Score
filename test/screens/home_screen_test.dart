import 'package:dartscore_app/providers/donation_provider.dart';
import 'package:dartscore_app/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_store.dart';
import '../support/test_app.dart';

void main() {
  group('the home screen', () {
    useFakeStore();

    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Renders the home screen at [size].
    Future<void> pumpHome(WidgetTester tester, Size size) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        ChangeNotifierProvider<DonationProvider>(
          create: (_) => DonationProvider(),
          child: testApp(const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stacks its buttons on a phone', (tester) async {
      await pumpHome(tester, const Size(375, 812));

      final players = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Manage Players'),
      );
      final settings = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Settings'),
      );

      expect(settings.top, greaterThan(players.bottom));
    });

    testWidgets('puts them in a row on a tablet', (tester) async {
      await pumpHome(tester, const Size(820, 1180));

      final players = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Manage Players'),
      );
      final settings = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Settings'),
      );

      expect(settings.left, greaterThan(players.right));
      expect((settings.top - players.top).abs(), lessThan(1));
    });

    testWidgets('uses the wider column on a tablet', (tester) async {
      await pumpHome(tester, const Size(820, 1180));

      final start = tester.getRect(
        find.widgetWithText(FilledButton, 'Competities & Toernooien'),
      );

      // Wider than the phone column, but not the full tablet width.
      expect(start.width, greaterThan(500));
      expect(start.width, lessThan(700));
    });


    testWidgets('shows competition as primary action on a tablet', (tester) async {
      await pumpHome(tester, const Size(820, 1180));

      expect(
        find.widgetWithText(FilledButton, 'Competities & Toernooien'),
        findsOneWidget,
      );

      expect(find.text('New Game'), findsNothing);
      expect(find.text('Game History'), findsNothing);
    });
  });
}
