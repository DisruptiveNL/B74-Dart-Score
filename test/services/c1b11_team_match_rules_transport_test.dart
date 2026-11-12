import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';

Map<String, dynamic> rules() => {
  'version': 1,
  'singles': {
    'startingScore': 501,
    'bestOf': 5,
    'checkIn': 'straight',
    'checkOut': 'double',
    'startPolicy': 'fixedHome',
    'bullDecidingLeg': false,
    'winPoints': 1,
  },
  'doubles': {
    'startingScore': 701,
    'bestOf': 5,
    'checkIn': 'double',
    'checkOut': 'master',
    'startPolicy': 'fixedAway',
    'bullDecidingLeg': true,
    'winPoints': 2,
  },
  'beer': {
    'startingScore': 1001,
    'bestOf': 1,
    'checkIn': 'straight',
    'checkOut': 'double',
    'startPolicy': 'bull',
    'bullDecidingLeg': false,
    'winPoints': 3,
  },
};

Map<String, dynamic> team(String id, int start) => {
  'teamId': id,
  'teamName': id,
  'players': List.generate(
    2,
    (i) => {
      'playerId': '$id$i',
      'name': '$id$i',
      'bondNumber': '${start + i}',
      'position': i + 1,
    },
  ),
};

Map<String, dynamic> packet() => {
  'type': B74TeamMatchContract.type,
  'version': 1,
  'matchId': 'm1',
  'gameId': 'm1:doubles701:1',
  'revision': 1,
  'kind': 'doubles701',
  'slot': 1,
  'startingScore': 701,
  'bestOf': 5,
  'checkIn': 'double',
  'startPolicy': 'away',
  'home': team('home', 100),
  'away': team('away', 200),
};

void main() {
  test('legacy teambericht zonder reglement blijft geldig', () {
    final p = packet();
    expect(B74TeamMatchContract.decode(B74TeamMatchContract.encode(p)), p);
  });
  test('volledig reglement reist verliesvrij mee', () {
    final p = packet()
      ..['matchRules'] = B74MatchRulesContract.create(
        matchId: 'm1',
        matchType: 'cup',
        snapshot: rules(),
      );
    final decoded = B74TeamMatchContract.decode(B74TeamMatchContract.encode(p));
    expect(decoded['matchRules'], p['matchRules']);
    expect(
      B74MatchRulesContract.forGame(
        decoded['matchRules'],
        'doubles',
      )['checkOut'],
      'master',
    );
  });
  test('koppels 1 t/m 4 wisselen eerste starter volgens reglement', () {
    for (var slot = 1; slot <= 4; slot++) {
      final p = packet()
        ..['slot'] = slot
        ..['gameId'] = 'm1:doubles701:$slot'
        ..['startPolicy'] = slot.isOdd ? 'away' : 'home'
        ..['matchRules'] = B74MatchRulesContract.create(
          matchId: 'm1',
          matchType: 'cup',
          snapshot: rules(),
        );
      expect(() => B74TeamMatchContract.validate(p), returnsNormally);
      p['startPolicy'] = slot.isOdd ? 'home' : 'away';
      expect(() => B74TeamMatchContract.validate(p), throwsFormatException);
    }
  });

  test('vaste thuisstarter wisselt eveneens en bull blijft bull', () {
    final homeRules = rules();
    (homeRules['doubles'] as Map<String, dynamic>)['startPolicy'] = 'fixedHome';
    for (var slot = 1; slot <= 4; slot++) {
      final p = packet()
        ..['slot'] = slot
        ..['startPolicy'] = slot.isOdd ? 'home' : 'away'
        ..['matchRules'] = B74MatchRulesContract.create(
          matchId: 'm1',
          matchType: 'regular',
          snapshot: homeRules,
        );
      expect(() => B74TeamMatchContract.validate(p), returnsNormally);
    }
    final bullRules = rules();
    (bullRules['doubles'] as Map<String, dynamic>)['startPolicy'] = 'bull';
    final p = packet()
      ..['slot'] = 2
      ..['startPolicy'] = 'bull'
      ..['matchRules'] = B74MatchRulesContract.create(
        matchId: 'm1',
        matchType: 'regular',
        snapshot: bullRules,
      );
    expect(() => B74TeamMatchContract.validate(p), returnsNormally);
    p['startPolicy'] = 'home';
    expect(() => B74TeamMatchContract.validate(p), throwsFormatException);
  });

  test('reglement van andere wedstrijd wordt geweigerd', () {
    final p = packet()
      ..['matchRules'] = B74MatchRulesContract.create(
        matchId: 'm2',
        matchType: 'cup',
        snapshot: rules(),
      );
    expect(() => B74TeamMatchContract.validate(p), throwsFormatException);
  });
  test('tegenstrijdige startscore of check-in wordt geweigerd', () {
    final p = packet()
      ..['matchRules'] = B74MatchRulesContract.create(
        matchId: 'm1',
        matchType: 'cup',
        snapshot: rules(),
      );
    p['startingScore'] = 501;
    expect(() => B74TeamMatchContract.validate(p), throwsFormatException);
    p['startingScore'] = 701;
    p['checkIn'] = 'straight';
    expect(() => B74TeamMatchContract.validate(p), throwsFormatException);
  });
}
