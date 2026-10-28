import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_screen.dart';
import 'package:dartscore_app/screens/cricket_screen.dart';
import 'package:dartscore_app/screens/mode_live_info_screen.dart';
import 'package:dartscore_app/screens/shanghai_screen.dart';
import 'package:dartscore_app/widgets/visit_darts_row.dart';
import 'package:dartscore_app/widgets/visit_pause.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The visit chips and the live info of the three target modes. Every game is
/// started and every dart thrown in `setUp`, never in a test body: both write
/// rows, and a widget test runs in fake async where a real write never
/// completes.
void main() {
  group('the visit chips and the live info', () {
    useInMemoryDatabase();

    late Widget wrapped;

    Future<void> pumpLive(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 900));
      await tester.pumpWidget(testApp(wrapped));
      await tester.pumpAndSettle();
    }

    /// Taps the name of the slot on turn, the first place it is printed.
    Future<void> openInfo(WidgetTester tester, String name) async {
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
    }

    group('Cricket', () {
      late CricketProvider cricket;

      setUp(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        final p = cricket = CricketProvider();
        await p.startGame(
          CricketGame(
            variant: CricketVariant.normal,
            scoringMode: CricketScoringMode.standard,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 9, 11),
            playerIds: players.map((pl) => pl.id!).toList(),
            startingOrder: StartingOrder.fixed,
          ),
          players,
        );
        await p.recordDart(20, 3);
        await p.recordDart(0, 0);
        wrapped = ChangeNotifierProvider<CricketProvider>.value(
          value: p,
          child: const CricketScreen(),
        );
      });

      testWidgets('shows the darts of the visit as chips', (tester) async {
        await pumpLive(tester);

        expect(find.byType(VisitDartsRow), findsOneWidget);
        expect(find.text('T20'), findsOneWidget);
        expect(find.text('Miss'), findsWidgets);
      });

      testWidgets('offers Continue while a finished visit is on show', (
        tester,
      ) async {
        await pumpLive(tester);
        final p = cricket;
        // A pause long enough never to run out on its own: what ends it here
        // is the button. The dart is a real write, let through.
        TurnPacing.debugVisitPause = const Duration(hours: 1);
        await tester.runAsync(() => p.recordDart(19, 1));
        await tester.pump();

        expect(p.visitPending, isTrue);
        expect(find.text('Continue'), findsOneWidget);
        expect(find.byType(VisitPauseBar), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.text('Continue'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        expect(p.visitPending, isFalse);
        expect(p.currentPlayerIndex, 1);
        expect(find.text('Continue'), findsNothing);
      });

      testWidgets('opens the info of a slot with its visit and its numbers', (
        tester,
      ) async {
        await pumpLive(tester);
        await openInfo(tester, 'Ada');

        expect(find.byType(ModeLiveInfoScreen), findsOneWidget);
        expect(find.text('Last 3 Visits'), findsOneWidget);
        expect(
          find.text('3 marks'),
          findsWidgets,
          reason: 'the visit, and the best visit is the same one',
        );
        expect(find.text('Marks per round'), findsOneWidget);
        expect(find.text('Fields closed'), findsOneWidget);
        expect(
          find.text('1 of 7'),
          findsOneWidget,
          reason: 'the triple closed the 20',
        );
      });
    });

    group('Shanghai', () {
      setUp(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        final p = ShanghaiProvider();
        await p.startGame(
          ShanghaiGame(
            variant: ShanghaiVariant.classic,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 9, 11),
            playerIds: players.map((pl) => pl.id!).toList(),
            startingOrder: StartingOrder.fixed,
          ),
          players,
        );
        await p.recordDart(3);
        wrapped = ChangeNotifierProvider<ShanghaiProvider>.value(
          value: p,
          child: const ShanghaiScreen(),
        );
      });

      testWidgets('labels the dart with the round\'s number', (tester) async {
        await pumpLive(tester);

        expect(find.text('T1'), findsOneWidget);
      });

      testWidgets('opens the info with points per round and Shanghais', (
        tester,
      ) async {
        await pumpLive(tester);
        await openInfo(tester, 'Ada');

        expect(find.text('3 points'), findsWidgets);
        expect(find.text('Points per round'), findsOneWidget);
        expect(find.text('Shanghais'), findsOneWidget);
      });
    });

    group('Around the Clock', () {
      setUp(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        final p = AroundTheClockProvider();
        await p.startGame(
          AroundTheClockGame(
            variant: AroundTheClockVariant.skipRules,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 9, 11),
            playerIds: players.map((pl) => pl.id!).toList(),
            startingOrder: StartingOrder.fixed,
          ),
          players,
        );
        // The clock starts on the 1, and a triple there skips two numbers.
        await p.recordDart(1, 3);
        wrapped = ChangeNotifierProvider<AroundTheClockProvider>.value(
          value: p,
          child: const AroundTheClockScreen(),
        );
      });

      testWidgets('opens the info with darts per target and skipped fields', (
        tester,
      ) async {
        await pumpLive(tester);
        expect(find.text('T1'), findsOneWidget);

        await openInfo(tester, 'Ada');

        expect(find.text('1 hit'), findsOneWidget);
        expect(find.text('Darts per target'), findsOneWidget);
        expect(find.text('Fields skipped'), findsOneWidget);
        expect(
          find.text('2'),
          findsWidgets,
          reason: 'the triple skipped the 2 and the 3',
        );
      });
    });
  });
}
