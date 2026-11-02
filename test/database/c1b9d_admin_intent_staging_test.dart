import 'package:dartscore_app/database/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_db.dart';

void main() {
  group('C1B9d admin intent staging (non-destructive)', () {
    useInMemoryDatabase();

    Future<String> stage({String match = 'official-1', int revision = 1,
      String mode = 'remove', String grant = 'grant-1'}) =>
        DbHelper.instance.stageAdminDeletionIntent(
          matchId: match, revision: revision, scope: 'official',
          statisticsMode: mode, authorizationId: grant);

    test('durably stages exact request without TEST tombstone', () async {
      expect(await stage(), 'staged');
      expect(await stage(), 'already_staged');
      final db = await DbHelper.instance.db;
      expect((await db.query('competition_admin_deletion_intents')).length, 1);
      expect(await db.query('competition_deletion_tombstones'), isEmpty);
      // In-memory SQLite is destroyed when its connection closes.
      // Reopen persistence must be tested separately using a file-backed DB.
    });

    test('rejects changed statistics mode, revision and reused grant', () async {
      await stage();
      expect(() => stage(mode: 'retain'), throwsStateError);
      expect(() => stage(revision: 2), throwsStateError);
      expect(() => stage(match: 'official-2'), throwsStateError);
    });

    test('rejects malformed requests before writing', () async {
      expect(() => stage(grant: ''), throwsFormatException);
      expect(() => stage(match: ' official-1'), throwsFormatException);
      expect(() => stage(revision: 0), throwsFormatException);
      final db = await DbHelper.instance.db;
      expect(await db.query('competition_admin_deletion_intents'), isEmpty);
    });
  });
}
