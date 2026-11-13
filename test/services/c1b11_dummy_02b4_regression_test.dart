import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';
import 'package:dartscore_app/services/b74_doubles_live_stats.dart';

String visit(int score, {bool dummy = false}) => jsonEncode({
  'type': 'visit',
  if (dummy) 'dummy': true,
  'score': score,
  'bust': false,
  'validCheckout': false,
});

void main() {
  test('701: Dummy zero visit preserves alternating teams and player rotation', () {
    final core = B74Doubles701(starterTeam: 0);
    core.confirmLegStarter(0);
    expect(core.currentVisit, (team: 0, player: 0));
    core.completeVisit(score: 0); // Dummy home position 0
    expect(core.remaining, [701, 701]);
    expect(core.currentVisit, (team: 1, player: 0));
    core.completeVisit(score: 60);
    expect(core.currentVisit, (team: 0, player: 1));
    core.completeVisit(score: 45);
    expect(core.currentVisit, (team: 1, player: 1));
  });

  test('1001: consecutive Dummy positions do not skip a turn', () {
    final core = B74Doubles701(
      starterTeam: 0, playersPerTeam: 4, startingScore: 1001, bestOf: 1,
    );
    core.confirmLegStarter(0);
    for (var i = 0; i < 8; i++) {
      expect(core.currentVisit, (team: i.isEven ? 0 : 1, player: i ~/ 2));
      core.completeVisit(score: 0);
    }
    expect(core.currentVisit, (team: 0, player: 0));
    expect(core.remaining, [1001, 1001]);
  });

  test('Dummy visit contributes three darts and zero points to match projection', () {
    final events = [
      jsonEncode({'type': 'starter', 'team': 0, 'viaBull': false}),
      visit(0, dummy: true),
      visit(60),
      visit(45),
    ];
    final stats = B74DoublesLiveStats.fromEvents(
      events, startTeam: 0, bestOf: 5, openingBullRequired: false,
    );
    expect(stats.player(0, 0).points, 0);
    expect(stats.player(0, 0).dartsThrown, 3);
    expect(stats.player(1, 0).points, 60);
    expect(stats.player(0, 1).points, 45);
  });

  test('Undo of Dummy visit removes its contribution from replay statistics', () {
    final events = [
      jsonEncode({'type': 'starter', 'team': 0, 'viaBull': false}),
      visit(0, dummy: true),
      jsonEncode({'type': 'undoVisit', 'targetSequence': 1}),
      visit(0, dummy: true),
    ];
    final stats = B74DoublesLiveStats.fromEvents(
      events, startTeam: 0, bestOf: 5, openingBullRequired: false,
    );
    expect(stats.player(0, 0).visits, 1);
    expect(stats.player(0, 0).dartsThrown, 3);
    expect(stats.player(1, 0).visits, 0);
  });
}
