import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/utils/throw_stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Guards the mapping between [ThrowStats] and the keys a snapshot stores.
///
/// Both sides share one implementation of the formulas, so this is no longer a
/// comparison of two calculations; what it catches is a wrong or renamed key on
/// the way into `local_stats_json`, which would silently zero a lifetime number.
/// The formulas themselves are pinned in `test/utils/throw_stats_test.dart`.
void main() {
  group('snapshot keys carry the ThrowStats values', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['A', 'B']);
    });

    /// The stats snapshot stored on [player] after the game was archived.
    Future<Map<String, dynamic>> statsFor(Player player) async {
      final stored = await DbHelper.instance.getPlayer(player.id!);
      return jsonDecode(stored!.localStatsJson!) as Map<String, dynamic>;
    }

    test('every shared counter is stored under its key', () async {
      await provider.startGame(
        Game(startScore: 301, legs: 3, createdAt: DateTime.now()),
        players,
      );

      // A: 301 to 121 with a 180.
      await provider.tapField(20, 3);
      await provider.tapField(20, 3);
      await provider.tapField(20, 3);
      // B: an ordinary 60.
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      // A: 121 left, overshoots with a triple 20 and busts inside the range.
      await provider.tapField(20, 3);
      await provider.tapField(20, 3);
      // B: another 60.
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      // A: 121 left, T20 leaves 61, then D20 leaves 21, then a miss.
      await provider.tapField(20, 3);
      await provider.tapField(20, 2);
      await provider.tapField(0, 1);
      // B: 60 again.
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      // A: 21 left, finishes on a single 1 and double 10.
      await provider.tapField(1, 1);
      await provider.tapField(10, 2);

      final liveThrows = provider.playerStates[0].throws;
      expect(liveThrows.any((t) => t.bust), isTrue);
      expect(
        liveThrows.any((t) => !t.bust && t.remainingBefore == t.score),
        isTrue,
      );

      final live = ThrowStats.fromThrows(liveThrows);
      await DbHelper.instance.snapshotGameStats(provider.game!.id!);
      final stored = await statsFor(players.first);

      expect(live.totalDarts, stored['total_darts']);
      expect(live.totalScored, stored['total_scored']);
      expect(live.totalVisits, stored['total_visits']);
      expect(live.busts, stored['busts']);
      expect(live.highestVisit, stored['highest_visit']);
      expect(live.highestCheckout, stored['highest_checkout']);
      expect(live.count180, stored['count_180']);
      expect(live.count140plus, stored['count_140_plus']);
      expect(live.count100plus, stored['count_100_plus']);
      expect(live.checkoutAttempts, stored['checkout_attempts']);
      expect(live.checkoutSuccesses, stored['checkout_successes']);
      expect(live.checkoutDarts, stored['checkout_darts']);
      expect(live.scoreSumSquares, stored['score_sum_squares']);
      expect(live.coAttemptSub40, stored['co_at_sub40']);
      expect(live.coSuccessSub40, stored['co_ok_sub40']);
      expect(live.coAttemptSub60, stored['co_at_sub60']);
      expect(live.coSuccessSub60, stored['co_ok_sub60']);
      expect(live.coAttemptSub100, stored['co_at_sub100']);
      expect(live.coSuccessSub100, stored['co_ok_sub100']);
      expect(live.coAttemptSub170, stored['co_at_sub170']);
      expect(live.coSuccessSub170, stored['co_ok_sub170']);
    });

    test('a player without a single finish is stored too', () async {
      await provider.startGame(
        Game(startScore: 501, legs: 1, createdAt: DateTime.now()),
        players,
      );

      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      await provider.tapField(20, 1);
      await provider.tapField(19, 1);
      await provider.tapField(19, 1);
      await provider.tapField(19, 1);

      final live = ThrowStats.fromThrows(provider.playerStates[1].throws);
      await DbHelper.instance.snapshotGameStats(provider.game!.id!);
      final stored = await statsFor(players[1]);

      expect(live.totalDarts, stored['total_darts']);
      expect(live.totalScored, stored['total_scored']);
      expect(live.checkoutAttempts, stored['checkout_attempts']);
      expect(live.highestCheckout, stored['highest_checkout']);
    });
  });
}
