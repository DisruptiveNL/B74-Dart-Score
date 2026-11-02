import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_match_deletion_contract.dart';

void main() {
  Map<String, Object> request({
    String division = 'test',
    bool retain = false,
    int revision = 1,
  }) => <String, Object>{
        'type': 'b74.match.deletion.request',
        'version': 1,
        'matchId': 'match-123',
        'revision': revision,
        'division': division,
        'retainOfficialStatistics': retain,
      };

  test('testdivisie mag nooit officiële statistieken behouden', () {
    expect(
      () => CompetitionMatchDeletionContract.decode(
        jsonEncode(request(division: ' TEST ', retain: true)),
      ),
      throwsFormatException,
    );
  });

  test('geldig testverzoek wordt als intentie geaccepteerd', () {
    final parsed = CompetitionMatchDeletionContract.decode(
      jsonEncode(request()),
    );
    expect(parsed['matchId'], 'match-123');
    expect(parsed['retainOfficialStatistics'], false);
  });

  test('officieel verzoek mag statistieken behouden', () {
    final parsed = CompetitionMatchDeletionContract.decode(
      jsonEncode(request(division: 'Eredivisie', retain: true)),
    );
    expect(parsed['retainOfficialStatistics'], true);
  });

  test('onjuiste revisie en ontbrekende velden worden geweigerd', () {
    expect(
      () => CompetitionMatchDeletionContract.decode(
        jsonEncode(request(revision: 0)),
      ),
      throwsFormatException,
    );
    expect(
      () => CompetitionMatchDeletionContract.decode(
        jsonEncode({'type': 'b74.match.deletion.request'}),
      ),
      throwsFormatException,
    );
  });
}
