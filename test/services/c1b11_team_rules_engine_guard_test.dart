import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';
import 'package:dartscore_app/services/competition_team_rules_guard.dart';

Map<String, dynamic> group(String kind) => {
  'startingScore': kind == 'singles' ? 501 : kind == 'beer' ? 1001 : 701,
  'bestOf': kind == 'beer' ? 1 : 5,
  'checkIn': 'straight', 'checkOut': 'double',
  'startPolicy': 'fixedAway',
  'bullDecidingLeg': kind == 'doubles', 'winPoints': 1,
};
Map<String, dynamic> packet({String kind = 'doubles701'}) {
  final beer = kind == 'beer1001';
  Map<String, dynamic> side(String id, int start) => {
    'teamId': id, 'teamName': id,
    'players': List.generate(beer ? 4 : 2, (i) => {
      'playerId': '$id$i', 'name': '$id$i',
      'bondNumber': '${start + i}', 'position': i + 1,
    }),
  };
  final snapshot = {'version': 1,
    'singles': group('singles'), 'doubles': group('doubles'), 'beer': group('beer')};
  return {
    'type': B74TeamMatchContract.type, 'version': 1,
    'matchId': 'm1', 'gameId': 'g1', 'revision': 1,
    'kind': kind, 'slot': 1, 'startingScore': beer ? 1001 : 701,
    'bestOf': beer ? 1 : 5, 'checkIn': 'straight', 'startPolicy': 'away',
    'home': side('h', 100), 'away': side('a', 200),
    'matchRules': B74MatchRulesContract.create(
      matchId: 'm1', matchType: 'regular', snapshot: snapshot),
  };
}
void main() {
  test('supported frozen doubles regulation is playable', () {
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(packet()), returnsNormally);
  });
  test('master out is refused before play', () {
    final p = packet();
    (p['matchRules']['rules']['doubles'] as Map)['checkOut'] = 'master';
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(p), throwsStateError);
  });
  test('optional deciding bull is not silently ignored', () {
    final p = packet();
    (p['matchRules']['rules']['doubles'] as Map)['bullDecidingLeg'] = false;
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(p), throwsStateError);
  });
  test('beer rules are checked separately', () {
    final p = packet(kind: 'beer1001');
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(p), returnsNormally);
    (p['matchRules']['rules']['beer'] as Map)['checkOut'] = 'straight';
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(p), throwsStateError);
  });
  test('legacy packet without snapshot retains legacy behavior', () {
    final p = packet()..remove('matchRules');
    expect(() => CompetitionTeamRulesGuard.validateForCurrentEngine(p), returnsNormally);
  });
}
