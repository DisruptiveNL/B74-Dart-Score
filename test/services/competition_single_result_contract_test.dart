import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_single_result_contract.dart';

void main() {
  Map<String, dynamic> sample() => {
    'type': CompetitionSingleResultContract.type,
    'version': 1,
    'matchId': 'match-42',
    'slot': 2,
    'resultId': 'match-42:single:2',
    'homePlayerId': 'home-1',
    'awayPlayerId': 'away-1',
    'homeLegs': 3,
    'awayLegs': 1,
    'winnerPlayerId': 'home-1',
    'statistics': <String, dynamic>{},
  };

  test('valid result round-trips', () {
    final payload = sample();
    expect(
      CompetitionSingleResultContract.decode(
        CompetitionSingleResultContract.encode(payload),
      ),
      payload,
    );
  });

  test('same match and slot has stable retry identity', () {
    expect(
      CompetitionSingleResultContract.resultId('match-42', 2),
      'match-42:single:2',
    );
  });

  test('wrong winner is rejected', () {
    final value = sample()..['winnerPlayerId'] = 'away-1';
    expect(
      () => CompetitionSingleResultContract.encode(value),
      throwsFormatException,
    );
  });

  test('wrong result id is rejected', () {
    final value = sample()..['resultId'] = 'another';
    expect(
      () => CompetitionSingleResultContract.encode(value),
      throwsFormatException,
    );
  });

  test('incomplete or tied match is rejected', () {
    final value = sample()..['awayLegs'] = 3;
    expect(
      () => CompetitionSingleResultContract.encode(value),
      throwsFormatException,
    );
  });
}
