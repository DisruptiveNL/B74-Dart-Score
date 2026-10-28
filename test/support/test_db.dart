import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/services/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points [DbHelper] at a fresh in-memory SQLite database for every test in
/// the calling group, so provider tests exercise the real schema, the real
/// queries and the real replay path instead of a stand-in.
///
/// Call once inside a `group`, before the tests that need a database.
void useInMemoryDatabase() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DbHelper.debugDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    // A new connection means a new empty in-memory database, created through
    // DbHelper's own onCreate, so the tests run against the shipped schema.
    await DbHelper.debugReset();

    // Building a sync packet asks who this device is, which is persisted
    // through shared_preferences and would go looking for a plugin that a test
    // does not have. A test acting out two devices calls [asDevice] on top.
    SharedPreferences.setMockInitialValues(const {});
    DeviceIdentity.debugSetId(null);

    // A completed visit settles at once. The pause it waits out in the app is
    // real time that a widget test's clock never reaches and a provider test
    // would have to sleep through; the tests of the pause set their own.
    TurnPacing.debugVisitPause = Duration.zero;
  });

  tearDown(() async {
    await DbHelper.debugReset();
    DeviceIdentity.debugSetId(null);
    TurnPacing.debugVisitPause = null;
  });
}

/// Makes everything that follows speak as the device called [id], so one test
/// can play both sides of a sync.
void asDevice(String id) => DeviceIdentity.debugSetId(id);

/// Writes [count] X01 visits for [playerId] in one batch, inside a game of
/// their own, and returns the game id.
///
/// A batch, because a test that needs a payload large enough to outgrow a
/// single QR code needs thousands of rows, and inserting those one await at a
/// time takes longer than the rest of the suite put together.
Future<int> seedThrows(int playerId, int count) async {
  final db = DbHelper.instance;
  final gameId = await db.insertGame(
    Game(startScore: 501, createdAt: DateTime(2026, 1, 1)),
    [playerId],
  );

  final d = await db.db;
  final batch = d.batch();
  for (var i = 0; i < count; i++) {
    // Varied on purpose. Identical visits compress away to almost nothing, so
    // a test that wants a payload too large for one QR code would never get
    // one out of a thousand copies of the same throw.
    final field = (i % 20) + 1;
    final score = field * ((i % 3) + 1);
    batch.insert('dart_throws', {
      'game_id': gameId,
      'player_id': playerId,
      'score': score,
      'darts_used': 3,
      'leg': (i ~/ 15) + 1,
      'set_': 1,
      'remaining_before': 501 - (i % 12) * 37,
      'thrown_at': DateTime(
        2026,
        1,
        1,
      ).add(Duration(minutes: i)).millisecondsSinceEpoch,
      'bust': i % 17 == 0 ? 1 : 0,
      'hits_json':
          '[{"f":$field,"m":${(i % 3) + 1}},'
          '{"f":${(i % 20) + 1},"m":1},{"f":${(i % 7) + 1},"m":2}]',
    });
  }
  await batch.commit(noResult: true);
  return gameId;
}

// ── Stored finish times ───────────────────────────────────────────────────────
//
// The finish time of a game exists in its row and nowhere else: every provider
// writes `finishedAt` straight to the database and leaves its own copy of the
// game untouched, so `provider.game!.finishedAt` is null even for a game that
// is over. History reads the row, which is what these helpers read too.

/// The finish time the X01 game [gameId] carries in the database.
Future<DateTime?> storedX01FinishedAt(int gameId) async =>
    (await DbHelper.instance.getGames())
        .firstWhere((g) => g.id == gameId)
        .finishedAt;

/// The finish time the Cricket game [gameId] carries in the database.
Future<DateTime?> storedCricketFinishedAt(int gameId) async =>
    (await DbHelper.instance.getCricketGames())
        .firstWhere((g) => g.id == gameId)
        .finishedAt;

/// The finish time the Shanghai game [gameId] carries in the database.
Future<DateTime?> storedShanghaiFinishedAt(int gameId) async =>
    (await DbHelper.instance.getShanghaiGames())
        .firstWhere((g) => g.id == gameId)
        .finishedAt;

/// The finish time the Around the Clock game [gameId] carries in the database.
Future<DateTime?> storedAroundTheClockFinishedAt(int gameId) async =>
    (await DbHelper.instance.getAroundTheClockGames())
        .firstWhere((g) => g.id == gameId)
        .finishedAt;

/// Inserts [names] as players and returns them with their assigned ids, in the
/// given order.
Future<List<Player>> insertPlayers(List<String> names) async {
  final db = DbHelper.instance;
  final players = <Player>[];
  for (final name in names) {
    final id = await db.insertPlayer(Player(name: name));
    players.add(Player(id: id, name: name));
  }
  return players;
}
