import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/player_stats_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// The lifetime stats a player sees are two things added together: the games
/// still on the device, counted from their stored throws, and a snapshot left
/// behind by games that were deleted. These tests cover that sum, because a
/// mistake in it is invisible in the app: the number simply reads a little low
/// and nobody can tell.
void main() {
  group('loadPlayerStats', () {
    useInMemoryDatabase();

    late List<Player> players;

    setUp(() async {
      players = await insertPlayers(['A', 'B']);
    });

    /// Plays one 501 leg (double out) with a known shape for A: two 180s down
    /// to 141, a visit from 141 that works down to 24 and then overshoots, then
    /// 141 checked out on a double. That gives two checkout attempts of which
    /// one succeeded, one bust, two 180s and twelve darts. B keeps the turn
    /// moving with 60s.
    ///
    /// Returns the finished game's id.
    Future<int> playGame() async {
      final provider = GameProvider();
      await provider.startGame(
        Game(startScore: 501, legs: 1, createdAt: DateTime.now()),
        players,
      );

      Future<void> oneEighty() async {
        await provider.tapField(20, 3);
        await provider.tapField(20, 3);
        await provider.tapField(20, 3);
      }

      Future<void> sixty() async {
        await provider.tapField(20, 1);
        await provider.tapField(20, 1);
        await provider.tapField(20, 1);
      }

      await oneEighty(); // A: 501 to 321
      await sixty(); // B
      await oneEighty(); // A: 321 to 141
      await sixty(); // B
      // A: 141 to 81 to 24, one dart from D12, then the triple 20 overshoots.
      await provider.tapField(20, 3);
      await provider.tapField(19, 3);
      await provider.tapField(20, 3);
      await sixty(); // B
      // A: T20, T19, D12 finishes 141 on a double.
      await provider.tapField(20, 3);
      await provider.tapField(19, 3);
      await provider.tapField(12, 2);

      expect(provider.gameOver, isTrue, reason: 'the leg should be finished');
      return provider.game!.id!;
    }

    test('adds a deleted game to the games still on the device', () async {
      final first = await playGame();
      final beforeDelete = await loadPlayerStats(players.first);

      // Deleting a game keeps its numbers, that is what the snapshot is for.
      await DbHelper.instance.snapshotGameStats(first);
      await DbHelper.instance.deleteGame(first);
      final afterDelete = await loadPlayerStats(players.first);

      expect(afterDelete.totalDarts, beforeDelete.totalDarts);
      expect(afterDelete.totalVisits, beforeDelete.totalVisits);
      expect(afterDelete.totalScored, beforeDelete.totalScored);
      expect(afterDelete.count180, beforeDelete.count180);
      expect(afterDelete.highestVisit, beforeDelete.highestVisit);
      expect(afterDelete.highestCheckout, beforeDelete.highestCheckout);
      expect(afterDelete.legsWon, beforeDelete.legsWon);
      expect(afterDelete.perfectLegs, beforeDelete.perfectLegs);
      expect(
        afterDelete.checkoutPercent,
        closeTo(beforeDelete.checkoutPercent, 0.001),
      );

      // A second game, this one still present, has to land on top of the
      // snapshot rather than replace it.
      await playGame();
      final merged = await loadPlayerStats(players.first);

      expect(merged.totalDarts, beforeDelete.totalDarts * 2);
      expect(merged.totalVisits, beforeDelete.totalVisits * 2);
      expect(merged.totalScored, beforeDelete.totalScored * 2);
      expect(merged.count180, beforeDelete.count180 * 2);
      expect(merged.legsWon, beforeDelete.legsWon * 2);
      expect(merged.gamesPlayed, 2);
      expect(
        merged.highestVisit,
        beforeDelete.highestVisit,
        reason: 'a maximum is not a sum',
      );
      expect(merged.highestCheckout, beforeDelete.highestCheckout);
      expect(
        merged.highestGameAverage,
        closeTo(beforeDelete.highestGameAverage, 0.001),
      );
    });

    test(
      'counts the busted attempt from 24 against the checkout rate',
      () async {
        await playGame();
        final stats = await loadPlayerStats(players.first);

        // Two visits put a dart on a finish: the overshoot from 24 and the
        // checkout. The two 180s never did, however low they left A.
        expect(stats.checkoutPercent, closeTo(50, 0.001));
        expect(stats.busts, 1);
        expect(stats.count180, 2, reason: 'the busted visit scores nothing');
        expect(stats.totalDarts, 12);
        expect(stats.totalScored, 501);
        expect(stats.highestCheckout, 141);
        expect(stats.perfectLegs, 0, reason: '12 darts is not a nine darter');
      },
    );

    test('counts a nine darter as a perfect leg', () async {
      // The counterpart to the case above: the same 501, finished in the
      // fewest darts it allows. Without it the perfect leg count could be
      // stuck at zero and every other assertion here would still pass.
      final provider = GameProvider();
      await provider.startGame(
        Game(startScore: 501, legs: 1, createdAt: DateTime.now()),
        players,
      );

      Future<void> visit(List<(int, int)> darts) async {
        for (final d in darts) {
          await provider.tapField(d.$1, d.$2);
        }
      }

      const maximum = [(20, 3), (20, 3), (20, 3)];
      const sixty = [(20, 1), (20, 1), (20, 1)];

      await visit(maximum); // 501 to 321
      await visit(sixty); // opponent
      await visit(maximum); // 321 to 141
      await visit(sixty); // opponent
      await visit([(20, 3), (19, 3), (12, 2)]); // 141 checked out on a double

      expect(provider.gameOver, isTrue);

      final stats = await loadPlayerStats(players.first);
      expect(stats.totalDarts, 9);
      expect(stats.perfectLegs, 1, reason: 'nine darts on a 501 is perfect');
    });

    test('leaves a player without any throws at zero', () async {
      final stats = await loadPlayerStats(players[1]);

      expect(stats.totalDarts, 0);
      expect(stats.totalVisits, 0);
      expect(stats.checkoutPercent, 0);
      expect(stats.highestGameAverage, 0);
    });
  });
}
