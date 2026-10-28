import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/services/competition_performance.dart';

DartThrow visit(
  int game,
  int player,
  int leg,
  int score,
  int darts,
  int index,
) => DartThrow(
  gameId: game,
  playerId: player,
  score: score,
  dartsUsed: darts,
  leg: leg,
  set: 1,
  remainingBefore: 501,
  thrownAt: DateTime.utc(2026, 10, index),
);

void main() {
  test('per-leg first 9 and overall exclude opponent visits', () {
    final visits = [
      visit(1, 10, 1, 60, 3, 1),
      visit(1, 20, 1, 180, 3, 2),
      visit(1, 10, 1, 100, 3, 3),
      visit(1, 10, 1, 80, 3, 4),
      visit(1, 10, 1, 40, 3, 5),
      visit(1, 10, 2, 90, 3, 6),
    ];
    final s = competitionSinglePerformance(10, visits);
    expect(s.legs.length, 2);
    expect(s.legs.first.stats.first9Average, closeTo(80, 0.001));
    expect(s.legs.first.stats.average, closeTo(70, 0.001));
    expect(s.overall.totalDarts, 15);
    expect(s.overall.totalScored, 370);
    expect(s.overall.average, closeTo(74, 0.001));
  });

  test('season uses weighted darts and deduplicates a single', () {
    final a = competitionSinglePerformance(10, [visit(1, 10, 1, 60, 3, 1)]);
    final b = competitionSinglePerformance(10, [
      visit(2, 10, 1, 100, 3, 2),
      visit(2, 10, 1, 80, 3, 3),
    ]);
    CompetitionPerformanceEntry entry(
      String id,
      int day,
      CompetitionSinglePerformance p,
    ) => CompetitionPerformanceEntry(
      competitionId: 'DOGD',
      seasonId: '2026',
      bondsnummer: '1234',
      singleId: id,
      playedAt: DateTime.utc(2026, 10, day),
      performance: p,
    );
    final e1 = entry('one', 1, a);
    final points = competitionSeasonTrend(
      competitionId: 'DOGD',
      seasonId: '2026',
      bondsnummer: '1234',
      entries: [entry('two', 2, b), e1, e1],
    );
    expect(points.length, 2);
    expect(points.first.matchAverage, 60);
    expect(points.last.matchAverage, 90);
    expect(points.last.seasonAverage, closeTo(80, 0.001));
  });
}
