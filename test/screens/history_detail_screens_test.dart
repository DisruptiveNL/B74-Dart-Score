import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_history_summary_screen.dart';
import 'package:dartscore_app/screens/cricket_history_summary_screen.dart';
import 'package:dartscore_app/screens/history_game_summary_screen.dart';
import 'package:dartscore_app/screens/shanghai_history_summary_screen.dart';
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

  // ── Cricket ─────────────────────────────────────────────────────────────────

  group('the Cricket history detail', () {
    useInMemoryDatabase();

    late CricketProvider provider;
    late List<Player> players;
    late CricketGame stored;

    setUp(() async {
      provider = CricketProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        CricketGame(
          variant: CricketVariant.normal,
          scoringMode: CricketScoringMode.standard,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1, 20, 15),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada closes every field with a triple while Zoe throws her visits away.
      for (final field in cricketFields) {
        await provider.recordDart(field, 3);
        if (provider.gameOver) break;
        if (provider.dartsInVisit == 0) {
          for (var i = 0; i < 3; i++) {
            await provider.recordDart(0, 0);
          }
        }
      }

      // The finish time only exists in the database: the provider writes it
      // without updating its own copy, and the winner is read off it here.
      stored = (await DbHelper.instance.getCricketGames()).firstWhere(
        (g) => g.id == provider.game!.id,
      );
    });

    Future<void> pumpDetail(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(CricketHistorySummaryScreen(game: stored, players: players)),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('reconstructs the winner and the closed fields', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
      expect(find.text('7/7 Fields closed'), findsOneWidget);
      expect(find.text('0/7 Fields closed'), findsOneWidget);
    });

    testWidgets('fills the pane it is embedded in', (tester) async {
      final width = await paneCardWidth(
        tester,
        CricketHistorySummaryScreen(
          game: stored,
          players: players,
          embedded: true,
        ),
      );
      expect(width, greaterThan(500));
    });

    testWidgets('rebuilds the marks grid down to the Bull', (tester) async {
      await pumpDetail(tester);

      expect(find.text('Marks'), findsOneWidget);
      expect(find.text('Bull'), findsOneWidget);
      expect(find.text('Cricket'), findsWidgets);
      expect(find.text('Standard (S/D/T)'), findsWidgets);
    });
  });

  // ── Shanghai ────────────────────────────────────────────────────────────────

  group('the Shanghai history detail', () {
    useInMemoryDatabase();

    late ShanghaiProvider provider;
    late List<Player> players;
    late ShanghaiGame stored;

    setUp(() async {
      provider = ShanghaiProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        ShanghaiGame(
          variant: ShanghaiVariant.classic,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1, 20, 15),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada scores a triple with every dart, Zoe misses every one.
      while (!provider.gameOver) {
        await provider.recordDart(provider.currentPlayerIndex == 0 ? 3 : 0);
      }

      stored = (await DbHelper.instance.getShanghaiGames()).firstWhere(
        (g) => g.id == provider.game!.id,
      );
    });

    Future<void> pumpDetail(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(ShanghaiHistorySummaryScreen(game: stored, players: players)),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('fills the pane it is embedded in', (tester) async {
      final width = await paneCardWidth(
        tester,
        ShanghaiHistorySummaryScreen(
          game: stored,
          players: players,
          embedded: true,
        ),
      );
      expect(width, greaterThan(500));
    });

    testWidgets('replays the game to the same result', (tester) async {
      final score = provider.playerStates[0].score;

      await pumpDetail(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
      expect(
        find.text('$score'),
        findsOneWidget,
        reason: 'the replay has to reach the score the game ended on',
      );
      expect(find.text('Classic (1-9)'), findsWidgets);
    });
  });

  // ── Around the Clock ────────────────────────────────────────────────────────

  group('the Around the Clock history detail', () {
    useInMemoryDatabase();

    late AroundTheClockProvider provider;
    late List<Player> players;
    late AroundTheClockGame stored;

    setUp(() async {
      provider = AroundTheClockProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        AroundTheClockGame(
          variant: AroundTheClockVariant.basic,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1, 20, 15),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada hits her target with every dart, Zoe never hits hers.
      while (!provider.gameOver) {
        if (provider.currentPlayerIndex == 0) {
          await provider.recordDart(provider.activeTarget, 1);
        } else {
          await provider.recordDart(0, 0);
        }
      }

      stored = (await DbHelper.instance.getAroundTheClockGames()).firstWhere(
        (g) => g.id == provider.game!.id,
      );
    });

    Future<void> pumpDetail(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(
          AroundTheClockHistorySummaryScreen(game: stored, players: players),
        ),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('fills the pane it is embedded in', (tester) async {
      final width = await paneCardWidth(
        tester,
        AroundTheClockHistorySummaryScreen(
          game: stored,
          players: players,
          embedded: true,
        ),
      );
      expect(width, greaterThan(500));
    });

    testWidgets('replays how far each player got', (tester) async {
      final total = aroundTheClockOrder.length;

      await pumpDetail(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
      expect(find.text('$total/$total hit'), findsOneWidget);
      expect(find.text('0/$total hit'), findsOneWidget);
      expect(find.text('Around the Clock'), findsWidgets);
    });
  });
}
