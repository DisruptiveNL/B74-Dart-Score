import 'package:dartscore_app/providers/donation_provider.dart';
import 'package:dartscore_app/screens/game_mode_selection_screen.dart';
import 'package:dartscore_app/screens/home_screen.dart';
import 'package:dartscore_app/screens/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_store.dart';
import 'support/test_app.dart';
import 'support/test_db.dart';

void main() {
  group('the home screen', () {
    useInMemoryDatabase();
    final store = useFakeStore();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    /// Pumps the home screen with its own donation provider.
    ///
    /// No waiting before the first pump: the provider reads its supporter flag
    /// through a mocked platform channel, and in a widget test the clock only
    /// moves while frames are being pumped. Awaiting anything beforehand waits
    /// on a timer that has nothing to advance it.
    Future<void> pumpHome(WidgetTester tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<DonationProvider>(
            create: (_) => DonationProvider(),
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the four ways into the app', (tester) async {
      await pumpHome(tester);

      expect(find.text('New Game'), findsOneWidget);
      expect(find.text('Manage Players'), findsOneWidget);
      expect(find.text('Game History'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('opens the mode picker from New Game', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();

      expect(find.byType(GameModeSelectionScreen), findsOneWidget);
    });

    testWidgets('opens the player list from Manage Players', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text('Manage Players'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayersScreen), findsOneWidget);
    });

    testWidgets('wears no heart before anyone has donated', (tester) async {
      await pumpHome(tester);

      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    });

    testWidgets('wears the heart once the user has donated', (tester) async {
      // Set before the first pump, because shared_preferences hands out a
      // cached instance and changing the values under a running screen would
      // not reach it.
      SharedPreferences.setMockInitialValues({'is_supporter': true});

      await pumpHome(tester);

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('asks the store for nothing on the way in', (tester) async {
      // The screen watches DonationProvider for that one flag. Building it
      // must not turn into a store connection and a round trip for the prices
      // on every launch.
      await pumpHome(tester);

      expect(store.calls, isNot(contains('isAvailable')));
      expect(store.calls, isNot(contains('queryProductDetails')));
    });
  });
}
