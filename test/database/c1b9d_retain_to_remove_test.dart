import 'dart:convert';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d RETAIN to REMOVE', () {
    useInMemoryDatabase();

    test('new grant removes retained match but preserves unrelated match', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      for (final id in ['retained', 'untouched']) {
        await db.insert('competition_inbox', {
          'match_id': id,
          'payload': jsonEncode({'division': 'Eredivisie'}),
          'received_at': 1,
        });
      }
      await helper.stageAdminDeletionIntent(matchId: 'retained', revision: 1,
          scope: 'official', statisticsMode: 'retain', authorizationId: 'grant-retain');
      expect(await helper.retainStagedAdminMatchForVerifiedCoordinator(
          matchId: 'retained', revision: 1, authorizationId: 'grant-retain'), 'retained');
      expect(await helper.stageAdminDeletionIntent(matchId: 'retained', revision: 1,
          scope: 'official', statisticsMode: 'remove', authorizationId: 'grant-remove'), 'staged');
      expect(await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
          matchId: 'retained', revision: 1, authorizationId: 'grant-remove'), 'purged');
      expect(await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
          matchId: 'retained', revision: 1, authorizationId: 'grant-remove'), 'already_purged');
      expect((await db.query('competition_inbox')).single['match_id'], 'untouched');
      final tombstone = (await db.query('competition_deletion_tombstones')).single;
      expect(tombstone['retain_official_statistics'], 0);
      expect(await db.query('competition_admin_deletion_intents'), hasLength(2));
      expect((await helper.readAdminDeletionStatus(matchId: 'retained', revision: 1,
          authorizationId: 'grant-retain'))['status'], 'completed');
      expect((await helper.readAdminDeletionStatus(matchId: 'retained', revision: 1,
          authorizationId: 'grant-remove'))['status'], 'completed');
    });

    test('cannot stage REMOVE before RETAIN completed', () async {
      final helper = DbHelper.instance;
      await helper.stageAdminDeletionIntent(matchId: 'm', revision: 1,
          scope: 'official', statisticsMode: 'retain', authorizationId: 'r');
      await expectLater(helper.stageAdminDeletionIntent(matchId: 'm', revision: 1,
          scope: 'official', statisticsMode: 'remove', authorizationId: 'd'), throwsStateError);
    });

    test('cannot reuse the RETAIN authorization for REMOVE', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'm', 'payload': jsonEncode({'division': 'Eredivisie'}), 'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(matchId: 'm', revision: 1,
          scope: 'official', statisticsMode: 'retain', authorizationId: 'r');
      await helper.retainStagedAdminMatchForVerifiedCoordinator(
          matchId: 'm', revision: 1, authorizationId: 'r');
      await expectLater(helper.stageAdminDeletionIntent(matchId: 'm', revision: 1,
          scope: 'official', statisticsMode: 'remove', authorizationId: 'r'), throwsStateError);
      expect((await db.query('competition_inbox')), hasLength(1));
    });
  });
}
