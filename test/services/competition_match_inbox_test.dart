import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/competition_match_inbox.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  useInMemoryDatabase();

  Map<String, dynamic> packet({String matchId = 'match-42'}) => {
    'type': CompetitionSyncContract.type,
    'version': CompetitionSyncContract.version,
    'matchId': matchId,
    'home': {'id': 'h', 'name': 'Home'},
    'away': {'id': 'a', 'name': 'Away'},
    'startingScore': 501,
    'singles': [
      for (var i = 1; i <= 4; i++)
        {
          'slot': i,
          'homePlayer': {'id': 'h$i', 'name': 'Home $i', 'bondNumber': 'H$i'},
          'awayPlayer': {'id': 'a$i', 'name': 'Away $i', 'bondNumber': 'A$i'},
        },
    ],
  };

  test('imports once, persists bond numbers and Bull defaults', () async {
    final inbox = CompetitionMatchInbox();
    final json = CompetitionSyncContract.encode(packet());
    expect(await inbox.receive(json), isTrue);
    expect(await inbox.receive(json), isFalse);
    final db = await DbHelper.instance.db;
    expect((await db.query('players')).length, 8);
    expect((await db.query('competition_player_links')).length, 8);
    expect(
      (await db.query('players')).every((p) => p['favorite_doubles'] == 'Bull'),
      isTrue,
    );
    expect((await db.query('competition_inbox')).length, 1);
  });

  test('rejects changed lineup without modifying stored match', () async {
    final inbox = CompetitionMatchInbox();
    await inbox.receive(CompetitionSyncContract.encode(packet()));
    final changed = packet();
    (changed['singles'] as List)[0]['homePlayer']['name'] = 'Different';
    await expectLater(
      inbox.receive(CompetitionSyncContract.encode(changed)),
      throwsStateError,
    );
    final db = await DbHelper.instance.db;
    expect((await db.query('competition_inbox')).length, 1);
    expect((await db.query('players')).length, 8);
  });

  test(
    'same name with different bond numbers creates distinct players',
    () async {
      final data = packet();
      (data['singles'] as List)[0]['homePlayer']['name'] = 'Jan';
      (data['singles'] as List)[0]['awayPlayer']['name'] = 'Jan';
      final inbox = CompetitionMatchInbox();
      expect(await inbox.receive(CompetitionSyncContract.encode(data)), isTrue);
      final db = await DbHelper.instance.db;
      final links = await db.query('competition_player_links');
      final home = links.singleWhere((r) => r['external_player_id'] == 'h1');
      final away = links.singleWhere((r) => r['external_player_id'] == 'a1');
      expect(home['player_id'], isNot(away['player_id']));
      expect(
        (await db.query(
          'players',
          where: 'name = ?',
          whereArgs: ['Jan'],
        )).length,
        2,
      );
    },
  );

  test(
    'same bond with new external ID reuses player and updates name',
    () async {
      final inbox = CompetitionMatchInbox();
      await inbox.receive(CompetitionSyncContract.encode(packet()));
      final db = await DbHelper.instance.db;
      final original = (await db.query(
        'competition_player_links',
        where: 'external_player_id = ?',
        whereArgs: ['h1'],
      )).single;
      final playerId = original['player_id'] as int;
      await db.update(
        'players',
        {'favorite_doubles': 'D16'},
        where: 'id = ?',
        whereArgs: [playerId],
      );

      final next = packet(matchId: 'match-43');
      (next['singles'] as List)[0]['homePlayer'] = {
        'id': 'new-h1',
        'name': 'Jan de Vries',
        'bondNumber': 'H1',
      };
      expect(await inbox.receive(CompetitionSyncContract.encode(next)), isTrue);
      final alias = (await db.query(
        'competition_player_links',
        where: 'external_player_id = ?',
        whereArgs: ['new-h1'],
      )).single;
      expect(alias['player_id'], playerId);
      expect(alias['bond_number'], isNull);
      final player = (await db.query(
        'players',
        where: 'id = ?',
        whereArgs: [playerId],
      )).single;
      expect(player['name'], 'Jan de Vries');
      expect(player['favorite_doubles'], 'D16');
      expect((await db.query('players')).length, 8);
      expect(
        await inbox.receive(CompetitionSyncContract.encode(next)),
        isFalse,
      );
    },
  );

  test('rejects an external ID changing to another bond number', () async {
    final inbox = CompetitionMatchInbox();
    await inbox.receive(CompetitionSyncContract.encode(packet()));
    final changed = packet(matchId: 'match-44');
    (changed['singles'] as List)[0]['homePlayer']['bondNumber'] = 'OTHER';
    await expectLater(
      inbox.receive(CompetitionSyncContract.encode(changed)),
      throwsStateError,
    );
    final db = await DbHelper.instance.db;
    expect((await db.query('competition_inbox')).length, 1);
  });

  test('rejects alias changing bond number', () async {
    final inbox = CompetitionMatchInbox();
    await inbox.receive(CompetitionSyncContract.encode(packet()));
    final alias = packet(matchId: 'match-45');
    (alias['singles'] as List)[0]['homePlayer']['id'] = 'new-h1';
    await inbox.receive(CompetitionSyncContract.encode(alias));
    final changed = packet(matchId: 'match-46');
    (changed['singles'] as List)[0]['homePlayer'] = {
      'id': 'new-h1',
      'name': 'Other',
      'bondNumber': 'A1',
    };
    await expectLater(
      inbox.receive(CompetitionSyncContract.encode(changed)),
      throwsStateError,
    );
  });
}
