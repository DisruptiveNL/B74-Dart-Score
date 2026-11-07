import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/services/competition_single_bull_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Seeds a valid Bo5 deciding-leg position: home and away each won two legs.
/// The final visit in each leg finishes from 141 after two 180 visits.
Future<({Game game, List<Player> players, int gameId})> seedDecider({
  required bool bullDecidingLeg,
}) async {
  final helper = DbHelper.instance;
  final players = <Player>[];
  for (final name in ['Home', 'Away']) {
    final id = await helper.insertPlayer(Player(name: name));
    players.add(Player(id: id, name: name));
  }
  final matchId = 'regression-${bullDecidingLeg ? 'bull' : 'alternate'}';
  final database = await helper.db;
  await database.insert('competition_inbox', {
    'match_id': matchId,
    'payload': jsonEncode({
      'x01Rules': {'bullDecidingLeg': bullDecidingLeg},
    }),
    'received_at': 1,
  });
  final game = Game(
    startScore: 501,
    legs: 3, // first to 3 = Best of 5
    sets: 1,
    createdAt: DateTime.now(),
    startingOrder: StartingOrder.fixed,
  );
  final gameId = await helper.insertGame(
    game,
    players.map((p) => p.id!).toList(),
    competitionMatchId: matchId,
    competitionSlot: 1,
    starterExternalId: 'home',
  );
  for (var leg = 1; leg <= 4; leg++) {
    final winner = players[(leg - 1) % 2];
    var remaining = 501;
    for (final score in [180, 180, 141]) {
      await helper.insertThrow(DartThrow(
        gameId: gameId,
        playerId: winner.id!,
        score: score,
        dartsUsed: 3,
        leg: leg,
        set: 1,
        remainingBefore: remaining,
        thrownAt: DateTime(2026, 11, 6, 20, leg),
      ));
      remaining -= score;
    }
  }
  return (game: Game(
    id: gameId,
    startScore: 501,
    legs: 3,
    sets: 1,
    createdAt: game.createdAt,
    startingOrder: StartingOrder.fixed,
  ), players: players, gameId: gameId);
}

void main() {
  group('C1B11 Singles deciding-leg bull integration', () {
    useInMemoryDatabase();

    test('blocks score entry until the winner is selected', () async {
      final setup = await seedDecider(bullDecidingLeg: true);
      final provider = GameProvider();
      await provider.resumeGame(setup.game, setup.players);
      expect(provider.currentLeg, 5);
      expect(provider.singleDecidingBullPending, isTrue);
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 0);
      await expectLater(
        provider.confirmSingleDecidingBull(999999),
        throwsStateError,
      );
      await provider.confirmSingleDecidingBull(setup.players.last.id!);
      expect(provider.singleDecidingBullPending, isFalse);
      expect(provider.singleStarterPending, isTrue);
      expect(provider.currentPlayerIndex, 1);
      expect(await CompetitionSingleBullStore().winner(
        gameId: setup.gameId, leg: 5), setup.players.last.id);
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 0,
          reason: 'Bullwinnaar moet starter nog expliciet bevestigen');
      await expectLater(
        provider.confirmSingleStarter(setup.players.first.id!),
        throwsStateError,
      );
      await provider.confirmSingleStarter(setup.players.last.id!);
      expect(provider.singleStarterPending, isFalse);
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 1);
      provider.dispose();
    });

    test('restores the recorded winner after a provider restart', () async {
      final setup = await seedDecider(bullDecidingLeg: true);
      final first = GameProvider();
      await first.resumeGame(setup.game, setup.players);
      await first.confirmSingleDecidingBull(setup.players.last.id!);
      await first.confirmSingleStarter(setup.players.last.id!);
      first.dispose();

      final resumed = GameProvider();
      await resumed.resumeGame(setup.game, setup.players);
      expect(resumed.singleDecidingBullPending, isFalse);
      expect(resumed.currentPlayerIndex, 1);
      await expectLater(
        resumed.confirmSingleDecidingBull(setup.players.first.id!),
        throwsStateError,
      );
      resumed.dispose();
    });

    test('restart mid-decider keeps the next thrower, not the bull winner', () async {
      final setup = await seedDecider(bullDecidingLeg: true);
      final first = GameProvider();
      await first.resumeGame(setup.game, setup.players);
      await first.confirmSingleDecidingBull(setup.players.last.id!);
      await first.confirmSingleStarter(setup.players.last.id!);
      first.dispose();

      final helper = DbHelper.instance;
      await helper.insertThrow(DartThrow(
        gameId: setup.gameId,
        playerId: setup.players.last.id!,
        score: 60,
        dartsUsed: 3,
        leg: 5,
        set: 1,
        remainingBefore: 501,
        thrownAt: DateTime(2026, 11, 6, 21, 5),
      ));

      final afterOneVisit = GameProvider();
      await afterOneVisit.resumeGame(setup.game, setup.players);
      expect(afterOneVisit.singleDecidingBullPending, isFalse);
      expect(afterOneVisit.currentLeg, 5);
      expect(afterOneVisit.currentPlayerIndex, 0,
          reason: 'After the bull winner throws, the opponent is next');
      afterOneVisit.dispose();

      await helper.insertThrow(DartThrow(
        gameId: setup.gameId,
        playerId: setup.players.first.id!,
        score: 45,
        dartsUsed: 3,
        leg: 5,
        set: 1,
        remainingBefore: 501,
        thrownAt: DateTime(2026, 11, 6, 21, 6),
      ));
      final afterTwoVisits = GameProvider();
      await afterTwoVisits.resumeGame(setup.game, setup.players);
      expect(afterTwoVisits.singleDecidingBullPending, isFalse);
      expect(afterTwoVisits.currentPlayerIndex, 1,
          reason: 'After both have thrown, the bull winner throws again');
      expect(afterTwoVisits.playerStates[1].remaining, 441);
      expect(afterTwoVisits.playerStates[0].remaining, 456);
      afterTwoVisits.dispose();
    });

    test('without mandatory bull the deciding leg requires explicit starter confirmation', () async {
      final setup = await seedDecider(bullDecidingLeg: false);
      final provider = GameProvider();
      await provider.resumeGame(setup.game, setup.players);
      expect(provider.currentLeg, 5);
      expect(provider.singleDecidingBullPending, isFalse);
      expect(provider.currentPlayerIndex, 0);
      expect(await CompetitionSingleBullStore().winner(
        gameId: setup.gameId, leg: 5), isNull);
      expect(provider.singleStarterPending, isTrue);
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 0);
      await provider.confirmSingleStarter(setup.players.last.id!);
      expect(provider.singleStarterPending, isFalse);
      expect(provider.currentPlayerIndex, 1,
          reason: 'Handmatige afwijking van voorgestelde starter is toegestaan');
      expect(await CompetitionSingleBullStore().starter(
        gameId: setup.gameId, leg: 5), setup.players.last.id);
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 1);
      provider.dispose();

      final resumed = GameProvider();
      await resumed.resumeGame(setup.game, setup.players);
      expect(resumed.singleStarterPending, isFalse);
      expect(resumed.currentPlayerIndex, 1);
      resumed.dispose();
    });
  });
}
