import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/competition_match_inbox.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  useInMemoryDatabase();

  Map<String, dynamic> packet() => {
    'type': CompetitionSyncContract.type,
    'version': CompetitionSyncContract.version,
    'matchId': 'match-42',
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
}
