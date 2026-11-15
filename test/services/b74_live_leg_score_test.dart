import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_live_leg_score.dart';

void main() {
  group('B74 Online Live singles leg-score regression', () {
    for (final legsToWin in [2, 3, 4]) {
      test('Best of ${legsToWin * 2 - 1}: retains winning final leg', () {
        for (var won = 0; won < legsToWin; won++) {
          expect(B74LiveLegScore.forScoreboard(
            gameLegs: legsToWin, gameSets: 1,
            setsWon: 0, legsWon: won,
          ), won);
        }
        expect(B74LiveLegScore.forScoreboard(
          gameLegs: legsToWin, gameSets: 1,
          setsWon: 1, legsWon: 0,
        ), legsToWin);
        expect(B74LiveLegScore.forScoreboard(
          gameLegs: legsToWin, gameSets: 1,
          setsWon: 0, legsWon: 0,
        ), 0);
      });
    }

    test('multi-set games retain the existing within-set leg display', () {
      expect(B74LiveLegScore.forScoreboard(
        gameLegs: 3, gameSets: 2, setsWon: 1, legsWon: 2,
      ), 2);
    });
  });
}
