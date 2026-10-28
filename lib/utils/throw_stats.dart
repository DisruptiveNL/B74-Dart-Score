import '../models/dart_throw.dart';
import '../models/game.dart';
import 'finish_calculator.dart';

/// How many darts of a visit were thrown at a finish: darts the player let go
/// while the remaining could be taken out by that single dart.
///
/// Zero means the visit never was an attempt at the leg. Being in checkout
/// range is not enough: a visit that starts on 156 and opens with a plain 20
/// can no longer be finished, and counting it would put an attempt on the
/// record that never existed on the board.
///
/// Two statistics come out of this. The check-out rate counts a visit once,
/// however many darts it put on a double, and answers how often a chance at
/// the leg was taken. The double rate counts every such dart and answers how
/// well the double itself is thrown. A visit from 60 that goes S20, D5, S10 is
/// one attempt and two darts at a finish: the opening dart flew from 60, which
/// no single dart takes out, the two after it from 40 and from 30, which do.
///
/// [dartScores] are the points of the individual darts in throwing order, so
/// the remaining can be walked dart by dart. [checkedOut] guarantees at least
/// one, because the dart that finished the leg was by definition thrown at the
/// finish even where the darts themselves were not recorded.
///
/// The migration in `db_helper.dart` calls this with hits decoded from the
/// database and the game provider with the visit it is about to record, which
/// is why it takes plain ints rather than the provider's own dart type.
int checkoutDartsInVisit(
  int remainingBefore,
  List<int> dartScores,
  CheckoutMode checkoutMode, {
  bool checkedOut = false,
}) {
  var remaining = remainingBefore;
  var darts = 0;
  for (final score in dartScores) {
    if (FinishCalculator.canFinishWithOneDart(remaining, checkoutMode)) {
      darts++;
    }
    remaining -= score;
    if (remaining < 0) break;
  }
  return darts == 0 && checkedOut ? 1 : darts;
}

/// Aggregated statistics derived from a list of X01 visits.
///
/// The single implementation of these formulas in the app. The live info screen
/// computes them from the visits held in memory, the summary and history screens
/// from the visits of one finished game, and `DbHelper` from the visits it is
/// about to archive, so a number read during a game means exactly what the same
/// number means on the lifetime stats screen years later.
///
/// The values are pinned by hand-computed cases in
/// `test/utils/throw_stats_test.dart`; that a snapshot stores them under the
/// right keys is a separate concern, checked by
/// `test/database/stats_snapshot_keys_test.dart`.
///
/// Two deliberate omissions:
/// * Legs won is not part of this record. The live screens read
///   `PlayerState.legsWon`, which the game provider maintains correctly for the
///   placement mode where a leg is played out by everyone.
/// * Only committed visits are counted. Darts of a visit that is still being
///   entered are not included, because folding them in would make every average
///   jump back once the visit is committed.
class ThrowStats {
  /// Number of committed visits (turns), busts included.
  final int totalVisits;

  /// Number of darts thrown across all visits, busts included.
  final int totalDarts;

  /// Points scored across all visits; a bust contributes nothing.
  final int totalScored;

  /// Number of visits that busted.
  final int busts;

  /// Highest score of a single visit; busts are ignored.
  final int highestVisit;

  /// Highest score that finished a leg.
  final int highestCheckout;

  final int count180;
  final int count140plus;
  final int count100plus;

  /// Visits that put the player one dart away from the finish, busts included.
  /// Decided per visit when it is recorded, see [checkoutDartsInVisit]; being
  /// in checkout range does not by itself make a visit an attempt.
  final int checkoutAttempts;

  /// Attempts that actually finished the leg.
  final int checkoutSuccesses;

  /// Individual darts thrown at a finish, so a visit that put three darts on a
  /// double counts three. The denominator of the double rate, where
  /// [checkoutAttempts] is the denominator of the check-out rate.
  final int checkoutDarts;

  /// Sum of the squared visit scores. Only the snapshot needs it, to keep the
  /// lifetime standard deviation computable after games have been deleted.
  final int scoreSumSquares;

  /// Darts used in the opening three visits of every leg.
  final int first9Darts;

  /// Points scored in the opening three visits of every leg.
  final int first9Scored;

  final int coAttemptSub40;
  final int coSuccessSub40;
  final int coAttemptSub60;
  final int coSuccessSub60;
  final int coAttemptSub100;
  final int coSuccessSub100;
  final int coAttemptSub170;
  final int coSuccessSub170;

