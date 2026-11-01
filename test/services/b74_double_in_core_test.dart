import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';

void main() {
  test('Straight In blijft standaard', () {
    final game = B74Doubles701(starterTeam: 0, bestOf: 1,
        startingScore: 1001, playersPerTeam: 4);
    game.confirmLegStarter(0);
    game.completeVisit(score: 60);
    expect(game.remaining[0], 941);
    expect(game.isOpened(0), isTrue);
  });

  test('Double In: beide teams openen onafhankelijk', () {
    final game = B74Doubles701(starterTeam: 0, bestOf: 1,
        startingScore: 1001, playersPerTeam: 4, checkIn: 'double');
    game.confirmLegStarter(0);
    game.completeVisit(score: 0);
    expect(game.remaining[0], 1001);
    expect(game.isOpened(0), isFalse);
    expect(() => game.completeVisit(score: 60), throwsStateError);
    game.completeVisit(score: 60, openingDouble: 40);
    expect(game.remaining[1], 941);
    expect(game.isOpened(1), isTrue);
    expect(game.isOpened(0), isFalse);
  });

  test('Ongeldige openingsdubbel wordt geweigerd', () {
    final game = B74Doubles701(starterTeam: 0, bestOf: 1,
        startingScore: 1001, playersPerTeam: 4, checkIn: 'double');
    game.confirmLegStarter(0);
    expect(() => game.completeVisit(score: 60, openingDouble: 25),
        throwsArgumentError);
    expect(game.remaining[0], 1001);
  });
}
