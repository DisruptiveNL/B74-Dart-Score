import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';

Map<String, dynamic> _group(String kind) => {
  'startingScore': kind == 'beer' ? 1001 : kind == 'doubles' ? 701 : 501,
  'bestOf': kind == 'beer' ? 1 : 5,
  'checkIn': 'straight', 'checkOut': 'double',
  'startPolicy': 'fixedAway', 'bullDecidingLeg': false, 'winPoints': 1,
};
Map<String, dynamic> _side(String id, int base) => {
  'teamId': id, 'teamName': id,
  'players': List.generate(2, (i) => {
    'playerId': '$id$i', 'name': '$id$i',
    'bondNumber': '${base + i}', 'position': i + 1,
  }),
};
Map<String, dynamic> _packet() => {
  'type': B74TeamMatchContract.type, 'version': B74TeamMatchContract.version,
  'matchId': 'match-04a', 'gameId': 'match-04a:doubles701:1',
  'revision': 1, 'kind': 'doubles701', 'slot': 1,
  'startingScore': 701, 'bestOf': 5, 'checkIn': 'straight',
  'startPolicy': 'away', 'home': _side('home', 100),
  'away': _side('away', 200),
};
Map<String, dynamic> _envelope() => B74MatchRulesContract.create(
  matchId: 'match-04a', matchType: 'regular',
  snapshot: {
    'version': 1, 'singles': _group('singles'),
    'doubles': _group('doubles'), 'beer': _group('beer'),
  },
);
void main() {
  test('04A score: immutable snapshot survives team transport', () {
    final packet = _packet()..['matchRules'] = _envelope();
    final decoded = B74TeamMatchContract.decode(B74TeamMatchContract.encode(packet));
    expect(decoded['matchRules'], packet['matchRules']);
  });
  test('04A score: foreign match snapshot rejected', () {
    final packet = _packet();
    final rules = _envelope()..['matchId'] = 'another-match';
    packet['matchRules'] = rules;
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('04A score: mismatching best-of rejected', () {
    final packet = _packet()..['matchRules'] = _envelope();
    (packet['matchRules']['rules']['doubles'] as Map)['bestOf'] = 7;
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('04A score: legacy packet remains valid', () {
    final packet = _packet();
    expect(() => B74TeamMatchContract.validate(packet), returnsNormally);
  });
}
