import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/player_stats_screen.dart';
import 'package:dartscore_app/screens/sync_screen.dart';
import 'package:dartscore_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// A sync can be cut back to the last few days, and then only those throws
/// travel as throws. Everything older has to arrive as aggregated stats
/// instead, or the receiving device's lifetime numbers quietly read low and
/// nobody can tell which sync lost them. These tests play real games, age part
/// of them, and check that what arrives adds up to what was sent whichever
/// range was picked.
void main() {
  group('syncing a limited range', () {
    useInMemoryDatabase();

    late List<Player> players;

    setUp(() async {
      players = await insertPlayers(['Sender', 'Opponent']);
    });

    /// Plays one 501 leg with a known shape for the first player: two 180s, an
    /// overshoot from 141, then 141 checked out on a double. That is two
    /// checkout attempts of which one succeeded, one bust and two 180s.
    Future<void> playLeg() async {
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

      await oneEighty(); // 501 to 321
      await sixty(); // opponent
      await oneEighty(); // 321 to 141
      await sixty(); // opponent
      await oneEighty(); // overshoots from 141
      await sixty(); // opponent
      await provider.tapField(20, 3);
      await provider.tapField(19, 3);
      await provider.tapField(12, 2);

      expect(provider.gameOver, isTrue, reason: 'the leg should be finished');
    }

    /// Moves every throw of the sender that was recorded so far [days] into the
    /// past, so a later game stays inside a short range and this one does not.
    Future<void> ageEverythingBy(int days) async {
      final d = await DbHelper.instance.db;
      final shift = Duration(days: days).inMilliseconds;
      await d.rawUpdate('UPDATE dart_throws SET thrown_at = thrown_at - ?', [
        shift,
      ]);
    }

    /// The player row as it currently stands, snapshot and all.
    Future<Player> reload(Player p) async =>
        (await DbHelper.instance.getPlayer(p.id!))!;

    /// Builds a packet the way the device called [device] would.
    Future<SyncPacket> packetFrom(
      Player player,
      SyncRange range, {
      String device = 'SENDER',
    }) async {
      asDevice(device);
      return buildSyncPacket(player, 'Test', range);
    }

    /// Replays [packet] onto a second player the way the receive tab does, and
    /// returns the lifetime stats that player then shows.
    ///
    /// Everything past the player row goes through the same call the screen
    /// makes, so no test can pass on an import path the app does not have.
    Future<PlayerStats> importInto(
      Player receiver,
      SyncPacket packet, {
      String device = 'RECEIVER',
    }) async {
      asDevice(device);

      final current = await reload(receiver);
      await DbHelper.instance.updatePlayer(
        current.copyWith(
          name: packet.playerName,
          favoriteDoubles: packet.favoriteDoubles,
        ),
      );

      await applySyncedData(packet, receiver.id!, localDevice: device);

      return loadPlayerStats(await reload(receiver));
    }

    /// Asserts that two lifetime stat sets carry the same numbers. The throw
    /// log is deliberately left out: that is the one thing a short range does
    /// give up.
    void expectSameLifetime(PlayerStats a, PlayerStats b) {
      expect(b.totalVisits, a.totalVisits, reason: 'visits');
      expect(b.totalDarts, a.totalDarts, reason: 'darts');
      expect(b.totalScored, a.totalScored, reason: 'scored');
      expect(b.busts, a.busts, reason: 'busts');
      expect(b.legsWon, a.legsWon, reason: 'legs won');
      expect(b.highestVisit, a.highestVisit, reason: 'highest visit');
      expect(b.highestCheckout, a.highestCheckout, reason: 'highest checkout');
      expect(b.count180, a.count180, reason: '180s');
      expect(b.count140plus, a.count140plus, reason: '140+');
      expect(b.count100plus, a.count100plus, reason: '100+');
      expect(
        b.checkoutPercent,
        closeTo(a.checkoutPercent, 0.001),
        reason: 'checkout percent',
      );
      expect(b.perfectLegs, a.perfectLegs, reason: 'perfect legs');
      // Both of these describe a game, not a throw, and a synced throw arrives
      // without its game. They only add up because they travel folded into the
      // snapshot alongside.
      expect(
        b.highestGameAverage,
        closeTo(a.highestGameAverage, 0.001),
        reason: 'highest game average',
      );
      // Which segment each dart hit is the one thing a synced throw cannot
      // carry, so it travels folded into the stats snapshot instead. It feeds
      // the dartboard heatmap and the top doubles.
      expect(b.segmentHits, a.segmentHits, reason: 'segment hits');
    }

    test(
      'a one week range carries the same lifetime numbers as everything',
      () async {
        // Two legs well in the past, one from today.
        await playLeg();
        await playLeg();
        await ageEverythingBy(40);
        await playLeg();

        final sender = await reload(players.first);
        final sent = await loadPlayerStats(sender);

        final receivers = await insertPlayers(['Full', 'Week']);

        final full = await importInto(
          receivers[0],
          await packetFrom(sender, SyncRange.all),
        );
        final week = await importInto(
          receivers[1],
          await packetFrom(sender, SyncRange.week),
        );

        expectSameLifetime(sent, full);
        expectSameLifetime(sent, week);
      },
    );

    test('the dartboard segments arrive whatever the range', () async {
      await playLeg();
      await ageEverythingBy(40);
      await playLeg();

      final sender = await reload(players.first);
      final sent = await loadPlayerStats(sender);
      expect(
        sent.segmentHits,
        isNotEmpty,
        reason: 'the games above were played on the board, not typed in',
      );

      final receivers = await insertPlayers(['Full', 'Day']);

      // The short range pushes most throws into the snapshot, the long one
      // sends them all as throws. Both have to end up with the same board.
      final full = await importInto(
        receivers[0],
        await packetFrom(sender, SyncRange.all),
      );
      final day = await importInto(
        receivers[1],
        await packetFrom(sender, SyncRange.day),
      );

      expect(full.segmentHits, sent.segmentHits);
      expect(day.segmentHits, sent.segmentHits);
    });

    test('the shorter range really does send fewer throws', () async {
      await playLeg();
      await ageEverythingBy(40);
      await playLeg();

      final sender = await reload(players.first);
      final all = await packetFrom(sender, SyncRange.all);
      final week = await packetFrom(sender, SyncRange.week);

      expect(week.throws.length, lessThan(all.throws.length));
      expect(week.rangeDays, 7);
      expect(all.rangeDays, isNull);
      // What it stops sending as throws it starts sending as stats.
      expect(week.localStatsJson, isNotNull);
      expect(jsonDecode(week.localStatsJson!)['total_visits'], greaterThan(0));
    });

    test('a range still covers games that were deleted', () async {
      await playLeg();
      final deleted = (await DbHelper.instance.getGameIdsForPlayer(
        players.first.id!,
      )).first;
      await DbHelper.instance.snapshotGameStats(deleted);
      await DbHelper.instance.deleteGame(deleted);

      await playLeg();
      await ageEverythingBy(40);
      await playLeg();

      final sender = await reload(players.first);
      final sent = await loadPlayerStats(sender);

      final receiver = (await insertPlayers(['Week'])).single;
      final week = await importInto(
        receiver,
        await packetFrom(sender, SyncRange.week),
      );

      expectSameLifetime(sent, week);
    });

    test('syncing the same player twice does not double any number', () async {
      await playLeg();
      await ageEverythingBy(40);
      await playLeg();

      final sender = await reload(players.first);
      final sent = await loadPlayerStats(sender);
      final receiver = (await insertPlayers(['Guest'])).single;

      final first = await importInto(
        receiver,
        await packetFrom(sender, SyncRange.week),
      );
      expectSameLifetime(sent, first);

      // The sender plays on, then syncs again with the same short range.
      await playLeg();
      final grown = await reload(players.first);
      final after = await loadPlayerStats(grown);

      final second = await importInto(
        receiver,
        await packetFrom(grown, SyncRange.week),
      );
      expectSameLifetime(after, second);
    });

    test('an import leaves games played on this device alone', () async {
      // The receiver has their own history with this player before any sync.
      await playLeg();
      final receiver = await reload(players.first);
      final own = await loadPlayerStats(receiver);
      expect(own.totalVisits, greaterThan(0));

      await DbHelper.instance.deleteSyncedThrowsForPlayer(receiver.id!);

      final still = await loadPlayerStats(await reload(receiver));
      expect(
        still.totalVisits,
        own.totalVisits,
        reason: 'locally played games are not marked is_synced',
      );
    });
  });
}
