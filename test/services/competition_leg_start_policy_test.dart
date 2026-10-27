import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_leg_start_policy.dart';

void main() {
  int? starter(int leg, int home, int away, {int? bull, int bestOf = 5,
      bool enabled = true}) => CompetitionLegStartPolicy.starterForLeg(
        legNumber: leg, bestOf: bestOf, homeLegs: home, awayLegs: away,
        bullDecidingLeg: enabled, decidingBullWinnerSlot: bull);

  test('ordinary legs alternate regardless of who won the previous leg', () {
    expect(starter(1, 0, 0), 0);
    expect(starter(2, 1, 0), 1);
    expect(starter(3, 1, 1), 0);
    expect(starter(4, 2, 1), 1);
  });

  test('best-of-five decider waits for bull and honours result', () {
    expect(starter(5, 2, 2), isNull);
    expect(starter(5, 2, 2, bull: 1), 1);
    expect(starter(5, 2, 2, bull: 0), 0);
  });

  test('best-of-seven decider at 3-3', () {
    expect(starter(7, 3, 3, bestOf: 7), isNull);
    expect(starter(7, 3, 3, bestOf: 7, bull: 1), 1);
  });

  test('disabled bull keeps ordinary alternation', () {
    expect(starter(5, 2, 2, enabled: false), 0);
  });

  test('invalid arguments are rejected', () {
    expect(() => starter(0, 0, 0), throwsArgumentError);
    expect(() => starter(5, 2, 2, bull: 3), throwsArgumentError);
    expect(() => starter(1, 0, 0, bestOf: 4), throwsArgumentError);
  });
}
