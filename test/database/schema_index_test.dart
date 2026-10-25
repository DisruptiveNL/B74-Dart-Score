import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// The indexes the repeated lookups depend on. Named rather than counted, so
/// dropping one to "clean up" fails here instead of quietly turning a lookup
/// back into a full table scan.
const _expectedIndexes = {
  'idx_dart_throws_player',
  'idx_dart_throws_game',
  'idx_game_players_player',
  'idx_cricket_throws_game',
  'idx_shanghai_throws_game',
  'idx_atc_throws_game',
  'idx_ladder_throws_game',
};

/// The names of every index the schema defines itself, ignoring the ones
/// SQLite creates on its own for primary keys.
Future<Set<String>> _indexNames(Database db) async {
  final rows = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'index' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  group('a fresh database', () {
    useInMemoryDatabase();

    test('carries every index the lookups rely on', () async {
      final db = await DbHelper.instance.db;

      expect(await _indexNames(db), containsAll(_expectedIndexes));
    });

    test('answers a throw lookup by player from the index, not by scanning',
        () async {
      final db = await DbHelper.instance.db;

      final plan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM dart_throws WHERE player_id = 1');

      expect(plan.map((r) => r['detail']).join(' '),
          contains('idx_dart_throws_player'));
    });

    test('answers a throw lookup by game from the index, not by scanning',
        () async {
      final db = await DbHelper.instance.db;

      final plan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM dart_throws WHERE game_id = 1');

      expect(plan.map((r) => r['detail']).join(' '),
          contains('idx_dart_throws_game'));
    });
  });

  group('upgrading a database that predates the indexes', () {
    late Directory dir;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // A file, because the migration has to survive closing the connection and
      // an in-memory database does not.
      dir = await Directory.systemTemp.createTemp('dartscore_migration');
      DbHelper.debugDatabasePath = '${dir.path}/dartscore.db';
      await DbHelper.debugReset();
    });

    tearDown(() async {
      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = null;
      await dir.delete(recursive: true);
    });

    /// Winds a current database back to how version 18 left it, so the
    /// migrations run against what they will actually meet in the field.
    /// Rebuilding the old schema by hand would only risk drifting from what
    /// version 18 shipped.
    Future<void> windBackTo18(Database db) async {
      for (final name in await _indexNames(db)) {
        await db.execute('DROP INDEX $name');
      }
      // Version 20 taught games where their throws came from.
      await db.execute('ALTER TABLE games DROP COLUMN origin_device');
      await db.execute('DROP TABLE player_origin_stats');
      // Version 22 recorded per visit how many darts flew at a finish.
      await db.execute('ALTER TABLE dart_throws DROP COLUMN checkout_darts');
      // Versions 23 and 24 gave players a bot tier and a number within it.
      await db.execute('ALTER TABLE players DROP COLUMN bot_ordinal');
      await db.execute('ALTER TABLE players DROP COLUMN bot_level');
      // Version 25 added the Checkout Ladder.
      await db.execute('DROP TABLE checkout_ladder_throws');
      await db.execute('DROP TABLE checkout_ladder_games');
      await db.execute('PRAGMA user_version = 18');
    }

    test('gets the indexes it never had', () async {
      final fresh = await DbHelper.instance.db;
      await windBackTo18(fresh);
      expect(await _indexNames(fresh), isEmpty);
      await DbHelper.debugReset();

      final upgraded = await DbHelper.instance.db;

      expect(await _indexNames(upgraded), containsAll(_expectedIndexes));
    });

    test('gets the Checkout Ladder tables', () async {
      final fresh = await DbHelper.instance.db;
      await windBackTo18(fresh);
      await DbHelper.debugReset();

      final db = DbHelper.instance;

      expect(await db.getCheckoutLadderGames(), isEmpty);
      expect(await db.getCheckoutLadderThrowsForGame(1), isEmpty);
    });

    test('keeps the rows it already held', () async {
      final fresh = await DbHelper.instance.db;
      await fresh.insert('players', {'name': 'Nik', 'uuid': 'u-1'});
      await windBackTo18(fresh);
      await DbHelper.debugReset();

      final players = await DbHelper.instance.getPlayers();

      expect(players.map((p) => p.name), ['Nik']);
    });

    test('moves what an earlier sync left behind into its own bucket',
        () async {
      // A player that was synced under a version that kept one snapshot
      // column, which the import of the day overwrote outright.
      final fresh = await DbHelper.instance.db;
      final playerId = await fresh.insert('players', {
        'name':             'Nik',
        'uuid':             'u-1',
        'last_synced_at':   1000,
        'local_stats_json': '{"total_darts":9}',
      });
      final ownId = await fresh.insert('players', {
        'name':             'Own',
        'uuid':             'u-2',
        'local_stats_json': '{"total_darts":3}',
      });
      await windBackTo18(fresh);
      await DbHelper.debugReset();

      final db = DbHelper.instance;

      // What the import wrote is no longer this device's own history, it is
      // one unnamed device's.
      expect((await db.getPlayer(playerId))!.localStatsJson, isNull);
      expect(await db.getOriginSnapshots(playerId), {'': '{"total_darts":9}'});

      // A player that was never synced is left exactly as they were.
      expect((await db.getPlayer(ownId))!.localStatsJson, '{"total_darts":3}');
      expect(await db.getOriginSnapshots(ownId), isEmpty);

      // Either way the lifetime numbers still add up to the same thing.
      expect(await db.combinedSnapshotJson(playerId),
          contains('"total_darts":9'));
    });

    test('files throws from an earlier sync under the unnamed device',
        () async {
      final fresh = await DbHelper.instance.db;
      final synced = await fresh.insert('games', {
        'start_score': 501,
        'created_at':  1000,
        'is_synced':   1,
      });
      final own = await fresh.insert('games', {
        'start_score': 501,
        'created_at':  1000,
      });
      await windBackTo18(fresh);
      await DbHelper.debugReset();

      final rows = await (await DbHelper.instance.db).query('games',
          columns: ['id', 'origin_device'], orderBy: 'id');

      expect(rows.firstWhere((r) => r['id'] == synced)['origin_device'], '');
      expect(rows.firstWhere((r) => r['id'] == own)['origin_device'], isNull);
    });
  });
}
