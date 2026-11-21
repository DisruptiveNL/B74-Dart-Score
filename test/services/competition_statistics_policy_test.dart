import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_statistics_policy.dart';

void main() {
  group('P1 officiële singles-publicatie: fail closed', () {
    for (final division in [
      null,
      '',
      '  ',
      'test',
      'TEST',
      ' Test ',
      'test - ',
      'TEST -',
      '        TEST',
      'Testklasse',
      'TEST - Oefenwedstrijd',
    ]) {
      test('blokkeert ${division ?? 'null'}', () {
        expect(
          CompetitionStatisticsPolicy.eligibleForStatisticsPublication(division),
          isFalse,
        );
      });
    }
    for (final division in ['Eredivisie', '1e divisie']) {
      test('accepteert expliciete divisie $division', () {
        expect(
          CompetitionStatisticsPolicy.eligibleForStatisticsPublication(division),
          isTrue,
        );
      });
    }
  });

  group('C1B9d divisie test', () {
    for (final value in ['test', 'TEST', ' Test ', 'tEsT']) {
      test('sluit $value uit van officiële statistieken', () {
        expect(CompetitionStatisticsPolicy.isTestDivision(value), isTrue);
        expect(
          CompetitionStatisticsPolicy.countsTowardsOfficialStatistics(value),
          isFalse,
        );
      });
    }

    for (final value in [null, '', 'Eredivisie', 'Testklasse', 'contest']) {
      test('laat ${value ?? 'null'} meetellen', () {
        expect(CompetitionStatisticsPolicy.isTestDivision(value), isFalse);
        expect(
          CompetitionStatisticsPolicy.countsTowardsOfficialStatistics(value),
          isTrue,
        );
      });
    }
  });
}
