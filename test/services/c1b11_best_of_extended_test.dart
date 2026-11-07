import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  for (final bestOf in [3, 5, 7, 9, 11]) {
    test('doubles engine accepts Best of $bestOf', () {
      final engine = B74Doubles701(starterTeam: 0, bestOf: bestOf);
      expect(engine.targetLegs, (bestOf + 1) ~/ 2);
      expect(engine.needsBull, false);
    });
  }
  test('beer game remains exactly one leg', () {
    expect(
      () => B74Doubles701(starterTeam: 0, startingScore: 1001,
          playersPerTeam: 4, bestOf: 3),
      throwsArgumentError,
    );
  });
}
