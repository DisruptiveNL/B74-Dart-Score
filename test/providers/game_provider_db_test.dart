import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Throws a full visit of three darts, or fewer if the visit ends early.
Future<void> _visit(
  GameProvider p,
  List<(int field, int modifier)> darts,
) async {
  for (final d in darts) {
    await p.tapField(d.$1, d.$2);
  }
}

/// Three singles of 20, a plain 60 that ends the visit.
Future<void> _sixty(GameProvider p) =>
    _visit(p, const [(20, 1), (20, 1), (20, 1)]);

/// Three misses: hands the turn on without moving the thrower's remaining.
Future<void> _missedVisit(GameProvider p) =>
    _visit(p, const [(0, 1), (0, 1), (0, 1)]);

void main() {
  group('GameProvider against a real database', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['A', 'B']);
    });

    Game game({
      int startScore = 501,
      int legs = 3,
      int sets = 1,
      CheckoutMode checkoutMode = CheckoutMode.doubleOut,
      bool placementMode = false,
      StartingOrder startingOrder = StartingOrder.random,
      List<TeamConfig>? teams,
    }) => Game(
      startScore: startScore,
      checkoutMode: checkoutMode,
      legs: legs,
      sets: sets,
      createdAt: DateTime.now(),
      placementMode: placementMode,
      startingOrder: startingOrder,
      teams: teams,
    );

    test('records a visit and passes the turn on', () async {
      await provider.startGame(game(), players);

      await _sixty(provider);

      expect(provider.playerStates[0].remaining, 441);
      expect(provider.currentPlayerIndex, 1);
    });

    test('a bust leaves the score untouched and ends the visit', () async {
      await provider.startGame(game(startScore: 101), players);

      // 60 + 60 overshoots 101, so the whole visit scores nothing.
      await _visit(provider, const [(20, 3), (20, 3)]);

      expect(provider.playerStates[0].remaining, 101);
      expect(provider.playerStates[0].throws.single.bust, isTrue);
      expect(provider.currentPlayerIndex, 1);
    });

    test('counts a leg finished in the minimum darts as perfect', () async {
      await provider.startGame(game(startScore: 101, legs: 2), players);

      // T17 plus Bull double is 101 in two darts, the minimum for 101.
      await _visit(provider, const [(17, 3), (25, 2)]);

      expect(provider.playerStates[0].legsWon, 1);
      expect(
        provider.playerStates[0].perfectLegs,
        1,
        reason: 'the checkout visit must not be counted twice',
      );
    });

    test('does not call an ordinary leg perfect', () async {
      await provider.startGame(game(startScore: 101, legs: 2), players);

      await _visit(provider, const [(1, 1), (1, 1), (1, 1)]); // A: 3, leaves 98
      await _sixty(provider); // B
      await _visit(provider, const [
        (20, 3),
        (19, 2),
      ]); // A: 60 + 38 = 98 left 0

      expect(provider.playerStates[0].legsWon, 1);
      expect(
        provider.playerStates[0].perfectLegs,
        0,
        reason: 'five darts is three more than 101 needs',
      );
    });

    group('undo and redo', () {
      test('takes back a single dart of the running visit', () async {
        await provider.startGame(game(), players);

        await provider.tapField(20, 3);
        await provider.tapField(20, 1);
        expect(provider.dartsInVisit, 2);

        await provider.undoLastDart();

        expect(provider.dartsInVisit, 1);
        expect(provider.currentVisitDarts.single.score, 60);
        expect(provider.canRedoDart, isTrue);
      });

      test('reopens a committed visit and returns the turn', () async {
        await provider.startGame(game(), players);

        await _sixty(provider);
        expect(provider.currentPlayerIndex, 1);

        await provider.undoLastDart();

        expect(
          provider.currentPlayerIndex,
          0,
          reason: 'the turn goes back to whoever threw the undone dart',
        );
        expect(provider.playerStates[0].remaining, 501);
        // The two darts before the undone one are prefilled again.
        expect(provider.dartsInVisit, 2);
      });

      test('redo restores the undone dart', () async {
        await provider.startGame(game(), players);

        await provider.tapField(20, 3);
        await provider.undoLastDart();
        await provider.redoLastDart();

        expect(provider.dartsInVisit, 1);
        expect(provider.currentVisitDarts.single.score, 60);
        expect(provider.canRedoDart, isFalse);
      });

      test('a new dart drops the redo stack', () async {
        await provider.startGame(game(), players);

        await provider.tapField(20, 3);
        await provider.undoLastDart();
        expect(provider.canRedoDart, isTrue);

        await provider.tapField(19, 3);

        expect(provider.canRedoDart, isFalse);
      });

      test(
        'returns the turn inside a leg that another player opened',
        () async {
          // Leg 2 opens with B, so from B's second visit on the visit counts of
          // the leg are level and no longer say whose turn it is.
          final three = [
            ...players,
            ...await insertPlayers(['C']),
          ];
          await provider.startGame(game(startScore: 101, legs: 3), three);

          await _visit(provider, const [(17, 3), (25, 2)]); // A wins leg 1
          expect(provider.currentLeg, 2);
          expect(provider.currentPlayerState.player.name, 'B');

          await _missedVisit(provider); // B
          await _missedVisit(provider); // C
          await _missedVisit(provider); // A
          await _missedVisit(provider); // B again
          expect(provider.currentPlayerState.player.name, 'C');

          await provider.undoLastDart();

          expect(provider.currentLeg, 2);
          expect(
            provider.currentPlayerState.player.name,
            'B',
            reason: 'the turn goes back to whoever threw the undone dart',
          );
        },
      );

      test('undoing the winning dart reopens the game', () async {
        await provider.startGame(game(startScore: 101, legs: 1), players);

        await _visit(provider, const [(17, 3), (25, 2)]);
        expect(provider.gameOver, isTrue);
        final gameId = provider.game!.id!;
        expect(
          await storedX01FinishedAt(gameId),
          isNotNull,
          reason: 'checking out has to close the stored game',
        );

        await provider.undoLastDart();

        expect(provider.gameOver, isFalse);
        expect(provider.winnerId, isNull);
        expect(provider.playerStates[0].legsWon, 0);
        expect(
          await storedX01FinishedAt(gameId),
          isNull,
          reason: 'history has to list the game as open again',
        );
      });

      test('takes the game back into the leg that was just won', () async {
        await provider.startGame(game(startScore: 101, legs: 3), players);

        await _visit(provider, const [(17, 3), (25, 2)]); // A wins leg 1
        expect(provider.currentLeg, 2);
        expect(provider.playerStates[0].legsWon, 1);

        await provider.undoLastDart();

        expect(provider.currentLeg, 1, reason: 'the won leg opens again');
        expect(provider.playerStates[0].legsWon, 0);
        expect(provider.playerStates[0].perfectLegs, 0);
        expect(provider.playerStates[0].remaining, 101);
        expect(provider.currentPlayerIndex, 0);
        expect(
          provider.dartsInVisit,
          1,
          reason: 'the darts before the undone one are prefilled again',
        );
        expect(provider.liveRunningRemaining, 50);

        await provider.redoLastDart();

        expect(provider.currentLeg, 2);
        expect(provider.playerStates[0].legsWon, 1);
        expect(provider.playerStates[0].perfectLegs, 1);
      });

      test('stays in the new leg when its first visit is taken back', () async {
        await provider.startGame(game(startScore: 101, legs: 3), players);

        await _visit(provider, const [(17, 3), (25, 2)]); // A wins leg 1
        await _sixty(provider); // B opens leg 2

        await provider.undoLastDart();

        expect(provider.currentLeg, 2, reason: 'leg 1 stays won and closed');
        expect(provider.playerStates[0].legsWon, 1);
        expect(provider.playerStates[0].remaining, 101);
        expect(provider.playerStates[1].remaining, 101);
        expect(provider.currentPlayerIndex, 1);
        expect(provider.dartsInVisit, 2);
      });

      test('takes the game back into the set that was just won', () async {
        await provider.startGame(
          game(startScore: 101, legs: 1, sets: 3),
          players,
        );

        await _visit(provider, const [(17, 3), (25, 2)]); // A wins set 1
        expect(provider.currentSet, 2);
        expect(provider.currentLeg, 1);
        expect(provider.playerStates[0].setsWon, 1);

        await provider.undoLastDart();

        expect(provider.currentSet, 1);
        expect(provider.currentLeg, 1);
        expect(provider.playerStates[0].setsWon, 0);
        expect(provider.playerStates[0].remaining, 101);
      });
    });

    test('a leg won but not yet opened resumes on the next leg', () async {
      await provider.startGame(game(startScore: 101, legs: 3), players);

      await _visit(provider, const [(17, 3), (25, 2)]); // A wins leg 1
      final stored = provider.game!;

      final fresh = GameProvider();
      await fresh.resumeGame(stored, players);

      expect(
        fresh.currentLeg,
        2,
        reason: 'the leg the checkout decided is over',
      );
      expect(fresh.playerStates[0].legsWon, 1);
      expect(
        fresh.playerStates[0].perfectLegs,
        1,
        reason: '101 in two darts is the minimum the score allows',
      );
      expect(fresh.playerStates[0].remaining, 101);
      expect(fresh.playerStates[1].remaining, 101);
      expect(
        fresh.currentPlayerIndex,
        1,
        reason: 'the leg opens with the slot after the winner',
      );
    });

    test('undo in a later set keeps the leg numbering of that set', () async {
      // Two legs per set: A wins set 1 by taking legs 1 and 2, then set 2
      // starts again at leg 1. The old code took the highest leg and the
      // highest set independently and landed on leg 2 of set 2, a leg without
      // a single throw.
      await provider.startGame(
        game(startScore: 101, legs: 2, sets: 2),
        players,
      );

      Future<void> checkoutA() async {
        await _visit(provider, const [(17, 3), (25, 2)]);
      }

      await checkoutA(); // set 1, leg 1
      await _sixty(provider); // B
      await checkoutA(); // set 1, leg 2, set 1 won
      expect(provider.currentSet, 2);
      expect(provider.currentLeg, 1);

      await _sixty(provider); // B opens set 2
      await _sixty(provider); // A scores 60
      expect(provider.playerStates[0].remaining, 41);

      await provider.undoLastDart();

      expect(provider.currentSet, 2);
      expect(provider.currentLeg, 1, reason: 'legs restart at 1 in every set');
      expect(
        provider.playerStates[1].remaining,
        41,
        reason: 'the running leg of set 2 keeps the scores already thrown',
      );
      // A's committed visit was taken back, the darts before the removed one
      // are prefilled again.
      expect(provider.playerStates[0].remaining, 101);
      expect(provider.dartsInVisit, 2);
      expect(provider.liveRunningRemaining, 61);
      expect(provider.playerStates[0].setsWon, 1);
    });

    test('resuming a stored game rebuilds the board', () async {
      await provider.startGame(game(startScore: 301), players);
      await _sixty(provider);
      await _sixty(provider);
      final stored = provider.game!;

      final fresh = GameProvider();
      await fresh.resumeGame(stored, players);

      expect(fresh.playerStates[0].remaining, 241);
      expect(fresh.playerStates[1].remaining, 241);
      expect(fresh.currentPlayerIndex, 0);
      expect(fresh.currentLeg, 1);
    });

    group('team game', () {
      late List<Player> four;

      setUp(() async {
        four = await insertPlayers(['C', 'D']);
      });

      test('rotates through the members of a team', () async {
        final all = [...players, ...four];
        final teams = [
          TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
          TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
        ];
        await provider.startGame(game(teams: teams), all);

        expect(provider.playerStates, hasLength(2));
        expect(provider.currentPlayerState.player.name, 'A');

        await _sixty(provider); // Team 1, member A
        expect(provider.currentPlayerState.player.name, 'B');

        await _sixty(provider); // Team 2, member B
        expect(
          provider.currentPlayerState.player.name,
          'C',
          reason: 'team 1 hands over to its second member',
        );
      });

      test('undo keeps the rotation a new leg carried over', () async {
        // Team 1 throws three visits in leg 1, so leg 2 opens with its second
        // member. Counting the visits of the running leg would hand the turn
        // to the first member from there on.
        final all = [...players, ...four];
        final teams = [
          TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
          TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
        ];
        await provider.startGame(
          game(startScore: 101, legs: 3, teams: teams),
          all,
        );

        await _sixty(provider); // Team 1, A
        await _sixty(provider); // Team 2, B
        await _missedVisit(provider); // Team 1, C
        await _missedVisit(provider); // Team 2, D
        await _missedVisit(provider); // Team 1, A
        await _visit(provider, const [(1, 1), (20, 2)]); // Team 2, B wins 41

        expect(provider.currentLeg, 2);
        expect(
          provider.currentPlayerState.player.name,
          'C',
          reason: 'team 1 carries its rotation into the new leg',
        );

        await _sixty(provider); // Team 1, C
        await _sixty(provider); // Team 2, D
        await _missedVisit(provider); // Team 1, A
        expect(provider.currentPlayerState.player.name, 'B');

        await provider.undoLastDart();

        expect(provider.currentLeg, 2);
        expect(provider.currentPlayerIndex, 0);
        expect(
          provider.currentPlayerState.player.name,
          'A',
          reason: 'the turn goes back to the member who threw',
        );
      });

      test('a resume restores the rotation of every team', () async {
        final all = [...players, ...four];
        final teams = [
          TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
          TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
        ];
        await provider.startGame(game(teams: teams), all);

        await _sixty(provider); // Team 1, A
        await _sixty(provider); // Team 2, B
        await _sixty(provider); // Team 1, C
        final stored = provider.game!;

        final fresh = GameProvider();
        await fresh.resumeGame(stored, all);

        expect(fresh.currentPlayerIndex, 1);
        expect(fresh.currentPlayerState.player.name, 'D');
        expect(
          fresh.playerStates[0].player.name,
          'A',
          reason: 'the idle team keeps the member who steps up next',
        );
      });

      test('shares one score across the team', () async {
        final all = [...players, ...four];
        final teams = [
          TeamConfig(name: 'Team 1', playerIds: [all[0].id!, all[2].id!]),
          TeamConfig(name: 'Team 2', playerIds: [all[1].id!, all[3].id!]),
        ];
        await provider.startGame(game(teams: teams), all);

        await _sixty(provider); // A
        await _sixty(provider); // B
        await _sixty(provider); // C, same slot as A

        expect(provider.playerStates[0].remaining, 381);
      });
    });

    group('placement mode', () {
      late List<Player> three;

      setUp(() async {
        three = [
          ...players,
          ...await insertPlayers(['C']),
        ];
      });

      test('ends the leg on the second to last checkout', () async {
        await provider.startGame(
          game(startScore: 101, legs: 2, placementMode: true),
          three,
        );

        // A finishes first, then B. C is left over and takes last place
        // without throwing its checkout.
        await _visit(provider, const [(17, 3), (25, 2)]); // A checks out
        expect(provider.playerStates[0].legPlacement, 1);
        expect(provider.playerStates[1].legPlacement, isNull);
        expect(
          provider.currentPlayerIndex,
          1,
          reason: 'a slot that has finished the leg is skipped',
        );

        await _sixty(provider); // B, 41 left
        await _sixty(provider); // C, 41 left
        await _visit(provider, const [(1, 1), (20, 2)]); // B checks out 41

        // The leg is over, so the per-leg positions are cleared for the next
        // one. The cumulative sum is what carries them.
        expect(provider.currentLeg, 2);
        expect(provider.playerStates[0].legsWon, 1);
        expect(provider.playerStates.map((s) => s.placementSum), [
          1,
          2,
          3,
        ], reason: 'the last slot is placed without checking out');
        // Three slots, so a leg pays 4 to the winner, 2 to the second and 1 to
        // the third. The points decide the final ranking, so the live game has
        // to keep them rather than work them out again at the end.
        expect(provider.playerStates.map((s) => s.placementPoints), [4, 2, 1]);
      });

      test('carries the placements through a resume', () async {
        await provider.startGame(
          game(startScore: 101, legs: 2, placementMode: true),
          three,
        );

        await _visit(provider, const [(17, 3), (25, 2)]);
        await _sixty(provider);
        await _sixty(provider);
        await _visit(provider, const [(1, 1), (20, 2)]);
        final stored = provider.game!;

        final fresh = GameProvider();
        await fresh.resumeGame(stored, three);

        expect(fresh.currentLeg, 2);
        expect(fresh.playerStates[0].legsWon, 1);
        expect(fresh.playerStates[0].placementSum, 1);
        expect(fresh.playerStates[1].placementSum, 2);
        expect(
          fresh.playerStates[2].placementSum,
          3,
          reason: 'the last place counts toward the tie breaker',
        );
        expect(fresh.playerStates.map((s) => s.placementPoints), [
          4,
          2,
          1,
        ], reason: 'the points a resume rebuilds are the points it left with');
      });
    });

    test('a fixed starting order survives a rematch', () async {
      await provider.startGame(
        game(startScore: 101, legs: 1, startingOrder: StartingOrder.fixed),
        players,
      );
      await _visit(provider, const [(17, 3), (25, 2)]);
      final finished = provider.game!;

      final order = provider.playerStates.expand((s) => s.players).toList();
      await provider.startRematch(finished, order);

      expect(provider.playerStates.map((s) => s.displayName), ['A', 'B']);
      expect(provider.game!.startingOrder, StartingOrder.fixed);
    });

    test(
      'a visit only counts as a checkout attempt once a dart can finish',
      () async {
        // The leg from the bug report, played out dart by dart.
        await provider.startGame(
          game(startScore: 156, legs: 1, startingOrder: StartingOrder.fixed),
          players,
        );

        // 156 is shown as T20, T20, D18. The plain 20 takes the finish out of
        // reach for the rest of the visit, and 136 and 76 are no closer.
        await _visit(provider, const [(20, 1), (20, 3), (17, 3)]);
        await _missedVisit(provider);
        // 25 left: the S9 leaves 16 with two darts still in hand.
        await _visit(provider, const [(9, 1), (0, 1), (0, 1)]);
        await _missedVisit(provider);
        // 16 left, an attempt before the first dart flies. The S3 busts from 2
        // and ends the visit early.
        await _visit(provider, const [(14, 1), (3, 1)]);
        await _missedVisit(provider);
        // 16 left again, checked out on D8.
        await _visit(provider, const [(8, 2)]);

        expect(provider.gameOver, isTrue);

        final visits = provider.playerStates[0].throws;
        expect(visits.map((t) => t.checkoutAttempt), [
          false,
          true,
          true,
          true,
        ], reason: 'the 156 visit was never one dart from the finish');
        expect(
          visits.map((t) => t.checkoutDarts),
          [0, 2, 2, 1],
          reason:
              'the two misses from 16 and the S3 from 2 all flew at a '
              'finish, so the attempts hold more darts than one each',
        );
      },
    );
  });
}
