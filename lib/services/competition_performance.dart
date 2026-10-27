import '../models/dart_throw.dart';
import '../utils/throw_stats.dart';

/// Derived statistics for one player's leg, single and season timeline.
/// No persisted averages: every number is recomputed from committed visits,
/// so corrections and Undo cannot leave stale statistics behind.
class CompetitionLegPerformance {
  final int set;
  final int leg;
  final ThrowStats stats;
  const CompetitionLegPerformance(this.set, this.leg, this.stats);
}

class CompetitionSinglePerformance {
  final int playerId;
  final ThrowStats overall;
  final List<CompetitionLegPerformance> legs;
  const CompetitionSinglePerformance(this.playerId, this.overall, this.legs);
}

/// Caller supplies all visits for a single, in actual throwing order.
/// The existing ThrowStats remains the only owner of the formulas.
CompetitionSinglePerformance competitionSinglePerformance(
  int playerId,
  List<DartThrow> visits,
) {
  final own = visits.where((t) => t.playerId == playerId).toList();
  final grouped = <(int, int), List<DartThrow>>{};
  for (final visit in own) {
    grouped.putIfAbsent((visit.set, visit.leg), () => []).add(visit);
  }
  final keys = grouped.keys.toList()
    ..sort((a, b) => a.$1 != b.$1
        ? a.$1.compareTo(b.$1)
        : a.$2.compareTo(b.$2));
  return CompetitionSinglePerformance(
    playerId,
    ThrowStats.fromThrows(own),
    List.unmodifiable(keys.map((key) => CompetitionLegPerformance(
      key.$1,
      key.$2,
      ThrowStats.fromThrows(grouped[key]!),
    ))),
  );
}

/// One completed competitive single belonging to one player.
/// The stable federation/player identifier is resolved by the caller from
/// competition + bondsnummer; local SQLite player ids are device-specific.
class CompetitionPerformanceEntry {
  final String competitionId;
  final String seasonId;
  final String bondsnummer;
  final String singleId;
  final DateTime playedAt;
  final CompetitionSinglePerformance performance;
  const CompetitionPerformanceEntry({
    required this.competitionId,
    required this.seasonId,
    required this.bondsnummer,
    required this.singleId,
    required this.playedAt,
    required this.performance,
  });
}

class CompetitionSeasonPoint {
  final String singleId;
  final DateTime playedAt;
  final double matchAverage;
  final double matchFirst9Average;
  final double seasonAverage;
  final double seasonFirst9Average;
  const CompetitionSeasonPoint({
    required this.singleId,
    required this.playedAt,
    required this.matchAverage,
    required this.matchFirst9Average,
    required this.seasonAverage,
    required this.seasonFirst9Average,
  });
}

/// Weighted cumulative averages, never a mean of match averages.
/// Deduplicates by single id and rejects conflicting duplicate statistics.
List<CompetitionSeasonPoint> competitionSeasonTrend({
  required String competitionId,
  required String seasonId,
  required String bondsnummer,
  required Iterable<CompetitionPerformanceEntry> entries,
}) {
  final selected = entries.where((e) =>
      e.competitionId == competitionId &&
      e.seasonId == seasonId &&
      e.bondsnummer == bondsnummer).toList()
    ..sort((a, b) {
      final date = a.playedAt.compareTo(b.playedAt);
      return date != 0 ? date : a.singleId.compareTo(b.singleId);
    });
  final seen = <String, CompetitionPerformanceEntry>{};
  var scored = 0, darts = 0, first9Scored = 0, first9Darts = 0;
  final result = <CompetitionSeasonPoint>[];
  for (final e in selected) {
    final previous = seen[e.singleId];
    if (previous != null) {
      final a = previous.performance.overall;
      final b = e.performance.overall;
      if (a.totalScored != b.totalScored || a.totalDarts != b.totalDarts ||
          a.first9Scored != b.first9Scored || a.first9Darts != b.first9Darts) {
        throw StateError('Conflicting results for competition single ${e.singleId}');
      }
      continue;
    }
    seen[e.singleId] = e;
    final s = e.performance.overall;
    scored += s.totalScored;
    darts += s.totalDarts;
    first9Scored += s.first9Scored;
    first9Darts += s.first9Darts;
    result.add(CompetitionSeasonPoint(
      singleId: e.singleId,
      playedAt: e.playedAt,
      matchAverage: s.average,
      matchFirst9Average: s.first9Average,
      seasonAverage: darts == 0 ? 0 : scored * 3 / darts,
      seasonFirst9Average: first9Darts == 0 ? 0 : first9Scored * 3 / first9Darts,
    ));
  }
  return List.unmodifiable(result);
}
