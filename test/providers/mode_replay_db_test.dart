import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('ShanghaiProvider against a real database', () {
    useInMemoryDatabase();

    late ShanghaiProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = ShanghaiProvider();
      players = await insertPlayers(['A', 'B']);
    });

    ShanghaiGame game({ShanghaiVariant variant = ShanghaiVariant.classic}) =>
        ShanghaiGame(
          variant: variant,
          legs: 1,
          sets: 1,
          createdAt: DateTime.now(),
          playerIds: players.map((p) => p.id!).toList(),
        );

    /// Throws [count] darts with the given multiplier for whoever is on turn.
    Future<void> throwDarts(int multiplier, {int count = 1}) async {
      for (var i = 0; i < count; i++) {
        await provider.recordDart(multiplier);
      }
    }

    test('scores multiplier times the round target', () async {
      await provider.startGame(game(), players);

      // Round 1, target 1: single, double, triple is 1 + 2 + 3.
      await provider.recordDart(1);
      await provider.recordDart(2);
      await provider.recordDart(3);

      expect(provider.playerStates[0].score, 6);
      expect(provider.currentPlayerIndex, 1);
    });

    test('advances the round after both players have thrown', () async {
      await provider.startGame(game(), players);

      await throwDarts(1, count: 3); // A, round 1
      expect(provider.currentRound, 1);
      await throwDarts(1, count: 3); // B, round 1

      expect(provider.currentRound, 2);
      expect(provider.activeTarget, 2);
    });

    test('a miss scores nothing but uses a dart', () async {
      await provider.startGame(game(), players);

      await provider.recordDart(0);

      expect(provider.playerStates[0].score, 0);
      expect(provider.dartsInVisit, 1);
    });

    test('undo replays the board from the remaining darts', () async {
      await provider.startGame(game(), players);

      await provider.recordDart(3); // target 1, three points
      await provider.recordDart(2); // two points
      expect(provider.playerStates[0].score, 5);

      await provider.undoLastDart();

      expect(provider.playerStates[0].score, 3);
      expect(provider.dartsInVisit, 1);
      expect(provider.currentPlayerIndex, 0);
    });

    test('undo reaches back across a finished visit', () async {
      await provider.startGame(game(), players);

      await throwDarts(1, count: 3); // A finishes its visit
      expect(provider.currentPlayerIndex, 1);

      await provider.undoLastDart();

      expect(
        provider.currentPlayerIndex,
        0,
        reason: 'the turn returns to whoever threw the undone dart',
      );
      expect(provider.playerStates[0].score, 2);
      expect(provider.dartsInVisit, 2);
    });

    test(
      'the sequential variant only advances on the current target',
      () async {
        await provider.startGame(
          game(variant: ShanghaiVariant.sequential),
          players,
        );

        expect(provider.activeTarget, 1);
        await provider.recordDart(1);
        expect(
          provider.activeTarget,
          2,
          reason: 'hitting the target moves on to the next number',
        );

        await provider.recordDart(0);
        expect(provider.activeTarget, 2, reason: 'a miss does not advance');
      },
    );

    test(
      'the winning dart closes the stored game, and undo reopens it',
      () async {
        await provider.startGame(game(), players);

        // A triples every dart, B misses every one, over all nine rounds.
        while (!provider.gameOver) {
          await provider.recordDart(provider.currentPlayerIndex == 0 ? 3 : 0);
        }
        final gameId = provider.game!.id!;
        expect(await storedShanghaiFinishedAt(gameId), isNotNull);

        await provider.undoLastDart();

        expect(provider.gameOver, isFalse);
        expect(provider.winnerId, isNull);
        expect(
          await storedShanghaiFinishedAt(gameId),
          isNull,
          reason: 'history has to list the game as open again',
        );
      },
    );

    test('resuming rebuilds scores and the turn', () async {
      await provider.startGame(game(), players);
      await throwDarts(2, count: 3); // A: three doubles of 1
      await throwDarts(1, count: 3); // B: three singles of 1

      final fresh = ShanghaiProvider();
      await fresh.resumeGame(provider.game!, players);

      expect(fresh.playerStates[0].score, 6);
      expect(fresh.playerStates[1].score, 3);
      expect(fresh.currentRound, 2);
      expect(fresh.currentPlayerIndex, 0);
    });

    test('a resume restores the rotation of every team', () async {
      final all = [
        ...players,
        ...await insertPlayers(['C', 'D']),
      ];
      final teams = [
        TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
        TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
      ];
      await provider.startGame(
        ShanghaiGame(
          variant: ShanghaiVariant.classic,
          legs: 1,
          sets: 1,
          createdAt: DateTime.now(),
          playerIds: all.map((p) => p.id!).toList(),
          teams: teams,
        ),
        all,
      );

      await throwDarts(1, count: 3); // Team 1, A
      await throwDarts(1, count: 3); // Team 2, B

      final fresh = ShanghaiProvider();
      await fresh.resumeGame(provider.game!, all);

      expect(fresh.currentPlayerIndex, 0);
      expect(fresh.currentPlayerState.player.name, 'C');
      expect(
        fresh.playerStates[1].player.name,
        'D',
        reason: 'the idle team keeps the member who steps up next',
      );
    });
  });

  group('AroundTheClockProvider against a real database', () {
    useInMemoryDatabase();

    late AroundTheClockProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = AroundTheClockProvider();
      players = await insertPlayers(['A', 'B']);
    });

    AroundTheClockGame game({
      AroundTheClockVariant variant = AroundTheClockVariant.basic,
    }) => AroundTheClockGame(
      variant: variant,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
    );

    test('hitting the target advances to the next number', () async {
      await provider.startGame(game(), players);

      expect(provider.activeTarget, aroundTheClockOrder.first);
      await provider.recordDart(aroundTheClockOrder.first, 1);

      expect(provider.activeTarget, aroundTheClockOrder[1]);
    });

    test('any other field leaves the target alone', () async {
      await provider.startGame(game(), players);

      await provider.recordDart(aroundTheClockOrder[5], 1);

      expect(provider.activeTarget, aroundTheClockOrder.first);
    });

    test('the full segments variant needs single, double and triple', () async {
      await provider.startGame(
        game(variant: AroundTheClockVariant.fullSegments),
        players,
      );
      final target = aroundTheClockOrder.first;

      await provider.recordDart(target, 1);
      expect(provider.activeTarget, target);
      await provider.recordDart(target, 2);
      expect(provider.activeTarget, target);
      await provider.recordDart(target, 3);

      // The third dart also ends the visit, so the turn is with B now. The
      // progress of the slot that threw is what tells us it advanced.
      expect(provider.playerStates[0].progress, 1);
      expect(provider.playerStates[0].currentTarget, aroundTheClockOrder[1]);
    });

    test('skip rules move further on a double or a triple', () async {
      await provider.startGame(
        game(variant: AroundTheClockVariant.skipRules),
        players,
      );

      await provider.recordDart(aroundTheClockOrder.first, 3);

      expect(
        provider.activeTarget,
        aroundTheClockOrder[3],
        reason: 'a triple advances three fields',
      );
    });

    test('undo replays the progress', () async {
      await provider.startGame(game(), players);

      await provider.recordDart(aroundTheClockOrder.first, 1);
      await provider.recordDart(aroundTheClockOrder[1], 1);
      expect(provider.activeTarget, aroundTheClockOrder[2]);

      await provider.undoLastDart();

      expect(provider.activeTarget, aroundTheClockOrder[1]);
      expect(provider.dartsInVisit, 1);
    });

    test('undoing the winning dart reopens the game', () async {
      await provider.startGame(game(), players);

      // A walks the whole board while B never hits its target.
      for (var i = 0; i < aroundTheClockOrder.length; i++) {
        await provider.recordDart(provider.activeTarget, 1);
        if (provider.gameOver) break;
        if (provider.dartsInVisit == 0) {
          // B wastes a full visit so the turn comes back to A.
          await provider.recordDart(0, 0);
          await provider.recordDart(0, 0);
          await provider.recordDart(0, 0);
        }
      }
      expect(provider.gameOver, isTrue);
      final gameId = provider.game!.id!;
      expect(
        await storedAroundTheClockFinishedAt(gameId),
        isNotNull,
        reason: 'winning has to close the stored game',
      );

      await provider.undoLastDart();

      expect(provider.gameOver, isFalse);
      expect(provider.winnerId, isNull);
      expect(
        await storedAroundTheClockFinishedAt(gameId),
        isNull,
        reason: 'history has to list the game as open again',
      );
    });

    test('resuming rebuilds the progress and the turn', () async {
      await provider.startGame(game(), players);
      await provider.recordDart(aroundTheClockOrder.first, 1);
      await provider.recordDart(0, 0);
      await provider.recordDart(0, 0); // A's visit is over

      final fresh = AroundTheClockProvider();
      await fresh.resumeGame(provider.game!, players);

      expect(fresh.playerStates[0].progress, 1);
      expect(fresh.currentPlayerIndex, 1);
    });

    test('a resume restores the rotation of every team', () async {
      final all = [
        ...players,
        ...await insertPlayers(['C', 'D']),
      ];
      final teams = [
        TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
        TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
      ];
      await provider.startGame(
        AroundTheClockGame(
          variant: AroundTheClockVariant.basic,
          legs: 1,
          sets: 1,
          createdAt: DateTime.now(),
          playerIds: all.map((p) => p.id!).toList(),
          teams: teams,
        ),
        all,
      );

      for (var i = 0; i < 6; i++) {
        await provider.recordDart(0, 0); // two visits of misses, A then B
      }

      final fresh = AroundTheClockProvider();
      await fresh.resumeGame(provider.game!, all);

      expect(fresh.currentPlayerIndex, 0);
      expect(fresh.currentPlayerState.player.name, 'C');
      expect(
        fresh.playerStates[1].player.name,
        'D',
        reason: 'the idle team keeps the member who steps up next',
      );
    });
  });

  group('CricketProvider against a real database', () {
    useInMemoryDatabase();

    late CricketProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = CricketProvider();
      players = await insertPlayers(['A', 'B']);
    });

    CricketGame game() => CricketGame(
      variant: CricketVariant.normal,
      scoringMode: CricketScoringMode.standard,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
    );

    /// Closes every Cricket field for whoever is on turn, three marks at a
    /// time, handing the other slot a full visit of misses in between.
    Future<void> closeEverything() async {
      for (final field in cricketFields) {
        await provider.recordDart(field, 3);
        if (provider.gameOver) return;
        await provider.recordDart(0, 0);
        await provider.recordDart(0, 0);
        for (var i = 0; i < 3; i++) {
          await provider.recordDart(0, 0);
        }
      }
    }

    test(
      'a finished game resumed from history still names its winner',
      () async {
        // The history view replays through this provider rather than deriving
        // the winner itself, so a replay that forgets the win leaves that screen
        // with no winner at all.
        await provider.startGame(game(), players);
        await closeEverything();

        expect(provider.gameOver, isTrue, reason: 'A closed everything first');
        final winner = provider.winnerId;
        expect(winner, players.first.id);

        final fresh = CricketProvider();
        await fresh.resumeGame(provider.game!, players);

        expect(fresh.gameOver, isTrue);
        expect(fresh.winnerId, winner);
        expect(fresh.playerStates.first.isWonBy(fresh.winnerId), isTrue);
      },
    );

    test('an unfinished game resumed from history has no winner', () async {
      await provider.startGame(game(), players);
      await provider.recordDart(20, 3);

      final fresh = CricketProvider();
      await fresh.resumeGame(provider.game!, players);

      expect(fresh.gameOver, isFalse);
      expect(fresh.winnerId, isNull);
    });
  });
}
