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
    dir = await Directory.systemTemp.createTemp('b74_dummy_02b6_');
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = '${dir.path}/dartscore.db';
  });
  tearDown(() async {
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = null;
    await dir.delete(recursive: true);
  });

  Future<void> addMatch(Database db, String matchId) async {
    await db.insert('competition_inbox', {
      'match_id': matchId, 'payload': '{}', 'received_at': 1,
    });
  }

  test('regulatory result saves without a game link, but requires a match', () async {
    final helper = DbHelper.instance;
    final db = await helper.db;
    await addMatch(db, 'dummy-match');
    await helper.saveCompletedCompetitionSingleResult('dummy-match', 1, '{"winner":"away"}');
    expect((await helper.competitionSingleResult('dummy-match', 1))?['status'], 'completed');
    await expectLater(
      helper.saveCompletedCompetitionSingleResult('missing-match', 1, '{}'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('v34 upgrade preserves existing single result and permits regulatory result', () async {
    final helper = DbHelper.instance;
    final db = await helper.db;
    await addMatch(db, 'old-match');
    await db.execute('DROP TABLE competition_single_results');
    await db.execute(
      'CREATE TABLE competition_single_results ('
      'match_id TEXT NOT NULL, slot INTEGER NOT NULL, '
      "status TEXT NOT NULL DEFAULT 'completed', "
      'payload TEXT NOT NULL, acknowledged_at INTEGER, '
      'PRIMARY KEY(match_id, slot), '
      'FOREIGN KEY(match_id, slot) REFERENCES competition_game_links(match_id, slot))',
    );
    await db.insert('games', {'start_score': 501, 'created_at': 1});
    final gameId = (await db.rawQuery('SELECT id FROM games ORDER BY id DESC LIMIT 1')).single['id'];
    await db.insert('competition_game_links', {
      'match_id': 'old-match', 'slot': 1, 'game_id': gameId,
      'starter_external_id': 'player-a',
    });
    await db.insert('competition_single_results', {
      'match_id': 'old-match', 'slot': 1, 'status': 'archived',
      'payload': '{"preserved":true}', 'acknowledged_at': 1234,
    });
    await db.setVersion(34);
    await DbHelper.debugReset();
    final upgraded = await helper.db;
    expect(await upgraded.getVersion(), 35);
    final old = await helper.competitionSingleResult('old-match', 1);
    expect(old?['payload'], '{"preserved":true}');
    expect(old?['status'], 'archived');
    expect(old?['acknowledged_at'], 1234);
    await helper.saveCompletedCompetitionSingleResult('old-match', 2, '{"dummy":true}');
    expect(await helper.competitionSingleResult('old-match', 2), isNotNull);
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
