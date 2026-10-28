import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/utils/throw_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single visit; everything that is not under test gets a harmless default.
DartThrow _visit(
  int score, {
  int remainingBefore = 501,
  int dartsUsed = 3,
  int leg = 1,
  int set = 1,
  int gameId = 1,
  int playerId = 1,
  bool bust = false,
  int checkoutDarts = 0,
}) => DartThrow(
  gameId: gameId,
  playerId: playerId,
  score: score,
  dartsUsed: dartsUsed,
  leg: leg,
  set: set,
  remainingBefore: remainingBefore,
  thrownAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  bust: bust,
  checkoutDarts: checkoutDarts,
);

void main() {
  group('ThrowStats.fromThrows', () {
    test('an empty list yields zeros instead of NaN', () {
      final s = ThrowStats.fromThrows([]);

      expect(s.totalVisits, 0);
      expect(s.totalDarts, 0);
      expect(s.totalScored, 0);
      expect(s.highestVisit, 0);
      expect(s.average, 0);
      expect(s.first9Average, 0);
      expect(s.bustRate, 0);
      expect(s.checkoutRate, 0);
    });

    test('a bust adds darts but no score', () {
      final s = ThrowStats.fromThrows([
        _visit(140),
        _visit(180, remainingBefore: 361, bust: true),
      ]);

      expect(s.totalVisits, 2);
      expect(s.totalDarts, 6);
      expect(s.totalScored, 140);
      expect(s.busts, 1);
      expect(s.highestVisit, 140, reason: 'the busted 180 does not count');
      expect(s.count180, 0);
      expect(s.count140plus, 1);
      expect(s.average, closeTo(70, 0.001));
      expect(s.bustRate, closeTo(50, 0.001));
    });

    test('a busted visit that was one dart away is still an attempt', () {
      final s = ThrowStats.fromThrows([
        _visit(60, remainingBefore: 41, bust: true, checkoutDarts: 1),
      ]);

      expect(s.checkoutAttempts, 1);
      expect(s.checkoutSuccesses, 0);
      expect(s.coAttemptSub60, 1);
      expect(s.coSuccessSub60, 0);
      expect(s.highestCheckout, 0);
    });

    test('being in checkout range is not by itself an attempt', () {
      final s = ThrowStats.fromThrows([_visit(60, remainingBefore: 156)]);

      expect(s.checkoutAttempts, 0);
      expect(s.checkoutRate, 0);
    });

    test('a finishing visit counts as attempt and success', () {
      final s = ThrowStats.fromThrows([
        _visit(101, remainingBefore: 101, dartsUsed: 2, checkoutDarts: 1),
        _visit(40, remainingBefore: 40, checkoutDarts: 1),
      ]);

      expect(s.checkoutAttempts, 2);
      expect(s.checkoutSuccesses, 2);
      expect(s.highestCheckout, 101);
      expect(s.checkoutRate, closeTo(100, 0.001));
    });

    test('checkout ranges split at 40, 60, 100 and 170 by the remaining the '
        'visit started on', () {
      final s = ThrowStats.fromThrows([
        _visit(0, remainingBefore: 40, checkoutDarts: 1),
        _visit(0, remainingBefore: 41, checkoutDarts: 1),
        _visit(0, remainingBefore: 60, checkoutDarts: 1),
        _visit(0, remainingBefore: 61, checkoutDarts: 1),
        _visit(0, remainingBefore: 100, checkoutDarts: 1),
        _visit(0, remainingBefore: 101, checkoutDarts: 1),
        _visit(0, remainingBefore: 170, checkoutDarts: 1),
        _visit(0, remainingBefore: 171),
      ]);

      expect(s.checkoutAttempts, 7, reason: 'the 171 was never one dart away');
      expect(s.coAttemptSub40, 1);
      expect(s.coAttemptSub60, 2);
      expect(s.coAttemptSub100, 2);
      expect(s.coAttemptSub170, 2);
    });

    test('the two rates count different things', () {
      // 60 left, S20, D5, S10: two darts at a finish, no checkout. Then 20
      // left and three misses: three more darts, still no checkout. Then 20
      // taken out with D10 on the first dart.
      final s = ThrowStats.fromThrows([
        _visit(40, remainingBefore: 60, checkoutDarts: 2),
        _visit(0, remainingBefore: 20, checkoutDarts: 3),
        _visit(20, remainingBefore: 20, checkoutDarts: 1),
      ]);

      expect(s.checkoutAttempts, 3);
      expect(s.checkoutDarts, 6);
      expect(s.checkoutSuccesses, 1);
      expect(
        s.checkoutRate,
        closeTo(100 / 3, 0.001),
        reason: 'one of three visits at the finish took it',
      );
      expect(
        s.doubleRate,
        closeTo(100 / 6, 0.001),
        reason: 'one of six darts at the finish hit it',
      );
    });

    test('score thresholds are inclusive', () {
      final s = ThrowStats.fromThrows([
        _visit(180),
        _visit(140),
        _visit(139),
        _visit(100),
        _visit(99),
      ]);

      expect(s.count180, 1);
      expect(s.count140plus, 2, reason: '180 and 140');
      expect(s.count100plus, 4, reason: '180, 140, 139 and 100');
    });

    group('first 9', () {
      test('takes only the opening three visits of a leg', () {
        final s = ThrowStats.fromThrows([
          _visit(60),
          _visit(60),
          _visit(60),
          _visit(180),
          _visit(180),
        ]);

        expect(s.first9Darts, 9);
        expect(s.first9Scored, 180);
        expect(s.first9Average, closeTo(60, 0.001));
      });

      test('sums the opening visits of every leg', () {
        final s = ThrowStats.fromThrows([
          _visit(60, leg: 1),
          _visit(60, leg: 1),
          _visit(60, leg: 1),
          _visit(100, leg: 2),
          _visit(100, leg: 2),
          _visit(100, leg: 2),
          _visit(20, leg: 2),
        ]);

        expect(s.first9Darts, 18);
        expect(s.first9Scored, 480);
      });

      test('keeps legs of the same number apart across games', () {
        // A lifetime list spans many games, and every one of them has a leg 1.
        final s = ThrowStats.fromThrows([
          _visit(60, gameId: 1),
          _visit(60, gameId: 1),
          _visit(60, gameId: 1),
          _visit(100, gameId: 2),
          _visit(100, gameId: 2),
        ]);

        expect(s.first9Darts, 15);
        expect(s.first9Scored, 380);
      });

      test('keeps legs of the same number apart across sets', () {
        final s = ThrowStats.fromThrows([
          _visit(60, leg: 1, set: 1),
          _visit(60, leg: 1, set: 1),
          _visit(60, leg: 1, set: 1),
          _visit(100, leg: 1, set: 2),
        ]);

        expect(s.first9Darts, 12);
        expect(s.first9Scored, 280);
      });

      test('counts a short finishing visit with its real dart count', () {
        final s = ThrowStats.fromThrows([
          _visit(180, remainingBefore: 501),
          _visit(180, remainingBefore: 321),
          _visit(141, remainingBefore: 141, dartsUsed: 3),
        ]);

        expect(s.first9Darts, 9);
        expect(s.first9Scored, 501);
        expect(s.first9Average, closeTo(167, 0.001));
      });

      test(
        'a bust among the opening visits contributes darts but no score',
        () {
          final s = ThrowStats.fromThrows([
            _visit(60),
            _visit(60, bust: true),
            _visit(60),
          ]);

          expect(s.first9Darts, 9);
          expect(s.first9Scored, 120);
        },
      );
    });

    test('the squared sum the snapshot needs adds up over scored visits', () {
      final s = ThrowStats.fromThrows([
        _visit(100),
        _visit(20),
        _visit(60, bust: true),
      ]);

      expect(
        s.scoreSumSquares,
        100 * 100 + 20 * 20,
        reason: 'the busted visit contributes nothing',
      );
    });
  });

  group('filters', () {
    test('throwsInLeg keeps only the given leg of the given set, in order', () {
      final throws = [
        _visit(1, leg: 1, set: 1),
        _visit(2, leg: 2, set: 1),
        _visit(3, leg: 1, set: 2),
        _visit(4, leg: 1, set: 1),
      ];

      expect(throwsInLeg(throws, 1, 1).map((t) => t.score), [1, 4]);
      expect(throwsInLeg(throws, 1, 2).map((t) => t.score), [3]);
      expect(throwsInLeg(throws, 3, 1), isEmpty);
    });

    test('throwsOfPlayer keeps only that player, in order', () {
      final throws = [
        _visit(1, playerId: 7),
        _visit(2, playerId: 8),
        _visit(3, playerId: 7),
      ];

      expect(throwsOfPlayer(throws, 7).map((t) => t.score), [1, 3]);
      expect(throwsOfPlayer(throws, 9), isEmpty);
    });
  });

  group('checkoutDartsInVisit', () {
    int darts(
      int remaining,
      List<int> thrown, {
      CheckoutMode mode = CheckoutMode.doubleOut,
      bool checkedOut = false,
    }) => checkoutDartsInVisit(remaining, thrown, mode, checkedOut: checkedOut);

    // The leg from the bug report, visit by visit. 156 is shown as
    // T20, T20, D18, the player opens with a plain 20 and works down from there.
    test('the reported leg puts no dart on a finish before the 25', () {
      expect(
        darts(156, [20, 60, 51]),
        0,
        reason: 'after the plain 20 no dart of this visit can finish',
      );
      expect(
        darts(25, [9, 0, 0]),
        2,
        reason: 'the S9 leaves 16, and the two misses fly at D8',
      );
      expect(
        darts(16, [14, 3, 0]),
        2,
        reason: '16 and the 2 the S14 leaves are both one-dart finishes',
      );
      expect(darts(8, [8], checkedOut: true), 1);
    });

    // The follow-up scenario: 60 left, S20, D5, S10, and then three darts from
    // 20. Two darts at a finish and three, five in total across two visits,
    // which are two attempts.
    test('counts every dart of a visit that flies at a finish', () {
      expect(
        darts(60, [20, 10, 10]),
        2,
        reason:
            'the opening dart flew from 60, the two after it from 40 and 30',
      );
      expect(
        darts(20, [0, 0, 0]),
        3,
        reason: '20 stays a one-dart finish through three misses',
      );
    });

    test('a finish reached on the last dart of a visit puts no dart on it', () {
      expect(
        darts(65, [0, 0, 25]),
        0,
        reason: 'the 40 it leaves belongs to the next visit',
      );
    });

    test('a bust does not undo the darts that already flew at the finish', () {
      expect(darts(16, [14, 3]), 2);
    });

    test('a visit that busts before reaching the finish counts none', () {
      expect(
        darts(60, [60]),
        0,
        reason: 'T20 busts double-out from 60 without ever being one away',
      );
    });

    test('the check-out rule decides what counts as one dart away', () {
      expect(darts(60, [0], mode: CheckoutMode.doubleOut), 0);
      expect(darts(60, [0], mode: CheckoutMode.masterOut), 1);
      expect(darts(19, [0], mode: CheckoutMode.doubleOut), 0);
      expect(darts(19, [0], mode: CheckoutMode.straightOut), 1);
    });

    test('a checkout counts one dart even without any recorded', () {
      expect(darts(501, const [], checkedOut: true), 1);
      expect(darts(501, const []), 0);
    });
  });
}
