import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/screens/player_stats_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('C1B11 admin deletion statistics regression', () {
    useInMemoryDatabase();

    test(
      'RETAIN preserves stats; REMOVE excludes only selected match',
      () async {
        final helper = DbHelper.instance;
        final db = await helper.db;

        final playerId = await db.insert('players', {'name': 'Speler A'});
        final player = (await helper.getPlayer(playerId))!;

        Future<int> addMatch(String matchId, int score) async {
          await db.insert('competition_inbox', {
            'match_id': matchId,
            'payload': jsonEncode({'division': 'Eredivisie'}),
            'received_at': 1,
          });

          final gameId = await helper.insertGame(
            Game(startScore: 501, createdAt: DateTime(2026, 11, 13)),
            [playerId],
            competitionMatchId: matchId,
            competitionSlot: 1,
            starterExternalId: 'player-a',
          );

          await helper.insertThrow(
            DartThrow(
              gameId: gameId,
              playerId: playerId,
              score: score,
              dartsUsed: 3,
              leg: 1,
              set: 1,
              remainingBefore: 501,
              thrownAt: DateTime(2026, 11, 13),
            ),
          );

          return gameId;
        }

        final retainGame = await addMatch('match-retain', 60);
        final removeGame = await addMatch('match-remove', 100);
        final untouchedGame = await addMatch('match-untouched', 140);

        final initial = await loadPlayerStats(player);
        expect(initial.totalDarts, 9);
        expect(initial.totalScored, 300);
        expect(initial.totalVisits, 3);

        await helper.stageAdminDeletionIntent(
          matchId: 'match-retain',
          revision: 1,
          scope: 'official',
          statisticsMode: 'retain',
          authorizationId: 'auth-retain',
        );
        expect(
          await helper.retainStagedAdminMatchForVerifiedCoordinator(
            matchId: 'match-retain',
            revision: 1,
            authorizationId: 'auth-retain',
          ),
          'retained',
        );

        final afterRetain = await loadPlayerStats(player);
        expect(afterRetain.totalDarts, initial.totalDarts);
        expect(afterRetain.totalScored, initial.totalScored);
        expect(afterRetain.totalVisits, initial.totalVisits);

        await helper.stageAdminDeletionIntent(
          matchId: 'match-remove',
          revision: 1,
          scope: 'official',
          statisticsMode: 'remove',
          authorizationId: 'auth-remove',
        );
        expect(
          await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
            matchId: 'match-remove',
            revision: 1,
            authorizationId: 'auth-remove',
          ),
          'purged',
        );

        final afterRemove = await loadPlayerStats(player);
        expect(afterRemove.totalDarts, 6);
        expect(afterRemove.totalScored, 200);
        expect(afterRemove.totalVisits, 2);

        expect(await helper.competitionGameId('match-retain', 1), retainGame);
        expect(await helper.competitionGameId('match-remove', 1), isNull);
        expect(
          await db.query('games', where: 'id = ?', whereArgs: [removeGame]),
          isEmpty,
        );
        expect(
          await helper.competitionGameId('match-untouched', 1),
          untouchedGame,
        );

        await helper.stageAdminDeletionIntent(
          matchId: 'match-retain',
          revision: 1,
          scope: 'official',
          statisticsMode: 'remove',
          authorizationId: 'auth-retain-to-remove',
        );
        expect(
          await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
            matchId: 'match-retain',
            revision: 1,
            authorizationId: 'auth-retain-to-remove',
          ),
          'purged',
        );

        final afterRetainToRemove = await loadPlayerStats(player);
        expect(afterRetainToRemove.totalDarts, 3);
        expect(afterRetainToRemove.totalScored, 140);
        expect(afterRetainToRemove.totalVisits, 1);

        expect(await helper.competitionGameId('match-retain', 1), isNull);
        expect(
          await helper.competitionGameId('match-untouched', 1),
          untouchedGame,
        );

        final remainingThrows = await helper.getThrowsForPlayer(playerId);
        expect(remainingThrows, hasLength(1));
        expect(remainingThrows.single.gameId, untouchedGame);

        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  });
}
