import 'dart:math';

import '../models/bot_level.dart';
import 'dartboard_geometry.dart';

/// How far a bot's darts scatter around the point it aims at, as the standard
/// deviation in millimetres of a circular normal distribution, one per tier.
///
/// This one number is the whole difference between the tiers. It was tuned
/// against the three-dart averages the calibration test pins, so change it
/// there and here together.
double scatterOf(BotLevel level) => switch (level) {
  BotLevel.rookie => 25.0,
  BotLevel.amateur => 16.5,
  BotLevel.semiPro => 12.0,
  BotLevel.pro => 8.5,
  BotLevel.legend => 6.5,
};

/// The three-dart average a tier plays to, which is what its name promises
/// and what the setup shows next to it. The calibration test holds
/// [scatterOf] to these numbers.
int expectedAverageOf(BotLevel level) => switch (level) {
  BotLevel.rookie => 35,
  BotLevel.amateur => 50,
  BotLevel.semiPro => 65,
  BotLevel.pro => 85,
  BotLevel.legend => 100,
};

/// Whether a bot of [level] goes for the triple when a plain hit on the
/// number would do, as in Cricket, Shanghai and Around the Clock. The upper
/// tiers land the triple often enough for it to pay; below them the fat
/// single is the surer way onto the number at all.
bool aimsForTriples(BotLevel level) => level.index >= BotLevel.semiPro.index;

/// Throws darts for a computer opponent: takes the target the strategy picked,
/// lands the dart somewhere around it, and reports the field it came down in.
///
/// The scatter is a two dimensional normal distribution with the tier's
/// [scatterOf] on both axes, which is the shape real throws cluster in. That
/// is what makes the errors look right without any rule about them: a wide
/// throw at the 20 finds the 1 or the 5, a dart at a double lands inside or
/// outside the wire, a triple attempt is mostly a fat single.
class BotThrower {
  final Random _rng;

  /// A thrower drawing from [rng], or from a fresh unseeded one. Tests hand in
  /// a seeded generator so a game replays the same way every run.
  BotThrower({Random? rng}) : _rng = rng ?? Random();

  /// Throws one dart of a bot at [level] aimed at [target].
  BoardHit throwAt(BoardHit target, BotLevel level) {
    final aim = aimPointFor(target);
    final sigma = scatterOf(level);
    return hitAt((
      x: aim.x + _gaussian() * sigma,
      y: aim.y + _gaussian() * sigma,
    ));
  }

  /// One draw from the standard normal distribution, by Box-Muller.
  double _gaussian() {
    // nextDouble can return zero, whose logarithm is not a number.
    final u1 = 1.0 - _rng.nextDouble();
    final u2 = _rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}
