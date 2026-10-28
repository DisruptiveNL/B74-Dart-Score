import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('upgrading a database that predates the bot tier', () {
    late Directory dir;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // A file, because the migration has to survive closing the connection and
      // an in-memory database does not.
      dir = await Directory.systemTemp.createTemp('dartscore_bot_level');
      DbHelper.debugDatabasePath = '${dir.path}/dartscore.db';
      await DbHelper.debugReset();
    });

    tearDown(() async {
      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = null;
      await dir.delete(recursive: true);
    });

    /// Winds a current database back to how version 22 left it, so the
    /// upgrade runs against a players table that never had the column.
    Future<void> windBackTo22(Database db) async {
      await db.execute('ALTER TABLE players DROP COLUMN bot_ordinal');
      await db.execute('ALTER TABLE players DROP COLUMN bot_level');
      await db.execute('PRAGMA user_version = 22');
    }

    /// Winds a current database back to how version 23 left it: bots had a
    /// tier but no number yet.
    Future<void> windBackTo23(Database db) async {
      await db.execute('ALTER TABLE players DROP COLUMN bot_ordinal');
      await db.execute('PRAGMA user_version = 23');
    }

    test('keeps every player it held and reads them all as people', () async {
      final fresh = await DbHelper.instance.db;
      await fresh.insert('players', {'name': 'Nik', 'uuid': 'u-1'});
      await fresh.insert('players', {
        'name': 'Old',
        'uuid': 'u-2',
        'is_deleted': 1,
      });
      await windBackTo22(fresh);
      await DbHelper.debugReset();

      final players = await DbHelper.instance.getPlayers();
      final bots = await DbHelper.instance.getBots();

      expect(players.map((p) => p.name), ['Nik']);
      expect(players.single.isBot, isFalse);
      expect(bots, isEmpty);
      expect(
        (await DbHelper.instance.getPlayersById()).length,
        2,
        reason: 'the deleted one stays for the history',
      );
    });

    test(
      'numbers the bots it already had as the first of their tier',
      () async {
        final fresh = await DbHelper.instance.db;
        await windBackTo23(fresh);
        await fresh.insert('players', {
          'name': BotLevel.pro.storedName,
          'uuid': BotLevel.pro.uuid,
          'bot_level': BotLevel.pro.index,
        });
        await fresh.insert('players', {'name': 'Nik', 'uuid': 'u-1'});
        await DbHelper.debugReset();

        final bots = await DbHelper.instance.getBots();
        final people = await DbHelper.instance.getPlayers();

        expect(bots.single.botOrdinal, 1);
        expect(
          bots.single.uuid,
          BotLevel.pro.uuidFor(1),
          reason: 'the first bot keeps the uuid it had before the numbering',
        );
        expect(people.single.botOrdinal, isNull);
      },
    );

    test('takes a bot row once upgraded', () async {
      final fresh = await DbHelper.instance.db;
      await windBackTo22(fresh);
      await DbHelper.debugReset();

      final id = await DbHelper.instance.insertPlayer(
        Player(
          name: BotLevel.rookie.storedName,
          uuid: BotLevel.rookie.uuid,
          botLevel: BotLevel.rookie,
        ),
      );

      expect((await DbHelper.instance.getBots()).single.id, id);
      expect((await DbHelper.instance.getBots()).single.botOrdinal, 1);
      expect(await DbHelper.instance.getPlayers(), isEmpty);
      expect(
        (await DbHelper.instance.getPlayersById())[id]?.botLevel,
        BotLevel.rookie,
      );
    });
  });
}
