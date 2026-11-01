import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

Map<String, dynamic> lockPacket({int homeWins = 5}) => {
  'type': 'b74.competition.match-locked.v1',
  'version': 1,
  'matchId': 'match-locked-test',
  'closedAt': 1793548800000,
  'homeWins': homeWins,
  'awayWins': 9 - homeWins,
};

void main() {
  group('C1B6b.3c.3 SQLite MATCH_LOCKED regressie', () {
    useInMemoryDatabase();

    test('persistente ontvangst, identieke retry en conflicterende retry', () async {
      final helper = DbHelper.instance;
      expect(await helper.receiveMatchLocked(lockPacket()), 'stored');
      expect(await helper.isCompetitionMatchLocked('match-locked-test'), isTrue);
      expect(await helper.receiveMatchLocked(lockPacket()), 'unchanged');
      await expectLater(
        helper.receiveMatchLocked(lockPacket(homeWins: 6)),
        throwsStateError,
      );
      expect((await (await helper.db).query('competition_match_locks')).length, 1);
    });

    test('afgesloten wedstrijd kan geen nieuwe competitiesingle starten', () async {
      final helper = DbHelper.instance;
      await helper.receiveMatchLocked(lockPacket());
      await expectLater(
        helper.insertGame(
          Game(startScore: 501, createdAt: DateTime(2026, 11, 1)),
          const [],
          competitionMatchId: 'match-locked-test',
          competitionSlot: 1,
          starterExternalId: 'home-1',
        ),
        throwsStateError,
      );
      expect(await (await helper.db).query('games'), isEmpty);
    });

    test('reeds geopende single weigert nieuwe beurten en undo', () async {
      final helper = DbHelper.instance;
      final database = await helper.db;
      await database.insert('competition_inbox', {
        'match_id': 'match-locked-test',
        'payload': '{}',
        'received_at': 1,
      });
      final gameId = await helper.insertGame(
        Game(startScore: 501, createdAt: DateTime(2026, 11, 1)),
        const [],
        competitionMatchId: 'match-locked-test',
        competitionSlot: 1,
        starterExternalId: 'home-1',
      );
      final playerId = await database.insert('players', {
        'name': 'Testspeler',
      });
      DartThrow visit() => DartThrow(
        gameId: gameId, playerId: playerId, score: 60,
        dartsUsed: 3, leg: 1, set: 1, remainingBefore: 501,
        thrownAt: DateTime(2026, 11, 1),
      );
      final throwId = await helper.insertThrow(visit());
      await helper.receiveMatchLocked(lockPacket());
      await expectLater(helper.insertThrow(visit()), throwsStateError);
      await expectLater(helper.deleteThrow(throwId), throwsStateError);
      expect((await database.query('dart_throws')).length, 1);
    });

    test('701 en 1001 weigeren events na LOCKED', () async {
      final helper = DbHelper.instance;
      final database = await helper.db;
      for (final (gameId, kind, slot) in [
        ('doubles-1', 'doubles701', 1),
        ('beer-1', 'beer1001', 1),
      ]) {
        await database.insert('competition_team_inbox', {
          'game_id': gameId, 'match_id': 'match-locked-test',
          'kind': kind, 'slot': slot, 'revision': 1,
          'payload': jsonEncode({'gameId': gameId}),
          'received_at': 1, 'started': 0,
        });
      }
      await helper.receiveMatchLocked(lockPacket());
      for (final gameId in ['doubles-1', 'beer-1']) {
        await expectLater(
          helper.appendCompetitionDoublesEvent(
            gameId: gameId, expectedSequence: 0,
            eventJson: '{}', isVisit: true,
          ),
          throwsStateError,
        );
        expect(await helper.competitionDoublesEvents(gameId), isEmpty);
      }
    });
  });
}
