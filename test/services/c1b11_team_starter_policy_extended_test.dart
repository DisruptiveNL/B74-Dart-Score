import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_leg_start_policy.dart';

void main() {
  test('best of 9 and 11 require bull only when configured', () {
    for (final bestOf in [9, 11]) {
      final legs = bestOf ~/ 2;
      expect(CompetitionLegStartPolicy.teamLegStarter(
        legNumber: bestOf, bestOf: bestOf, homeLegs: legs,
        awayLegs: legs, firstLegStarterSlot: 1,
      ), isNull);
      expect(CompetitionLegStartPolicy.teamLegStarter(
        legNumber: bestOf, bestOf: bestOf, homeLegs: legs,
        awayLegs: legs, firstLegStarterSlot: 1,
        decidingBullWinnerSlot: 0,
      ), 0);
      expect(CompetitionLegStartPolicy.teamLegStarter(
        legNumber: bestOf, bestOf: bestOf, homeLegs: legs,
        awayLegs: legs, firstLegStarterSlot: 1,
        bullDecidingLeg: false,
      ), 1);
    }
  });

  test('best of 3 without deciding bull alternates from first starter', () {
    expect(CompetitionLegStartPolicy.teamLegStarter(
      legNumber: 3, bestOf: 3, homeLegs: 1, awayLegs: 1,
      firstLegStarterSlot: 0, bullDecidingLeg: false,
    ), 0);
  });
}
