import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fills a running simulator's database with profiles sized for every sync
/// transport, so the range picker and the three transports can be tried by
/// hand without playing a few thousand legs first.
///
/// Run it against the booted iOS simulator with the app installed:
///
///     flutter test test/tools/seed_simulator_db.dart
///
/// Quit the app first, otherwise it holds the database open and the seeded
/// rows are not visible until the next launch. Pass `--dart-define=reset=true`
/// to remove previously seeded profiles instead of adding more.
///
/// It lives under `test/` and runs through the test runner rather than
/// `dart run` for two reasons: [DbHelper] needs the Flutter bindings, and
/// going through it means the snapshots and stats these profiles carry come
/// from the app's own code rather than a second implementation that could
/// drift from it. The name carries no `_test` suffix, so a plain
/// `flutter test` never picks it up.
///
/// The games it writes have a single player. That keeps the row count in
/// proportion and costs nothing here, because every sync number is derived
/// from one player's own throws.

/// Bundle id of the app whose container holds the database.
const _kBundleId = 'com.ratka.dartscore';

/// Prefix every seeded player's name carries, so a reset can find them again.
const _kPrefix = 'ZZ Test';

/// The profiles to create: how many visits, spread over how many days.
///
/// The sizes are picked against the measured transport limits, a single code
/// holding about 350 visits and an animated transfer about 21000, so that
/// changing the range on a profile walks through the transports rather than
/// jumping. One session per day keeps that predictable: seven days hold roughly
/// a seventh of what thirty days hold.
///
/// Gross is deliberately just under the animated limit, because a transfer
/// close to the cap is the one worth trying by hand: it runs for half a minute
/// and is where a camera dropping frames shows up at all.
const _kProfiles = [
  (name: '$_kPrefix Klein', visits: 220, days: 5),
  (name: '$_kPrefix Mittel', visits: 2500, days: 45),
  (name: '$_kPrefix Gross', visits: 19000, days: 150),
  (name: '$_kPrefix Riesig', visits: 45000, days: 220),
  (name: '$_kPrefix Snapshot', visits: 500, days: 20),
];

