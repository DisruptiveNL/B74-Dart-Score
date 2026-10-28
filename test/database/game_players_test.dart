import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('reading every line-up at once', () {
    useInMemoryDatabase();

    Game game() => Game(startScore: 501, createdAt: DateTime.now());

    test(
      'returns the same players in the same order as asking per game',
      () async {
        final db = DbHelper.instance;
        final players = await insertPlayers(['A', 'B', 'C']);
        final first = await db.insertGame(game(), [
          players[2].id!,
          players[0].id!,
        ]);
        final second = await db.insertGame(game(), [
          players[1].id!,
          players[2].id!,
          players[0].id!,
        ]);

        final byGame = await db.getGamePlayerIdsByGame();

        expect(byGame[first], await db.getGamePlayerIds(first));
        expect(byGame[second], await db.getGamePlayerIds(second));
      },
    );

    test(
      'keeps turn order rather than the order rows happen to come back in',
      () async {
        final db = DbHelper.instance;
        final players = await insertPlayers(['A', 'B', 'C']);
        final ordered = [players[2].id!, players[0].id!, players[1].id!];
        final gameId = await db.insertGame(game(), ordered);

        final byGame = await db.getGamePlayerIdsByGame();

        expect(byGame[gameId], ordered);
      },
    );

    test('leaves out a game nobody was assigned to', () async {
      final db = DbHelper.instance;
      final gameId = await db.insertGame(game(), const []);

      final byGame = await db.getGamePlayerIdsByGame();

      expect(byGame.containsKey(gameId), isFalse);
    });
  });
}
