import 'dartboard_geometry.dart';

/// Where a bot aims its next dart in Shanghai: at [target], the number the
/// provider says the dart is for.
///
/// In the classic variant a Shanghai needs the single, the double and the
/// triple of the round's number in one visit, and [neededMultipliers] says
/// which are still missing while one is reachable; the bot takes the highest
/// of them, so the points come first and the Shanghai stays open. Where no
/// Shanghai is reachable, and in the variants that score on consecutive
/// numbers, the triple is simply the ring worth most.
BoardHit shanghaiTarget({required int target, List<int>? neededMultipliers}) {
  if (neededMultipliers != null && neededMultipliers.isNotEmpty) {
    final highest = neededMultipliers.reduce((a, b) => a > b ? a : b);
    return (field: target, multiplier: highest);
  }
  return (field: target, multiplier: 3);
}
