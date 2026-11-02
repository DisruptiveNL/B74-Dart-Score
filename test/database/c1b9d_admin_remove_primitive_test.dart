import 'dart:convert';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d admin REMOVE primitive, not transport-connected', () {
    useInMemoryDatabase();

    test('refuses missing exact intent without modifying match', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'official-x',
        'payload': jsonEncode({'division': 'Eredivisie'}),
        'received_at': 1,
      });
      await expectLater(
        helper.purgeStagedAdminRemoveForVerifiedCoordinator(
          matchId: 'official-x', revision: 1, authorizationId: 'unknown',
        ), throwsStateError,
      );
      expect(await db.query('competition_inbox'), hasLength(1));
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
    });

    test('exact REMOVE retry after completed transaction is idempotent', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'official-retry',
        'payload': jsonEncode({'division': 'Eredivisie'}),
        'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(
        matchId: 'official-retry', revision: 1, scope: 'official',
        statisticsMode: 'remove', authorizationId: 'auth-retry',
      );
      expect(await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
        matchId: 'official-retry', revision: 1,
        authorizationId: 'auth-retry',
      ), 'purged');
      expect(await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
        matchId: 'official-retry', revision: 1,
        authorizationId: 'auth-retry',
      ), 'already_purged');
      expect(await db.query('competition_inbox'), isEmpty);
      expect(await db.query('competition_deletion_tombstones'), hasLength(1));
    });

    test('different authorization cannot replay completed REMOVE', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'official-auth',
        'payload': jsonEncode({'division': 'Eredivisie'}),
        'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(
        matchId: 'official-auth', revision: 1, scope: 'official',
        statisticsMode: 'remove', authorizationId: 'auth-original',
      );
      await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
        matchId: 'official-auth', revision: 1,
        authorizationId: 'auth-original',
      );
      await expectLater(
        helper.purgeStagedAdminRemoveForVerifiedCoordinator(
          matchId: 'official-auth', revision: 1,
          authorizationId: 'auth-other',
        ), throwsStateError,
      );
    });

    test('retain is refused and preserves all data', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'official-y',
        'payload': jsonEncode({'division': 'Eredivisie'}),
        'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(
        matchId: 'official-y', revision: 1, scope: 'official',
        statisticsMode: 'retain', authorizationId: 'auth-y',
      );
      await expectLater(
        helper.purgeStagedAdminRemoveForVerifiedCoordinator(
          matchId: 'official-y', revision: 1, authorizationId: 'auth-y',
        ), throwsStateError,
      );
      expect(await db.query('competition_inbox'), hasLength(1));
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
    });

    test('remove only selected match, records durable tombstone', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      for (final id in ['official-a', 'official-b']) {
        await db.insert('competition_inbox', {
          'match_id': id,
          'payload': jsonEncode({'division': 'Eredivisie'}),
          'received_at': 1,
        });
      }
      await helper.stageAdminDeletionIntent(
        matchId: 'official-a', revision: 1, scope: 'official',
        statisticsMode: 'remove', authorizationId: 'auth-a',
      );
      expect(await helper.purgeStagedAdminRemoveForVerifiedCoordinator(
        matchId: 'official-a', revision: 1, authorizationId: 'auth-a',
      ), 'purged');
      expect((await db.query('competition_inbox')).single['match_id'], 'official-b');
      final tombstone = (await db.query('competition_deletion_tombstones')).single;
      expect(tombstone['match_id'], 'official-a');
      expect(tombstone['cleaned_at'], isNotNull);
      expect(await db.query('competition_admin_deletion_intents'), hasLength(1));
    });
  });
}
