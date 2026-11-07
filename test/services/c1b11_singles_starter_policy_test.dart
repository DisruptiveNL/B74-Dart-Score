import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_leg_start_policy.dart';

void main() {
  int? starter({
    required int leg,
    required int home,
    required int away,
    int first = 0,
    int bestOf = 5,
    bool decidingBull = true,
    int? bullWinner,
  }) => CompetitionLegStartPolicy.singlesStarter(
    legNumber: leg,
    bestOf: bestOf,
    homeLegs: home,
    awayLegs: away,
    firstLegStarterSlot: first,
    bullDecidingLeg: decidingBull,
    decidingBullWinnerSlot: bullWinner,
  );

  test('home first alternates independently of leg winner', () {
    expect(starter(leg: 1, home: 0, away: 0), 0);
    expect(starter(leg: 2, home: 1, away: 0), 1);
    expect(starter(leg: 3, home: 1, away: 1), 0);
    expect(starter(leg: 4, home: 2, away: 1), 1);
  });

  test('away first alternates in home/away slots', () {
    expect(starter(leg: 1, home: 0, away: 0, first: 1), 1);
    expect(starter(leg: 2, home: 0, away: 1, first: 1), 0);
    expect(starter(leg: 3, home: 1, away: 1, first: 1), 1);
  });

  test('deciding bull is required only when enabled', () {
    expect(starter(leg: 5, home: 2, away: 2), isNull);
    expect(starter(leg: 5, home: 2, away: 2, bullWinner: 1), 1);
    expect(starter(leg: 5, home: 2, away: 2, decidingBull: false), 0);
    expect(starter(leg: 5, home: 2, away: 2, first: 1, decidingBull: false), 1);
  });

  test('best-of-nine and eleven support the decider', () {
    expect(starter(leg: 9, home: 4, away: 4, bestOf: 9), isNull);
    expect(starter(leg: 11, home: 5, away: 5, bestOf: 11, bullWinner: 0), 0);
  });

  test('invalid states are rejected instead of silently starting', () {
    expect(() => starter(leg: 0, home: 0, away: 0), throwsRangeError);
    expect(() => starter(leg: 2, home: 0, away: 0), throwsArgumentError);
    expect(() => starter(leg: 1, home: 0, away: 0, first: 2), throwsArgumentError);
    expect(() => starter(leg: 5, home: 2, away: 2, bullWinner: 2), throwsArgumentError);
  });
}
