import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('competition single result outbox', () {
    useInMemoryDatabase();

    Future<void> setupSingle() async {
      final helper = DbHelper.instance;
      final db = await helper.db;
      await db.insert('competition_inbox', {
        'match_id': 'match-1',
        'payload': '{}',
        'received_at': 1,
      });
      await helper.insertGame(
        Game(startScore: 501, createdAt: DateTime.now()),
        const [],
        competitionMatchId: 'match-1',
        competitionSlot: 1,
        starterExternalId: 'player-a',
      );
    }

    test(
      'result survives reads and can be archived after matching ack',
      () async {
        await setupSingle();
        final helper = DbHelper.instance;
        await helper.saveCompletedCompetitionSingleResult(
          'match-1',
          1,
          '{"score":"3-1"}',
        );
        expect(
          (await helper.competitionSingleResult('match-1', 1))!['status'],
          'completed',
        );
        expect(
          await helper.beginCompetitionSingleResultSend('match-1', 1),
          isTrue,
        );
        expect(
          await helper.acknowledgeCompetitionSingleResult(
            'match-1',
            1,
            '{"score":"WRONG"}',
          ),
          isFalse,
        );
        expect(
          await helper.acknowledgeCompetitionSingleResult(
            'match-1',
            1,
            '{"score":"3-1"}',
          ),
          isTrue,
        );
        expect(
          (await helper.competitionSingleResult('match-1', 1))!['status'],
          'archived',
        );
        expect(
          await helper.acknowledgeCompetitionSingleResult(
            'match-1',
            1,
            '{"score":"3-1"}',
          ),
          isTrue,
        );
        await expectLater(
          helper.saveCompletedCompetitionSingleResult(
            'match-1',
            1,
            '{"score":"3-2"}',
          ),
          throwsStateError,
        );
      },
    );

    test('failed transfer can retry, but cannot archive before send', () async {
      await setupSingle();
      final helper = DbHelper.instance;
      await helper.saveCompletedCompetitionSingleResult(
        'match-1',
        1,
        '{"score":"3-0"}',
      );
      expect(
        await helper.acknowledgeCompetitionSingleResult(
          'match-1',
          1,
          '{"score":"3-0"}',
        ),
        isFalse,
      );
      expect(
        await helper.beginCompetitionSingleResultSend('match-1', 1),
        isTrue,
      );
      expect(
        await helper.beginCompetitionSingleResultSend('match-1', 1),
        isFalse,
      );
      expect(
        await helper.failCompetitionSingleResultSend('match-1', 1),
        isTrue,
      );
      expect(
        await helper.beginCompetitionSingleResultSend('match-1', 1),
        isTrue,
      );
    });
  });
}
