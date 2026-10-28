import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/utils/around_the_clock_rules.dart';
import 'package:dartscore_app/utils/cricket_stats.dart';
import 'package:dartscore_app/utils/shanghai_stats.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 9, 11);

CricketThrow _c(int field, int multiplier) => CricketThrow(
  gameId: 1,
  playerId: 1,
  field: field,
  multiplier: multiplier,
  leg: 1,
  set_: 1,
  thrownAt: _at,
);

ShanghaiThrow _s(int target, int multiplier, {int round = 1}) => ShanghaiThrow(
  gameId: 1,
  playerId: 1,
  target: target,
  multiplier: multiplier,
  round: round,
  leg: 1,
  set_: 1,
  thrownAt: _at,
);

AroundTheClockThrow _a(int field, int multiplier) => AroundTheClockThrow(
  gameId: 1,
  playerId: 1,
  field: field,
  multiplier: multiplier,
  leg: 1,
  set_: 1,
  thrownAt: _at,
);

void main() {
  group('Cricket numbers', () {
    test('count marks per round over every hit on a Cricket field', () {
      final throws = [
        _c(20, 3), _c(20, 1), _c(0, 0), // 4 marks
        _c(19, 1), _c(19, 1), _c(19, 2), // 4 marks
        _c(0, 0), _c(18, 1), _c(0, 0), // 1 mark
      ];
      final stats = CricketStats.of(throws, CricketScoringMode.standard);

      expect(stats.darts, 9);
      expect(stats.hits, 6);
      expect(stats.marks, 9);
      expect(stats.marksPerRound, 3.0);
      expect(stats.hitRate, closeTo(0.667, 0.001));
      expect(stats.bestVisitMarks, 4);
      expect(cricketVisits(throws), hasLength(3));
    });

    test(
      'count a hit as one mark under simple scoring and ignore stray numbers',
      () {
        expect(cricketMarksOf(_c(20, 3), CricketScoringMode.simple), 1);
        expect(cricketMarksOf(_c(5, 3), CricketScoringMode.standard), 0);
        expect(cricketMarksOf(_c(25, 2), CricketScoringMode.standard), 2);
      },
    );

    test('leave a short last visit as the one in progress', () {
      final visits = cricketVisits([
        _c(20, 1),
        _c(20, 1),
        _c(20, 1),
        _c(19, 1),
      ]);
      expect(visits.map((v) => v.length), [3, 1]);
    });
  });

  group('Shanghai numbers', () {
    test('score the ring times the target and see a classic Shanghai', () {
      final throws = [
        _s(1, 1), _s(1, 2), _s(1, 3), // 6 points, Shanghai
        _s(2, 0, round: 2), _s(2, 3, round: 2), _s(2, 1, round: 2), // 8 points
      ];
      final stats = ShanghaiStats.of(throws, ShanghaiVariant.classic, 3);

      expect(stats.points, 14);
      expect(stats.visits, 2);
      expect(stats.pointsPerRound, 7.0);
      expect(stats.hits, 5);
      expect(stats.bestVisitPoints, 8);
      expect(stats.shanghais, 1);
    });

    test('see a Shanghai on three consecutive numbers in clockwise', () {
      final visit = [
        _s(1, 1),
        _s(2, 1),
        _s(3, 1),
        _s(4, 0),
        _s(5, 0),
        _s(6, 0),
        _s(7, 0),
      ];
      expect(isShanghaiVisit(visit, ShanghaiVariant.clockwise), isTrue);
      expect(
        isShanghaiVisit([
          _s(1, 1),
          _s(2, 0),
          _s(3, 1),
        ], ShanghaiVariant.sequential),
        isFalse,
      );
      expect(shanghaiVisits(visit, 7), hasLength(1));
    });
  });

  group('the Around the Clock rule', () {
    const start = (progress: 0, hitSegments: <int>{});

    test('advances on any ring of the number in basic', () {
      final next = applyAroundTheClockDart(
        variant: AroundTheClockVariant.basic,
        position: start,
        field: 1,
        multiplier: 3,
      );
      expect(next.progress, 1);
      expect(
        applyAroundTheClockDart(
          variant: AroundTheClockVariant.basic,
          position: start,
          field: 2,
          multiplier: 1,
        ).progress,
        0,
      );
    });

    test('collects the rings before moving on under full segments', () {
      var p = applyAroundTheClockDart(
        variant: AroundTheClockVariant.fullSegments,
        position: start,
        field: 1,
        multiplier: 1,
      );
      expect(p.progress, 0);
      expect(p.hitSegments, {1});
      p = applyAroundTheClockDart(
        variant: AroundTheClockVariant.fullSegments,
        position: p,
        field: 1,
        multiplier: 2,
      );
      p = applyAroundTheClockDart(
        variant: AroundTheClockVariant.fullSegments,
        position: p,
        field: 1,
        multiplier: 3,
      );
      expect(p.progress, 1);
      expect(p.hitSegments, isEmpty);
    });

    test('jumps by the ring and lets the bull skip under skip rules', () {
      expect(
        applyAroundTheClockDart(
          variant: AroundTheClockVariant.skipRules,
          position: start,
          field: 1,
          multiplier: 3,
        ).progress,
        3,
      );
      expect(
        applyAroundTheClockDart(
          variant: AroundTheClockVariant.skipRules,
          position: start,
          field: 25,
          multiplier: 2,
        ).progress,
        1,
      );
    });

    test('never runs past the end of the board', () {
      final last = (
        progress: aroundTheClockOrder.length - 1,
        hitSegments: <int>{},
      );
      final next = applyAroundTheClockDart(
        variant: AroundTheClockVariant.skipRules,
        position: last,
        field: 25,
        multiplier: 2,
      );
      expect(next.progress, aroundTheClockOrder.length);
    });
  });

  group('Around the Clock numbers', () {
    test('tell hits from misses by replaying the rule', () {
      // Spelled through the order rather than as numbers, so the test says
      // nothing about which number the clock starts on.
      final o = aroundTheClockOrder;
      final throws = [
        _a(o[0], 1), _a(0, 0), _a(o[1], 1), // 2 hits
        _a(o[2], 1),
        _a(o[3], 1),
        _a(o[4], 1), // 3 hits, streak of 4 with the second
        _a(o[6], 1), _a(0, 0), _a(o[5], 1), // 1 hit, the o[6] came too early
      ];
      final stats = AroundTheClockStats.of(throws, AroundTheClockVariant.basic);

      expect(stats.darts, 9);
      expect(stats.hits, 6);
      expect(stats.progress, 6);
      expect(stats.dartsPerTarget, 1.5);
      expect(stats.hitRate, closeTo(0.667, 0.001));
      expect(stats.longestStreak, 4);
      expect(stats.fieldsSkipped, 0);
      expect(stats.visitHits, [
        [true, false, true],
        [true, true, true],
        [false, false, true],
      ]);
    });

    test('count the numbers skipped under skip rules', () {
      final o = aroundTheClockOrder;
      final throws = [_a(o[0], 3), _a(25, 2), _a(o[4], 1)];
      final stats = AroundTheClockStats.of(
        throws,
        AroundTheClockVariant.skipRules,
      );

      expect(stats.progress, 5);
      expect(stats.hits, 3);
      expect(
        stats.fieldsSkipped,
        3,
        reason: 'two numbers by the triple, one by the joker',
      );
    });
  });
}
