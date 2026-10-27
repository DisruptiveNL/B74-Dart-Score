import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_match_catalog.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';

void main() {
  test('singles are ordered by slot, regardless of packet order', () {
    final singles = List.generate(4, (i) => {
      'slot': 4 - i,
      'homePlayer': {'id': 'h$i', 'name': 'Home $i', 'bondNumber': '10$i'},
      'awayPlayer': {'id': 'a$i', 'name': 'Away $i', 'bondNumber': '20$i'},
    });
    final packet = {
      'type': CompetitionSyncContract.type,
      'version': CompetitionSyncContract.version,
      'matchId': 'm1',
      'home': {'id': 'home', 'name': 'Home team'},
      'away': {'id': 'away', 'name': 'Away team'},
      'singles': singles,
      'startingScore': 501,
      'x01Rules': CompetitionX01Rules.defaults(),
    };
    final match = CompetitionMatchSummary.fromPacket(packet, receivedAt: 1);
    expect(match.singles.map((s) => s.slot), [1, 2, 3, 4]);
    expect(match.singles.first.homeBond, '103');
    expect(match.rules['bullDecidingLeg'], true);
  });
}
