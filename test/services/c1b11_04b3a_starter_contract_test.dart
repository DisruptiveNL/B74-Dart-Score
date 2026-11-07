import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';

Map<String, dynamic> group(String kind, String policy) => {
  'startingScore': kind == 'beer' ? 1001 : kind == 'doubles' ? 701 : 501,
  'bestOf': kind == 'beer' ? 1 : 5,
  'checkIn': 'straight', 'checkOut': 'master',
  'startPolicy': policy, 'bullDecidingLeg': false, 'winPoints': 1,
};
Map<String, dynamic> side(String id, int base) => {
  'teamId': id, 'teamName': id,
  'players': List.generate(2, (i) => {
    'playerId': '$id$i', 'name': '$id$i',
    'bondNumber': '${base + i}', 'position': i + 1,
  }),
};
Map<String, dynamic> packet(String frozenPolicy, String transportPolicy) => {
  'type': B74TeamMatchContract.type,
  'version': B74TeamMatchContract.version,
  'matchId': 'match-b3', 'gameId': 'match-b3:doubles701:1',
  'revision': 1, 'kind': 'doubles701', 'slot': 1,
  'startingScore': 701, 'bestOf': 5, 'checkIn': 'straight',
  'startPolicy': transportPolicy,
  'home': side('home', 100), 'away': side('away', 200),
  'matchRules': B74MatchRulesContract.create(
    matchId: 'match-b3', matchType: 'regular',
    snapshot: {
      'version': 1,
      'singles': group('singles', 'fixedHome'),
      'doubles': group('doubles', frozenPolicy),
      'beer': group('beer', 'fixedHome'),
    },
  ),
};

void main() {
  test('04B.3A fixedHome maps to home', () {
    expect(() => B74TeamMatchContract.validate(packet('fixedHome', 'home')),
        returnsNormally);
  });
  test('04B.3A fixedAway maps to away', () {
    expect(() => B74TeamMatchContract.validate(packet('fixedAway', 'away')),
        returnsNormally);
  });
  test('04B.3A bull maps to bull', () {
    expect(() => B74TeamMatchContract.validate(packet('bull', 'bull')),
        returnsNormally);
  });
  test('04B.3A mismatched starter is rejected', () {
    expect(() => B74TeamMatchContract.validate(packet('fixedHome', 'away')),
        throwsFormatException);
  });
  test('04B.3A legacy packet remains supported', () {
    final legacy = packet('fixedHome', 'away')..remove('matchRules');
    expect(() => B74TeamMatchContract.validate(legacy), returnsNormally);
  });
}
