import 'dart:convert';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d RETAIN primitive, coordinator-only', () {
    useInMemoryDatabase();

    test('keeps source records, tombstones and idempotently replays', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      for (final id in ['match-a', 'match-b']) {
        await db.insert('competition_inbox', {
          'match_id': id,
          'payload': jsonEncode({'division': 'Eredivisie'}),
          'received_at': 1,
        });
      }
      await helper.stageAdminDeletionIntent(
        matchId: 'match-a', revision: 1, scope: 'official',
        statisticsMode: 'retain', authorizationId: 'auth-a',
      );
      expect(await helper.retainStagedAdminMatchForVerifiedCoordinator(
        matchId: 'match-a', revision: 1, authorizationId: 'auth-a',
      ), 'retained');
      expect(await helper.retainStagedAdminMatchForVerifiedCoordinator(
        matchId: 'match-a', revision: 1, authorizationId: 'auth-a',
      ), 'already_retained');
      expect(await db.query('competition_inbox'), hasLength(2));
      final t = (await db.query('competition_deletion_tombstones')).single;
      expect(t['match_id'], 'match-a');
      expect(t['retain_official_statistics'], 1);
      expect(t['cleaned_at'], isNotNull);
    });

    test('refuses mismatched authorization without mutations', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'match-a',
        'payload': jsonEncode({'division': 'Eredivisie'}),
        'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(
        matchId: 'match-a', revision: 1, scope: 'official',
        statisticsMode: 'retain', authorizationId: 'auth-a',
      );
      await expectLater(helper.retainStagedAdminMatchForVerifiedCoordinator(
        matchId: 'match-a', revision: 1, authorizationId: 'wrong',
      ), throwsStateError);
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
      expect(await db.query('competition_inbox'), hasLength(1));
    });

    test('refuses TEST division even with a staged official intent', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'match-test',
        'payload': jsonEncode({'division': ' test '}),
        'received_at': 1,
      });
      await helper.stageAdminDeletionIntent(
        matchId: 'match-test', revision: 1, scope: 'official',
        statisticsMode: 'retain', authorizationId: 'auth-test',
      );
      await expectLater(helper.retainStagedAdminMatchForVerifiedCoordinator(
        matchId: 'match-test', revision: 1, authorizationId: 'auth-test',
      ), throwsStateError);
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
    });
  });
}
