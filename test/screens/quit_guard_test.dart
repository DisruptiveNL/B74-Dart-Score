import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_screen.dart';
import 'package:dartscore_app/screens/cricket_screen.dart';
import 'package:dartscore_app/screens/shanghai_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The quit guard on the three live screens that are not X01. X01 has its own
/// file, where the input is exercised as well.
///
/// CLAUDE.md makes this a convention across all four: a running game must not
/// be lost to a stray back gesture, so the route refuses to pop and asks the
/// same question the close button asks. Because `PopScope` also governs the iOS
/// edge swipe, a screen that quietly loses it changes behaviour on both
/// platforms at once, which nobody notices until a game is gone.
///
/// Every game is started in `setUp`, never inside the test body: starting one
/// writes rows, and a widget test runs in fake async where a real database
/// write never completes.
void main() {
  group('the quit guard', () {
    useInMemoryDatabase();

    late List<Player> players;

    /// The screen instance under test, kept so the assertions can look for
    /// exactly this one rather than for its type.
    late Widget screen;

    /// That screen with its own provider around it, correctly typed. Typing it
    /// as ChangeNotifier would register it under that type, and the screen's
    /// Consumer would never find it.
    late Widget wrapped;

    setUp(() async {
      players = await insertPlayers(['Ada', 'Zoe']);
    });

    /// Pumps the screen of the mode prepared for this group.
    Future<void> pumpLive(WidgetTester tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(testApp(wrapped));
      await tester.pumpAndSettle();
    }

    /// The three cases, each asserting the same contract on its own screen.
    void sharedCases() {
      testWidgets('answers the system back with the quit question', (
        tester,
      ) async {
        await pumpLive(tester);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byWidget(screen), findsOneWidget);
      });

      testWidgets('asks the same thing from the close button', (tester) async {
        await pumpLive(tester);

        // Scoped to the app bar, because the dartboard input below has a Miss
        // button with a close icon of its own.
        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.close_rounded),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('stays in the game when the question is declined', (
        tester,
      ) async {
        await pumpLive(tester);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byWidget(screen), findsOneWidget);
      });
    }

    group('Cricket', () {
      setUp(() async {
        final p = CricketProvider();
        await p.startGame(
          CricketGame(
            variant: CricketVariant.normal,
            scoringMode: CricketScoringMode.standard,
            legs: 1,
            sets: 1,
            createdAt: DateTime.now(),
            playerIds: players.map((pl) => pl.id!).toList(),
          ),
          players,
        );
        screen = const CricketScreen();
        wrapped = ChangeNotifierProvider<CricketProvider>.value(
          value: p,
          child: screen,
        );
      });

      sharedCases();
    });

    group('Shanghai', () {
      setUp(() async {
        final p = ShanghaiProvider();
        await p.startGame(
          ShanghaiGame(
            variant: ShanghaiVariant.classic,
            legs: 1,
            sets: 1,
            createdAt: DateTime.now(),
            playerIds: players.map((pl) => pl.id!).toList(),
          ),
          players,
        );
        screen = const ShanghaiScreen();
        wrapped = ChangeNotifierProvider<ShanghaiProvider>.value(
          value: p,
          child: screen,
        );
      });

      sharedCases();
    });

    group('Around the Clock', () {
      setUp(() async {
        final p = AroundTheClockProvider();
        await p.startGame(
          AroundTheClockGame(
            variant: AroundTheClockVariant.basic,
            legs: 1,
            sets: 1,
            createdAt: DateTime.now(),
            playerIds: players.map((pl) => pl.id!).toList(),
          ),
          players,
        );
        screen = const AroundTheClockScreen();
        wrapped = ChangeNotifierProvider<AroundTheClockProvider>.value(
          value: p,
          child: screen,
        );
      });

      sharedCases();
    });
  });
}
