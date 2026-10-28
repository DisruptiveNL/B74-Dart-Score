import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/player.dart';
import '../models/dart_throw.dart';
import '../providers/game_provider.dart' show minimumDartsForScore;
import '../utils/throw_stats.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/stat_row.dart';
import '../widgets/throw_row.dart';
import '../utils/game_labels.dart';
import '../utils/layout.dart';
import '../utils/segment_color.dart';

// ── Data model ────────────────────────────────────────────────────────────────

/// Aggregated lifetime statistics for one player, computed by [loadPlayerStats]
/// from stored games, throws, and any persisted historical stats snapshot.
/// Covers totals, averages, score distribution, segment hits, weekly comparison,
/// and checkout breakdown by remaining bracket.
///
/// Public only so the merge of live throws and snapshot can be tested; the
/// screen is the sole caller in the app.
@visibleForTesting
class PlayerStats {
  final int gamesPlayed;
  final int gamesFinished;

  /// Games this player, or their team, took: the deciding leg was theirs.
  final int gamesWon;
  final int totalVisits;
  final int totalDarts;
  final int totalScored; // excludes busts
  final int busts;
  final int legsWon;
  final int highestVisit;
  final int highestCheckout; // highest score that reached 0
  final double highestGameAverage; // best three-dart average in a single game
  final int count180;
  final int count140plus;
  final int count100plus;
  final double checkoutPercent; // successful checkouts / attempts
  /// Individual darts thrown at a finish, the denominator of [doublePercent].
  final int checkoutDarts;
  final double doublePercent; // successful checkouts / darts at a finish
  final List<DartThrow> recentThrows;
  final Map<int, int> scoreDistribution;
  final int perfectLegs;

  // ── Extended stats ───────────────────────────────────────────────────────
  /// field (1-20, 25=bull) → multiplier (1/2/3) → hit count
  final Map<int, Map<int, int>> segmentHits;
  final double scoreStdDev;
  // Week comparison (Mon–today vs previous Mon–Sun)
  final double thisWeekAvg;
  final double lastWeekAvg;
  final int thisWeekVisits;
  final int lastWeekVisits;
  final int thisWeek180s;
  final int lastWeek180s;
  // Checkout breakdown by remaining-before bracket
  final int coAttemptSub40;
  final int coSuccessSub40;
  final int coAttemptSub60;
  final int coSuccessSub60;
  final int coAttemptSub100;
  final int coSuccessSub100;
  final int coAttemptSub170;
  final int coSuccessSub170;

  const PlayerStats({
    required this.gamesPlayed,
    required this.gamesFinished,
    required this.gamesWon,
    required this.totalVisits,
    required this.totalDarts,
    required this.totalScored,
    required this.busts,
    required this.legsWon,
    required this.highestVisit,
    required this.highestCheckout,
    this.highestGameAverage = 0,
    required this.count180,
    required this.count140plus,
    required this.count100plus,
    required this.checkoutPercent,
    this.checkoutDarts = 0,
    this.doublePercent = 0,
    required this.recentThrows,
    required this.scoreDistribution,
    this.perfectLegs = 0,
    this.segmentHits = const {},
    this.scoreStdDev = 0,
    this.thisWeekAvg = 0,
    this.lastWeekAvg = 0,
    this.thisWeekVisits = 0,
    this.lastWeekVisits = 0,
    this.thisWeek180s = 0,
    this.lastWeek180s = 0,
    this.coAttemptSub40 = 0,
    this.coSuccessSub40 = 0,
    this.coAttemptSub60 = 0,
    this.coSuccessSub60 = 0,
    this.coAttemptSub100 = 0,
    this.coSuccessSub100 = 0,
    this.coAttemptSub170 = 0,
    this.coSuccessSub170 = 0,
  });

  /// Lifetime three-dart average (busts excluded from scored points).
  double get average3Dart =>
      totalDarts == 0 ? 0 : (totalScored / totalDarts) * 3;

  /// Percentage of visits that busted.
  double get bustRate => totalVisits == 0 ? 0 : (busts / totalVisits) * 100;
}

/// Everything [aggregatePlayerStats] needs, and nothing that would drag the
/// database or the UI along into another isolate.
///
/// The games are reduced to the three things the aggregation actually asks of
/// them, so a player with hundreds of games does not pay to have them all
/// copied across.
@visibleForTesting
class PlayerStatsInput {
  final int playerId;
  final List<DartThrow> throws;

  /// Start score per game, for the dart count a perfect leg would take.
  final Map<int, int> startScoreByGame;
  final int gamesPlayed;
  final int gamesFinished;

  /// How many of them this player won, decided from the throws of each.
  final int gamesWon;

  /// The snapshot of games that were deleted, still counted in the lifetime
  /// numbers. See the sync notes in CLAUDE.md.
  final String? localStatsJson;

  const PlayerStatsInput({
    required this.playerId,
    required this.throws,
    required this.startScoreByGame,
    required this.gamesPlayed,
    required this.gamesFinished,
    required this.gamesWon,
    required this.localStatsJson,
  });
}

/// Loads and aggregates a player's lifetime statistics from the database,
/// merging live game data with any persisted historical snapshot.
///
/// Reads on this isolate, because sqflite lives here, then hands the counting
/// to [aggregatePlayerStats] on another one. That part walks every throw the
/// player has ever made and decodes the dart hits of each, which is the sort of
/// work that shows up as a stutter when the screen opens.
///
/// Public only so the merge can be tested; the screen is the sole caller in
/// the app.
@visibleForTesting
Future<PlayerStats> loadPlayerStats(Player player) async {
  final playerId = player.id!;
  final db = DbHelper.instance;

  // Always reload from DB so local_stats_json reflects deletions done since screen opened
  player = await db.getPlayer(playerId) ?? player;

  final throws = await db.getThrowsForPlayer(playerId);

  // One query, then a lookup. Asking the database again for every game the
  // player has ever played reads the whole table once per game.
  final gameIds = (await db.getGameIdsForPlayer(playerId)).toSet();
  // Read from the throws rather than from a column, because no column holds a
  // winner. See utils/game_winner.dart.
  final wonGameIds = await db.getWonGameIds(playerId);
  final games = {
    for (final g in await db.getGames())
      if (gameIds.contains(g.id)) g.id!: g,
  };

  return compute(
    aggregatePlayerStats,
    PlayerStatsInput(
      playerId: playerId,
      throws: throws,
      startScoreByGame: {
        for (final e in games.entries) e.key: e.value.startScore,
      },
      gamesPlayed: gameIds.length,
      gamesFinished: games.values.where((g) => g.finishedAt != null).length,
      gamesWon: wonGameIds.length,
      // Every snapshot the player carries at once: this device's own cleared
      // games plus one per device that ever synced here. Which is which only
      // matters to the next sync, never to a lifetime number.
      localStatsJson: await db.combinedSnapshotJson(playerId),
    ),
  );
}

