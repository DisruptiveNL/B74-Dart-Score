import '../models/cricket_game.dart';

/// The darts of one slot in Cricket, three to a visit, oldest first. The last
/// group is the visit in progress when it holds fewer than three.
List<List<CricketThrow>> cricketVisits(List<CricketThrow> throws) => [
  for (var i = 0; i < throws.length; i += 3)
    throws.sublist(i, i + 3 > throws.length ? throws.length : i + 3),
];

/// The marks one dart is worth: the ring on a Cricket field, one mark for any
/// hit under simple scoring, nothing for a miss or a number off the seven.
int cricketMarksOf(CricketThrow t, CricketScoringMode scoring) {
  if (t.isMiss || !cricketFields.contains(t.field)) return 0;
  return scoring == CricketScoringMode.simple ? 1 : t.multiplier;
}

/// The marks a whole visit brought in.
int cricketMarksOfVisit(List<CricketThrow> visit, CricketScoringMode scoring) =>
    visit.fold(0, (sum, t) => sum + cricketMarksOf(t, scoring));

/// What one slot's darts add up to in Cricket, for the live info.
///
/// Marks count every hit on a Cricket field, whether it closed the field or
/// scored, which is how marks per round is read at the oche. The fields it
/// has closed and the points it holds are the slot's own state, not derived
/// here: both depend on what the opponents had closed at the time.
class CricketStats {
  final int darts;
  final int hits;
  final int marks;
  final int visits;
  final int bestVisitMarks;

  const CricketStats({
    required this.darts,
    required this.hits,
    required this.marks,
    required this.visits,
    required this.bestVisitMarks,
  });

  /// Marks per three darts, the marks per round of Cricket.
  double get marksPerRound => darts == 0 ? 0 : marks / darts * 3;

  /// The share of darts that landed on a Cricket field, 0 to 1.
  double get hitRate => darts == 0 ? 0 : hits / darts;

  /// Aggregates [throws] of one slot under [scoring].
  factory CricketStats.of(
    List<CricketThrow> throws,
    CricketScoringMode scoring,
  ) {
    final visits = cricketVisits(throws);
    var best = 0;
    for (final v in visits) {
      final m = cricketMarksOfVisit(v, scoring);
      if (m > best) best = m;
    }
    return CricketStats(
      darts: throws.length,
      hits: throws.where((t) => cricketMarksOf(t, scoring) > 0).length,
      marks: cricketMarksOfVisit(throws, scoring),
      visits: visits.length,
      bestVisitMarks: best,
    );
  }
}
