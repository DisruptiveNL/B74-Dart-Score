import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d TEST cleanup', () {
    useInMemoryDatabase();

    test('refuses purge without durable tombstone', () async {
      expect(() => DbHelper.instance.purgeTombstonedTestMatch('test-1'),
          throwsStateError);
    });

    test('refuses official deletion even when tombstoned', () async {
      final helper = DbHelper.instance;
      await helper.receiveCompetitionDeletion(
        matchId: 'official-1', revision: 1, division: 'Eredivisie',
        retainOfficialStatistics: false,
      );
      expect(() => helper.purgeTombstonedTestMatch('official-1'),
          throwsStateError);
    });

    test('cleans test inbox and team results, retains tombstone', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await helper.receiveCompetitionDeletion(
        matchId: 'test-1', revision: 1, division: 'test',
        retainOfficialStatistics: false,
      );
      await db.insert('competition_inbox', {
        'match_id': 'test-1', 'payload': '{}', 'received_at': 1,
      });
      await db.insert('competition_team_inbox', {
        'game_id': 'team-1', 'match_id': 'test-1',
        'kind': 'doubles701', 'slot': 1, 'revision': 1,
        'payload': '{}', 'received_at': 1,
      });
      await db.insert('competition_doubles_results', {
        'game_id': 'team-1', 'match_id': 'test-1', 'slot': 1,
        'revision': 1, 'payload': '{}',
      });
      await db.insert('competition_doubles_events', {
        'game_id': 'team-1', 'sequence': 1, 'event_json': '{}',
        'created_at': 1,
      });
      expect(await helper.isTombstonedTestMatchCleaned('test-1', 1), isFalse);
      expect(await helper.purgeTombstonedTestMatch('test-1'), 'purged');
      expect(await helper.isTombstonedTestMatchCleaned('test-1', 1), isTrue);
      expect(await helper.isTombstonedTestMatchCleaned('test-1', 2), isFalse);
      expect(await helper.purgeTombstonedTestMatch('test-1'), 'purged');
      expect(await helper.isTombstonedTestMatchCleaned('test-1', 1), isTrue);
      expect(await helper.isTombstonedTestMatchCleaned('test-1', 2), isFalse);
      for (final table in [
        'competition_inbox', 'competition_team_inbox',
        'competition_doubles_results', 'competition_doubles_events',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      expect((await db.query('competition_deletion_tombstones')).length, 1);
    });
  });
}
