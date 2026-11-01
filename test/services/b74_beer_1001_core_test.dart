import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';
import 'package:dartscore_app/services/b74_doubles_rotation.dart';

void main() {
  test('701 blijft 2 spelers, 701 punten en best-of-5', () {
    final game = B74Doubles701(starterTeam: 0);
    expect(game.remaining, [701, 701]);
    expect(game.bestOf, 5);
    game.confirmLegStarter(0);
    expect(game.currentVisit, (team: 0, player: 0));
  });

  test('biergame 1001 roteert vier spelers per team', () {
    final game = B74Doubles701(starterTeam: 0,
        startingScore: 1001, playersPerTeam: 4, bestOf: 1);
    expect(game.remaining, [1001, 1001]);
    game.confirmLegStarter(0);
    for (var i = 0; i < 16; i++) {
      expect(game.currentVisit, B74DoublesRotation.visit(
          starterTeam: 0, turnIndex: i, playersPerTeam: 4));
      game.completeVisit(score: 0);
    }
    expect(game.currentVisit, (team: 0, player: 0));
  });

  test('biergame heeft slechts een winnende leg', () {
    final game = B74Doubles701(starterTeam: 0,
        startingScore: 1001, playersPerTeam: 4, bestOf: 1);
    game.confirmLegStarter(0);
    // Scoring per visit remains validated by the existing X01 checkout rules.
    expect(game.targetLegs, 1);
  });

  test('ongeldige combinaties worden afgewezen', () {
    expect(() => B74Doubles701(starterTeam: 0, startingScore: 1001,
        playersPerTeam: 2, bestOf: 1), throwsArgumentError);
    expect(() => B74Doubles701(starterTeam: 0, startingScore: 701,
        playersPerTeam: 4), throwsArgumentError);
  });
}
