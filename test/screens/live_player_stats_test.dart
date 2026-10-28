import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/providers/tablet_layout_provider.dart';
import 'package:dartscore_app/screens/live_player_stats_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:dartscore_app/widgets/throw_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The live info opened by tapping a slot on the scoreboard. On a tablet held
/// on its side it carries two players at once, where it used to be a phone
/// sized column in the middle of the screen.
void main() {
  group('the live info screen', () {
    useInMemoryDatabase();

    late GameProvider game;
    late List<Player> players;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      game = GameProvider();
    });

    /// Starts a game of [names] and renders the info screen on [slot].
    Future<void> pumpInfo(
      WidgetTester tester, {
      required Size size,
      List<String> names = const ['Ada', 'Zoe'],
      int slot = 0,
    }) async {
      await tester.runAsync(() async {
        players = await insertPlayers(names);
        await game.startGame(
          Game(
            startScore: 501,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 4, 1),
            startingOrder: StartingOrder.fixed,
          ),
          players,
        );
      });

      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        ChangeNotifierProvider<TabletLayoutProvider>.value(
          value: TabletLayoutProvider(),
          child: testApp(
            LivePlayerStatsScreen(initialSlotIndex: slot),
            game: game,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Where the header card naming [name] sits.
    Rect headerRect(WidgetTester tester, String name) => tester.getRect(
      find.descendant(of: find.byType(Card), matching: find.text(name)),
    );

    testWidgets('carries two players side by side on a tablet turned over', (
      tester,
    ) async {
      await pumpInfo(tester, size: const Size(1180, 820));

      expect(find.byKey(kPaneDividerKey), findsOneWidget);
      expect(
        headerRect(tester, 'Zoe').left,
        greaterThan(headerRect(tester, 'Ada').right),
      );
      // Both are named at once, so the bar names both.
      expect(find.text('Ada · Zoe'), findsOneWidget);
    });

    testWidgets('keeps one player a page upright', (tester) async {
      await pumpInfo(tester, size: const Size(820, 1180));

      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(find.text('Ada'), findsWidgets);
      expect(find.text('Zoe'), findsNothing);
    });

    testWidgets('pages in twos, and gives the odd player the middle', (
      tester,
    ) async {
      await pumpInfo(
        tester,
        size: const Size(1180, 820),
        names: ['Ada', 'Zoe', 'Bo'],
      );

      // Three players make two pages, and one turn of the page skips two of
      // them rather than one.
      expect(find.bySemanticsLabel('Player 1 of 3'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Player 3 of 3'), findsOneWidget);
      expect(find.text('Bo'), findsWidgets);
      // Alone on its page, the last one stands in the middle rather than in
      // half a screen with nothing beside it.
      final header = headerRect(tester, 'Bo');
      expect(header.center.dx, closeTo(1180 / 2, 40));
      expect(find.byKey(kPaneDividerKey), findsNothing);
    });

    testWidgets('shows the last three visits, and says so before the first', (
      tester,
    ) async {
      await pumpInfo(tester, size: const Size(400, 1400));
      expect(find.text('No visits yet'), findsOneWidget);
      expect(find.byType(ThrowRow), findsNothing);

      // Four visits by Ada, with Zoe missing in between so the turn returns.
      await tester.runAsync(() async {
        for (final score in [(20, 1), (19, 1), (18, 1), (17, 1)]) {
          for (var d = 0; d < 3; d++) {
            await game.tapField(score.$1, score.$2);
          }
          for (var d = 0; d < 3; d++) {
            await game.tapField(0, 1);
          }
        }
      });
      await tester.pumpAndSettle();

      final shown = tester
          .widgetList<ThrowRow>(find.byType(ThrowRow))
          .map((r) => r.t.score)
          .toList();
      expect(shown, [
        57,
        54,
        51,
      ], reason: 'the newest three in order, the sixty has dropped off');
    });

    testWidgets('is one column at a phone size', (tester) async {
      await pumpInfo(tester, size: const Size(400, 900));

      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(find.text('Ada'), findsWidgets);
      expect(find.text('Zoe'), findsNothing);
    });
  });
}
