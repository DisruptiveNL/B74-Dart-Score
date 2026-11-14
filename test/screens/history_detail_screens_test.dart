import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/history_game_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The four history detail screens, which rebuild a finished game from its
/// stored throws rather than from a live provider.
///
/// Each group plays a real game in `setUp` and then hands the stored game back
/// to the screen, so what is under test is the reconstruction: the same throws
/// have to produce the same result a second time, hours or a sync later.
/// Renders a detail the way the tablet history does: embedded in a pane that is
/// a part of a wide window, and reports how wide its first card comes out.
///
/// The screens used to pad themselves by measuring the window, which inside a
/// pane leaves the margin of a whole screen on either side of half of one and
/// squeezes the content to nothing.
Future<double> paneCardWidth(WidgetTester tester, Widget detail) async {
  usePhoneSurface(tester, size: const Size(1180, 820));
  await tester.pumpWidget(
    testApp(Center(child: SizedBox(width: 560, height: 800, child: detail))),
  );
  await pumpUntilLoaded(tester);
  return tester.getRect(find.byType(Card).first).width;
}

void main() {
  // ── X01 ─────────────────────────────────────────────────────────────────────

  group('the X01 history detail', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;
    late Game stored;
    late Game empty;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        Game(
          startScore: 101,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1, 20, 15),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
      // Zoe never gets a turn: Ada takes 101 out in one visit.
      await provider.tapField(20, 3);
      await provider.tapField(9, 1);
      await provider.tapField(16, 2);

      // A game can reach history without a single visit: the row is written
      // when it starts, and quitting right away leaves it behind.
      final emptyId = await DbHelper.instance.insertGame(
        Game(startScore: 501, createdAt: DateTime(2026, 4, 2)),
        players.map((p) => p.id!).toList(),
      );

      // Read back rather than reuse the provider's copy: history hands the
      // screen what the database holds, which is where a finished game gets
      // its finish time.
      final games = await DbHelper.instance.getGames();
      stored = games.firstWhere((g) => g.id == provider.game!.id);
      empty = games.firstWhere((g) => g.id == emptyId);
    });

    Future<void> pumpDetail(WidgetTester tester, {Game? game}) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(
          HistoryGameSummaryScreen(game: game ?? stored, players: players),
        ),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('titles itself with when the game was played', (tester) async {
      await pumpDetail(tester);

      expect(find.text('01.04.26  20:15'), findsOneWidget);
    });

    testWidgets('offers the rematch on a bar under the game, not inside it', (
      tester,
    ) async {
      await pumpDetail(tester);

      final again = tester.getRect(find.text('Replay'));
      final list = tester.getRect(find.byType(ListView));
      expect(again.top, greaterThan(list.bottom));
    });

    testWidgets(
      'rebuilds the winner and the throw log from the stored throws',
      (tester) async {
        await pumpDetail(tester);

        expect(find.text('🎯 Ada wins!'), findsOneWidget);
        expect(find.text('All Throws'), findsOneWidget);
        expect(
          find.text('101'),
          findsWidgets,
          reason: 'the checkout visit belongs in the log',
        );
      },
    );

    testWidgets('says so when a game carries no throws at all', (tester) async {
      await pumpDetail(tester, game: empty);

      expect(find.text('No throw data available.'), findsOneWidget);
    });
  });

  group('the X01 history detail of a team game', () {
    useInMemoryDatabase();

    late List<Player> players;
    late Game stored;

    setUp(() async {
      final provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe', 'Kim', 'Rio']);
      await provider.startGame(
        Game(
          startScore: 101,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 4, 20, 15),
          startingOrder: StartingOrder.fixed,
          teams: [
            TeamConfig(
              name: 'Reds',
              playerIds: [players[0].id!, players[2].id!],
            ),
            TeamConfig(
              name: 'Blues',
              playerIds: [players[1].id!, players[3].id!],
            ),
          ],
        ),
        players,
      );
      // Ada throws for the Reds and takes 101 out in one visit.
      await provider.tapField(20, 3);
      await provider.tapField(9, 1);
      await provider.tapField(16, 2);

      final games = await DbHelper.instance.getGames();
      stored = games.firstWhere((g) => g.id == provider.game!.id);
    });

    testWidgets('announces the team, not the member who hit the double', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(HistoryGameSummaryScreen(game: stored, players: players)),
      );
      await pumpUntilLoaded(tester);

      expect(find.text('🎯 Reds wins!'), findsOneWidget);
      expect(
        find.text('🎯 Ada wins!'),
        findsNothing,
        reason: 'the side won the game, not one of its members',
      );
    });
  });

  group('the X01 history detail of a placement game', () {
    useInMemoryDatabase();

    late List<Player> players;
    late Game stored;

    setUp(() async {
      final provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe', 'Kim']);
      await provider.startGame(
        Game(
          startScore: 101,
          legs: 1,
          sets: 1,
          placementMode: true,
          createdAt: DateTime(2026, 4, 3, 20, 15),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
      // Ada and Zoe each take 101 out in one visit. The leg ends the moment the
      // second-to-last checks out, so Kim is third without throwing a dart.
      for (var i = 0; i < 2; i++) {
        await provider.tapField(20, 3);
        await provider.tapField(9, 1);
        await provider.tapField(16, 2);
      }

      final games = await DbHelper.instance.getGames();
      stored = games.firstWhere((g) => g.id == provider.game!.id);
    });

    testWidgets('ranks the player who never threw and scores all three '
        'against the full line-up', (tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(HistoryGameSummaryScreen(game: stored, players: players)),
      );
      await pumpUntilLoaded(tester);

      // Zoe threw the last checkout of the game, but a placement game is won
      // on points, and those are Ada's.
      expect(find.text('🎯 Ada wins!'), findsOneWidget);
      expect(
        find.text('Kim'),
        findsWidgets,
        reason: 'a participant without a dart is still one of them',
      );
      // Three participants, so a leg is worth 4 points to the winner, 2 to the
      // second and 1 to the third. Counting the participants off the throws
      // would take one point off each of them.
      expect(find.text('Points: 4'), findsOneWidget, reason: 'Ada');
      expect(find.text('Points: 2'), findsOneWidget, reason: 'Zoe');
      expect(find.text('Points: 1'), findsOneWidget, reason: 'Kim');
    });
  });
}
