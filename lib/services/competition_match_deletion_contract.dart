import 'dart:convert';

/// C1B9d-3b2a: score-tablet validation of Dashboard's deletion intent.
/// Parsing does not execute a deletion or acknowledge its completion.
class CompetitionMatchDeletionContract {
  const CompetitionMatchDeletionContract._();

  static Map<String, Object> decode(String encoded) {
    final dynamic value;
    try {
      value = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('Ongeldige JSON voor verwijderverzoek');
    }
    if (value is! Map<String, dynamic> ||
        value['type'] != 'b74.match.deletion.request' ||
        value['version'] != 1 ||
        value['matchId'] is! String ||
        value['division'] is! String ||
        value['revision'] is! int ||
        value['retainOfficialStatistics'] is! bool) {
      throw const FormatException('Ongeldig verwijderverzoek');
    }
    final matchId = value['matchId'] as String;
    final division = value['division'] as String;
    final revision = value['revision'] as int;
    final retain = value['retainOfficialStatistics'] as bool;
    if (matchId.trim().isEmpty || revision < 1 ||
        (division.trim().toLowerCase() == 'test' && retain)) {
      throw const FormatException('Verwijderverzoek niet toegestaan');
    }
    return <String, Object>{
      'type': 'b74.match.deletion.request',
      'version': 1,
      'matchId': matchId,
      'division': division,
      'revision': revision,
      'retainOfficialStatistics': retain,
    };
  }
}
