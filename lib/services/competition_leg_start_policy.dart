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
    if (bestOf < 1 || bestOf.isEven)
      throw ArgumentError.value(bestOf, 'bestOf');
    if (homeLegs < 0 || awayLegs < 0) {
      throw ArgumentError('Won legs cannot be negative');
    }
    if (decidingBullWinnerSlot != null &&
        decidingBullWinnerSlot != 0 &&
        decidingBullWinnerSlot != 1) {
      throw ArgumentError.value(
        decidingBullWinnerSlot,
        'decidingBullWinnerSlot',
      );
    }
    final threshold = bestOf ~/ 2;
    final isDecider =
        bullDecidingLeg &&
        bestOf >= 3 &&
        homeLegs == threshold &&
        awayLegs == threshold;
    if (isDecider) return decidingBullWinnerSlot;
    return (legNumber - 1) % 2;
  }

  /// Resolves a Singles starter using *home/away* slots (home=0, away=1).
  /// Unlike [starterForLeg], this does not assume home started leg one.
  /// A null result means that a bull winner must first be recorded.
  static int? singlesStarter({
    required int legNumber,
    required int bestOf,
    required int homeLegs,
    required int awayLegs,
    required int firstLegStarterSlot,
    required bool bullDecidingLeg,
    int? decidingBullWinnerSlot,
  }) {
    if (firstLegStarterSlot != 0 && firstLegStarterSlot != 1) {
      throw ArgumentError.value(firstLegStarterSlot, 'firstLegStarterSlot');
    }
    if (!{3, 5, 7, 9, 11}.contains(bestOf)) {
      throw ArgumentError.value(bestOf, 'bestOf');
    }
    if (legNumber < 1 || legNumber > bestOf) {
      throw RangeError.range(legNumber, 1, bestOf, 'legNumber');
    }
    final target = (bestOf + 1) ~/ 2;
    if (homeLegs < 0 || awayLegs < 0 ||
        homeLegs >= target || awayLegs >= target ||
        homeLegs + awayLegs != legNumber - 1) {
      throw ArgumentError('Invalid Singles leg state');
    }
    if (decidingBullWinnerSlot != null &&
        decidingBullWinnerSlot != 0 && decidingBullWinnerSlot != 1) {
      throw ArgumentError.value(decidingBullWinnerSlot, 'decidingBullWinnerSlot');
    }
    if (requiresBull(
      bestOf: bestOf,
      homeLegs: homeLegs,
      awayLegs: awayLegs,
      enabled: bullDecidingLeg,
    )) {
      return decidingBullWinnerSlot;
    }
    return legNumber.isOdd ? firstLegStarterSlot : 1 - firstLegStarterSlot;
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

  /// Team match slots follow the official B74 competition order:
  /// away, home, away, home. Beer game starts away.
  /// Returns 'bull' when the first-leg bull option is enabled.
  static String teamStartPolicy({
    required String kind,
    required int slot,
    bool bullStart = false,
  }) {
    if (kind == 'beer1001') {
      if (slot != 1) throw RangeError.range(slot, 1, 1, 'slot');
      return bullStart ? 'bull' : 'away';
    }
    if (kind != 'doubles701') {
      throw ArgumentError.value(kind, 'kind', 'Unsupported team game');
    }
    if (slot < 1 || slot > 4) {
      throw RangeError.range(slot, 1, 4, 'slot');
    }
    return bullStart ? 'bull' : (slot.isOdd ? 'away' : 'home');
  }

  /// A deciding-leg bull is configurable for team matches.
  /// Slot 0 is home and slot 1 is away, independent of who started leg one.
  static int? teamLegStarter({
    required int legNumber,
    required int bestOf,
    required int homeLegs,
    required int awayLegs,
    required int firstLegStarterSlot,
    int? decidingBullWinnerSlot,
    bool bullDecidingLeg = true,
  }) {
    if (firstLegStarterSlot != 0 && firstLegStarterSlot != 1) {
      throw ArgumentError.value(firstLegStarterSlot, 'firstLegStarterSlot');
    }
    if (!{3, 5, 7, 9, 11}.contains(bestOf)) {
      throw ArgumentError.value(bestOf, 'bestOf');
    }
    if (homeLegs < 0 || awayLegs < 0 ||
        homeLegs >= (bestOf + 1) ~/ 2 ||
        awayLegs >= (bestOf + 1) ~/ 2) {
      throw ArgumentError('Invalid unfinished team match score');
    }
    if (decidingBullWinnerSlot != null &&
        decidingBullWinnerSlot != 0 && decidingBullWinnerSlot != 1) {
      throw ArgumentError.value(decidingBullWinnerSlot, 'decidingBullWinnerSlot');
    }
    if (requiresBull(
      bestOf: bestOf, homeLegs: homeLegs, awayLegs: awayLegs,
      enabled: bullDecidingLeg,
    )) {
      return decidingBullWinnerSlot;
    }
    return (legNumber - 1).isEven
        ? firstLegStarterSlot
        : 1 - firstLegStarterSlot;
  }
}