  const ThrowStats._({
    required this.totalVisits,
    required this.totalDarts,
    required this.totalScored,
    required this.busts,
    required this.highestVisit,
    required this.highestCheckout,
    required this.count180,
    required this.count140plus,
    required this.count100plus,
    required this.checkoutAttempts,
    required this.checkoutSuccesses,
    required this.checkoutDarts,
    required this.scoreSumSquares,
    required this.first9Darts,
    required this.first9Scored,
    required this.coAttemptSub40,
    required this.coSuccessSub40,
    required this.coAttemptSub60,
    required this.coSuccessSub60,
    required this.coAttemptSub100,
    required this.coSuccessSub100,
    required this.coAttemptSub170,
    required this.coSuccessSub170,
  });

  /// Stats of a player who has not thrown yet: every counter is zero.
  static const ThrowStats empty = ThrowStats._(
    totalVisits: 0,
    totalDarts: 0,
    totalScored: 0,
    busts: 0,
    highestVisit: 0,
    highestCheckout: 0,
    count180: 0,
    count140plus: 0,
    count100plus: 0,
    checkoutAttempts: 0,
    checkoutSuccesses: 0,
    checkoutDarts: 0,
    scoreSumSquares: 0,
    first9Darts: 0,
    first9Scored: 0,
    coAttemptSub40: 0,
    coSuccessSub40: 0,
    coAttemptSub60: 0,
    coSuccessSub60: 0,
    coAttemptSub100: 0,
    coSuccessSub100: 0,
    coAttemptSub170: 0,
    coSuccessSub170: 0,
  );

  /// Aggregates [throws] into one stats record.
  ///
  /// [throws] is expected in throwing order, which is how the game provider and
  /// the database both hand it out. The order only matters for the first 9
  /// values, which take the opening visits of each leg.
  factory ThrowStats.fromThrows(List<DartThrow> throws) {
    if (throws.isEmpty) return empty;

    int totalDarts = 0, totalScored = 0, busts = 0;
    int highestVisit = 0, highestCheckout = 0;
    int count180 = 0, count140plus = 0, count100plus = 0;
    int checkoutAttempts = 0, checkoutSuccesses = 0, checkoutDarts = 0;
    int scoreSumSquares = 0;
    int first9Darts = 0, first9Scored = 0;
    int coAt40 = 0, coOk40 = 0;
    int coAt60 = 0, coOk60 = 0;
    int coAt100 = 0, coOk100 = 0;
    int coAt170 = 0, coOk170 = 0;

    // Visits already seen per leg, so the opening three of each leg can be
    // picked out without sorting the list. Keyed by game as well, because leg
    // and set numbers repeat across games and a lifetime list spans many.
    final visitsPerLeg = <String, int>{};

    for (final t in throws) {
      totalDarts += t.dartsUsed;

      final legKey = '${t.gameId}-${t.set}-${t.leg}';
      final legVisits = visitsPerLeg[legKey] ?? 0;
      visitsPerLeg[legKey] = legVisits + 1;
      if (legVisits < 3) {
        first9Darts += t.dartsUsed;
        first9Scored += t.bust ? 0 : t.score;
      }

      if (t.bust) {
        busts++;
      } else {
        totalScored += t.score;
        scoreSumSquares += t.score * t.score;
        if (t.score > highestVisit) highestVisit = t.score;
        if (t.score == 180) count180++;
        if (t.score >= 140) count140plus++;
        if (t.score >= 100) count100plus++;
      }

      // The band still follows the remaining the visit started on. Banding by
      // the remaining at the moment the finish came into reach would put every
      // attempt below 61 and leave the two upper bands permanently empty.
      if (t.checkoutAttempt) {
        checkoutAttempts++;
        checkoutDarts += t.checkoutDarts;
        final success = !t.bust && t.remainingBefore - t.score == 0;
        if (t.remainingBefore <= 40) {
          coAt40++;
          if (success) coOk40++;
        } else if (t.remainingBefore <= 60) {
          coAt60++;
          if (success) coOk60++;
        } else if (t.remainingBefore <= 100) {
          coAt100++;
          if (success) coOk100++;
        } else {
          coAt170++;
          if (success) coOk170++;
        }
        if (success) {
          checkoutSuccesses++;
          if (t.score > highestCheckout) highestCheckout = t.score;
        }
      }
    }

    return ThrowStats._(
      totalVisits: throws.length,
      totalDarts: totalDarts,
      totalScored: totalScored,
      busts: busts,
      highestVisit: highestVisit,
      highestCheckout: highestCheckout,
      count180: count180,
      count140plus: count140plus,
      count100plus: count100plus,
      checkoutAttempts: checkoutAttempts,
      checkoutSuccesses: checkoutSuccesses,
      checkoutDarts: checkoutDarts,
      scoreSumSquares: scoreSumSquares,
      first9Darts: first9Darts,
      first9Scored: first9Scored,
      coAttemptSub40: coAt40,
      coSuccessSub40: coOk40,
      coAttemptSub60: coAt60,
      coSuccessSub60: coOk60,
      coAttemptSub100: coAt100,
      coSuccessSub100: coOk100,
      coAttemptSub170: coAt170,
      coSuccessSub170: coOk170,
    );
  }