void main() {
  test('seed the simulator database', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DbHelper.debugDatabasePath = _findSimulatorDatabase();

    final db = DbHelper.instance;
    await _removeSeededProfiles(db);

    if (const String.fromEnvironment('reset') == 'true') {
      // ignore: avoid_print
      print('Seeded profiles removed.');
      return;
    }

    final random = Random(7);
    for (final profile in _kProfiles) {
      final player = await _seedProfile(
        db,
        profile.name,
        profile.visits,
        profile.days,
        random,
      );

      // One profile keeps part of its history only as a snapshot, which is what
      // a player who cleared their old games looks like. The ids come back
      // newest first, so the oldest games are the ones at the end.
      if (profile.name.endsWith('Snapshot')) {
        final games = await db.getGameIdsForPlayer(player.id!);
        for (final gameId in games.reversed.take(5)) {
          await db.snapshotGameStats(gameId);
          await db.deleteGame(gameId);
        }
      }

      final throws = await db.getThrowsForPlayer(player.id!);
      // ignore: avoid_print
      print(
        '${profile.name}: ${throws.length} visits over ${profile.days} days',
      );
    }

    // ignore: avoid_print
    print('\nDatabase: ${DbHelper.debugDatabasePath}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Locates the app's database inside the booted simulator's data container.
String _findSimulatorDatabase() {
  final result = Process.runSync('xcrun', [
    'simctl',
    'get_app_container',
    'booted',
    _kBundleId,
    'data',
  ]);

  if (result.exitCode != 0) {
    fail(
      'Could not find the app container. Is a simulator booted with the '
      'app installed?\n${result.stderr}',
    );
  }

  final path = '${(result.stdout as String).trim()}/Documents/dartscore.db';
  if (!File(path).existsSync()) {
    fail('No database at $path. Launch the app once so it creates one.');
  }
  return path;
}

/// Deletes every player this tool created before, with their games and throws.
Future<void> _removeSeededProfiles(DbHelper db) async {
  final d = await db.db;
  final rows = await d.query(
    'players',
    columns: ['id'],
    where: 'name LIKE ?',
    whereArgs: ['$_kPrefix%'],
  );

  for (final row in rows) {
    final playerId = row['id'] as int;
    final gameIds = await d.query(
      'game_players',
      columns: ['game_id'],
      where: 'player_id = ?',
      whereArgs: [playerId],
    );
    for (final game in gameIds) {
      await db.deleteGame(game['game_id'] as int);
    }
    await d.delete(
      'dart_throws',
      where: 'player_id = ?',
      whereArgs: [playerId],
    );
    await d.delete('players', where: 'id = ?', whereArgs: [playerId]);
  }
}

/// Creates one profile with [visits] visits spread over the last [days] days.
///
/// One session per day keeps the ranges predictable: seven days hold roughly a
/// seventh of a month, which is what makes the picker walk through the
/// transports instead of jumping straight from one code to the server.
Future<Player> _seedProfile(
  DbHelper db,
  String name,
  int visits,
  int days,
  Random random,
) async {
  final playerId = await db.insertPlayer(Player(name: name));
  final perSession = (visits / days).ceil();

  var written = 0;
  for (var day = days - 1; day >= 0 && written < visits; day--) {
    // Evening session, with a little drift so timestamps are not on a grid.
    final start = DateTime.now()
        .subtract(Duration(days: day))
        .copyWith(hour: 19, minute: random.nextInt(60), second: 0)
        .millisecondsSinceEpoch;

    final target = min(perSession, visits - written);
    final throws = _playSession(target, start, random);

    final gameId = await db.insertGame(
      Game(
        startScore: 501,
        legs: 3,
        createdAt: DateTime.fromMillisecondsSinceEpoch(start),
        finishedAt: throws.last.thrownAt,
      ),
      [playerId],
    );

    final d = await db.db;
    final batch = d.batch();
    for (final t in throws) {
      batch.insert('dart_throws', {
        'game_id': gameId,
        'player_id': playerId,
        'score': t.score,
        'darts_used': t.dartsUsed,
        'leg': t.leg,
        'set_': t.set,
        'remaining_before': t.remainingBefore,
        'thrown_at': t.thrownAt.millisecondsSinceEpoch,
        'bust': t.bust ? 1 : 0,
        'hits_json': t.hitsJson,
      });
    }
    await batch.commit(noResult: true);

    written += throws.length;
  }

  return (await db.getPlayer(playerId))!;
}

/// Plays [visits] visits of 501 double out, returning them in throwing order.
///
/// The darts are thrown rather than the scores drawn, so every visit carries
/// the per dart record the dartboard input produces. Without it the seeded
/// profiles could not exercise the heatmap or the top doubles at all, which is
/// exactly the part of a sync that is easiest to get wrong.
List<DartThrow> _playSession(int visits, int startMs, Random random) {
  final out = <DartThrow>[];
  var time = startMs;
  var leg = 1;
  var set = 1;
  var remaining = 501;

  while (out.length < visits) {
    final darts = <(int, int)>[];
    var scored = 0;
    var bust = false;
    var finished = false;

    while (darts.length < 3 && !bust && !finished) {
      final aim = _aimFor(remaining - scored);
      final dart = _throwAt(aim.$1, aim.$2, random);
      darts.add(dart);

      final left = remaining - scored - _dartScore(dart.$1, dart.$2);
      // A leg ends on a double, and one point left cannot be finished.
      if (left < 0 || left == 1 || (left == 0 && dart.$2 != 2)) {
        bust = true;
      } else {
        scored = remaining - left;
        finished = left == 0;
      }
    }

    out.add(
      DartThrow(
        gameId: 0, // filled in by the caller
        playerId: 0,
        score: bust ? 0 : scored,
        dartsUsed: darts.length,
        leg: leg,
        set: set,
        remainingBefore: remaining,
        thrownAt: DateTime.fromMillisecondsSinceEpoch(time),
        bust: bust,
        hitsJson: jsonEncode(darts.map((d) => {'f': d.$1, 'm': d.$2}).toList()),
      ),
    );

    time += 35000 + random.nextInt(25000);
    if (!bust) remaining -= scored;

    if (remaining == 0) {
      leg++;
      if (leg > 3) {
        set++;
        leg = 1;
      }
      remaining = 501;
    }
  }

  return out;
}

/// Where the player aims with [remaining] left.
///
/// The treble twenty while the score is high, a double once a finish is on,
/// and a single in between to leave an even number to finish on.
(int, int) _aimFor(int remaining) {
  if (remaining > 60) return (20, 3);
  if (remaining == 50) return (25, 2);
  if (remaining <= 40 && remaining.isEven) return (remaining ~/ 2, 2);
  return ((remaining > 40 ? remaining - 40 : 1).clamp(1, 20), 1);
}

/// Throws one dart at [field] with [multiplier] and reports where it landed.
///
/// A decent club player hits the treble they aimed at less than a fifth of the
/// time, usually catching the single of the same number and often enough a
/// neighbouring segment. That spread is what gives a heatmap its shape, and it
/// puts the three dart average somewhere around seventy rather than at the
/// hundred a professional throws.
(int, int) _throwAt(int field, int multiplier, Random random) {
  final roll = random.nextInt(100);
  if (roll < 18) return (field, multiplier);
  if (roll < 62) return (field, 1);
  if (roll < 85) return (_neighbourOf(field, random), 1);
  if (roll < 93) return (field, multiplier == 3 ? 2 : 1);
  return (0, 1); // off the board
}

/// A segment next to [field] on the board, either side.
int _neighbourOf(int field, Random random) {
  const order = [
    20,
    1,
    18,
    4,
    13,
    6,
    10,
    15,
    2,
    17,
    3,
    19,
    7,
    16,
    8,
    11,
    14,
    9,
    12,
    5,
  ];
  final index = order.indexOf(field);
  if (index < 0) return field; // the bull has no neighbours worth modelling
  return order[(index + (random.nextBool() ? 1 : order.length - 1)) %
      order.length];
}

/// Points a dart on [field] with [multiplier] is worth.
int _dartScore(int field, int multiplier) => switch (field) {
  0 => 0,
  25 => multiplier == 2 ? 50 : 25,
  _ => field * multiplier,
};
