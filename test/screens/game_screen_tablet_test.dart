import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/providers/tablet_layout_provider.dart';
import 'package:dartscore_app/screens/game_screen.dart';
import 'package:dartscore_app/screens/live_player_stats_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:dartscore_app/widgets/dartboard_input.dart';
import 'package:dartscore_app/widgets/finish_suggestion_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// A 10.9 inch tablet, upright and on its side, with the insets it carries.
const _tabletPortrait  = Size(820, 1180);
const _tabletLandscape = Size(1180, 820);
const _tabletInsets    = EdgeInsets.only(top: 24, bottom: 20);

void main() {
  group('the live X01 screen on a tablet', () {
    useInMemoryDatabase();

    late GameProvider game;
    late TabletLayoutProvider inputSide;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      game = GameProvider();
      inputSide = TabletLayoutProvider();
    });

    /// Starts a two player game and renders it at the given size.
    Future<void> pumpGame(
      WidgetTester tester, {
      required Size surface,
      InputSide? side,
      double? fraction,
    }) async {
      await tester.runAsync(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        await game.startGame(
          Game(
            startScore: 501,
            legs: 3,
            sets: 1,
            createdAt: DateTime.now(),
            startingOrder: StartingOrder.fixed,
          ),
          players,
        );
        if (side != null) await inputSide.setSide(side);
      });
      if (fraction != null) {
        inputSide.setSplitFraction(SplitPane.game, fraction,
            landscape: surface.width >= surface.height);
      }

      usePhoneSurface(tester, size: surface, safeArea: _tabletInsets);
      await tester.pumpWidget(
        ChangeNotifierProvider<TabletLayoutProvider>.value(
          value: inputSide,
          child: testApp(const GameScreen(), game: game),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The horizontal centre of the input, and of the live stats beside it.
    (double, double) paneCentres(WidgetTester tester) => (
          tester.getRect(find.byType(DartboardInput<GameProvider>)).center.dx,
          tester.getRect(find.byType(LivePlayerStatsPanel)).center.dx,
        );

    testWidgets('shows the stats of whoever is throwing beside the input',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      expect(find.byType(LivePlayerStatsPanel), findsOneWidget);
      // The panel names the slot it describes, and Ada throws first.
      expect(find.text('Ada'), findsWidgets);
      expect(find.byType(DartboardInput<GameProvider>), findsOneWidget);
    });

    testWidgets('follows the turn without being asked', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);
      expect(game.currentPlayerIndex, 0);

      await tester.runAsync(() async {
        await game.tapField(20, 1);
        await game.tapField(20, 1);
        await game.tapField(20, 1);
      });
      await tester.pumpAndSettle();

      expect(game.currentPlayerIndex, 1);
      final panel = tester.widget<LivePlayerStatsPanel>(
          find.byType(LivePlayerStatsPanel));
      expect(panel.slotIndex, 1);
    });

    testWidgets('starts with the input on the left', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final (input, stats) = paneCentres(tester);
      expect(input, lessThan(stats));
    });

    testWidgets('moves the input over when the setting says right',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape, side: InputSide.right);

      final (input, stats) = paneCentres(tester);
      expect(input, greaterThan(stats));
    });

    testWidgets('swaps the panes from the app bar', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);
      final (inputBefore, statsBefore) = paneCentres(tester);
      expect(inputBefore, lessThan(statsBefore));

      await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
      await tester.pumpAndSettle();

      final (inputAfter, statsAfter) = paneCentres(tester);
      expect(inputAfter, greaterThan(statsAfter));
      expect(inputSide.side, InputSide.right);
    });

    testWidgets('offers the swap only where there are two panes',
        (tester) async {
      await pumpGame(tester, surface: const Size(375, 812));

      expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
    });

    testWidgets('splits only the space below the scoreboard in portrait',
        (tester) async {
      await pumpGame(tester, surface: _tabletPortrait);

      final (input, stats) = paneCentres(tester);
      expect(input, lessThan(stats));

      // The scoreboard spans the full width above both panes rather than
      // sharing a row with them.
      final board = tester.getRect(find.text('501').first);
      final inputTop = tester.getRect(find.byType(DartboardInput<GameProvider>)).top;
      expect(board.bottom, lessThan(inputTop));
    });

    testWidgets('gives the input the full height of its pane', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final pane = tester.getRect(find.byType(DartboardInput<GameProvider>));
      // Bull closes the action column, so it is what has to reach the bottom.
      final bull = tester.getRect(find.widgetWithText(InkWell, 'Bull (25)').first);
      final field = tester.getRect(find.widgetWithText(InkWell, '20').first);

      // The action row ends at the bottom of the pane instead of floating in
      // the middle of it, the buttons grew past their phone size, and no hole
      // is left between the last row of numbers and the actions.
      expect(pane.bottom - bull.bottom, lessThan(30));
      expect(field.height, greaterThan(45));
      expect(bull.top - field.bottom, lessThan(80));
    });

    testWidgets('puts the actions beside the numbers in landscape',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final field = tester.getRect(find.widgetWithText(InkWell, '20').first);
      final miss  = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);
      final bull  = tester.getRect(find.widgetWithText(InkWell, 'Bull (25)').first);

      // Beside, not below, and the column ends where the grid ends rather than
      // floating next to it.
      expect(miss.left, greaterThan(field.right));
      expect((bull.bottom - field.bottom).abs(), lessThan(2));
      // The height the row under the grid used to take went to the numbers,
      // which are well past their phone size of 37 to 51.
      expect(field.height, greaterThan(60));
    });

    testWidgets('gives Miss and Bull the same size beside the numbers',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final miss = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);
      final bull =
          tester.getRect(find.widgetWithText(InkWell, 'Bull (25)').first);

      expect(miss.width, moreOrLessEquals(bull.width, epsilon: 1));
      expect(miss.height, moreOrLessEquals(bull.height, epsilon: 1));
    });

    testWidgets('names the slot its stats belong to', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      // Twice: once on the score card, once as the heading over the stats.
      expect(find.text('Ada'), findsNWidgets(2));
      // And only once for what the card already carries, which is what the
      // header card of the full screen would have repeated.
      expect(find.byType(FinishSuggestionWidget), findsOneWidget);
    });

    testWidgets('leaves no dead space under the numbers in portrait',
        (tester) async {
      // A grid stretched to a box taller than it needs parks the difference
      // inside its own viewport, where no spacing can reach it.
      await pumpGame(tester, surface: _tabletPortrait);

      final field = tester.getRect(find.widgetWithText(InkWell, '20').first);
      final miss  = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);

      expect(miss.top - field.bottom, lessThan(80));
    });

    testWidgets('gives the action row a tablet height in portrait',
        (tester) async {
      // Under the grid the row would otherwise keep the height its content
      // needs, which is the phone height, next to number buttons twice that
      // size. The grid gives up what the row takes.
      await pumpGame(tester, surface: _tabletPortrait);

      final miss  = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);
      final label = tester.getRect(find.text('Miss'));

      expect(miss.height, greaterThan(70));
      expect(label.height, greaterThan(18));
    });

    testWidgets('keeps the actions under the numbers in portrait',
        (tester) async {
      // Half of a portrait tablet is too narrow to give a column away: the
      // numbers would pay for it in width.
      await pumpGame(tester, surface: _tabletPortrait);

      final field = tester.getRect(find.widgetWithText(InkWell, '20').first);
      final miss  = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);

      expect(miss.top, greaterThan(field.bottom));
    });

    testWidgets('hangs input, stats and divider off the scoreboard alike',
        (tester) async {
      await pumpGame(tester, surface: _tabletPortrait);

      final hint    = tester.getRect(find.byType(FinishSuggestionWidget));
      final input   = tester.getRect(find.byType(DartboardInput<GameProvider>));
      final stats   = tester.getRect(find.byType(LivePlayerStatsPanel));
      final divider = tester.getRect(find.byKey(kPaneDividerKey));

      expect(input.top, closeTo(stats.top, 0.5));
      expect(divider.top, closeTo(stats.top, 0.5));
      // And all three start below the score block rather than against it.
      expect(stats.top, greaterThan(hint.bottom));
    });

    testWidgets('starts with the divider in the middle', (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final input = tester.getRect(find.byType(DartboardInput<GameProvider>));
      final stats = tester.getRect(find.byType(LivePlayerStatsPanel));

      expect((input.width - stats.width).abs(), lessThan(kDividerHitWidth + 2));
    });

    testWidgets('rebalances the panes when the divider is dragged',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);
      final before = tester.getRect(find.byType(DartboardInput<GameProvider>)).width;

      // The input sits on the left, so dragging the divider right grows it.
      // No touch slop, so the pane moves by exactly what the drag says.
      await tester.drag(find.byKey(kPaneDividerKey), const Offset(120, 0),
          touchSlopX: 0);
      await tester.pumpAndSettle();

      final after = tester.getRect(find.byType(DartboardInput<GameProvider>)).width;
      expect(after - before, closeTo(120, 4));
      expect(inputSide.splitFraction(SplitPane.game, landscape: true),
          greaterThan(kDefaultSplitFraction));
    });

    testWidgets('keeps the action column as tall as the numbers beside it',
        (tester) async {
      // Dragged wide enough, portrait puts the actions beside the grid too,
      // which on a 12.9 inch tablet is a pane over 700 dp wide and 900 tall.
      // Stretched to the pane instead of to the grid the buttons would be
      // 300 dp tall and the grid would hide the difference inside itself.
      await pumpGame(
        tester,
        surface: const Size(1024, 1366),
        fraction: 0.7,
      );

      final firstRow = tester.getRect(find.widgetWithText(InkWell, '1').first);
      final lastRow  = tester.getRect(find.widgetWithText(InkWell, '20').first);
      final miss     = tester.getRect(find.widgetWithText(InkWell, 'Miss').first);
      final bull     = tester.getRect(find.widgetWithText(InkWell, 'Bull (25)').first);

      // Pinned at both ends: the column starts where the numbers start and
      // ends where they end, whatever height the grid turns out to have.
      expect(miss.left, greaterThan(lastRow.right));
      expect((miss.top - firstRow.top).abs(), lessThan(2));
      expect((bull.bottom - lastRow.bottom).abs(), lessThan(2));
    });

    testWidgets('stops the drag before a pane stops being usable',
        (tester) async {
      await pumpGame(tester, surface: _tabletPortrait);

      // Far past the end of the range, in both directions.
      await tester.drag(find.byKey(kPaneDividerKey), const Offset(-600, 0),
          touchSlopX: 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DartboardInput<GameProvider>)).width,
          greaterThanOrEqualTo(kMinPaneWidth));

      await tester.drag(find.byKey(kPaneDividerKey), const Offset(600, 0),
          touchSlopX: 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(LivePlayerStatsPanel)).width,
          greaterThanOrEqualTo(kMinPaneWidth));
    });

    testWidgets('fits the larger cards on a small tablet', (tester) async {
      // The tablet sizes are the tallest the scoreboard gets, so the smallest
      // tablet on its side is where they run out of room first. An overflow
      // fails the test on its own.
      await pumpGame(tester, surface: const Size(1133, 744));

      expect(find.byType(LivePlayerStatsPanel), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Bull (25)'), findsOneWidget);
    });

    testWidgets('stays a single column on a phone sized window',
        (tester) async {
      await pumpGame(tester, surface: const Size(375, 812));

      expect(find.byType(LivePlayerStatsPanel), findsNothing);
      expect(find.byType(DartboardInput<GameProvider>), findsOneWidget);
    });

    testWidgets('moves the checkout hint over the input once it is wide',
        (tester) async {
      // Wide enough for the actions beside the grid, which is where the column
      // above them becomes short enough to carry the hint.
      await pumpGame(
        tester,
        surface: const Size(1024, 1366),
        fraction: 0.7,
      );

      final hint = tester.getRect(find.byType(FinishSuggestionWidget));
      final board = tester.getRect(find.text('501').first);
      final input = tester.getRect(find.byType(DartboardInput<GameProvider>));

      // Below the scoreboard it used to hang under, and inside the pane the
      // input has to itself.
      expect(hint.top, greaterThan(board.bottom));
      expect(hint.bottom, lessThan(input.top));
      expect(hint.left, greaterThanOrEqualTo(input.left - 1));
      expect(hint.right, lessThanOrEqualTo(input.right + 1));
    });

    testWidgets('keeps the checkout hint under the score while it is narrow',
        (tester) async {
      await pumpGame(
        tester,
        surface: const Size(1024, 1366),
        fraction: kMinSplitFraction,
      );

      final hint = tester.getRect(find.byType(FinishSuggestionWidget));
      final input = tester.getRect(find.byType(DartboardInput<GameProvider>));

      // Spanning the width above both panes, not sitting in one of them.
      expect(hint.width, greaterThan(input.width));
    });

    testWidgets('centres the modifier switch under the visit row',
        (tester) async {
      await pumpGame(tester, surface: _tabletLandscape);

      final segment = tester.getRect(find.byType(SegmentedButton<int>));
      final pane    = tester.getRect(find.byType(DartboardInput<GameProvider>));

      // A switch for the whole input, so it sits on the middle line of the
      // pane rather than over one column of it.
      expect(segment.center.dx, closeTo(pane.center.dx, 2));
      // And carries a tablet size, not the one it has on a phone: as wide as
      // the pane allows it, and taller than a phone draws it.
      expect(segment.width, closeTo(pane.width - 20, 2));
      expect(segment.height, greaterThan(60));
    });
  });
}