  /// Three-dart average over all visits; busts count as zero scored.
  double get average => totalDarts == 0 ? 0 : (totalScored / totalDarts) * 3;

  /// Three-dart average over the opening three visits of every leg.
  double get first9Average =>
      first9Darts == 0 ? 0 : (first9Scored / first9Darts) * 3;

  /// Share of visits that busted, in percent.
  double get bustRate => totalVisits == 0 ? 0 : (busts / totalVisits) * 100;

  /// Share of checkout attempts that finished a leg, in percent. One visit
  /// counts once, however many darts it put on a double.
  double get checkoutRate =>
      checkoutAttempts == 0 ? 0 : (checkoutSuccesses / checkoutAttempts) * 100;

  /// Share of the darts thrown at a finish that hit it, in percent. Every dart
  /// counts, so this is the accuracy on the double rather than how often a
  /// chance at the leg was taken.
  double get doubleRate =>
      checkoutDarts == 0 ? 0 : (checkoutSuccesses / checkoutDarts) * 100;
}

/// The best three-dart average reached in any single game within [throws].
///
/// Groups by game id, so it works both for the visits of one game, where the
/// result is simply that game's average, and for a player's whole history.
double bestGameAverage(List<DartThrow> throws) {
  final darts = <int, int>{};
  final scored = <int, int>{};
  for (final t in throws) {
    darts[t.gameId] = (darts[t.gameId] ?? 0) + t.dartsUsed;
    if (!t.bust) scored[t.gameId] = (scored[t.gameId] ?? 0) + t.score;
  }

  var best = 0.0;
  for (final entry in darts.entries) {
    if (entry.value == 0) continue;
    final average = (scored[entry.key] ?? 0) / entry.value * 3;
    if (average > best) best = average;
  }
  return best;
}

/// Legs in [throws] finished within the fewest darts their game allows.
///
/// [minDartsFor] gives that minimum for a game id, or null when the game is
/// unknown or its start score has no published minimum, in which case none of
/// its legs can be perfect.
///
/// The dart count per leg is gathered in one pass up front. Counting it per
/// checkout instead means rescanning every throw for every leg won, which over
/// a lifetime of a few tens of thousands of throws is the difference between a
/// stats screen that opens instantly and one that visibly stalls.
int perfectLegsFromThrows(
  List<DartThrow> throws,
  int? Function(int gameId) minDartsFor,
) {
  final legDarts = <String, int>{};
  for (final t in throws) {
    final key = '${t.gameId}-${t.set}-${t.leg}';
    legDarts[key] = (legDarts[key] ?? 0) + t.dartsUsed;
  }

  var count = 0;
  for (final t in throws) {
    if (t.bust || t.remainingBefore - t.score != 0) continue;
    final minDarts = minDartsFor(t.gameId);
    if (minDarts == null) continue;
    if ((legDarts['${t.gameId}-${t.set}-${t.leg}'] ?? 999) <= minDarts) count++;
  }
  return count;
}

/// Legs won according to the throws alone: visits that took the slot to exactly
/// zero.
///
/// Not valid in placement mode, where every slot checks out every leg and the
/// leg winner follows from the finishing order instead; use the provider's
/// tally or `placementRanking` there.
int legsWonFromThrows(List<DartThrow> throws) =>
    throws.where((t) => !t.bust && t.remainingBefore - t.score == 0).length;

/// The subset of [throws] played in [leg] of [set], in their original order.
List<DartThrow> throwsInLeg(List<DartThrow> throws, int leg, int set) =>
    throws.where((t) => t.leg == leg && t.set == set).toList();

/// The subset of [throws] thrown by [playerId], in their original order. Used
/// to break a team slot's throws down by member.
List<DartThrow> throwsOfPlayer(List<DartThrow> throws, int playerId) =>
    throws.where((t) => t.playerId == playerId).toList();
