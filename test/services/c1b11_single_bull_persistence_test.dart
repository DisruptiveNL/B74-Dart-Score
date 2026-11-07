import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/services/competition_single_bull_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('C1B11 durable Singles deciding bull', () {
    useInMemoryDatabase();

    test('survives store recreation, is idempotent, rejects conflicting winner',
        () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'bull-match', 'payload': '{}', 'received_at': 1,
      });
      final ids = [
        await helper.insertPlayer(Player(name: 'Home bull')),
        await helper.insertPlayer(Player(name: 'Away bull')),
      ];
      final gameId = await helper.insertGame(
        Game(startScore: 501, createdAt: DateTime.now()), ids,
        competitionMatchId: 'bull-match', competitionSlot: 1,
        starterExternalId: 'home',
      );
      final store = CompetitionSingleBullStore();
      expect(await store.winner(gameId: gameId, leg: 5), isNull);
      await store.record(gameId: gameId, leg: 5, winnerPlayerId: ids.first);
      await store.record(gameId: gameId, leg: 5, winnerPlayerId: ids.first);
      expect(await CompetitionSingleBullStore().winner(gameId: gameId, leg: 5),
          ids.first);
      await expectLater(
        store.record(gameId: gameId, leg: 5, winnerPlayerId: ids.last),
        throwsStateError,
      );
      await expectLater(
        store.record(gameId: gameId, leg: 3, winnerPlayerId: 999999),
        throwsStateError,
      );
    });
  });
}
