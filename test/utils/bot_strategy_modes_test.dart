import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/utils/bot_strategy_around_the_clock.dart';
import 'package:dartscore_app/utils/bot_strategy_cricket.dart';
import 'package:dartscore_app/utils/bot_strategy_shanghai.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('where the bot aims in Cricket', () {
    BoardHitMatcher aims(int field, int multiplier) =>
        BoardHitMatcher(field, multiplier);

    test('closes from the top, on the triple or the fat single by tier', () {
      final fresh = cricketTarget(
        ownMarks: {},
        opponentMarks: [{}],
        ownScore: 0,
        opponentScores: [0],
        variant: CricketVariant.normal,
        scoring: CricketScoringMode.standard,
        aimTriples: true,
      );
      expect(fresh, aims(20, 3));

      final weak = cricketTarget(
        ownMarks: {20: 3, 19: 3},
        opponentMarks: [{}],
        ownScore: 0,
        opponentScores: [0],
        variant: CricketVariant.normal,
        scoring: CricketScoringMode.standard,
        aimTriples: false,
      );
      expect(weak, aims(18, 1));
    });

    test('scores on a closed field the opponent has open when behind', () {
      final target = cricketTarget(
        ownMarks: {20: 3, 19: 1},
        opponentMarks: [
          {20: 1, 19: 3},
        ],
        ownScore: 40,
        opponentScores: [95],
        variant: CricketVariant.normal,
        scoring: CricketScoringMode.standard,
        aimTriples: true,
      );
      expect(
        target,
        aims(20, 3),
        reason: 'the 20 is closed for us and open for them',
      );
    });

    test('keeps closing when ahead, even with a scoring field available', () {
      final target = cricketTarget(
        ownMarks: {20: 3, 19: 1},
        opponentMarks: [
          {20: 1, 19: 3},
        ],
        ownScore: 95,
        opponentScores: [40],
        variant: CricketVariant.normal,
        scoring: CricketScoringMode.standard,
        aimTriples: true,
      );
      expect(target, aims(19, 3));
    });

    test('reads behind the other way round in cut-throat', () {
      final target = cricketTarget(
        ownMarks: {20: 3},
        opponentMarks: [
          {20: 0},
        ],
        ownScore: 60,
        opponentScores: [0],
        variant: CricketVariant.cutThroat,
        scoring: CricketScoringMode.standard,
        aimTriples: true,
      );
      expect(
        target,
        aims(20, 3),
        reason: 'more points is behind, so push points onto them',
      );
    });

    test(
      'only scores once everything of its own is closed and it is not ahead',
      () {
        final allClosed = {for (final f in cricketFields) f: 3};
        final target = cricketTarget(
          ownMarks: allClosed,
          opponentMarks: [
            {20: 3, 19: 3, 15: 0},
          ],
          ownScore: 10,
          opponentScores: [50],
          variant: CricketVariant.normal,
          scoring: CricketScoringMode.standard,
          aimTriples: true,
        );
        expect(
          target,
          aims(18, 3),
          reason: 'the highest field they still have open',
        );
      },
    );

    test(
      'never aims a triple under simple scoring, where a hit is one mark',
      () {
        final target = cricketTarget(
          ownMarks: {},
          opponentMarks: [{}],
          ownScore: 0,
          opponentScores: [0],
          variant: CricketVariant.normal,
          scoring: CricketScoringMode.simple,
          aimTriples: true,
        );
        expect(target, aims(20, 1));
      },
    );

    test('aims the bull at its centre', () {
      final target = cricketTarget(
        ownMarks: {
          for (final f in cricketFields)
            if (f != 25) f: 3,
        },
        opponentMarks: [{}],
        ownScore: 0,
        opponentScores: [0],
        variant: CricketVariant.normal,
        scoring: CricketScoringMode.standard,
        aimTriples: false,
      );
      expect(target, aims(25, 2));
    });
  });

  group('where the bot aims in Shanghai', () {
    test('takes the highest ring still missing for a Shanghai', () {
      expect(
        shanghaiTarget(target: 4, neededMultipliers: [1, 2, 3]),
        BoardHitMatcher(4, 3),
      );
      expect(
        shanghaiTarget(target: 4, neededMultipliers: [1, 2]),
        BoardHitMatcher(4, 2),
      );
      expect(
        shanghaiTarget(target: 4, neededMultipliers: [1]),
        BoardHitMatcher(4, 1),
      );
    });

    test('goes for the triple once no Shanghai is on', () {
      expect(
        shanghaiTarget(target: 7, neededMultipliers: null),
        BoardHitMatcher(7, 3),
      );
      expect(
        shanghaiTarget(target: 7, neededMultipliers: []),
        BoardHitMatcher(7, 3),
      );
    });
  });

  group('where the bot aims in Around the Clock', () {
    test('takes the single or the triple of the number by tier', () {
      expect(
        aroundTheClockTarget(
          target: 5,
          variant: AroundTheClockVariant.basic,
          aimTriples: false,
        ),
        BoardHitMatcher(5, 1),
      );
      expect(
        aroundTheClockTarget(
          target: 5,
          variant: AroundTheClockVariant.skipRules,
          aimTriples: true,
        ),
        BoardHitMatcher(5, 3),
      );
    });

    test('works through the missing segments from the single up', () {
      expect(
        aroundTheClockTarget(
          target: 12,
          variant: AroundTheClockVariant.fullSegments,
          aimTriples: true,
          neededSegments: [2, 3],
        ),
        BoardHitMatcher(12, 2),
      );
      expect(
        aroundTheClockTarget(
          target: 25,
          variant: AroundTheClockVariant.fullSegments,
          aimTriples: true,
          neededSegments: [1],
        ),
        BoardHitMatcher(25, 1),
      );
    });

    test('aims the bull at its centre otherwise', () {
      expect(
        aroundTheClockTarget(
          target: 25,
          variant: AroundTheClockVariant.basic,
          aimTriples: false,
        ),
        BoardHitMatcher(25, 2),
      );
    });
  });

  test('the upper three tiers go for triples, the lower two do not', () {
    expect(BotLevel.values.where(aimsForTriples), [
      BotLevel.semiPro,
      BotLevel.pro,
      BotLevel.legend,
    ]);
  });
}

/// Matches a board hit by field and ring.
class BoardHitMatcher extends Matcher {
  final int field;
  final int multiplier;
  BoardHitMatcher(this.field, this.multiplier);

  @override
  bool matches(Object? item, Map matchState) =>
      item is ({int field, int multiplier}) &&
      item.field == field &&
      item.multiplier == multiplier;

  @override
  Description describe(Description d) =>
      d.add('(field: $field, multiplier: $multiplier)');
}
