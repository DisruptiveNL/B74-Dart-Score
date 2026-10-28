import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/player_stats_screen.dart';
import 'package:dartscore_app/screens/sync_screen.dart';
import 'package:dartscore_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Syncing the same player back and forth between two devices.
///
/// One device sending to another is the easy direction and was always right.
/// What was not is the way back: the receiver used to hand the sender its own
/// history as part of its own total, on top of the throws the sender still
/// held, and every lifetime number the two shared drifted upwards a little
/// with each round. Nothing in the app shows that, which is why it is pinned
/// down here.
///
/// Each device is acted out by one player row in one database, which is enough
/// because a device is only ever an id to the code under test.
void main() {
  group('syncing back and forth', () {
    useInMemoryDatabase();

    late List<Player> opponents;

    setUp(() async {
      opponents = await insertPlayers(['A', 'B', 'Opponent']);
    });

    /// The player row as it currently stands, snapshot and all.
    Future<Player> reload(Player p) async =>
        (await DbHelper.instance.getPlayer(p.id!))!;

    /// How many legs have been played, so each one can be given a time of its
    /// own.
    var legsPlayed = 0;

    /// Plays one 501 leg for [player] against the shared opponent: two 180s, an
    /// overshoot from 141, then 141 checked out on a double.
    ///
    /// The leg is then moved a few minutes into the past, further with each
    /// call. A test writes every throw of both devices inside the same
    /// millisecond or two, and `thrownAt` is the deduplication key: two
    /// devices landing on the same millisecond would have one device's visit
    /// discarded as a copy of the other's. Real play cannot do that, one
    /// person cannot throw on two devices at once, so spacing the legs out is
    /// what makes the test the situation it is meant to be.
    Future<void> playLeg(Player player) async {
      final provider = GameProvider();
      await provider.startGame(
        Game(startScore: 501, legs: 1, createdAt: DateTime.now()),
        [player, opponents.last],
      );

      Future<void> oneEighty() async {
        for (var i = 0; i < 3; i++) {
          await provider.tapField(20, 3);
        }
      }

      Future<void> sixty() async {
        for (var i = 0; i < 3; i++) {
          await provider.tapField(20, 1);
        }
      }

      await oneEighty();
      await sixty();
      await oneEighty();
      await sixty();
      await oneEighty();
      await sixty();
      await provider.tapField(20, 3);
      await provider.tapField(19, 3);
      await provider.tapField(12, 2);

      expect(provider.gameOver, isTrue, reason: 'the leg should be finished');

      legsPlayed++;
      final d = await DbHelper.instance.db;
      await d.rawUpdate(
        'UPDATE dart_throws SET thrown_at = thrown_at - ? '
        'WHERE game_id = (SELECT MAX(id) FROM games)',
        [Duration(minutes: 5 * legsPlayed).inMilliseconds],
      );
    }

    /// Plays a nine dart leg for [player]: 180, 180, then 141 on T20, T19, D12.
    ///
    /// The only leg shape here that is perfect, and the one with a game
    /// average worth reading. Both are properties of a game rather than of a
    /// throw, so they are also the two numbers a synced throw cannot carry on
    /// its own.
    Future<void> playPerfectLeg(Player player) async {
      final provider = GameProvider();
      await provider.startGame(
        Game(startScore: 501, legs: 1, createdAt: DateTime.now()),
        [player, opponents.last],
      );

      for (var i = 0; i < 3; i++) {
        await provider.tapField(20, 3);
      }
      for (var i = 0; i < 3; i++) {
        await provider.tapField(20, 1);
      }
      for (var i = 0; i < 3; i++) {
        await provider.tapField(20, 3);
      }
      for (var i = 0; i < 3; i++) {
        await provider.tapField(20, 1);
      }
      await provider.tapField(20, 3);
      await provider.tapField(19, 3);
      await provider.tapField(12, 2);

      expect(provider.gameOver, isTrue, reason: 'the leg should be finished');

      legsPlayed++;
      final d = await DbHelper.instance.db;
      await d.rawUpdate(
        'UPDATE dart_throws SET thrown_at = thrown_at - ? '
        'WHERE game_id = (SELECT MAX(id) FROM games)',
        [Duration(minutes: 5 * legsPlayed).inMilliseconds],
      );
    }

    /// Ages every throw recorded so far, so a later leg stays inside a short
    /// range and this one does not.
    Future<void> ageEverythingBy(int days) async {
      final d = await DbHelper.instance.db;
      await d.rawUpdate('UPDATE dart_throws SET thrown_at = thrown_at - ?', [
        Duration(days: days).inMilliseconds,
      ]);
    }

    /// Sends [player]'s history as the device called [from].
    Future<SyncPacket> send(
      Player player,
      String from, {
      SyncRange range = SyncRange.all,
    }) async {
      asDevice(from);
      return buildSyncPacket(await reload(player), 'Test', range);
    }

    /// Receives [packet] into [player] on the device called [on], the way the
    /// receive tab does.
    Future<void> receive(SyncPacket packet, Player player, String on) async {
      asDevice(on);
      await applySyncedData(packet, player.id!, localDevice: on);
    }

    /// What that player's statistics screen would show.
    Future<PlayerStats> statsOf(Player p) async =>
        loadPlayerStats(await reload(p));

    test('a full round trip leaves the sender where it started', () async {
      final a = opponents[0];
      final b = opponents[1];

      await playLeg(a);
      final before = await statsOf(a);

      // A to B, then straight back.
      await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
      await receive(await send(b, 'DEVICE-B'), a, 'DEVICE-A');

      final after = await statsOf(a);

      expect(after.totalVisits, before.totalVisits, reason: 'visits');
      expect(after.totalDarts, before.totalDarts, reason: 'darts');
      expect(after.count180, before.count180, reason: '180s');
      expect(after.legsWon, before.legsWon, reason: 'legs won');
      // The dartboard is the one that used to drift even over a full range:
      // segments cannot travel per throw, so they go folded into a snapshot
      // and used to come home inside the other device's total.
      expect(after.segmentHits, before.segmentHits, reason: 'segment hits');
    });

    test(
      'a round trip over a short range leaves the sender where it started',
      () async {
        final a = opponents[0];
        final b = opponents[1];

        // History old enough that a week-long range has to fold it away.
        await playLeg(a);
        await ageEverythingBy(40);
        await playLeg(a);

        final before = await statsOf(a);

        await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
        await receive(
          await send(b, 'DEVICE-B', range: SyncRange.week),
          a,
          'DEVICE-A',
        );

        final after = await statsOf(a);

        expect(after.totalVisits, before.totalVisits, reason: 'visits');
        expect(after.totalDarts, before.totalDarts, reason: 'darts');
        expect(after.totalScored, before.totalScored, reason: 'scored');
        expect(after.count180, before.count180, reason: '180s');
        expect(after.busts, before.busts, reason: 'busts');
        expect(after.segmentHits, before.segmentHits, reason: 'segment hits');
      },
    );

    test('both devices end up showing the same lifetime numbers', () async {
      final a = opponents[0];
      final b = opponents[1];

      // Each device has played some of this player's history itself.
      await playLeg(a);
      await playLeg(b);
      await ageEverythingBy(40);
      await playLeg(a);
      await playLeg(b);

      // One round each way, which is what it takes for both sides to hold
      // everything.
      await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
      await receive(
        await send(b, 'DEVICE-B', range: SyncRange.week),
        a,
        'DEVICE-A',
      );

      final onA = await statsOf(a);
      final onB = await statsOf(b);

      expect(onA.totalVisits, onB.totalVisits, reason: 'visits');
      expect(onA.totalDarts, onB.totalDarts, reason: 'darts');
      expect(onA.totalScored, onB.totalScored, reason: 'scored');
      expect(onA.count180, onB.count180, reason: '180s');
      expect(onA.legsWon, onB.legsWon, reason: 'legs won');
      expect(onA.segmentHits, onB.segmentHits, reason: 'segment hits');
    });

    test(
      'syncing the same round twice changes nothing the second time',
      () async {
        final a = opponents[0];
        final b = opponents[1];

        await playLeg(a);
        await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
        final once = await statsOf(b);

        await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
        final twice = await statsOf(b);

        expect(twice.totalVisits, once.totalVisits, reason: 'visits');
        expect(twice.totalDarts, once.totalDarts, reason: 'darts');
        expect(twice.segmentHits, once.segmentHits, reason: 'segment hits');
      },
    );

    test('an import leaves the games this device cleared away alone', () async {
      final a = opponents[0];
      final b = opponents[1];

      // B has a history of its own that it has since cleared, which lives on
      // as its snapshot and nowhere else.
      await playLeg(b);
      final cleared = (await DbHelper.instance.getGameIdsForPlayer(
        b.id!,
      )).first;
      await DbHelper.instance.snapshotGameStats(cleared);
      await DbHelper.instance.deleteGame(cleared);

      final ownVisits = (await statsOf(b)).totalVisits;
      expect(ownVisits, greaterThan(0));

      await playLeg(a);
      final sentVisits = (await statsOf(a)).totalVisits;

      await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');

      expect(
        (await statsOf(b)).totalVisits,
        ownVisits + sentVisits,
        reason: 'the import used to overwrite the receiver own snapshot',
      );
      expect(
        (await reload(b)).localStatsJson,
        isNotNull,
        reason: 'that snapshot is the only copy of a cleared game',
      );
    });

    test(
      'what a third device sent is not touched by an import from another',
      () async {
        final a = opponents[0];
        final b = opponents[1];
        final c = (await insertPlayers(['C'])).single;

        await playLeg(a);
        await playLeg(c);

        // B collects from both, one after the other.
        await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
        final afterFirst = await statsOf(b);
        await receive(await send(c, 'DEVICE-C'), b, 'DEVICE-B');
        final afterSecond = await statsOf(b);

        expect(
          afterSecond.totalVisits,
          afterFirst.totalVisits + (await statsOf(c)).totalVisits,
          reason: 'importing from C used to delete what A had sent',
        );

        // And syncing with A again replaces only A's part.
        await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
        expect((await statsOf(b)).totalVisits, afterSecond.totalVisits);
      },
    );

    test(
      'what a game knows about itself survives a sync, at every range',
      () async {
        final a = opponents[0];

        for (final range in SyncRange.values) {
          await DbHelper.debugReset();
          opponents = await insertPlayers(['A', 'B', 'Opponent']);
          final sender = opponents[0];
          final receiver = opponents[1];

          // A nine darter, and an older ordinary leg so a short range has
          // something to fold away as well.
          await playLeg(sender);
          await ageEverythingBy(40);
          await playPerfectLeg(sender);

          final sent = await statsOf(sender);
          expect(sent.perfectLegs, 1, reason: 'the nine darter is perfect');
          expect(
            sent.highestGameAverage,
            greaterThan(100),
            reason: 'a nine darter averages 167',
          );

          await receive(
            await send(sender, 'DEVICE-A', range: range),
            receiver,
            'DEVICE-B',
          );
          final got = await statsOf(receiver);

          // A synced throw arrives without its game: every one of them lands in
          // one hidden sync-game with no start score, so neither number can be
          // recomputed on the other side and both have to travel folded in.
          expect(
            got.perfectLegs,
            sent.perfectLegs,
            reason: 'perfect legs at ${range.name}',
          );
          expect(
            got.highestGameAverage,
            closeTo(sent.highestGameAverage, 0.001),
            reason: 'highest game average at ${range.name}',
          );
          expect(
            got.gamesPlayed,
            sent.gamesPlayed,
            reason: 'games played at ${range.name}',
          );
          expect(
            got.gamesFinished,
            sent.gamesFinished,
            reason: 'games finished at ${range.name}',
          );
        }

        // The round trip must not turn one perfect leg into two.
        await DbHelper.debugReset();
        opponents = await insertPlayers(['A', 'B', 'Opponent']);
        await playPerfectLeg(opponents[0]);
        final before = await statsOf(opponents[0]);

        await receive(
          await send(opponents[0], 'DEVICE-A'),
          opponents[1],
          'DEVICE-B',
        );
        await receive(
          await send(opponents[1], 'DEVICE-B'),
          opponents[0],
          'DEVICE-A',
        );

        final after = await statsOf(opponents[0]);
        expect(after.perfectLegs, before.perfectLegs, reason: 'back home');
        expect(
          after.highestGameAverage,
          closeTo(before.highestGameAverage, 0.001),
          reason: 'back home',
        );
        expect(a.id, isNotNull);
      },
    );

    test('a device knows only what was sent to it', () async {
      final phone = opponents[0]; // mine, where the profile lives
      final tablet = opponents[1]; // a friend's, which does not know me yet

      // Day one, at home on my phone.
      await playLeg(phone);
      await ageEverythingBy(3);

      // Day two, at his place. The profile gets there by being synced over,
      // then we play.
      await receive(await send(phone, 'PHONE'), tablet, 'TABLET');
      await playLeg(tablet);
      await receive(
        await send(tablet, 'TABLET', range: SyncRange.day),
        phone,
        'PHONE',
      );
      await ageEverythingBy(3);

      // Day three, at home again. His tablet hears nothing of this.
      await playLeg(phone);
      await ageEverythingBy(3);

      // Day four, at his place again, this time with no sync beforehand.
      await playLeg(tablet);
      await receive(
        await send(tablet, 'TABLET', range: SyncRange.day),
        phone,
        'PHONE',
      );

      final mine = await statsOf(phone);
      final his = await statsOf(tablet);

      expect(
        mine.gamesPlayed,
        4,
        reason: 'every evening was sent to the phone, one way or another',
      );
      expect(
        his.gamesPlayed,
        3,
        reason: 'nobody ever told the tablet about day three',
      );
      expect(mine.totalVisits, greaterThan(his.totalVisits));

      // A transfer moves data one way. Only sending the other way evens them.
      await receive(await send(phone, 'PHONE'), tablet, 'TABLET');
      final evened = await statsOf(tablet);

      expect(evened.gamesPlayed, mine.gamesPlayed, reason: 'games');
      expect(evened.totalVisits, mine.totalVisits, reason: 'visits');
      expect(evened.totalDarts, mine.totalDarts, reason: 'darts');
      expect(evened.count180, mine.count180, reason: '180s');
      expect(evened.perfectLegs, mine.perfectLegs, reason: 'perfect legs');
      expect(evened.segmentHits, mine.segmentHits, reason: 'segments');
    });

    test('a short range keeps the numbers but not the older throws', () async {
      final phone = opponents[0];
      final tablet = opponents[1];

      await playLeg(tablet);
      await receive(
        await send(tablet, 'TABLET', range: SyncRange.day),
        phone,
        'PHONE',
      );
      final afterFirst = await statsOf(phone);

      final d = await DbHelper.instance.db;
      Future<int> tabletThrowsOnPhone() async =>
          (await d.rawQuery(
                'SELECT COUNT(*) AS n FROM dart_throws t JOIN games g '
                "ON g.id = t.game_id WHERE t.player_id = ? AND g.origin_device = 'TABLET'",
                [phone.id],
              )).first['n']
              as int;

      expect(await tabletThrowsOnPhone(), greaterThan(0));

      // A second evening there, a day later, sent with the same short range.
      await ageEverythingBy(3);
      await playLeg(tablet);
      await receive(
        await send(tablet, 'TABLET', range: SyncRange.day),
        phone,
        'PHONE',
      );

      final afterSecond = await statsOf(phone);

      // The packet is authoritative for the tablet, so the first evening's
      // throws are dropped and arrive again as part of its snapshot. Every
      // number still adds up; what is gone is the visit by visit record.
      expect(
        afterSecond.totalVisits,
        afterFirst.totalVisits * 2,
        reason: 'both evenings still counted',
      );
      expect(afterSecond.gamesPlayed, 2, reason: 'both evenings still counted');
      expect(
        await tabletThrowsOnPhone(),
        afterFirst.totalVisits,
        reason: 'only the last evening is still there throw by throw',
      );
    });

    test('play, sync, play on the other one, sync back', () async {
      final ios = opponents[0];
      final android = opponents[1];

      /// Darts cannot outnumber three per visit. A device whose two numbers
      /// break that is adding them up from different sets of throws.
      void expectPlausible(PlayerStats s, String where) {
        expect(
          s.totalDarts,
          lessThanOrEqualTo(s.totalVisits * 3),
          reason: '$where: ${s.totalDarts} darts over ${s.totalVisits} visits',
        );
      }

      // A shared history to start from, sent over with the full range.
      await playLeg(ios);
      await playLeg(ios);
      await ageEverythingBy(3);
      await receive(await send(ios, 'IOS'), android, 'ANDROID');

      // A round on the Android, then back to the iPhone: both level.
      await playLeg(android);
      await receive(await send(android, 'ANDROID'), ios, 'IOS');

      final levelIos = await statsOf(ios);
      final levelAndroid = await statsOf(android);
      expect(levelIos.totalVisits, levelAndroid.totalVisits, reason: 'level');
      expect(levelIos.totalDarts, levelAndroid.totalDarts, reason: 'level');

      // A game on the iPhone, then over to the Android.
      await playLeg(ios);
      await receive(await send(ios, 'IOS'), android, 'ANDROID');

      final finalIos = await statsOf(ios);
      final finalAndroid = await statsOf(android);

      expectPlausible(finalIos, 'iOS');
      expectPlausible(finalAndroid, 'Android');

      expect(
        finalIos.totalVisits,
        levelIos.totalVisits + 4,
        reason: 'the iPhone only played one more leg',
      );
      expect(finalAndroid.totalVisits, finalIos.totalVisits, reason: 'visits');
      expect(finalAndroid.totalDarts, finalIos.totalDarts, reason: 'darts');
      expect(
        finalAndroid.average3Dart,
        closeTo(finalIos.average3Dart, 0.01),
        reason: 'average',
      );
    });

    test('the range still cuts throws that came from another device', () async {
      final a = opponents[0];
      final b = opponents[1];

      // Old history on A, synced to B, then a fresh leg played on B itself.
      await playLeg(a);
      await ageEverythingBy(40);
      await receive(await send(a, 'DEVICE-A'), b, 'DEVICE-B');
      await playLeg(b);

      final all = await send(b, 'DEVICE-B');
      final week = await send(b, 'DEVICE-B', range: SyncRange.week);

      expect(
        week.throws.length,
        lessThan(all.throws.length),
        reason: 'what a sync brought in is subject to the range as well',
      );
    });

    test(
      'the range cannot cut throws from before devices were told apart',
      () async {
        final b = opponents[1];

        // What the migration leaves behind: throws under the unnamed device,
        // which is how every sync before this looked.
        await playLeg(b);
        await ageEverythingBy(40);
        final d = await DbHelper.instance.db;
        await d.update('games', {'is_synced': 1, 'origin_device': ''});

        final all = await send(b, 'DEVICE-B');
        final week = await send(b, 'DEVICE-B', range: SyncRange.week);

        // Deliberate, and the reason the range looks like it does nothing on a
        // device that has synced before: there is no snapshot this data could be
        // folded into without handing it back to whoever played it. It travels
        // whole until one sync has given it a device to belong to.
        expect(week.throws.length, all.throws.length);
        expect(all.throws, isNotEmpty);
      },
    );

    test('a device passing on a third one keeps whose data it is', () async {
      final a = opponents[0];
      final b = opponents[1];
      final c = (await insertPlayers(['C'])).single;

      await playLeg(c);
      await ageEverythingBy(40);

      // C to B, then B on to A, with a range short enough that C's throws are
      // folded away on the way.
      await receive(await send(c, 'DEVICE-C'), b, 'DEVICE-B');
      await receive(
        await send(b, 'DEVICE-B', range: SyncRange.week),
        a,
        'DEVICE-A',
      );

      final onA = await statsOf(a);
      expect(onA.totalVisits, (await statsOf(c)).totalVisits);

      // Now back to C, which already holds all of it. Attributing those throws
      // to whoever passed them on is what would count them a second time here.
      final before = await statsOf(c);
      await receive(
        await send(a, 'DEVICE-A', range: SyncRange.week),
        c,
        'DEVICE-C',
      );
      final after = await statsOf(c);

      expect(after.totalVisits, before.totalVisits, reason: 'visits');
      expect(after.totalDarts, before.totalDarts, reason: 'darts');
      expect(after.segmentHits, before.segmentHits, reason: 'segment hits');
    });
  });
}
