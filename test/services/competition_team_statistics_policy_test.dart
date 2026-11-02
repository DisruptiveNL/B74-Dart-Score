import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_statistics_policy.dart';

void main() {
  group('C1B9d teamwedstrijd-statistieken', () {
    test('testdivisie wordt uitgesloten', () {
      for (final division in ['test', 'TEST', ' Test ']) {
        expect(CompetitionStatisticsPolicy.countsTowardsOfficialStatistics(division), isFalse);
      }
    });
    test('andere divisies blijven officieel', () {
      for (final division in ['Eredivisie', '1e divisie', null]) {
        expect(CompetitionStatisticsPolicy.countsTowardsOfficialStatistics(division), isTrue);
      }
    });
  });
  test('officiële projectie sluit test uit en behoudt originele rijen', () {
    final rows = <Map<String, Object?>>[
      {'game_id': 'a', 'match_payload': '{"division":"test"}'},
      {'game_id': 'b', 'match_payload': '{"division":"Eredivisie"}'},
      {'game_id': 'c', 'match_payload': '{"division":" TEST "}'},
      {'game_id': 'd', 'match_payload': '{}'},
    ];
    final official = CompetitionStatisticsPolicy.officialTeamResultRows(rows);
    expect(official.map((r) => r['game_id']), ['b', 'd']);
    expect(official.every((r) => !r.containsKey('match_payload')), isTrue);
    expect(rows.first.containsKey('match_payload'), isTrue);
  });

  test('ongeldige payload wordt niet officieel meegeteld', () {
    final rows = <Map<String, Object?>>[
      {'game_id': 'broken', 'match_payload': '{broken'},
      {'game_id': 'missing', 'match_payload': null},
    ];
    expect(CompetitionStatisticsPolicy.officialTeamResultRows(rows), isEmpty);
  });

}
