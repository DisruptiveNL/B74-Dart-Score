import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  test('automatic first and second leg starter alternate without bull', () {
    final engine = B74Doubles701(starterTeam: 1, bestOf: 3,
        bullDecidingLeg: false);
    expect(engine.suggestedStarter, 1);
    engine.confirmLegStarter(engine.suggestedStarter!);
    expect(engine.starterHistory.single.team, 1);
    // Test next-leg alternation by setting the state to an unfinished leg 2.
    engine.leg = 2;
    final next = B74Doubles701(starterTeam: 1, bestOf: 3,
        bullDecidingLeg: false)..leg = 2;
    expect(next.suggestedStarter, 0);
    next.confirmLegStarter(next.suggestedStarter!);
    expect(next.starterHistory.single.viaBull, false);
  });

  test('deciding bull is never automatically selected', () {
    final engine = B74Doubles701(starterTeam: 0, bestOf: 3);
    engine.legsWon[0] = 1;
    engine.legsWon[1] = 1;
    engine.leg = 3;
    expect(engine.needsBull, true);
    expect(engine.suggestedStarter, isNull);
    expect(engine.awaitingStarter, true);
  });

  test('beer game has no deciding bull', () {
    final engine = B74Doubles701(starterTeam: 1, bestOf: 1,
        startingScore: 1001, playersPerTeam: 4);
    expect(engine.suggestedStarter, 1);
    expect(engine.needsBull, false);
  });
}
