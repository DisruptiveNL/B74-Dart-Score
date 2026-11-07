import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_701.dart';
import 'package:dartscore_app/services/b74_doubles_checkout.dart';

void main() {
  group('C1B11 04B.3B - checkoutmodi', () {
    test('straight out accepteert single, double en triple als laatste dart', () {
      for (final dart in ['S20', 'D10', 'T20']) {
        final score = B74DoublesCheckout.value(dart);
        expect(B74DoublesCheckout.valid(
          remaining: score, score: score, darts: [dart],
          checkOut: 'straight',
        ), isTrue, reason: dart);
      }
    });

    test('double out accepteert dubbel en bull, maar geen single/triple', () {
      expect(B74DoublesCheckout.valid(
        remaining: 40, score: 40, darts: ['D20'], checkOut: 'double',
      ), isTrue);
      expect(B74DoublesCheckout.valid(
        remaining: 50, score: 50, darts: ['BULL'], checkOut: 'double',
      ), isTrue);
      expect(B74DoublesCheckout.valid(
        remaining: 20, score: 20, darts: ['S20'], checkOut: 'double',
      ), isFalse);
      expect(B74DoublesCheckout.valid(
        remaining: 60, score: 60, darts: ['T20'], checkOut: 'double',
      ), isFalse);
    });

    test('master out accepteert triple en dubbel, maar geen single', () {
      expect(B74DoublesCheckout.valid(
        remaining: 60, score: 60, darts: ['T20'], checkOut: 'master',
      ), isTrue);
      expect(B74DoublesCheckout.valid(
        remaining: 40, score: 40, darts: ['D20'], checkOut: 'master',
      ), isTrue);
      expect(B74DoublesCheckout.valid(
        remaining: 20, score: 20, darts: ['S20'], checkOut: 'master',
      ), isFalse);
    });

    test('checkout weigert verkeerde som en darts na finish', () {
      expect(B74DoublesCheckout.valid(
        remaining: 40, score: 40, darts: ['D10'], checkOut: 'double',
      ), isFalse);
      expect(B74DoublesCheckout.valid(
        remaining: 40, score: 40, darts: ['D20', 'S1'],
        checkOut: 'straight',
      ), isFalse);
    });
  });

  group('C1B11 04B.3B - Double In en score-engine', () {
    test('drie mislukte openingspogingen leveren nul punten op', () {
      final engine = B74Doubles701(
        starterTeam: 0, checkIn: 'double', startingScore: 301,
      );
      engine.confirmLegStarter(0);
      engine.completeVisit(score: 0);
      expect(engine.remaining[0], 301);
      expect(engine.opened[0], isFalse);
    });

    test('score zonder openingsdubbel wordt geweigerd', () {
      final engine = B74Doubles701(
        starterTeam: 0, checkIn: 'double', startingScore: 301,
      );
      engine.confirmLegStarter(0);
      expect(() => engine.completeVisit(score: 32), throwsStateError);
      expect(engine.remaining[0], 301);
      expect(engine.opened[0], isFalse);
    });

    test('dubbel op dart 2 telt mee, volgende score wordt verwerkt', () {
      final engine = B74Doubles701(
        starterTeam: 0, checkIn: 'double', startingScore: 301,
      );
      engine.confirmLegStarter(0);
      engine.completeVisit(
        score: 52, openingDouble: 32, openingDart: 2,
      );
      expect(engine.remaining[0], 249);
      expect(engine.opened[0], isTrue);
    });

    test('bust wijzigt geen score en opent team niet', () {
      final engine = B74Doubles701(
        starterTeam: 0, checkIn: 'double', startingScore: 301,
      );
      engine.confirmLegStarter(0);
      expect(() => engine.completeVisit(
        score: 32, openingDouble: 32, openingDart: 1, bust: true,
      ), throwsStateError);
      expect(engine.remaining[0], 301);
      expect(engine.opened[0], isFalse);
    });

    test('een nieuwe leg reset de ingestelde startscore en Double In', () {
      final engine = B74Doubles701(
        starterTeam: 0, bestOf: 3, startingScore: 301,
        checkIn: 'double', checkOut: 'straight',
      );
      engine.confirmLegStarter(0);
      // Arrange a remaining checkout score; validate the leg reset.
      engine.remaining[0] = 32;
      engine.completeVisit(
        score: 32, openingDouble: 32, openingDart: 1,
        validCheckout: true,
      );
      expect(engine.leg, 2);
      expect(engine.remaining, [301, 301]);
      expect(engine.opened, [false, false]);
      expect(engine.awaitingStarter, isTrue);
    });
  });

  group('C1B11 04B.3B - beslissende bull', () {
    test('verplichte bull blokkeert handmatige starter in beslissende leg', () {
      final engine = B74Doubles701(
        starterTeam: 0, bestOf: 3, bullDecidingLeg: true,
      );
      engine.legsWon[0] = 1;
      engine.legsWon[1] = 1;
      engine.leg = 3;
      expect(engine.awaitingBull, isTrue);
      expect(() => engine.confirmLegStarter(0), throwsStateError);
      engine.recordDecidingBullWinner(1);
      expect(engine.legStarter, 1);
      expect(engine.starterHistory.last.viaBull, isTrue);
    });

    test('zonder beslissende bull blijft starter expliciet bevestigbaar', () {
      final engine = B74Doubles701(
        starterTeam: 0, bestOf: 3, bullDecidingLeg: false,
      );
      engine.legsWon[0] = 1;
      engine.legsWon[1] = 1;
      engine.leg = 3;
      expect(engine.awaitingBull, isFalse);
      engine.confirmLegStarter(1);
      expect(engine.legStarter, 1);
      expect(engine.starterHistory.last.viaBull, isFalse);
    });
  });
}
