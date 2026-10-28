import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/screens/cricket_screen.dart';
import 'package:dartscore_app/widgets/cricket_marks_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The Cricket board on a tablet, where it used to be a phone sized card with
/// half the screen empty under it and the last player cut off its right edge.
///
/// Every game is started in `setUp`, never in a test body: starting one writes
/// rows, and a widget test runs in fake async where a real database write never
/// completes.
void main() {
  group('the Cricket board', () {
    useInMemoryDatabase();

    late CricketProvider provider;

    /// Starts a game of [count] players, named P1 to Pn so a column can be
    /// found by the name over it.
    Future<void> startGame(int count) async {
      final players = await insertPlayers(
        List.generate(count, (i) => 'P${i + 1}'),
      );
      provider = CricketProvider();
      await provider.startGame(
        CricketGame(
          variant: CricketVariant.normal,
          scoringMode: CricketScoringMode.standard,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
    }

    Future<void> pumpBoard(WidgetTester tester, Size size) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<CricketProvider>.value(
            value: provider,
            child: const CricketScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The board card, which is the only Card on this screen.
    Finder boardCard() => find.byType(Card);

    /// The size one mark is drawn at, which follows the height of a row.
    double markSize(WidgetTester tester) => tester
        .widget<CricketMarksWidget>(find.byType(CricketMarksWidget).first)
        .size;

    group('with six players', () {
      setUp(() => startGame(6));

      testWidgets('fills the height it is given on a tablet', (tester) async {
        await pumpBoard(tester, const Size(1180, 820));

        final card = tester.getRect(boardCard());
        final input = tester.getRect(find.text('Miss'));

        // Down to the input rather than stopping a third of the way there. The
        // old board was a fixed 411 dp whatever the screen offered.
        expect(card.height, greaterThan(500));
        expect(card.bottom, lessThan(input.top));
        // And the rows grew with it, marks and all.
        expect(markSize(tester), greaterThan(36));
      });

      testWidgets('gives every player a column that is on the screen', (
        tester,
      ) async {
        await pumpBoard(tester, const Size(1180, 820));

        // The sixth player used to sit past the right edge of a card capped at
        // a phone's width, reachable only by scrolling the grid.
        expect(
          tester.getRect(find.text('P6')).right,
          lessThanOrEqualTo(tester.getRect(boardCard()).right),
        );

        // Upright too, where there is less width to divide.
        await pumpBoard(tester, const Size(820, 1180));
        expect(
          tester.getRect(find.text('P6')).right,
          lessThanOrEqualTo(tester.getRect(boardCard()).right),
        );
      });
    });

    group('with two players', () {
      setUp(() => startGame(2));

      testWidgets(
        'stands centred rather than stretching them across the room',
        (tester) async {
          await pumpBoard(tester, const Size(1180, 820));

          final card = tester.getRect(boardCard());
          expect(card.center.dx, closeTo(1180 / 2, 8));
          // Two columns at their cap plus the labels, not the whole window.
          expect(card.width, lessThan(600));
        },
      );

      testWidgets('is the same fixed board on a phone', (tester) async {
        await pumpBoard(tester, const Size(400, 900));

        expect(markSize(tester), 36);
        // Full width, as it has always been, rather than shrunk to its columns.
        expect(tester.getRect(boardCard()).width, greaterThan(340));
      });
    });
  });
}
