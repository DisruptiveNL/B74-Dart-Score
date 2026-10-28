import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/screens/sync_screen.dart';
import 'package:dartscore_app/services/sync_service.dart';
import 'package:dartscore_app/services/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// A backup is the database file itself, so these run against a real file on
/// disk rather than an in-memory database: everything that can go wrong here
/// (the write-ahead log, the swap, a file that is not ours) only exists once
/// there is a file.
void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentity.debugSetId(null);
    dir = await Directory.systemTemp.createTemp('dartscore_backup');
    dbPath = '${dir.path}/dartscore.db';
    DbHelper.debugDatabasePath = dbPath;
    await DbHelper.debugReset();
  });

  tearDown(() async {
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = null;
    DeviceIdentity.debugSetId(null);
    await dir.delete(recursive: true);
  });

  /// Writes a backup of the current database to its own file and returns the
  /// path, the way the export does.
  Future<String> writeBackup(
    String deviceId, {
    String name = 'backup.db',
  }) async {
    final source = await DbHelper.instance.prepareBackup(deviceId, 'iPhone');
    final target = '${dir.path}/$name';
    await File(source).copy(target);
    return target;
  }

  group('reading a backup before anything is replaced', () {
    test('reports the device, the time and what it holds', () async {
      await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
      await DbHelper.instance.insertPlayer(Player(name: 'Bob'));
      await DbHelper.instance.insertPlayer(
        Player(
          name: BotLevel.pro.storedName,
          uuid: BotLevel.pro.uuid,
          botLevel: BotLevel.pro,
        ),
      );

      final path = await writeBackup('DEVICE0000000001');
      final info = await DbHelper.instance.inspectBackup(path);

      expect(info, isNotNull);
      expect(info!.deviceId, 'DEVICE0000000001');
      expect(
        info.deviceLabel,
        'iPhone',
        reason: 'the receiving screen names where the data comes from',
      );
      expect(
        info.playerCount,
        2,
        reason: 'a bot is a row, not a person the backup holds',
      );
      expect(info.gameCount, 0);
      expect(info.schemaVersion, DbHelper.schemaVersion);
      expect(info.createdAt, isNotNull);
      expect(info.sizeBytes, greaterThan(0));
    });

    test('describes the live database in the same terms as a file', () async {
      final id = await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
      await seedThrows(id, 20);

      final path = await writeBackup('DEVICE0000000001');
      final fromFile = await DbHelper.instance.inspectBackup(path);
      final fromLive = await DbHelper.instance.describeLocal();

      // The sending screen reads the live database and the receiving screen
      // reads the file. They have to agree, or the two ends of one transfer
      // describe different things.
      expect(fromLive.deviceId, fromFile!.deviceId);
      expect(fromLive.deviceLabel, fromFile.deviceLabel);
      expect(fromLive.createdAt, fromFile.createdAt);
      expect(fromLive.playerCount, fromFile.playerCount);
      expect(fromLive.gameCount, fromFile.gameCount);
      expect(fromLive.sizeBytes, fromFile.sizeBytes);
    });

    test('refuses a file that is not a database', () async {
      final path = '${dir.path}/notes.txt';
      await File(path).writeAsString('not a database');

      expect(await DbHelper.instance.inspectBackup(path), isNull);
    });

    test('refuses a database that is not this app', () async {
      final path = '${dir.path}/foreign.db';
      final foreign = await databaseFactory.openDatabase(path);
      await foreign.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY)');
      await foreign.close();

      expect(await DbHelper.instance.inspectBackup(path), isNull);
    });

    test('refuses a database that only looks like this app', () async {
      // The table names alone are a weak test, and a restore cannot be undone.
      // A file carrying the right tables but not the marker is not one this
      // app wrote, and must not be offered as something to replace the live
      // database with.
      final path = '${dir.path}/lookalike.db';
      final lookalike = await databaseFactory.openDatabase(path);
      for (final table in ['players', 'games', 'dart_throws']) {
        await lookalike.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
      }
      await lookalike.close();

      expect(await DbHelper.instance.inspectBackup(path), isNull);
    });

    test('refuses a backup whose marker was tampered with', () async {
      final path = await writeBackup('DEVICE0000000001');
      final file = await databaseFactory.openDatabase(path);
      await file.update(
        'app_meta',
        {'value': 'something-else'},
        where: 'key = ?',
        whereArgs: ['format'],
      );
      await file.close();

      expect(await DbHelper.instance.inspectBackup(path), isNull);
    });

    test(
      'describes a file from a newer app version instead of failing',
      () async {
        final path = await writeBackup('DEVICE0000000001');
        final newer = await databaseFactory.openDatabase(path);
        await newer.execute(
          'PRAGMA user_version = ${DbHelper.schemaVersion + 5}',
        );
        await newer.close();

        final info = await DbHelper.instance.inspectBackup(path);

        expect(info, isNotNull);
        expect(info!.schemaVersion, greaterThan(DbHelper.schemaVersion));
      },
    );
  });

  group('restoring', () {
    test(
      'brings back what the backup held and drops what came after',
      () async {
        await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
        final path = await writeBackup('DEVICE0000000001');

        await DbHelper.instance.insertPlayer(Player(name: 'Later'));
        expect((await DbHelper.instance.getPlayers()).length, 2);

        await DbHelper.instance.replaceDatabase(path);

        final players = await DbHelper.instance.getPlayers();
        expect(players.map((p) => p.name), ['Ann']);
      },
    );

    test('leaves nothing of the old database beside the new one', () async {
      await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
      final path = await writeBackup('DEVICE0000000001');

      // A write-ahead log left over from the replaced database would be
      // applied on top of the restored file.
      await File('$dbPath-wal').writeAsBytes([0, 1, 2, 3]);
      await File('$dbPath-shm').writeAsBytes([0, 1, 2, 3]);

      await DbHelper.instance.replaceDatabase(path);

      expect(await File('$dbPath-wal').exists(), isFalse);
      expect(await File('$dbPath-shm').exists(), isFalse);
      expect(await File('$dbPath.replaced').exists(), isFalse);
    });

    test('keeps the current data when the file cannot be copied', () async {
      await DbHelper.instance.insertPlayer(Player(name: 'Ann'));

      await expectLater(
        DbHelper.instance.replaceDatabase('${dir.path}/gone.db'),
        throwsA(isA<Exception>()),
      );

      expect((await DbHelper.instance.getPlayers()).map((p) => p.name), [
        'Ann',
      ]);
    });
  });

  group('a backup restored onto another device', () {
    /// The origin every game of [playerId] is filed under, `null` meaning the
    /// device believes it played the game itself.
    Future<Set<String?>> originsOf(int playerId) async {
      final byOrigin = await DbHelper.instance.getThrowsForPlayerByOrigin(
        playerId,
      );
      return byOrigin.keys.toSet();
    }

    test('stops claiming the source device\'s games as its own', () async {
      final id = await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
      await seedThrows(id, 12);
      expect(await originsOf(id), {null});

      await DbHelper.instance.attributeRestoredHistory('DEVICE0000000001');

      // Filed under the device that played them, which is what lets the two
      // devices go on syncing instead of each dropping the other's copy.
      expect(await originsOf(id), {'DEVICE0000000001'});
    });

    test(
      'moves the source\'s own snapshot into the source\'s bucket',
      () async {
        final id = await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
        final db = await DbHelper.instance.db;
        await db.update(
          'players',
          {'local_stats_json': '{"total_darts":300,"legs_won":4}'},
          where: 'id = ?',
          whereArgs: [id],
        );

        await DbHelper.instance.attributeRestoredHistory('DEVICE0000000001');

        final snapshots = await DbHelper.instance.getOriginSnapshots(id);
        expect(snapshots.keys, ['DEVICE0000000001']);
        expect(snapshots['DEVICE0000000001'], contains('300'));

        // Nothing may be left claiming to be this device's own history, or a
        // third device would count the same games twice, once from each.
        final rows = await db.query(
          'players',
          columns: ['local_stats_json'],
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(rows.first['local_stats_json'], isNull);

        // And the lifetime numbers are untouched by the move.
        expect(
          await DbHelper.instance.combinedSnapshotJson(id),
          contains('300'),
        );
      },
    );

    test(
      'adds to a snapshot the backup already held for that device',
      () async {
        final id = await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
        final db = await DbHelper.instance.db;
        await db.update(
          'players',
          {'local_stats_json': '{"total_darts":300}'},
          where: 'id = ?',
          whereArgs: [id],
        );
        await db.insert('player_origin_stats', {
          'player_id': id,
          'origin_device': 'DEVICE0000000001',
          'snapshot_json': '{"total_darts":45}',
        });

        await DbHelper.instance.attributeRestoredHistory('DEVICE0000000001');

        final snapshots = await DbHelper.instance.getOriginSnapshots(id);
        expect(
          snapshots['DEVICE0000000001'],
          contains('345'),
          reason: 'both cover games of the same device and neither may be lost',
        );
      },
    );

    test('leaves this device its own identity', () async {
      final before = await DeviceIdentity.id;
      await DbHelper.instance.attributeRestoredHistory('DEVICE0000000001');

      expect(
        await DeviceIdentity.id,
        before,
        reason: 'two live devices on one id can never sync again',
      );
    });

    test('can still sync profiles with the device it came from', () async {
      const deviceA = 'DEVICEAAAA000001';
      const deviceB = 'DEVICEBBBB000002';

      /// Moves every throw recorded so far into the past, so the next batch
      /// gets timestamps of its own. `thrownAt` is the deduplication key, and
      /// two batches on the same millisecond would look like one.
      Future<void> ageEverything() async {
        final d = await DbHelper.instance.db;
        await d.rawUpdate('UPDATE dart_throws SET thrown_at = thrown_at - ?', [
          const Duration(days: 1).inMilliseconds,
        ]);
      }

      // ── The old phone plays, and its database is handed over ──────────────
      asDevice(deviceA);
      final annOnA = await DbHelper.instance.insertPlayer(Player(name: 'Ann'));
      await seedThrows(annOnA, 30);
      await ageEverything();

      final transferred = await writeBackup(deviceA, name: 'transfer.db');

      // And then plays some more, after the hand-over.
      await seedThrows(annOnA, 10);
      final packetFromA = await buildSyncPacket(
        (await DbHelper.instance.getPlayers()).first,
        'Test',
        SyncRange.all,
      );

      // ── The new phone comes up on that database ───────────────────────────
      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = '${dir.path}/device_b.db';
      await File(transferred).copy(DbHelper.debugDatabasePath!);
      asDevice(deviceB);
      await DbHelper.instance.attributeRestoredHistory(deviceA);

      final annOnB = (await DbHelper.instance.getPlayers()).first.id!;
      var onB = await DbHelper.instance.getThrowsForPlayerByOrigin(annOnB);
      expect(onB.keys, [deviceA]);
      expect(onB[deviceA], hasLength(30));

      // ── The old phone syncs to it, and is heard ───────────────────────────
      await applySyncedData(packetFromA, annOnB, localDevice: deviceB);

      onB = await DbHelper.instance.getThrowsForPlayerByOrigin(annOnB);
      expect(
        onB[deviceA],
        hasLength(40),
        reason:
            'the ten legs played after the hand-over have to arrive, and '
            'the thirty from before it must not arrive a second time',
      );
      expect(onB.keys, [
        deviceA,
      ], reason: 'none of it was played on this phone');

      // ── And the way back changes nothing on the old phone ─────────────────
      final packetFromB = await buildSyncPacket(
        (await DbHelper.instance.getPlayers()).first,
        'Test',
        SyncRange.all,
      );

      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = dbPath;
      asDevice(deviceA);
      await applySyncedData(packetFromB, annOnA, localDevice: deviceA);

      final onA = await DbHelper.instance.getThrowsForPlayerByOrigin(annOnA);
      expect(onA.keys, [null], reason: 'the old phone still owns its games');
      expect(
        onA[null],
        hasLength(40),
        reason: 'its own history must not come back to it as somebody else\'s',
      );
    });
  });
}
