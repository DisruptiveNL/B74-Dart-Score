import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/b74_doubles_result_contract.dart';
import '../../lib/services/competition_dummy_identity.dart';

void main() {
  Map<String, dynamic> result(String kind) {
    final beer = kind == 'beer1001';
    final home = 'home-team';
    final away = 'away-team';
    return {
      'type': B74DoublesResultContract.type,
      'version': B74DoublesResultContract.version,
      'kind': kind,
      'matchId': 'match-1',
      'gameId': beer ? 'match-1:beer1001:1' : 'match-1:doubles701:1',
      'slot': 1,
      'revision': 1,
      'resultId': B74DoublesResultContract.resultId('match-1', 1, kind: kind),
      'homeTeamId': home,
      'awayTeamId': away,
      'bestOf': beer ? 1 : 3,
      'homeLegs': beer ? 1 : 2,
      'awayLegs': 0,
      'winnerTeamId': home,
      'players': [
        for (var i = 0; i < (beer ? 8 : 4); i++)
          {
            'playerId': i == 0
                ? CompetitionDummyIdentity.participantId(home)
                : 'real-$i',
            'teamId': i < (beer ? 4 : 2) ? home : away,
            if (i == 0) 'officialStatisticsEligible': false,
            'statistics': i == 0
                ? <String, dynamic>{}
                : <String, dynamic>{'visits': 2, 'darts': 6, 'scored': 80},
          },
      ],
    };
  }

  for (final kind in ['doubles701', 'beer1001']) {
    test('$kind accepts Dummy slot without individual stats', () {
      final value = result(kind);
      expect(B74DoublesResultContract.decode(
          B74DoublesResultContract.encode(value)), value);
      expect((value['players'] as List).length, kind == 'beer1001' ? 8 : 4);
    });

    test('$kind rejects individual Dummy statistics', () {
      final value = result(kind);
      (value['players'] as List).first['statistics'] = {'darts': 3};
      expect(() => B74DoublesResultContract.validate(value),
          throwsFormatException);
    });

    test('$kind rejects Dummy impersonation and real player exclusion', () {
      final value = result(kind);
      (value['players'] as List).first['playerId'] =
          CompetitionDummyIdentity.participantId('wrong-team');
      expect(() => B74DoublesResultContract.validate(value),
          throwsFormatException);
      final another = result(kind);
      (another['players'] as List)[1]['officialStatisticsEligible'] = false;
      expect(() => B74DoublesResultContract.validate(another),
          throwsFormatException);
    });
  }
}
