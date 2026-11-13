import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('C1B11 competitiegeschiedenis beveiliging', () {
    useInMemoryDatabase();

    test(
      'competitiegame mag niet worden gesnapshot of normaal verwijderd',
      () async {
        final helper = DbHelper.instance;
        final db = await helper.db;

        final playerId = await db.insert('players', {
          'name': 'Competitiespeler',
        });

        await db.insert('competition_inbox', {
          'match_id': 'protected-match',
          'payload': jsonEncode({'division': 'Eredivisie'}),
          'received_at': 1,
        });

        final gameId = await helper.insertGame(
          Game(startScore: 501, createdAt: DateTime(2026, 11, 13)),
          [playerId],
          competitionMatchId: 'protected-match',
          competitionSlot: 1,
          starterExternalId: 'player-a',
        );

        await helper.insertThrow(
          DartThrow(
            gameId: gameId,
            playerId: playerId,
            score: 60,
            dartsUsed: 3,
            leg: 1,
            set: 1,
            remainingBefore: 501,
            thrownAt: DateTime(2026, 11, 13),
          ),
        );

        // Competitieworpen mogen nooit permanent worden
        // samengevoegd met de gewone historische snapshots.
        await helper.snapshotGameStats(gameId);

        final playerRows = await db.query(
          'players',
          columns: ['local_stats_json'],
          where: 'id = ?',
          whereArgs: [playerId],
        );

        final snapshot = playerRows.single['local_stats_json'];
        expect(snapshot == null || snapshot == '', isTrue);

        // De algemene verwijderfunctie moet competitiegames weigeren.
        await expectLater(helper.deleteGame(gameId), throwsStateError);

        // Alle oorspronkelijke competitiegegevens blijven intact.
        expect(
          await db.query('games', where: 'id = ?', whereArgs: [gameId]),
          hasLength(1),
        );

        expect(
          await db.query(
            'dart_throws',
            where: 'game_id = ?',
            whereArgs: [gameId],
          ),
          hasLength(1),
        );

        expect(
          await db.query(
            'game_players',
            where: 'game_id = ?',
            whereArgs: [gameId],
          ),
          hasLength(1),
        );

        expect(
          await db.query(
            'competition_game_links',
            where: 'game_id = ?',
            whereArgs: [gameId],
          ),
          hasLength(1),
        );
      },
    );
  });
}
