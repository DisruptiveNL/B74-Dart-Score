import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  group('C1B11 04B.2 variabele startscore', () {
    for (final score in [301, 501, 701]) {
      test('Koppels start en hervat deterministisch vanaf $score', () {
        final engine = B74Doubles701(
          starterTeam: 0, startingScore: score, playersPerTeam: 2,
        );
        expect(engine.remaining, [score, score]);
      });
    }
    for (final score in [301, 501, 701, 1001]) {
      test('Biergame accepteert $score', () {
        final engine = B74Doubles701(
          starterTeam: 0, startingScore: score, playersPerTeam: 4,
          bestOf: 1,
        );
        expect(engine.remaining, [score, score]);
      });
    }
    test('Biergame mag geen Best of 3', () {
      expect(() => B74Doubles701(starterTeam: 0,
          startingScore: 501, playersPerTeam: 4, bestOf: 3), throwsArgumentError);
    });
    test('Koppels mag geen 1001', () {
      expect(() => B74Doubles701(starterTeam: 0,
          startingScore: 1001, playersPerTeam: 2), throwsArgumentError);
    });
  });
}
