import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/b74_doubles_result_contract.dart';

void main() {
  test('beer result ID is separate from doubles slot 1', () {
    expect(B74DoublesResultContract.resultId('m', 1, kind: 'beer1001'), 'm:beer:1');
    expect(B74DoublesResultContract.resultId('m', 1), 'm:doubles:1');
  });
  test('beer result requires eight players and a single leg', () {
    final players = List.generate(8, (i) => {
      'playerId': 'p$i', 'teamId': i < 4 ? 'h' : 'a', 'statistics': <String, dynamic>{}
    });
    final value = <String, dynamic>{
      'type': B74DoublesResultContract.type,
      'version': B74DoublesResultContract.version,
      'kind': 'beer1001', 'resultId': 'm:beer:1',
      'matchId': 'm', 'gameId': 'm:beer1001:1', 'slot': 1,
      'revision': 1, 'homeTeamId': 'h', 'awayTeamId': 'a',
      'bestOf': 1, 'homeLegs': 1, 'awayLegs': 0,
      'winnerTeamId': 'h', 'players': players,
    };
    expect(() => B74DoublesResultContract.validate(value), returnsNormally);
    value['players'] = players.take(4).toList();
    expect(() => B74DoublesResultContract.validate(value), throwsFormatException);
  });
}
