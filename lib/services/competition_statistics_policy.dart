import 'dart:convert';

/// C1B9d: centrale, deterministische uitsluitingsregel voor officiële statistieken.
///
/// Dit is een beleidsfunctie. De aanroepplaatsen bij database, statistiekaggregatie
/// en export moeten afzonderlijk worden aangesloten voordat de functie actief is.
abstract final class CompetitionStatisticsPolicy {
  static bool isTestDivision(String? division) =>
      division?.trim().toLowerCase() == 'test';

  static bool countsTowardsOfficialStatistics(String? division) =>
      !isTestDivision(division);

  /// Strikte toelatingscontrole voor publicatie naar Statistics Library.
  /// Anders dan bestaande lokale rapportage is onbekend NOOIT officieel.
  /// Dit is uitsluitend de publicatiepoort; geen wijziging aan bestaande
  /// teamrapportages of wedstrijdsynchronisatie.
  static bool eligibleForStatisticsPublication(String? division) {
    final value = division?.trim().toLowerCase();

    if (value == null || value.isEmpty) return false;

    // Alle testvarianten uitsluiten.
    if (RegExp(r'^test', caseSensitive: false).hasMatch(value)) {
      return false;
    }

    return true;
  }

  /// Filter an official report projection using the saved inbox payload.
  /// The result outbox and live scoreboard remain unfiltered.
  static List<Map<String, Object?>> officialTeamResultRows(
    Iterable<Map<String, Object?>> rows,
  ) {
    return rows
        .where((row) {
          try {
            final packet = jsonDecode(row['match_payload'] as String);
            if (packet is! Map<String, dynamic>) return false;
            return countsTowardsOfficialStatistics(
              packet['division'] as String?,
            );
          } on FormatException {
            return false;
          } on TypeError {
            return false;
          }
        })
        .map((row) {
          final result = Map<String, Object?>.from(row);
          result.remove('match_payload');
          return result;
        })
        .toList(growable: false);
  }
}
