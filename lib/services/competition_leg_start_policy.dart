/// Deterministic start policy for a two-player competition X01 match.
///
/// Slot 0 is the player who started leg one. This module deliberately does
/// not persist a bull result or change GameProvider's generic X01 behaviour.
/// Persistence and the scoring UI are integrated in the next patch.
class CompetitionLegStartPolicy {
  const CompetitionLegStartPolicy._();

  /// Returns the zero-based starter slot for a leg, unless the deciding leg
  /// requires a fresh bull result that has not yet been recorded.
  ///
  /// [decidingBullWinnerSlot] must be 0 or 1 and is only used on the decider.
  static int? starterForLeg({
    required int legNumber,
    required int bestOf,
    required int homeLegs,
    required int awayLegs,
    required bool bullDecidingLeg,
    int? decidingBullWinnerSlot,
  }) {
    if (legNumber < 1) throw ArgumentError.value(legNumber, 'legNumber');
    if (bestOf < 1 || bestOf.isEven) throw ArgumentError.value(bestOf, 'bestOf');
    if (homeLegs < 0 || awayLegs < 0) {
      throw ArgumentError('Won legs cannot be negative');
    }
    if (decidingBullWinnerSlot != null &&
        decidingBullWinnerSlot != 0 && decidingBullWinnerSlot != 1) {
      throw ArgumentError.value(decidingBullWinnerSlot, 'decidingBullWinnerSlot');
    }
    final threshold = bestOf ~/ 2;
    final isDecider = bullDecidingLeg && bestOf >= 3 &&
        homeLegs == threshold && awayLegs == threshold;
    if (isDecider) return decidingBullWinnerSlot;
    return (legNumber - 1) % 2;
  }

  /// A recorded bull winner is relevant only to the actual deciding leg.
  static bool requiresBull({
    required int bestOf,
    required int homeLegs,
    required int awayLegs,
    required bool enabled,
  }) {
    if (!enabled || bestOf < 3 || bestOf.isEven) return false;
    final threshold = bestOf ~/ 2;
    return homeLegs == threshold && awayLegs == threshold;
  }
}
