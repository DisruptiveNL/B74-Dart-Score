import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/screens/history_game_summary_screen.dart';
import 'package:dartscore_app/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:dartscore_app/providers/tablet_layout_provider.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The history list. Everything is written in `setUp`, because a widget test
/// runs in fake async where a real database write never completes.
void main() {
  group('the history list', () {
    useInMemoryDatabase();

    late List<Player> players;
    late TabletLayoutProvider layout;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      layout = TabletLayoutProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      final ids = players.map((p) => p.id!).toList();
      final db = DbHelper.instance;

      // An unfinished X01 game with both players, in that order.
      await db.insertGame(
        Game(startScore: 501, createdAt: DateTime(2026, 3, 1)),
        ids,
      );
      // A finished X01 game, so the two tabs have something to separate.
      await db.insertGame(
        Game(
          startScore: 301,
          createdAt: DateTime(2026, 2, 1),
          finishedAt: DateTime(2026, 2, 1, 1),
        ),
        ids,
      );
      // An unfinished Cricket game, to give the mode filter something to do.
      await db.insertCricketGame(
        CricketGame(
          variant: CricketVariant.normal,
          scoringMode: CricketScoringMode.standard,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 3, 2),
          playerIds: ids,
        ),
      );
    });

    /// Pumps the screen and lets the list load.
    ///
    /// The body is a FutureBuilder over a database read, which is real I/O the
    /// fake clock never reaches, so it has to be let through before anything
    /// settles on the spinner standing in for it.
    Future<void> pumpHistory(
      WidgetTester tester, {
      Size size = const Size(400, 1200),
    }) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        ChangeNotifierProvider<TabletLayoutProvider>.value(
          value: layout,
          child: testApp(const HistoryScreen()),
        ),
      );
      await pumpUntilLoaded(tester);
    }

    /// Opens the Finished tab, where the detail of a game can be reached.
    Future<void> openFinished(WidgetTester tester) async {
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
    }

    testWidgets('names both players of a game, in turn order', (tester) async {
      // The line-ups come from one batched read rather than a query per game.
      // If that ever regressed to returning nothing, the title would collapse
      // to an empty string rather than fail loudly.
      await pumpHistory(tester);

      expect(find.text('Ada vs Zoe'), findsWidgets);
    });

    testWidgets('keeps unfinished games apart from finished ones', (
      tester,
    ) async {
      await pumpHistory(tester);

      // Open: the 501 game and the Cricket one. The finished 301 is elsewhere.
      expect(find.textContaining('501'), findsOneWidget);
      expect(find.textContaining('301'), findsNothing);

      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();

      expect(find.textContaining('301'), findsOneWidget);
    });

    testWidgets('offers a filter only for the modes actually present', (
      tester,
    ) async {
      await pumpHistory(tester);

      // The open tab holds an X01 and a Cricket game and nothing else, so
      // Shanghai and Around the Clock have no chip to offer.
      expect(find.widgetWithText(FilterChip, 'Cricket'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Shanghai'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Around the Clock'), findsNothing);
    });

    testWidgets('narrows the list to the chosen mode', (tester) async {
      await pumpHistory(tester);
      expect(find.textContaining('501'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Cricket'));
      await tester.pumpAndSettle();

      expect(find.textContaining('501'), findsNothing);
      expect(find.text('Ada vs Zoe'), findsOneWidget);
    });

    testWidgets('opens a game beside the list on a tablet', (tester) async {
      await pumpHistory(tester, size: const Size(1180, 820));
      await openFinished(tester);

      // Nothing picked yet, so the pane says what to do.
      expect(find.textContaining('Pick a game'), findsOneWidget);

      await tester.tap(find.textContaining('301'));
      // Bounded on purpose: what is asserted is where the detail is put, and
      // the pane header is there a frame later, long before the throws it
      // reads for the body have arrived.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The list is still there, so nothing was pushed over it, and the date
      // now reads twice: once on the tile, once as the title of the pane.
      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('Pick a game'), findsNothing);

      final dates = tester.widgetList<Text>(find.textContaining('01.02.26'));
      expect(dates.length, 2);

      // Rendered bare, because the pane around it carries the title.
      final detail = tester.widget<HistoryGameSummaryScreen>(
        find.byType(HistoryGameSummaryScreen),
      );
      expect(detail.embedded, isTrue);

      final list = tester.getRect(find.byType(ListView).first);
      final title = tester.getRect(find.textContaining('01.02.26').last);
      expect(title.left, greaterThan(list.right));
    });

    testWidgets('opens it on top of the list on a phone', (tester) async {
      await pumpHistory(tester);
      await openFinished(tester);

      await tester.tap(find.textContaining('301'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Pushed as its own screen, with the bars that belong to one.
      final detail = tester.widget<HistoryGameSummaryScreen>(
        find.byType(HistoryGameSummaryScreen),
      );
      expect(detail.embedded, isFalse);
    });

    testWidgets('leaves the open tab the whole width on a tablet', (
      tester,
    ) async {
      await pumpHistory(tester, size: const Size(1180, 820));

      // An open game is resumed, not read: there is nothing to put beside the
      // list, so the list keeps the width instead of facing an empty half.
      expect(find.textContaining('Pick a game'), findsNothing);
      // The list keeps its readable width but sits in the middle of the
      // window rather than pushed into a third of it.
      final list = tester.getRect(find.byType(ListView).first);
      expect(list.center.dx, closeTo(1180 / 2, 20));

      await openFinished(tester);
      expect(find.textContaining('Pick a game'), findsOneWidget);
    });

    testWidgets('keeps a divider position of its own', (tester) async {
      // Its own key, so a divider dragged in the game does not move this one.
      layout.setSplitFraction(SplitPane.history, 0.62, landscape: true);

      await pumpHistory(tester, size: const Size(1180, 820));
      await openFinished(tester);

      // Measured at the divider: the list inside the pane keeps its own
      // readable width and sits centred in whatever the pane gives it.
      final divider = tester.getRect(find.byKey(kPaneDividerKey));
      expect(divider.left, closeTo(1180 * 0.62, 4));

      // And a drag here writes back to that key.
      await tester.drag(
        find.byKey(kPaneDividerKey),
        const Offset(-120, 0),
        touchSlopX: 0,
      );
      await tester.pumpAndSettle();

      expect(
        layout.splitFraction(SplitPane.history, landscape: true),
        lessThan(0.62),
      );
    });
  });
}
