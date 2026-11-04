import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';


Map<String, dynamic> group(int score, int bestOf, {String checkIn = 'straight'}) => {
  'startingScore': score,
  'bestOf': bestOf,
  'checkIn': checkIn,
  'checkOut': 'master',
  'startPolicy': 'fixedAway',
  'bullDecidingLeg': false,
  'winPoints': 2,
};

void main() {
  test('C1B11: full snapshot roundtrip for cup with independent game rules', () {
    final rules = <String, dynamic>{
      'version': 1,
      'singles': group(301, 9, checkIn: 'double'),
      'doubles': group(501, 11),
      'beer': group(701, 1),
    };
    final packet = B74MatchRulesContract.create(
      matchId: 'wedstrijd-42', matchType: 'cup', snapshot: rules,
    );
    final restored = B74MatchRulesContract.decode(B74MatchRulesContract.encode(packet));
    expect(restored['matchType'], 'cup');
    expect(B74MatchRulesContract.forGame(restored, 'singles')['checkIn'], 'double');
    expect(B74MatchRulesContract.forGame(restored, 'doubles')['bestOf'], 11);
    expect(B74MatchRulesContract.forGame(restored, 'beer')['startingScore'], 701);
    rules['singles'] = group(701, 3);
    expect(B74MatchRulesContract.forGame(packet, 'singles')['startingScore'], 301);
  });

  test('C1B11: malformed or unsupported rules are rejected', () {
    final rules = <String, dynamic>{
      'version': 1,
      'singles': group(501, 5),
      'doubles': group(701, 5),
      'beer': group(1001, 1),
    };
    final packet = B74MatchRulesContract.create(
      matchId: 'm1', matchType: 'regular', snapshot: rules,
    );
    (packet['rules'] as Map<String, dynamic>)['beer'] = group(1001, 3);
    expect(() => B74MatchRulesContract.encode(packet), throwsFormatException);
    expect(() => B74MatchRulesContract.decode('{"type":"wrong"}'), throwsFormatException);
  });
}
