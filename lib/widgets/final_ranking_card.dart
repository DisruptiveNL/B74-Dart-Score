import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/dart_throw.dart';
import '../utils/placement.dart';

/// Final ranking of a placement-mode X01 game, shared by the post-game summary
/// and the history detail screen.
///
/// Slots are keyed by an id the caller chooses: a player id for individual
/// games, a team index for team games. Everything is derived from [throwsById],
/// except that a caller who already keeps an authoritative tally can hand it in
/// through [points], [legsWon] and [placementSum] so the card never contradicts
/// the rest of its screen.
///
/// The order of the rows is [placementOrder]'s, the same one the live game names
/// its winner by.
class FinalRankingCard extends StatelessWidget {
  /// Every slot's visits, keyed by slot id and in throwing order.
  final Map<int, List<DartThrow>> throwsById;

  /// Display name per slot id.
  final Map<int, String> namesById;

  /// Legs won per slot id; derived from the throws when null.
  final Map<int, int>? legsWon;

  /// Cumulative per-leg finishing positions per slot id, the tie-breaker;
  /// derived from the throws when null.
  final Map<int, int>? placementSum;

  /// Points per slot id, what the ranking is decided on; derived from the
  /// throws when null.
  final Map<int, int>? points;

  const FinalRankingCard({
    super.key,
    required this.throwsById,
    required this.namesById,
    this.legsWon,
    this.placementSum,
    this.points,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final maxLeg = throwsById.values
        .expand((t) => t)
        .map((t) => t.leg)
        .fold(0, (a, b) => b > a ? b : a);

    final ranking = placementRanking(throwsById, maxLeg, 1);
    final legTable = legPlacementsTable(throwsById, maxLeg, 1);
    final pointsOf = points ?? placementPointsTotal(throwsById, maxLeg, 1);
    final legsWonOf = legsWon ?? ranking.legsWon;
    final placementOf = placementSum ?? ranking.placementSum;

    final ranked = placementOrder(
      throwsById.keys,
      points: pointsOf,
      legsWon: legsWonOf,
      placementSum: placementOf,
    );

    // The margin the stat cards around it carry, so a column
    // of cards comes out one width.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.finalRanking,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...ranked.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final id = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$rank.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        namesById[id] ?? '?',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${l.legs}: ${legsWonOf[id] ?? 0}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${l.points}: ${pointsOf[id] ?? 0}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (maxLeg > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                l.legByLegPlacements,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l.placementPointsHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(40),
                  columnWidths: {
                    0: const FixedColumnWidth(100),
                    maxLeg + 1: const FixedColumnWidth(56),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: cs.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                  children: [
                    TableRow(
                      children: [
                        const SizedBox.shrink(),
                        for (var leg = 1; leg <= maxLeg; leg++)
                          _RankCell(
                            l.legAbbr(leg),
                            bold: true,
                            alignment: Alignment.center,
                          ),
                        _RankCell(
                          l.points,
                          bold: true,
                          alignment: Alignment.center,
                        ),
                      ],
                    ),
                    ...ranked.map(
                      (id) => TableRow(
                        children: [
                          _RankCell(
                            namesById[id] ?? '?',
                            alignment: Alignment.centerLeft,
                          ),
                          for (var leg = 1; leg <= maxLeg; leg++)
                            _RankCell(
                              legTable[leg]?[id] != null
                                  ? '${legTable[leg]![id]}.'
                                  : '-',
                              alignment: Alignment.center,
                            ),
                          _RankCell(
                            '${pointsOf[id] ?? 0}',
                            bold: true,
                            alignment: Alignment.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single padded, optionally bold cell used in the per-leg placement table.
class _RankCell extends StatelessWidget {
  final String text;
  final bool bold;
  final Alignment alignment;

  const _RankCell(
    this.text, {
    this.bold = false,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: bold ? FontWeight.bold : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
