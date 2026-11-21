import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_single_publish_mapper.dart';

void main() {
  Map<String, dynamic> stats() => {
    'visits': 12,
    'darts': 36,
    'scored': 501,
    'average3Dart': 41.75,
    'highestVisit': 140,
    'hundreds': 2,
    'oneForties': 1,
    'oneEighties': 0,
  };

  Map<String, dynamic> result() => {
    'type': 'b74.competition.single-result.v1',
    'version': 1,
    'resultId': 'match-1:single:2',
    'matchId': 'match-1',
    'slot': 2,
    'homePlayerId': 'home-1',
    'awayPlayerId': 'away-1',
    'homeLegs': 3,
    'awayLegs': 1,
    'winnerPlayerId': 'home-1',
    'statistics': {'home': stats(), 'away': stats()},
  };

  Map<String, dynamic>? map({
    String? division = 'Eredivisie',
    bool verified = true,
    String? homeBond = 'B001',
    String? awayBond = 'B002',
    String? matchType = 'regular',
    Map<String, dynamic>? source,
  }) => CompetitionSinglePublishMapper.map(
    completedResult: source ?? result(),
    division: division,
    matchType: matchType,
    homeBondNumber: homeBond,
    awayBondNumber: awayBond,
    officialMatchVerified: verified,
  );

  test('maps real completed single with stable event identity', () {
    final payload = map()!;
    expect(payload['eventType'], 'SINGLE_PUBLISH');
    expect(payload['eventId'], 'match-1:single:2:revision:1');
    expect(payload['officialMatch'], true);
    expect(payload['game']['result']['status'], 'completed');
    expect(payload['game']['players'][0]['bondNumber'], 'B001');
    expect(payload['game']['players'][0]['statistics']['oneForties'], 1);
    expect(
      payload['game']['players'][0]['statistics'].containsKey(
        'firstNineAverage',
      ),
      false,
    );
    expect(map(), payload);
  });

  test('requires separately verified official provenance', () {
    expect(map(verified: false), isNull);
  });

  for (final division in <String?>[
    null,
    '',
    ' TEST ',
    'Testklasse',
    'test - oefenwedstrijd',
  ]) {
    test(
      'excludes division $division',
      () => expect(map(division: division), isNull),
    );
  }

  test('excludes dummy and regulatory result', () {
    final regulatory = result()..['statistics'] = {'home': null, 'away': null};
    expect(map(source: regulatory), isNull);
    expect(map(homeBond: 'DUMMY'), isNull);
  });

  test('rejects unknown match type and missing bonds', () {
    expect(map(matchType: null), isNull);
    expect(map(homeBond: null), isNull);
    expect(map(awayBond: 'B001'), isNull);
  });

  test('rejects malformed real statistics instead of inventing values', () {
    final malformed = result();
    (malformed['statistics']['home'] as Map<String, dynamic>).remove('visits');
    expect(() => map(source: malformed), throwsFormatException);
  });
}