/// Counts a player's lifetime statistics out of [input].
///
/// Pure and top level so it can run in another isolate. Nothing here may reach
/// for the database, a binding or the widget tree.
@visibleForTesting
PlayerStats aggregatePlayerStats(PlayerStatsInput input) {
  final playerId = input.playerId;
  final throws = input.throws;
  final localStatsJson = input.localStatsJson;

  // ── Counters from the games still on the device ───────────────────────────
  // The snapshot of deleted games is added on top further down, so these start
  // at the live values instead of at zero and stay mutable.
  final live = ThrowStats.fromThrows(throws);

  int totalScored = live.totalScored;
  int busts = live.busts;
  // A leg is won by finishing it, so a successful checkout is a leg.
  int legsWon = live.checkoutSuccesses;
  int highestVisit = live.highestVisit;
  int highestCheckout = live.highestCheckout;
  int count180 = live.count180;
  int count140plus = live.count140plus;
  int count100plus = live.count100plus;
  int checkoutAttempts = live.checkoutAttempts;
  int checkoutSuccess = live.checkoutSuccesses;
  int checkoutDarts = live.checkoutDarts;
  int scoreSumSquares = live.scoreSumSquares;
  int coAtSub40 = live.coAttemptSub40, coOkSub40 = live.coSuccessSub40;
  int coAtSub60 = live.coAttemptSub60, coOkSub60 = live.coSuccessSub60;
  int coAtSub100 = live.coAttemptSub100, coOkSub100 = live.coSuccessSub100;
  int coAtSub170 = live.coAttemptSub170, coOkSub170 = live.coSuccessSub170;

  // ── Accumulators the shared record does not carry ─────────────────────────
  int perfectLegs = 0;
  final scoreDistribution = <int, int>{};
  final segmentHits = <int, Map<int, int>>{};
  // daily_stats: date → {scored, darts, visits, s180}
  final dailyStats = <String, Map<String, int>>{};

  for (final t in throws) {
    // Heatmap
    if (t.hitsJson != null) {
      try {
        final hits = jsonDecode(t.hitsJson!) as List<dynamic>;
        for (final h in hits) {
          final field = h['f'] as int;
          final mul = h['m'] as int;
          segmentHits.putIfAbsent(field, () => {});
          segmentHits[field]![mul] = (segmentHits[field]![mul] ?? 0) + 1;
        }
      } catch (_) {}
    }

    // Daily stats (all throws, for activity and week windows)
    final day =
        '${t.thrownAt.year}-'
        '${t.thrownAt.month.toString().padLeft(2, '0')}-'
        '${t.thrownAt.day.toString().padLeft(2, '0')}';
    final ds = dailyStats.putIfAbsent(
      day,
      () => {'scored': 0, 'darts': 0, 'visits': 0, 's180': 0},
    );
    ds['darts'] = (ds['darts'] ?? 0) + t.dartsUsed;

    if (!t.bust) {
      final bucket = (t.score ~/ 20) * 20;
      scoreDistribution[bucket] = (scoreDistribution[bucket] ?? 0) + 1;

      ds['scored'] = (ds['scored'] ?? 0) + t.score;
      ds['visits'] = (ds['visits'] ?? 0) + 1;
      if (t.score == 180) ds['s180'] = (ds['s180'] ?? 0) + 1;
    }
  }

  // Perfect legs need the leg's whole dart count and its game's start score,
  // so they cannot come from the shared record and are counted separately.
  perfectLegs = perfectLegsFromThrows(throws, (gameId) {
    final startScore = input.startScoreByGame[gameId];
    return startScore == null ? null : minimumDartsForScore[startScore];
  });

  int gamesFinished = input.gamesFinished;
  int gamesWon = input.gamesWon;
  final liveTotalDarts = live.totalDarts;
  final liveTotalVisits = live.totalVisits;
  final liveNonBustVisits = live.totalVisits - live.busts;

  double highestGameAvg = bestGameAverage(throws);

  // ── Merge persistent snapshot (deleted games) ─────────────────────────────
  int persistentTotalDarts = 0;
  int persistentTotalVisits = 0;
  int persistentGamesPlayed = 0;
  int persistentNonBusts = 0;
  // Snapshot recent throws: compact maps from deleted games
  var snapRecentThrows = <Map<String, dynamic>>[];

  if (localStatsJson != null && localStatsJson.isNotEmpty) {
    try {
      final p = jsonDecode(localStatsJson) as Map<String, dynamic>;
      int pi(String k) => p[k] as int? ?? 0;
      double pd(String k) => (p[k] as num?)?.toDouble() ?? 0;

      highestGameAvg = max(highestGameAvg, pd('highest_game_avg'));

      persistentTotalDarts = pi('total_darts');
      persistentTotalVisits = pi('total_visits');
      persistentGamesPlayed = pi('games_played');
      persistentNonBusts = persistentTotalVisits - pi('busts');

      totalScored += pi('total_scored');
      busts += pi('busts');
      legsWon += pi('legs_won');
      highestVisit = max(highestVisit, pi('highest_visit'));
      highestCheckout = max(highestCheckout, pi('highest_checkout'));
      count180 += pi('count_180');
      count140plus += pi('count_140_plus');
      count100plus += pi('count_100_plus');
      checkoutAttempts += pi('checkout_attempts');
      checkoutSuccess += pi('checkout_successes');
      checkoutDarts += pi('checkout_darts');
      scoreSumSquares += pi('score_sum_squares');
      perfectLegs += pi('perfect_legs');
      gamesFinished += pi('games_finished');
      // Snapshots written before games won was counted carry no such key, so
      // the deleted games behind them stay out of the count rather than being
      // guessed at.
      gamesWon += pi('games_won');
      coAtSub40 += pi('co_at_sub40');
      coOkSub40 += pi('co_ok_sub40');
      coAtSub60 += pi('co_at_sub60');
      coOkSub60 += pi('co_ok_sub60');
      coAtSub100 += pi('co_at_sub100');
      coOkSub100 += pi('co_ok_sub100');
      coAtSub170 += pi('co_at_sub170');
      coOkSub170 += pi('co_ok_sub170');

      // Heatmap
      final pHits = (p['segment_hits'] as Map?)?.cast<String, dynamic>();
      if (pHits != null) {
        for (final e in pHits.entries) {
          final field = int.tryParse(e.key);
          if (field == null) continue;
          final muls = (e.value as Map?)?.cast<String, dynamic>() ?? {};
          segmentHits.putIfAbsent(field, () => {});
          for (final m in muls.entries) {
            final mul = int.tryParse(m.key);
            if (mul == null) continue;
            segmentHits[field]![mul] =
                (segmentHits[field]![mul] ?? 0) + (m.value as int? ?? 0);
          }
        }
      }

      // Score distribution
      final pDist = (p['score_distribution'] as Map?)?.cast<String, dynamic>();
      if (pDist != null) {
        for (final e in pDist.entries) {
          final bucket = int.tryParse(e.key);
          if (bucket == null) continue;
          scoreDistribution[bucket] =
              (scoreDistribution[bucket] ?? 0) + (e.value as int? ?? 0);
        }
      }

      // Daily stats (for week comparison and activity heatmap)
      final pDs = (p['daily_stats'] as Map?)?.cast<String, dynamic>();
      if (pDs != null) {
        for (final e in pDs.entries) {
          final day = e.key;
          final src = (e.value as Map?)?.cast<String, dynamic>() ?? {};
          final dst = dailyStats.putIfAbsent(
            day,
            () => {'scored': 0, 'darts': 0, 'visits': 0, 's180': 0},
          );
          dst['scored'] = (dst['scored'] ?? 0) + (src['scored'] as int? ?? 0);
          dst['darts'] = (dst['darts'] ?? 0) + (src['darts'] as int? ?? 0);
          dst['visits'] = (dst['visits'] ?? 0) + (src['visits'] as int? ?? 0);
          dst['s180'] = (dst['s180'] ?? 0) + (src['s180'] as int? ?? 0);
        }
      }

      // Snapshot recent throws
      final pRt = (p['recent_throws'] as List?)?.cast<dynamic>();
      if (pRt != null) {
        snapRecentThrows = pRt
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
  }

  // ── Week comparison from merged dailyStats ────────────────────────────────
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final thisWeekStart = todayStart.subtract(
    Duration(days: todayStart.weekday - 1),
  );
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
  double thisWeekScored = 0;
  int thisWeekDarts = 0;
  double lastWeekScored = 0;
  int lastWeekDarts = 0;
  int thisWeekVisits = 0, lastWeekVisits = 0;
  int thisWeek180s = 0, lastWeek180s = 0;

  for (final entry in dailyStats.entries) {
    final parts = entry.key.split('-');
    if (parts.length != 3) continue;
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final ds = entry.value;

    final inThisWeek = !date.isBefore(thisWeekStart);
    final inLastWeek =
        !date.isBefore(lastWeekStart) && date.isBefore(thisWeekStart);
    if (inThisWeek) {
      thisWeekScored += ds['scored'] ?? 0;
      thisWeekDarts += ds['darts'] ?? 0;
      thisWeekVisits += ds['visits'] ?? 0;
      thisWeek180s += ds['s180'] ?? 0;
    } else if (inLastWeek) {
      lastWeekScored += ds['scored'] ?? 0;
      lastWeekDarts += ds['darts'] ?? 0;
      lastWeekVisits += ds['visits'] ?? 0;
      lastWeek180s += ds['s180'] ?? 0;
    }
  }

  // ── Recent throws: live (newest first) + snapshot, deduplicated, top 20 ──
  // The individual darts ride along where they were recorded, so the list can
  // name them. The snapshot of a deleted game carries no hits, and those rows
  // simply show none.
  final liveRecent = throws.reversed
      .map(
        (t) => {
          'score': t.score,
          'darts_used': t.dartsUsed,
          'bust': t.bust ? 1 : 0,
          'remaining_before': t.remainingBefore,
          'thrown_at': t.thrownAt.millisecondsSinceEpoch,
          'hits_json': t.hitsJson,
        },
      )
      .toList();
  final liveTimestamps = liveRecent.map((m) => m['thrown_at'] as int).toSet();
  final combined =
      [
        ...liveRecent,
        ...snapRecentThrows.where(
          (m) => !liveTimestamps.contains(m['thrown_at'] as int? ?? -1),
        ),
      ]..sort(
        (a, b) => ((b['thrown_at'] as int? ?? 0).compareTo(
          a['thrown_at'] as int? ?? 0,
        )),
      );
  final recentThrows = combined
      .take(20)
      .map(
        (m) => DartThrow(
          gameId: -1,
          playerId: playerId,
          score: m['score'] as int? ?? 0,
          dartsUsed: m['darts_used'] as int? ?? 3,
          leg: 1,
          set: 1,
          remainingBefore: m['remaining_before'] as int? ?? 0,
          thrownAt: DateTime.fromMillisecondsSinceEpoch(
            m['thrown_at'] as int? ?? 0,
          ),
          bust: (m['bust'] as int? ?? 0) == 1,
          hitsJson: m['hits_json'] as String?,
        ),
      )
      .toList();

  // ── Standard deviation via Var = E[x²] − E[x]² ───────────────────────────
  final totalNonBusts = liveNonBustVisits + persistentNonBusts;
  double stdDev = 0;
  if (totalNonBusts > 1 && scoreSumSquares > 0) {
    final mean = totalScored / totalNonBusts;
    final variance = (scoreSumSquares / totalNonBusts) - mean * mean;
    if (variance > 0) stdDev = sqrt(variance);
  }

  final checkoutPercent = checkoutAttempts == 0
      ? 0.0
      : (checkoutSuccess / checkoutAttempts) * 100;
  final doublePercent = checkoutDarts == 0
      ? 0.0
      : (checkoutSuccess / checkoutDarts) * 100;
  final thisWeekAvg3 = thisWeekDarts == 0
      ? 0.0
      : (thisWeekScored / thisWeekDarts) * 3;
  final lastWeekAvg3 = lastWeekDarts == 0
      ? 0.0
      : (lastWeekScored / lastWeekDarts) * 3;

  return PlayerStats(
    gamesPlayed: input.gamesPlayed + persistentGamesPlayed,
    gamesFinished: gamesFinished,
    gamesWon: gamesWon,
    totalVisits: liveTotalVisits + persistentTotalVisits,
    totalDarts: liveTotalDarts + persistentTotalDarts,
    totalScored: totalScored,
    busts: busts,
    legsWon: legsWon,
    highestVisit: highestVisit,
    highestCheckout: highestCheckout,
    highestGameAverage: highestGameAvg,
    count180: count180,
    count140plus: count140plus,
    count100plus: count100plus,
    checkoutPercent: checkoutPercent,
    checkoutDarts: checkoutDarts,
    doublePercent: doublePercent,
    recentThrows: recentThrows,
    scoreDistribution: scoreDistribution,
    perfectLegs: perfectLegs,
    segmentHits: segmentHits,
    scoreStdDev: stdDev,
    thisWeekAvg: thisWeekAvg3,
    lastWeekAvg: lastWeekAvg3,
    thisWeekVisits: thisWeekVisits,
    lastWeekVisits: lastWeekVisits,
    thisWeek180s: thisWeek180s,
    lastWeek180s: lastWeek180s,
    coAttemptSub40: coAtSub40,
    coSuccessSub40: coOkSub40,
    coAttemptSub60: coAtSub60,
    coSuccessSub60: coOkSub60,
    coAttemptSub100: coAtSub100,
    coSuccessSub100: coOkSub100,
    coAttemptSub170: coAtSub170,
    coSuccessSub170: coOkSub170,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Per-player lifetime statistics screen: loads aggregated stats and renders
/// the hero summary, charts, breakdowns, and (if available) synced stats.
class PlayerStatsScreen extends StatefulWidget {
  final Player player;

  /// Whether this sits inside a pane that brings its own title bar, as the
  /// master detail layout of the player list does on a tablet. Embedded it
  /// renders its content alone, without a screen around it.
  final bool embedded;

  const PlayerStatsScreen({
    super.key,
    required this.player,
    this.embedded = false,
  });

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  /// Started once and kept, not started again on every build.
  ///
  /// A read begun inside `build` is begun again by every rebuild, and a pane
  /// whose divider is being dragged rebuilds on every frame: the screen would
  /// fall back to its spinner for the length of the drag and hammer the
  /// database while it lasted.
  late Future<PlayerStats> _future = loadPlayerStats(widget.player);

  @override
  void didUpdateWidget(PlayerStatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.id != widget.player.id) {
      _future = loadPlayerStats(widget.player);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _wrap(
      context,
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: FutureBuilder<PlayerStats>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || snap.data == null) {
                return Center(
                  child: Text('${context.l10n.error}: ${snap.error}'),
                );
              }
              final stats = snap.data!;
              // No throws at all: show synced snapshot or empty state
              if (stats.totalVisits == 0 && widget.player.syncedStats != null) {
                return _SyncedStatsView(player: widget.player);
              }
              if (stats.totalVisits == 0) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 56,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.noGamesFor(widget.player.name),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }
              return _StatsBody(player: widget.player, stats: stats);
            },
          ),
        ),
      ),
    );
  }

  /// Puts the screen around [content], or hands it over bare when this view is
  /// widget.embedded in a pane that already has a title bar of its own.
  Widget _wrap(BuildContext context, Widget content) => widget.embedded
      ? content
      : Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.statisticsOf(widget.player.name)),
          ),
          body: content,
        );
}

