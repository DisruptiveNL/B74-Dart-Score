import '../models/shanghai_game.dart';

/// The darts of one slot in Shanghai grouped into visits of up to
/// [dartLimit], oldest first; the last group is the visit in progress when it
/// is short. Seven in clockwise, three otherwise.
List<List<ShanghaiThrow>> shanghaiVisits(
  List<ShanghaiThrow> throws,
  int dartLimit,
) => [
  for (var i = 0; i < throws.length; i += dartLimit)
    throws.sublist(
      i,
      i + dartLimit > throws.length ? throws.length : i + dartLimit,
    ),
];

/// The points one dart scored: the ring times the target.
int shanghaiPointsOf(ShanghaiThrow t) => t.isMiss ? 0 : t.multiplier * t.target;

/// The points a whole visit scored.
int shanghaiPointsOfVisit(List<ShanghaiThrow> visit) =>
    visit.fold(0, (sum, t) => sum + shanghaiPointsOf(t));

/// Whether [visit] is a Shanghai under [variant]: the single, the double and
/// the triple of one number in the classic game, three hits in a row on three
/// consecutive numbers in the others. The same reading the provider decides
/// the win by.
bool isShanghaiVisit(List<ShanghaiThrow> visit, ShanghaiVariant variant) {
  final hits = visit.where((d) => !d.isMiss).toList();
  if (variant == ShanghaiVariant.classic) {
    if (hits.length < 3) return false;
    final sameTarget = hits.every((d) => d.target == hits.first.target);
    return sameTarget &&
        hits.map((d) => d.multiplier).toSet().containsAll([1, 2, 3]);
  }
  for (var i = 0; i + 2 < visit.length; i++) {
    final a = visit[i], b = visit[i + 1], c = visit[i + 2];
    if (a.isMiss || b.isMiss || c.isMiss) continue;
    if (b.target == a.target + 1 && c.target == b.target + 1) return true;
  }
  return false;
}

/// What one slot's darts add up to in Shanghai, for the live info.
class ShanghaiStats {
  final int darts;
  final int hits;
  final int points;
  final int visits;
  final int bestVisitPoints;
  final int shanghais;

  const ShanghaiStats({
    required this.darts,
    required this.hits,
    required this.points,
    required this.visits,
    required this.bestVisitPoints,
    required this.shanghais,
  });

  /// Points per visit.
  double get pointsPerRound => visits == 0 ? 0 : points / visits;

  /// The share of darts that hit their target, 0 to 1.
  double get hitRate => darts == 0 ? 0 : hits / darts;

  /// Aggregates [throws] of one slot, grouped into visits of [dartLimit].
  factory ShanghaiStats.of(
    List<ShanghaiThrow> throws,
    ShanghaiVariant variant,
    int dartLimit,
  ) {
    final visits = shanghaiVisits(throws, dartLimit);
    var best = 0;
    var shanghais = 0;
    for (final v in visits) {
      final p = shanghaiPointsOfVisit(v);
      if (p > best) best = p;
      if (isShanghaiVisit(v, variant)) shanghais++;
    }
    return ShanghaiStats(
      darts: throws.length,
      hits: throws.where((t) => !t.isMiss).length,
      points: shanghaiPointsOfVisit(throws),
      visits: visits.length,
      bestVisitPoints: best,
      shanghais: shanghais,
    );
  }
}
