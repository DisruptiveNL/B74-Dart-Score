import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/b74_doubles_result_contract.dart';

void main() {
  Map<String, dynamic> result() => {
    'type': B74DoublesResultContract.type,
    'version': B74DoublesResultContract.version,
    'matchId': 'match-1', 'gameId': 'game-1', 'slot': 2, 'revision': 1,
    'resultId': 'match-1:doubles:2',
    'homeTeamId': 'steady', 'awayTeamId': 'test',
    'bestOf': 5, 'homeLegs': 3, 'awayLegs': 2,
    'winnerTeamId': 'steady',
    'players': [
      for (var i = 0; i < 4; i++)
        {'playerId': 'p$i', 'teamId': i < 2 ? 'steady' : 'test',
         'statistics': <String, dynamic>{}},
    ],
  };

  test('valid result roundtrip and stable identity', () {
    final data = result();
    expect(B74DoublesResultContract.decode(
      B74DoublesResultContract.encode(data)), data);
    expect(B74DoublesResultContract.resultId('match-1', 2),
        'match-1:doubles:2');
  });
  test('reject unfinished match', () {
    final data = result()..['homeLegs'] = 2;
    expect(() => B74DoublesResultContract.validate(data), throwsFormatException);
  });
  test('reject conflicting winner', () {
    final data = result()..['winnerTeamId'] = 'test';
    expect(() => B74DoublesResultContract.validate(data), throwsFormatException);
  });
  test('reject incorrect identity', () {
    final data = result()..['resultId'] = 'another';
    expect(() => B74DoublesResultContract.validate(data), throwsFormatException);
  });
  test('reject duplicate player', () {
    final data = result();
    (data['players'] as List)[3]['playerId'] = 'p0';
    expect(() => B74DoublesResultContract.validate(data), throwsFormatException);
  });
}