// ── Body ──────────────────────────────────────────────────────────────────────

/// Assembles the full stats layout from the loaded [PlayerStats] sections.
class _StatsBody extends StatelessWidget {
  final Player player;
  final PlayerStats stats;

  const _StatsBody({required this.player, required this.stats});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        // ── X01-only hint ───────────────────────────────────────────────
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.l10n.statsX01Only,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Hero average ────────────────────────────────────────────────
        _HeroCard(stats: stats),
        const SizedBox(height: 12),
        // ── Highlights row ──────────────────────────────────────────────
        _SectionTitle(context.l10n.highlights),
        const SizedBox(height: 6),
        // Perfect games + highest average row
        Row(
          children: [
            Expanded(
              child: _HighlightTile(
                label: context.l10n.perfectGames,
                value: '${stats.perfectLegs}',
                icon: Icons.emoji_events_rounded,
                highlight: stats.perfectLegs > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightTile(
                label: context.l10n.highestAverage,
                value: stats.highestGameAverage == 0
                    ? '—'
                    : stats.highestGameAverage.toStringAsFixed(2),
                icon: Icons.speed_rounded,
                highlight: stats.highestGameAverage >= 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _HighlightTile(
                label: context.l10n.count180,
                value: '${stats.count180}',
                icon: Icons.star_rounded,
                highlight: stats.count180 > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightTile(
                label: context.l10n.count140plus,
                value: '${stats.count140plus}',
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightTile(
                label: context.l10n.count100plus,
                value: '${stats.count100plus}',
                icon: Icons.bar_chart,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _HighlightTile(
                label: context.l10n.highestVisit,
                value: '${stats.highestVisit}',
                icon: Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightTile(
                label: context.l10n.highestCheckout,
                value: stats.highestCheckout == 0
                    ? '—'
                    : '${stats.highestCheckout}',
                icon: Icons.flag_rounded,
                highlight: stats.highestCheckout >= 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── Overview ────────────────────────────────────────────────────
        _SectionTitle(context.l10n.overview),
        const SizedBox(height: 6),
        _StatCard(
          children: [
            StatRow(
              label: context.l10n.gamesPlayed,
              value: '${stats.gamesPlayed}',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.gamesWon,
              value: '${stats.gamesWon}',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.legsWon,
              value: '${stats.legsWon}',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.totalVisits,
              value: '${stats.totalVisits}',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.totalDarts,
              value: '${stats.totalDarts}',
              spacious: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── Accuracy ────────────────────────────────────────────────────
        _SectionTitle(context.l10n.accuracy),
        const SizedBox(height: 6),
        _StatCard(
          children: [
            StatRow(
              label: context.l10n.threeDartAvg,
              value: stats.average3Dart.toStringAsFixed(2),
              spacious: true,
            ),
            StatRow(
              label: context.l10n.busts,
              value: '${stats.busts}',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.bustRate,
              value: '${stats.bustRate.toStringAsFixed(1)} %',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.checkoutRate,
              value: '${stats.checkoutPercent.toStringAsFixed(1)} %',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.doubleRate,
              value: '${stats.doublePercent.toStringAsFixed(1)} %',
              spacious: true,
            ),
            StatRow(
              label: context.l10n.dartsAtFinish,
              value: '${stats.checkoutDarts}',
              spacious: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── Score Distribution ───────────────────────────────────────────
        if (stats.scoreDistribution.isNotEmpty) ...[
          _SectionTitle(context.l10n.scoreDistribution),
          const SizedBox(height: 6),
          _ScoreChart(distribution: stats.scoreDistribution),
          const SizedBox(height: 14),
        ],
        // ── Dartboard Heatmap ─────────────────────────────────────────────
        if (stats.segmentHits.isNotEmpty) ...[
          _SectionTitle(context.l10n.dartboardHeatmap),
          const SizedBox(height: 6),
          _DartboardHeatmap(segmentHits: stats.segmentHits),
          const SizedBox(height: 14),
        ],
        // ── Top Doubles ───────────────────────────────────────────────────
        if (stats.segmentHits.values.any((m) => (m[2] ?? 0) > 0)) ...[
          _SectionTitle(context.l10n.topDoubles),
          const SizedBox(height: 6),
          _TopDoublesCard(stats: stats),
          const SizedBox(height: 14),
        ],
        // ── Stability ───────────────────────────────────────────────────
        if (stats.scoreStdDev > 0) ...[
          _SectionTitle(context.l10n.stability),
          const SizedBox(height: 6),
          _StabilityCard(stats: stats),
          const SizedBox(height: 14),
        ],
        // ── Checkout Breakdown ───────────────────────────────────────────
        if (stats.coAttemptSub40 +
                stats.coAttemptSub60 +
                stats.coAttemptSub100 +
                stats.coAttemptSub170 >
            0) ...[
          _SectionTitle(context.l10n.checkoutBreakdown),
          const SizedBox(height: 6),
          _CheckoutBreakdownCard(stats: stats),
          const SizedBox(height: 14),
        ],
        // ── Wochenvergleich ──────────────────────────────────────────────
        if (stats.thisWeekVisits > 0 || stats.lastWeekVisits > 0) ...[
          _SectionTitle(context.l10n.weekComparison),
          const SizedBox(height: 6),
          _WeekComparisonCard(stats: stats),
          const SizedBox(height: 14),
        ],
        // ── Recent Throws ────────────────────────────────────────────────
        if (stats.recentThrows.isNotEmpty) ...[
          _SectionTitle(context.l10n.recentThrows),
          const SizedBox(height: 6),
          _StatCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            // These visits come from different games, so their leg and set say
            // nothing; the date is what places them.
            children: stats.recentThrows
                .map(
                  (t) =>
                      ThrowRow(t: t, showPosition: false, thrownAt: t.thrownAt),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

// ── Hero card (big average) ───────────────────────────────────────────────────

/// Hero summary card showing the player's headline stats (average, games, etc.).
class _HeroCard extends StatelessWidget {
  final PlayerStats stats;
  const _HeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.threeDartAvg,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  stats.average3Dart.toStringAsFixed(2),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _HeroStatTable(
            cs: cs,
            rows: [
              (context.l10n.darts_, '${stats.totalDarts}'),
              (context.l10n.visits, '${stats.totalVisits}'),
              (context.l10n.legsWon, '${stats.legsWon}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// The labeled values beside the big average in a hero card.
///
/// A table rather than a column of rows, so the labels share one column and
/// the numbers share the next. Stacked rows of their own would each be only as
/// wide as their own text, and the numbers would sit at a different offset on
/// every line.
class _HeroStatTable extends StatelessWidget {
  /// Label and value per line, in the order they are shown.
  final List<(String, String)> rows;
  final ColorScheme cs;

  const _HeroStatTable({required this.rows, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onPrimary.withValues(alpha: 0.7),
    );
    final valueStyle = theme.textTheme.labelLarge?.copyWith(
      color: cs.onPrimary,
      fontWeight: FontWeight.bold,
    );

    return IntrinsicWidth(
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (label, value) in rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: Text(label, style: labelStyle),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Score distribution bar chart ──────────────────────────────────────────────

/// Bar chart of the player's score distribution across visit-score buckets.
class _ScoreChart extends StatelessWidget {
  final Map<int, int> distribution;
  const _ScoreChart({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Build sorted buckets 0,20,40,…,180
    final buckets = List.generate(10, (i) => i * 20);
    final labels = [
      '0–19',
      '20–39',
      '40–59',
      '60–79',
      '80–99',
      '100–119',
      '120–139',
      '140–159',
      '160–179',
      '180',
    ];
    final counts = buckets.map((b) => distribution[b] ?? 0).toList();
    final maxCount = counts.reduce((a, b) => a > b ? a : b).clamp(1, 99999);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          children: List.generate(buckets.length, (i) {
            final count = counts[i];
            final frac = count / maxCount;
            final isTop = i >= 7; // 140+
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      labels[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(
                            height: 18,
                            decoration: BoxDecoration(
                              color: isTop ? cs.tertiary : cs.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: count > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: count > 0 ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Reusable building blocks ──────────────────────────────────────────────────

/// A section heading within the stats body.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A card grouping a list of label/value stat rows.
class _StatCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  const _StatCard({required this.children, this.padding});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: children
              .expand(
                (w) => [
                  w,
                  if (w != children.last)
                    Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              )
              .toList(),
        ),
      ),
    );
  }
}

/// A highlighted metric tile (e.g. highest checkout, 180s) with icon and value.
class _HighlightTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  const _HighlightTile({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: highlight ? cs.tertiaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight ? cs.onTertiaryContainer : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? cs.onTertiaryContainer : cs.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlight
                  ? cs.onTertiaryContainer.withValues(alpha: 0.8)
                  : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dartboard Heatmap ─────────────────────────────────────────────────────────

/// Dartboard heatmap visualizing how often the player hit each segment.
class _DartboardHeatmap extends StatelessWidget {
  final Map<int, Map<int, int>> segmentHits;
  const _DartboardHeatmap({required this.segmentHits});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Total hits per field (all multipliers combined) for legend. Field 0 is a
    // miss and stands for no field at all, so it never belongs in a ranking of
    // the busiest ones.
    final perField = <int, int>{};
    for (final entry in segmentHits.entries) {
      if (entry.key == 0) continue;
      perField[entry.key] = entry.value.values.fold(0, (a, b) => a + b);
    }

    // Global max across all individual segment×multiplier combinations
    int globalMax = 1;
    for (final muls in segmentHits.values) {
      for (final count in muls.values) {
        if (count > globalMax) globalMax = count;
      }
    }

    // Top hit fields for the legend
    final sorted = perField.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFields = sorted.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _DartboardPainter(
                  segmentHits: segmentHits,
                  globalMax: globalMax,
                  outlineColor: cs.outline.withValues(alpha: 0.4),
                  onSurfaceColor: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Color scale legend
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '0',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 10,
                        child: CustomPaint(painter: _HeatScalePainter()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'max',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Legend: top 3 fields
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: topFields.map((e) {
                final fieldName = e.key == 25 ? 'Bull' : '${e.key}';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$fieldName · ${e.value}×',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            _SegmentBreakdown(segmentHits: segmentHits),
          ],
        ),
      ),
    );
  }
}

/// The exact hit count of every segment the player ever hit, folded away under
/// the heatmap because it is a long list next to a picture that already says
/// where the darts land.
///
/// A table of one row per number, single, double and triple in fixed columns,
/// so a field is read across and the columns are compared down. Every cell is
/// filled even where the count is zero: a missing cell would read as a hole in
/// the table rather than as a segment the player has yet to hit. The bull and
/// the misses share the closing row, none of them having three variants.
class _SegmentBreakdown extends StatelessWidget {
  final Map<int, Map<int, int>> segmentHits;
  const _SegmentBreakdown({required this.segmentHits});

  /// The numbered fields, highest first, each of which gets a row of its own.
  static const _numberedFields = [
    20,
    19,
    18,
    17,
    16,
    15,
    14,
    13,
    12,
    11,
    10,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
    1,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    /// One cell: the segment and how often it was hit, zero included. A field
    /// the player never hit says so, because an empty place in the column is
    /// read as a gap in the table rather than as a count.
    Widget cell(int field, int mul) => _SegmentChip(
      label: segmentLabel(l, field, mul),
      count: segmentHits[field]?[mul] ?? 0,
      multiplier: mul,
    );

    if (segmentHits.isEmpty) return const SizedBox.shrink();

    return Theme(
      // The tile sits inside the heatmap card, so it carries neither the
      // divider lines nor the rounded outline an expansion tile draws by
      // default; both would cut the card in two.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          l.allSegments,
          style: theme.textTheme.labelLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            defaultColumnWidth: const FlexColumnWidth(),
            children: [
              for (final field in _numberedFields)
                TableRow(
                  children: [
                    for (final mul in const [1, 2, 3]) cell(field, mul),
                  ],
                ),
              // The bull and the misses close the table: the outer bull, the
              // bull's eye and the darts that hit nothing at all. None of the
              // three belongs under a single/double/triple column, and
              // together they fill exactly one row.
              TableRow(children: [cell(25, 1), cell(25, 2), cell(0, 1)]),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single segment and how often it was hit, colored by its multiplier:
/// neutral for a single, green for a double, blue for a triple, the same tones
/// the board input and the checkout hint use.
///
/// A segment that was never hit keeps its column's color but is faded, so the
/// zero reads as "not yet" without breaking the run of the column.
class _SegmentChip extends StatelessWidget {
  final String label;
  final int count;
  final int multiplier;

  const _SegmentChip({
    required this.label,
    required this.count,
    required this.multiplier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (background, foreground) = switch (multiplier) {
      2 => (doubleContainerColor(context), onDoubleContainerColor(context)),
      3 => (tripleContainerColor(context), onTripleContainerColor(context)),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    final empty = count == 0;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: empty ? background.withValues(alpha: 0.35) : background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label: $count',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: empty ? foreground.withValues(alpha: 0.5) : foreground,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// Horizontal gradient bar: gray → green → yellow → red
/// Paints the color gradient legend for the heatmap (low to high hit count).
class _HeatScalePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      colors: [
        _heatColor(0.05),
        _heatColor(0.25),
        _heatColor(0.50),
        _heatColor(0.75),
        _heatColor(1.0),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_HeatScalePainter old) => false;
}

// Maps intensity [0..1] to the 3-color heat scheme: green → yellow → red
// intensity == 0 → fully transparent (no hits)
Color _heatColor(double intensity) {
  if (intensity <= 0) {
    return const Color(0x00000000); // transparent – no hits
  } else if (intensity < 0.5) {
    // green → yellow
    final t = intensity / 0.5;
    return Color.lerp(
      const Color(0xFF2E7D32), // dark green
      const Color(0xFFF9A825), // amber/yellow
      t,
    )!.withValues(alpha: 0.20 + t * 0.50);
  } else {
    // yellow → red
    final t = (intensity - 0.5) / 0.5;
    return Color.lerp(
      const Color(0xFFF9A825), // amber/yellow
      const Color(0xFFB71C1C), // dark red
      t,
    )!.withValues(alpha: 0.65 + t * 0.35);
  }
}

/// Paints the dartboard heatmap itself, coloring each segment ring by how
/// frequently the player hit it relative to the busiest segment.
class _DartboardPainter extends CustomPainter {
  final Map<int, Map<int, int>> segmentHits;
  final int globalMax;
  final Color outlineColor;
  final Color onSurfaceColor;

  // Standard dartboard segment order (clockwise from top)
  static const _order = [
    20,
    1,
    18,
    4,
    13,
    6,
    10,
    15,
    2,
    17,
    3,
    19,
    7,
    16,
    8,
    11,
    14,
    9,
    12,
    5,
  ];

  _DartboardPainter({
    required this.segmentHits,
    required this.globalMax,
    required this.outlineColor,
    required this.onSurfaceColor,
  });

  /// Heat color for a single segment ring, scaled by its hit count relative to
  /// the busiest segment.
  Color _color(int field, int multiplier) {
    final hits = segmentHits[field]?[multiplier] ?? 0;
    final intensity = hits == 0 ? 0.0 : (hits / globalMax).clamp(0.05, 1.0);
    return _heatColor(intensity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);

    // Radii (as fraction of r)
    final rBullInner = r * 0.06;
    final rBull = r * 0.13;
    final rTriple1 = r * 0.53;
    final rTriple2 = r * 0.60;
    final rDouble1 = r * 0.84;
    final rDouble2 = r * 0.93;

    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    final segCount = _order.length;
    final angleStep = (2 * pi) / segCount;
    final halfStep = angleStep / 2;
    final startAngle = -pi / 2 - halfStep;

    void drawArc(
      Canvas c,
      Offset center,
      double r1,
      double r2,
      double aStart,
      double aSweep,
      Color fill,
    ) {
      final path = Path();
      path.moveTo(center.dx + r1 * cos(aStart), center.dy + r1 * sin(aStart));
      path.arcTo(
        Rect.fromCircle(center: center, radius: r2),
        aStart,
        aSweep,
        false,
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: r1),
        aStart + aSweep,
        -aSweep,
        false,
      );
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(path, outlinePaint);
    }

    final center = Offset(cx, cy);

    for (var i = 0; i < segCount; i++) {
      final field = _order[i];
      final a0 = startAngle + i * angleStep;
      final sweep = angleStep;

      // Inner single (multiplier 1): extends from bull to triple ring
      drawArc(canvas, center, rBull, rTriple1, a0, sweep, _color(field, 1));
      // Triple ring (multiplier 3)
      drawArc(canvas, center, rTriple1, rTriple2, a0, sweep, _color(field, 3));
      // Outer single (multiplier 1)
      drawArc(canvas, center, rTriple2, rDouble1, a0, sweep, _color(field, 1));
      // Double ring (multiplier 2)
      drawArc(canvas, center, rDouble1, rDouble2, a0, sweep, _color(field, 2));
    }

    // Bullseye (double bull = multiplier 2, key 25)
    final bullseyeColor = _color(25, 2);

    canvas.drawCircle(center, rBullInner, Paint()..color = bullseyeColor);
    canvas.drawCircle(center, rBullInner, outlinePaint);

    // Wire outer board boundary
    canvas.drawCircle(center, rDouble2, outlinePaint);

    // Number labels
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < segCount; i++) {
      final field = _order[i];
      final angle = startAngle + i * angleStep + halfStep;
      final labelR = r * 0.975 + 4;
      final lx = cx + labelR * cos(angle);
      final ly = cy + labelR * sin(angle);

      tp.text = TextSpan(
        text: '$field',
        style: TextStyle(
          fontSize: r * 0.09,
          fontWeight: FontWeight.bold,
          color: onSurfaceColor.withValues(alpha: 0.85),
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DartboardPainter old) =>
      old.segmentHits != segmentHits || old.globalMax != globalMax;
}

// ── Top Doubles Card ──────────────────────────────────────────────────────────

/// Card listing the doubles hit most often, ranked by hit count (top 3).
class _TopDoublesCard extends StatelessWidget {
  final PlayerStats stats;
  const _TopDoublesCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final doubleHits = <int, int>{};
    for (final entry in stats.segmentHits.entries) {
      final hits = entry.value[2] ?? 0;
      if (hits > 0) doubleHits[entry.key] = hits;
    }
    final top = doubleHits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _StatCard(
      children: top.take(3).map((e) {
        final label = e.key == 25
            ? context.l10n.bullLabel(true)
            : '${context.l10n.double_} ${e.key}';
        return StatRow(label: label, value: '${e.value}×', spacious: true);
      }).toList(),
    );
  }
}

// ── Stability Card ────────────────────────────────────────────────────────────

/// Card showing scoring consistency (standard deviation of visit scores).
class _StabilityCard extends StatelessWidget {
  final PlayerStats stats;
  const _StabilityCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final std = stats.scoreStdDev;

    final (label, color) = switch (std) {
      < 20 => (context.l10n.stabilityVeryHigh, cs.tertiary),
      < 35 => (context.l10n.stabilityHigh, cs.primary),
      < 50 => (context.l10n.stabilityMedium, cs.secondary),
      _ => (context.l10n.stabilityLow, cs.error),
    };

    // Normalize: stdDev 0 → max consistency, 70 → minimum display
    final frac = (1 - (std / 70)).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  'σ ${std.toStringAsFixed(1)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.stabilityHint(std.toStringAsFixed(1)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Checkout Breakdown Card ───────────────────────────────────────────────────

/// Card breaking down checkout success rate by remaining-score bracket.
class _CheckoutBreakdownCard extends StatelessWidget {
  final PlayerStats stats;
  const _CheckoutBreakdownCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('≤ 40', stats.coAttemptSub40, stats.coSuccessSub40),
      ('41–60', stats.coAttemptSub60, stats.coSuccessSub60),
      ('61–100', stats.coAttemptSub100, stats.coSuccessSub100),
      ('101–170', stats.coAttemptSub170, stats.coSuccessSub170),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          children: rows
              .where((r) => r.$2 > 0)
              .expand(
                (r) => [
                  _CheckoutBracketRow(
                    label: r.$1,
                    attempts: r.$2,
                    successes: r.$3,
                  ),
                  if (r != rows.where((x) => x.$2 > 0).last)
                    Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              )
              .toList(),
        ),
      ),
    );
  }
}

/// A single bracket row in the checkout breakdown (attempts, successes, rate).
class _CheckoutBracketRow extends StatelessWidget {
  final String label;
  final int attempts;
  final int successes;
  const _CheckoutBracketRow({
    required this.label,
    required this.attempts,
    required this.successes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = attempts == 0 ? 0.0 : (successes / attempts) * 100;
    final frac = pct / 100;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: pct >= 50 ? cs.tertiary : cs.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              '$successes/$attempts  ${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Week Comparison Card ──────────────────────────────────────────────────────

/// Card comparing this week's performance to last week's (average, visits, 180s).
class _WeekComparisonCard extends StatelessWidget {
  final PlayerStats stats;
  const _WeekComparisonCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    double delta(double current, double previous) => current - previous;

    Widget col(String title, String thisVal, String lastVal, {double? diff}) {
      final up = diff != null && diff > 0;
      final down = diff != null && diff < 0;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            // This week
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                thisVal,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            // Last week
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                lastVal,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (diff != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    up
                        ? Icons.arrow_upward
                        : down
                        ? Icons.arrow_downward
                        : Icons.remove,
                    size: 12,
                    color: up
                        ? cs.tertiary
                        : down
                        ? cs.error
                        : cs.onSurfaceVariant,
                  ),
                  Text(
                    diff == 0
                        ? '—'
                        : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: up
                          ? cs.tertiary
                          : down
                          ? cs.error
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                col(
                  l10n.threeDartAvg,
                  stats.thisWeekAvg.toStringAsFixed(2),
                  stats.lastWeekAvg.toStringAsFixed(2),
                  diff: delta(stats.thisWeekAvg, stats.lastWeekAvg),
                ),
                const SizedBox(width: 8),
                col(
                  l10n.visits,
                  '${stats.thisWeekVisits}',
                  '${stats.lastWeekVisits}',
                  diff: (stats.thisWeekVisits - stats.lastWeekVisits)
                      .toDouble(),
                ),
                const SizedBox(width: 8),
                col(
                  l10n.count180,
                  '${stats.thisWeek180s}',
                  '${stats.lastWeek180s}',
                  diff: (stats.thisWeek180s - stats.lastWeek180s).toDouble(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WeekLegendItem(
                  color: cs.primaryContainer,
                  label: l10n.thisWeek,
                ),
                const SizedBox(width: 16),
                _WeekLegendItem(
                  color: cs.surfaceContainerHighest,
                  label: l10n.lastWeek,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single legend entry for the week comparison card: a colored dot matching
/// a chip's background color, followed by its label.
class _WeekLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _WeekLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Synced stats view (no local data, shows snapshot from sender) ─────────────

/// Read-only view of stats received from another device via sync.
class _SyncedStatsView extends StatelessWidget {
  final Player player;
  const _SyncedStatsView({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final SyncStats s;
    try {
      s = SyncStats.fromJson(
        jsonDecode(player.syncedStats!) as Map<String, dynamic>,
      );
    } catch (_) {
      return Center(child: Text(context.l10n.statsLoadError));
    }

    final fmt = player.lastSyncedAt != null
        ? DateFormat(
            'dd.MM.yy HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(player.lastSyncedAt!))
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        // Sync banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.sync, size: 16, color: cs.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fmt != null
                      ? '${context.l10n.syncedStatsFrom} $fmt'
                      : context.l10n.syncedStats,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Hero average
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.threeDartAvg,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      s.average.toStringAsFixed(2),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _HeroStatTable(
                cs: cs,
                rows: [
                  (context.l10n.darts_, '${s.totalDarts}'),
                  (context.l10n.visits, '${s.totalVisits}'),
                  (context.l10n.legsWon, '${s.legsWon}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Highlights
        _SyncHighlights(s: s),
        const SizedBox(height: 14),
        // Details
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                _SRow(context.l10n.highestVisit, '${s.highestVisit}'),
                const Divider(height: 1),
                _SRow(context.l10n.count180, '${s.count180}'),
                const Divider(height: 1),
                _SRow(context.l10n.busts, '${s.busts}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Highlight tiles (e.g. 180s, highest visit) for synced stats.
class _SyncHighlights extends StatelessWidget {
  final SyncStats s;
  const _SyncHighlights({required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _SyncTile(
            context.l10n.count180,
            '${s.count180}',
            Icons.star_rounded,
            s.count180 > 0,
            cs,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SyncTile(
            context.l10n.highestVisit,
            '${s.highestVisit}',
            Icons.arrow_upward,
            false,
            cs,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SyncTile(
            context.l10n.legsWon,
            '${s.legsWon}',
            Icons.flag_rounded,
            s.legsWon > 0,
            cs,
          ),
        ),
      ],
    );
  }
}

/// A single highlight tile within the synced stats view.
class _SyncTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final bool highlight;
  final ColorScheme cs;
  const _SyncTile(this.label, this.value, this.icon, this.highlight, this.cs);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: highlight ? cs.tertiaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight ? cs.onTertiaryContainer : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? cs.onTertiaryContainer : cs.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlight
                  ? cs.onTertiaryContainer.withValues(alpha: 0.8)
                  : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value row in the synced stats view.
class _SRow extends StatelessWidget {
  final String l, v;
  const _SRow(this.l, this.v);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            v,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
