import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_leg_start_policy.dart';

void main() {
  test('four doubles alternate away/home and beer starts away', () {
    for (var slot = 1; slot <= 4; slot++) {
      expect(CompetitionLegStartPolicy.teamStartPolicy(
        kind: 'doubles701', slot: slot),
        slot.isOdd ? 'away' : 'home');
    }
    expect(CompetitionLegStartPolicy.teamStartPolicy(
      kind: 'beer1001', slot: 1), 'away');
  });

  test('explicit first-leg bull policy', () {
    expect(CompetitionLegStartPolicy.teamStartPolicy(
      kind: 'doubles701', slot: 2, bullStart: true), 'bull');
  });

  test('decider cannot start without recorded bull winner', () {
    for (final bestOf in [3, 5, 7]) {
      final legs = bestOf ~/ 2;
      expect(CompetitionLegStartPolicy.teamLegStarter(
        legNumber: bestOf, bestOf: bestOf, homeLegs: legs,
        awayLegs: legs, firstLegStarterSlot: 1), isNull);
      expect(CompetitionLegStartPolicy.teamLegStarter(
        legNumber: bestOf, bestOf: bestOf, homeLegs: legs,
        awayLegs: legs, firstLegStarterSlot: 1,
        decidingBullWinnerSlot: 0), 0);
    }
  });

  test('ordinary legs alternate from the resolved first starter', () {
    expect(CompetitionLegStartPolicy.teamLegStarter(
      legNumber: 1, bestOf: 5, homeLegs: 0,
      awayLegs: 0, firstLegStarterSlot: 1), 1);
    expect(CompetitionLegStartPolicy.teamLegStarter(
      legNumber: 2, bestOf: 5, homeLegs: 0,
      awayLegs: 1, firstLegStarterSlot: 1), 0);
  });

  test('invalid slots, winners and finished matches rejected', () {
    expect(() => CompetitionLegStartPolicy.teamStartPolicy(
      kind: 'doubles701', slot: 5), throwsRangeError);
    expect(() => CompetitionLegStartPolicy.teamLegStarter(
      legNumber: 3, bestOf: 3, homeLegs: 1, awayLegs: 1,
      firstLegStarterSlot: 1, decidingBullWinnerSlot: 2),
      throwsArgumentError);
    expect(() => CompetitionLegStartPolicy.teamLegStarter(
      legNumber: 3, bestOf: 3, homeLegs: 2, awayLegs: 0,
      firstLegStarterSlot: 1), throwsArgumentError);
  });
}
