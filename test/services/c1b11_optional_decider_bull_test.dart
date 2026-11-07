import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  test('legacy default requires deciding bull', () {
    final engine = B74Doubles701(starterTeam: 0, bestOf: 3);
    engine.legsWon[0] = 1;
    engine.legsWon[1] = 1;
    engine.leg = 3;
    expect(engine.needsBull, isTrue);
    expect(engine.suggestedStarter, isNull);
    expect(() => engine.confirmLegStarter(0), throwsStateError);
    engine.recordDecidingBullWinner(1);
    expect(engine.legStarter, 1);
  });

  test('optional deciding bull allows explicit starter selection', () {
    final engine = B74Doubles701(
      starterTeam: 0, bestOf: 3, bullDecidingLeg: false,
    );
    engine.legsWon[0] = 1;
    engine.legsWon[1] = 1;
    engine.leg = 3;
    expect(engine.needsBull, isFalse);
    expect(engine.suggestedStarter, 0);
    expect(() => engine.recordDecidingBullWinner(1), throwsStateError);
    engine.confirmLegStarter(1);
    expect(engine.legStarter, 1);
    expect(engine.starterHistory.last.viaBull, isFalse);
  });

  test('beer game does not require deciding bull', () {
    final engine = B74Doubles701(
      starterTeam: 0, bestOf: 1, startingScore: 1001,
      playersPerTeam: 4, bullDecidingLeg: false,
    );
    expect(engine.needsBull, isFalse);
  });
}
