import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('b74_stats_outbox_');
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = '${dir.path}/dartscore.db';
  });
  tearDown(() async {
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = null;
    await dir.delete(recursive: true);
  });

  test('pending survives database reopen and ACK is durable', () async {
    final helper = DbHelper.instance;
    await helper.enqueueStatisticsSingle(
      matchId: 'm1',
      slot: 1,
      revision: 1,
      payload: '{"single":1}',
    );
    expect(await helper.pendingStatisticsSingles(), hasLength(1));
    await DbHelper.debugReset();
    expect(await helper.pendingStatisticsSingles(), hasLength(1));
    expect(
      await helper.acknowledgeStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 1,
      ),
      isTrue,
    );
    await DbHelper.debugReset();
    expect(await helper.pendingStatisticsSingles(), isEmpty);
  });

  test(
    'duplicate revision preserves ACK; conflicting payload rejected',
    () async {
      final helper = DbHelper.instance;
      await helper.enqueueStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 1,
        payload: 'A',
      );
      await helper.acknowledgeStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 1,
      );
      await helper.enqueueStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 1,
        payload: 'A',
      );
      expect(await helper.pendingStatisticsSingles(), isEmpty);
      await expectLater(
        helper.enqueueStatisticsSingle(
          matchId: 'm1',
          slot: 1,
          revision: 1,
          payload: 'B',
        ),
        throwsStateError,
      );
    },
  );

  test('new revision becomes pending; stale ACK is ignored', () async {
    final helper = DbHelper.instance;
    await helper.enqueueStatisticsSingle(
      matchId: 'm1',
      slot: 1,
      revision: 1,
      payload: 'A',
    );
    await helper.enqueueStatisticsSingle(
      matchId: 'm1',
      slot: 1,
      revision: 2,
      payload: 'B',
    );
    expect(
      await helper.acknowledgeStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 1,
      ),
      isFalse,
    );
    expect(await helper.pendingStatisticsSingles(), hasLength(1));
    expect(
      await helper.acknowledgeStatisticsSingle(
        matchId: 'm1',
        slot: 1,
        revision: 2,
      ),
      isTrue,
    );
  });

  test('v35 migration preserves existing competition data', () async {
    final helper = DbHelper.instance;
    final db = await helper.db;
    await db.insert('competition_inbox', {
      'match_id': 'existing',
      'payload': '{}',
      'received_at': 1,
    });
    await db.setVersion(35);
    await DbHelper.debugReset();
    final migrated = await helper.db;
    expect(await migrated.getVersion(), 36);
    expect(
      await migrated.query(
        'competition_inbox',
        where: 'match_id = ?',
        whereArgs: ['existing'],
      ),
      hasLength(1),
    );
    expect(await migrated.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
