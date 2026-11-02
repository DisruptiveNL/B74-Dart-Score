import 'dart:convert';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d durable admin status (read only)', () {
    useInMemoryDatabase();

    test('staging never claims completed execution', () async {
      final helper = DbHelper.instance;
      await helper.stageAdminDeletionIntent(matchId: 'm1', revision: 1,
          scope: 'official', statisticsMode: 'retain', authorizationId: 'a1');
      final receipt = await helper.readAdminDeletionStatus(
          matchId: 'm1', revision: 1, authorizationId: 'a1');
      expect(receipt['status'], 'staged');
      expect(receipt['executionCompleted'], false);
    });

    test('completed RETAIN is recognized without modifying statistics', () async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {'match_id': 'm2',
        'payload': jsonEncode({'division': 'Eredivisie'}), 'received_at': 1});
      await helper.stageAdminDeletionIntent(matchId: 'm2', revision: 1,
          scope: 'official', statisticsMode: 'retain', authorizationId: 'a2');
      await helper.retainStagedAdminMatchForVerifiedCoordinator(
          matchId: 'm2', revision: 1, authorizationId: 'a2');
      final receipt = await helper.readAdminDeletionStatus(
          matchId: 'm2', revision: 1, authorizationId: 'a2');
      expect(receipt['status'], 'completed');
      expect(receipt['executionCompleted'], true);
      expect(await db.query('competition_inbox'), hasLength(1));
    });

    test('different authorization cannot read receipt', () async {
      final helper = DbHelper.instance;
      await helper.stageAdminDeletionIntent(matchId: 'm3', revision: 1,
          scope: 'official', statisticsMode: 'remove', authorizationId: 'a3');
      await expectLater(helper.readAdminDeletionStatus(
          matchId: 'm3', revision: 1, authorizationId: 'wrong'), throwsStateError);
    });
  });
}
