import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  test('shared scores and player rotation reset at next leg', () {
    final game = B74Doubles701(starterTeam: 1, bestOf: 5);
    expect(game.awaitingStarter, isTrue);
    game.confirmLegStarter(1);
    expect(game.currentVisit, (team: 1, player: 0));
    game.completeVisit(score: 100);
    expect(game.remaining, [701, 601]);
    expect(game.currentVisit, (team: 0, player: 0));
    game.completeVisit(score: 60);
    expect(game.currentVisit, (team: 1, player: 1));
    game.completeVisit(score: 180);
    expect(game.remaining, [641, 421]);
  });

  test('bust preserves team score but advances to other team', () {
    final game = B74Doubles701(starterTeam: 1);
    game.confirmLegStarter(1);
    game.completeVisit(score: 100, bust: true);
    expect(game.remaining, [701, 701]);
    expect(game.currentVisit, (team: 0, player: 0));
  });

  test('unvalidated checkout is blocked', () {
    final game = B74Doubles701(starterTeam: 1);
    game.confirmLegStarter(1);
    for (var i = 0; i < 8; i++) game.completeVisit(score: 150);
    // Both teams now have 101 remaining.
    expect(() => game.completeVisit(score: 101), throwsStateError);
    expect(game.remaining, [101, 101]);
  });

  test('checkout wins leg, resets both scores and alternates starter', () {
    final game = B74Doubles701(starterTeam: 1, bestOf: 3);
    game.confirmLegStarter(1);
    // Away completes 701 in five visits, home scores zero in between.
    for (var i = 0; i < 4; i++) {
      game.completeVisit(score: 150);
      game.completeVisit(score: 0);
    }
    game.completeVisit(score: 101, validCheckout: true);
    expect(game.legsWon, [0, 1]);
    expect(game.leg, 2);
    expect(game.remaining, [701, 701]);
    expect(game.awaitingStarter, isTrue);
    expect(game.suggestedStarter, 0);
    game.confirmLegStarter(0);
    expect(game.currentVisit, (team: 0, player: 0));
  });

  test('invalid score and premature bull are rejected', () {
    final game = B74Doubles701(starterTeam: 0);
    game.confirmLegStarter(0);
    expect(() => game.completeVisit(score: 181), throwsArgumentError);
    expect(() => game.recordDecidingBullWinner(1), throwsStateError);
  });
  test('starter is mandatory and override resets player order', () {
    final game = B74Doubles701(starterTeam: 1, bestOf: 3);
    expect(game.suggestedStarter, 1);
    expect(() => game.currentVisit, throwsStateError);
    game.confirmLegStarter(0);
    expect(game.currentVisit, (team: 0, player: 0));
    expect(game.starterHistory.single.team, 0);
    expect(game.starterHistory.single.viaBull, isFalse);
    expect(() => game.confirmLegStarter(1), throwsStateError);
    game.completeVisit(score: 60);
    expect(game.currentVisit, (team: 1, player: 0));
    game.completeVisit(score: 0);
    expect(game.currentVisit, (team: 0, player: 1));
  });

  test('manual override does not change alternating proposed starter', () {
    final game = B74Doubles701(starterTeam: 1, bestOf: 5);
    game.confirmLegStarter(0);
    for (var i = 0; i < 4; i++) {
      game.completeVisit(score: 150);
      game.completeVisit(score: 0);
    }
    game.completeVisit(score: 101, validCheckout: true);
    expect(game.leg, 2);
    expect(game.suggestedStarter, 0);
    expect(() => game.currentVisit, throwsStateError);
    game.confirmLegStarter(1);
    expect(game.currentVisit, (team: 1, player: 0));
    expect(game.starterHistory.map((e) => e.team).toList(), [0, 1]);
  });

  test('deciding leg requires bull and records bull starter', () {
    final game = B74Doubles701(starterTeam: 1, bestOf: 3);
    void winLeg(int team) {
      game.confirmLegStarter(team);
      for (var i = 0; i < 4; i++) {
        game.completeVisit(score: 150);
        game.completeVisit(score: 0);
      }
      game.completeVisit(score: 101, validCheckout: true);
    }

    winLeg(0);
    winLeg(1);
    expect(game.leg, 3);
    expect(game.awaitingBull, isTrue);
    expect(game.suggestedStarter, isNull);
    expect(() => game.confirmLegStarter(0), throwsStateError);
    expect(() => game.currentVisit, throwsStateError);
    game.recordDecidingBullWinner(1);
    expect(game.currentVisit, (team: 1, player: 0));
    expect(game.starterHistory.last.legNumber, 3);
    expect(game.starterHistory.last.viaBull, isTrue);
    expect(() => game.recordDecidingBullWinner(0), throwsStateError);
  });
  for (final bestOf in [3, 5, 7]) {
    test('best-of $bestOf completes only at target legs', () {
      final game = B74Doubles701(starterTeam: 0, bestOf: bestOf);
      for (var leg = 1; leg <= (bestOf + 1) ~/ 2; leg++) {
        game.confirmLegStarter(0);
        for (var i = 0; i < 4; i++) {
          game.completeVisit(score: 150);
          game.completeVisit(score: 0);
        }
        game.completeVisit(score: 101, validCheckout: true);
        if (leg < (bestOf + 1) ~/ 2) {
          expect(game.winner, isNull);
          expect(game.awaitingStarter, isTrue);
        }
      }
      expect(game.winner, 0);
      expect(() => game.currentVisit, throwsStateError);
    });
  }
}
