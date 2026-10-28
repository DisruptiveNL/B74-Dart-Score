import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/utils/placement.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scoring visit that leaves [remainingAfter] on the board.
DartThrow _visit(int leg, int remainingBefore, int score, int msOffset) =>
    DartThrow(
      gameId: 1,
      playerId: 1,
      score: score,
      dartsUsed: 3,
      leg: leg,
      set: 1,
      remainingBefore: remainingBefore,
      thrownAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + msOffset),
      bust: false,
    );

/// A checkout visit in [leg], finishing at [ms] so the order of finishes is
/// deterministic.
DartThrow _checkout(int leg, int ms) => _visit(leg, 40, 40, ms);

void main() {
  group('completedLegPlacements', () {
    test('adds the last participant, who never checks out', () {
      // Three players, A and B check out. The leg ends the moment B finishes,
      // so C has no checkout throw of its own.
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_checkout(1, 200)],
        3: [_visit(1, 180, 60, 150)],
      };

      expect(legPlacements(throwsById, 1, 1), {1: 1, 2: 2});
      expect(completedLegPlacements(throwsById, 1, 1), {1: 1, 2: 2, 3: 3});
    });

    test('leaves an unfinished leg alone', () {
      // Only one of three has checked out, two are still playing.
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_visit(1, 180, 60, 120)],
        3: [_visit(1, 180, 60, 150)],
      };

      expect(completedLegPlacements(throwsById, 1, 1), {1: 1});
    });

    test('handles a two player leg', () {
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_visit(1, 180, 60, 80)],
      };

      expect(completedLegPlacements(throwsById, 1, 1), {1: 1, 2: 2});
    });
  });

  group('placementPointsTotal', () {
    test('awards the last place its point instead of dropping it', () {
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_checkout(1, 200)],
        3: [_visit(1, 180, 60, 150)],
      };

      final points = placementPointsTotal(throwsById, 1, 1);

      // 1st of 3: 3 base + 1 winner bonus, 2nd: 2, 3rd: 1.
      expect(points, {1: 4, 2: 2, 3: 1});
    });

    test('sums over several legs with changing finishing order', () {
      final throwsById = {
        1: [_checkout(1, 100), _visit(2, 180, 60, 350)],
        2: [_checkout(1, 200), _checkout(2, 300)],
        3: [_visit(1, 180, 60, 150), _checkout(2, 400)],
      };

      final points = placementPointsTotal(throwsById, 2, 1);

      // Leg 1: 1 -> 4, 2 -> 2, 3 -> 1. Leg 2: 2 -> 4, 3 -> 2, 1 -> 1.
      expect(points, {1: 5, 2: 6, 3: 3});
    });
  });

  group('placementRanking', () {
    test('counts the last place in the tie-breaking sum', () {
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_checkout(1, 200)],
        3: [_visit(1, 180, 60, 150)],
      };

      final ranking = placementRanking(throwsById, 1, 1);

      expect(ranking.legsWon, {1: 1, 2: 0, 3: 0});
      expect(ranking.placementSum, {1: 1, 2: 2, 3: 3});
    });
  });

  group('legPlacementsTable', () {
    test('gives every participant a position in a finished leg', () {
      final throwsById = {
        1: [_checkout(1, 100)],
        2: [_checkout(1, 200)],
        3: [_visit(1, 180, 60, 150)],
      };

      expect(legPlacementsTable(throwsById, 1, 1), {
        1: {1: 1, 2: 2, 3: 3},
      });
    });
  });

  group('placementPoints', () {
    test('gives last place one point and the winner a bonus', () {
      expect(placementPoints(1, 4), 5);
      expect(placementPoints(2, 4), 3);
      expect(placementPoints(3, 4), 2);
      expect(placementPoints(4, 4), 1);
    });
  });

  group('placementOrder', () {
    test('puts the most points first', () {
      expect(
        placementOrder(
          const [1, 2, 3],
          points: const {1: 4, 2: 9, 3: 6},
          legsWon: const {1: 2, 2: 1, 3: 0},
          placementSum: const {1: 3, 2: 4, 3: 8},
        ),
        [2, 3, 1],
      );
    });

    test('breaks a tie on points by legs won, and that one by the lowest sum '
        'of finishing positions', () {
      expect(
        placementOrder(
          const [1, 2, 3],
          points: const {1: 6, 2: 6, 3: 6},
          legsWon: const {1: 1, 2: 2, 3: 1},
          placementSum: const {1: 7, 2: 9, 3: 5},
        ),
        [2, 3, 1],
        reason: 'player 2 leads on legs, then 3 on the lower sum',
      );
    });

    test('leaves slots that tie on everything in the order they came in', () {
      expect(
        placementOrder(
          const [3, 1, 2],
          points: const {1: 0, 2: 0, 3: 0},
          legsWon: const {1: 0, 2: 0, 3: 0},
          placementSum: const {1: 0, 2: 0, 3: 0},
        ),
        [3, 1, 2],
      );
    });
  });
}
