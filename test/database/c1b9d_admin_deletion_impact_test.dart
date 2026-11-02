import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d admin deletion impact is non-destructive', () {
    useInMemoryDatabase();

    test('requires an exact staged intent', () async {
      final helper = DbHelper.instance;
      await helper.stageAdminDeletionIntent(
        matchId: 'official-1', revision: 4, scope: 'official',
        statisticsMode: 'retain', authorizationId: 'auth-1',
      );
      expect(() => helper.inspectAdminDeletionImpact(
        matchId: 'official-1', revision: 5, authorizationId: 'auth-1',
      ), throwsStateError);
      expect(() => helper.inspectAdminDeletionImpact(
        matchId: 'official-1', revision: 4, authorizationId: 'auth-other',
      ), throwsStateError);
      final impact = await helper.inspectAdminDeletionImpact(
        matchId: 'official-1', revision: 4, authorizationId: 'auth-1',
      );
      expect(impact['statisticsMode'], 'retain');
      expect(impact['executionAllowed'], false);
      expect(impact['dartThrows'], 0);
      final db = await helper.db;
      expect(await db.query('competition_admin_deletion_intents'), hasLength(1));
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
    });

    test('inspection never removes staged rows', () async {
      final helper = DbHelper.instance;
      await helper.stageAdminDeletionIntent(
        matchId: 'official-2', revision: 1, scope: 'official',
        statisticsMode: 'remove', authorizationId: 'auth-2',
      );
      final first = await helper.inspectAdminDeletionImpact(
        matchId: 'official-2', revision: 1, authorizationId: 'auth-2',
      );
      final second = await helper.inspectAdminDeletionImpact(
        matchId: 'official-2', revision: 1, authorizationId: 'auth-2',
      );
      expect(first, second);
      expect(first['executionAllowed'], false);
      expect(await helper.stageAdminDeletionIntent(
        matchId: 'official-2', revision: 1, scope: 'official',
        statisticsMode: 'remove', authorizationId: 'auth-2',
      ), 'already_staged');
    });
  });
}
