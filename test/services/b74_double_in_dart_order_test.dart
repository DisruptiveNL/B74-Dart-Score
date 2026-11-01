import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  B74Doubles701 game() => B74Doubles701(
    starterTeam: 0, bestOf: 1, startingScore: 1001,
    playersPerTeam: 4, checkIn: 'double',
  )..confirmLegStarter(0);

  test('D16 on dart 2 and T20 on dart 3 scores 92', () {
    final g = game();
    g.completeVisit(score: 92, openingDouble: 32, openingDart: 2);
    expect(g.remaining[0], 909);
    expect(g.isOpened(0), isTrue);
    expect(g.currentVisit.team, 1);
  });

  test('D16 on dart 3 scores 32 and advances player', () {
    final g = game();
    g.completeVisit(score: 32, openingDouble: 32, openingDart: 3);
    expect(g.remaining[0], 969);
    expect(g.currentVisit.team, 1);
  });

  test('Three misses score zero, do not open, advance turn', () {
    final g = game();
    g.completeVisit(score: 0);
    expect(g.remaining[0], 1001);
    expect(g.isOpened(0), isFalse);
    expect(g.currentVisit.team, 1);
  });

  test('Invalid dart number rejected without changing score', () {
    final g = game();
    expect(() => g.completeVisit(score: 32, openingDouble: 32, openingDart: 4),
        throwsStateError);
    expect(g.remaining[0], 1001);
  });
}
