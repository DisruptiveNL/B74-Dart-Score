import 'competition_single_result_contract.dart';
import 'competition_statistics_policy.dart';

/// Pure P1.4a mapping only: no network, storage, or side effects.
///
/// [officialMatchVerified] must come from a trusted provenance check, not
/// merely from the division name or an unchecked field in an inbound packet.
abstract final class CompetitionSinglePublishMapper {
  static Map<String, dynamic>? map({
    required Map<String, dynamic> completedResult,
    required String? division,
    required String? matchType,
    required String? homeBondNumber,
    required String? awayBondNumber,
    required bool officialMatchVerified,
    int revision = 1,
  }) {
    if (!officialMatchVerified ||
        !CompetitionStatisticsPolicy.eligibleForStatisticsPublication(
          division,
        )) {
      return null;
    }
    if (matchType != 'regular' && matchType != 'cup') {
      return null;
    }
    if (revision < 1) throw const FormatException('Ongeldige revisie');
    CompetitionSingleResultContract.validate(completedResult);
    final stats = completedResult['statistics'] as Map<String, dynamic>;
    final home = stats['home'];
    final away = stats['away'];
    // Reglementaire dummy-resultaten bevatten geen echte spelstatistieken.
    if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
      return null;
    }
    final homeBond = homeBondNumber?.trim();
    final awayBond = awayBondNumber?.trim();
    if (homeBond == null ||
        homeBond.isEmpty ||
        awayBond == null ||
        awayBond.isEmpty ||
        homeBond.toUpperCase() == 'DUMMY' ||
        awayBond.toUpperCase() == 'DUMMY' ||
        homeBond == awayBond) {
      return null;
    }

    Map<String, dynamic> playerStats(Map<String, dynamic> source) {
      final mapped = <String, dynamic>{};
      for (final field in [
        'visits',
        'darts',
        'scored',
        'highestVisit',
        'hundreds',
        'oneForties',
        'oneEighties',
      ]) {
        final value = source[field];
        if (value is! int || value < 0) {
          throw FormatException('Ongeldige statistiek: $field');
        }
        mapped[field] = value;
      }
      final average = source['average3Dart'];
      if (average is! num || !average.isFinite || average < 0) {
        throw const FormatException('Ongeldig 3-dartgemiddelde');
      }
      mapped['average3Dart'] = average.toDouble();
      // firstNineAverage is optional in the server contract. Dart Score's
      // persisted result does not currently include a first-nine average.
      return mapped;
    }

    final matchId = completedResult['matchId'] as String;
    final slot = completedResult['slot'] as int;
    return {
      'schemaVersion': 1,
      'eventType': 'SINGLE_PUBLISH',
      'eventId': '$matchId:single:$slot:revision:$revision',
      'matchId': matchId,
      'revision': revision,
      'matchType': matchType,
      'division': division!.trim(),
      'officialMatch': true,
      'game': {
        'kind': 'single501',
        'slot': slot,
        'result': {'status': 'completed'},
        'players': [
          {
            'playerId': completedResult['homePlayerId'],
            'bondNumber': homeBond,
            'statistics': playerStats(home),
          },
          {
            'playerId': completedResult['awayPlayerId'],
            'bondNumber': awayBond,
            'statistics': playerStats(away),
          },
        ],
      },
    };
  }
}
