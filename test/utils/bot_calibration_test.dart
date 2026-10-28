import 'dart:math';

import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/utils/bot_strategy_x01.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:dartscore_app/utils/dartboard_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// How far a tier's measured average may drift from the one `expectedAverageOf`
/// promises. A change to `scatterOf` that moves a tier out of this band is a
/// change to the product, not a tuning.
const _tolerance = 4.0;

/// Plays [legs] legs of 501 double-out for one bot and returns its three-dart
/// average over all of them, busts counted as zero the way `ThrowStats`
/// counts them.
({double average, int darts}) _play(BotLevel level, int legs, Random rng) {
  final thrower = BotThrower(rng: rng);
  var scored = 0;
  var darts = 0;

  for (var leg = 0; leg < legs; leg++) {
    var remaining = 501;
    while (remaining > 0) {
      var visitScore = 0;
      var bust = false;
      for (var dart = 0; dart < 3; dart++) {
        final target = x01Target(
          remaining: remaining - visitScore,
          dartsLeft: 3 - dart,
          checkedIn: true,
        );
        final hit = thrower.throwAt(target, level);
        darts++;
        visitScore += scoreOf(hit);
        final left = remaining - visitScore;
        if (left < 0 || left == 1 || (left == 0 && hit.multiplier != 2)) {
          bust = true;
          break;
        }
        if (left == 0) break;
      }
      if (!bust) {
        scored += visitScore;
        remaining -= visitScore;
      }
    }
  }
  return (average: scored / darts * 3, darts: darts);
}

void main() {
  group('the tiers play the averages their names promise', () {
    for (final level in BotLevel.values) {
      test('${level.name} averages about ${expectedAverageOf(level)}', () {
        final result = _play(level, 300, Random(20260910));

        expect(
          result.average,
          closeTo(expectedAverageOf(level), _tolerance),
          reason: '${level.name} over ${result.darts} darts',
        );
      });
    }

    test('each tier is better than the one below it', () {
      final averages = [
        for (final level in BotLevel.values)
          _play(level, 100, Random(7)).average,
      ];
      for (var i = 1; i < averages.length; i++) {
        expect(averages[i], greaterThan(averages[i - 1]));
      }
    });
  });
}
