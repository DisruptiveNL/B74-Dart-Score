import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/dart_throw.dart';
import '../utils/throw_stats.dart';
import 'stat_row.dart';

/// One member of a team card: their name and the visits they threw themselves.
typedef SummaryMember = (String name, List<DartThrow> throws);

/// Summary card for one slot of a finished X01 game, shared by the post-game
/// summary and the history detail screen.
///
/// Works for a single player and for a whole team; a team passes [members] and
/// gets a per member breakdown under the combined numbers.
class SummaryPlayerCard extends StatelessWidget {
  /// Player or team name shown in the header.
  final String name;

  /// Every visit of this slot, team members combined.
  final List<DartThrow> throws;

  /// Legs won by this slot. Passed in rather than derived, because placement
  /// mode counts legs differently from "a visit that reached zero".
  final int legsWon;

  /// Sets won, or null where the source does not track sets per slot; then the
  /// header names the legs only.
  final int? setsWon;

  /// The slot's members, empty for an individual player.
  final List<SummaryMember> members;

  /// A short honour to stand in the top right of the header, such as a leg
  /// checked out in the fewest darts the start score allows. Null where the
  /// source cannot tell, which is why it is passed in rather than derived: the
  /// live game counts perfect legs as they happen, a stored one does not.
  final String? badge;

  const SummaryPlayerCard({
    super.key,
    required this.name,
    required this.throws,
    required this.legsWon,
    this.setsWon,
    this.members = const [],
    this.badge,
  });

  /// Whether this card stands for a team rather than a single player.
  bool get isTeam => members.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final stats = ThrowStats.fromThrows(throws);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: isTeam
                      ? Icon(
                          Icons.groups_rounded,
                          color: cs.onPrimaryContainer,
                          size: 20,
                        )
                      : Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        setsWon != null
                            ? l.setsLegsWon(setsWon!, legsWon)
                            : '${l.legsWon}: $legsWon',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  _Badge(label: badge!),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            StatRow(label: l.totalDarts, value: '${stats.totalDarts}'),
            StatRow(label: l.visits, value: '${stats.totalVisits}'),
            StatRow(
              label: l.threeDartAvg,
              value: stats.average.toStringAsFixed(2),
            ),
            StatRow(label: l.highestVisit, value: '${stats.highestVisit}'),
            StatRow(label: l.busts, value: '${stats.busts}'),
            if (isTeam) ...[
              const SizedBox(height: 12),
              Text(
                l.teamPlayers,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              for (final member in members)
                _MemberRow(name: member.$1, throws: member.$2),
            ],
          ],
        ),
      ),
    );
  }
}

/// The honour in the corner of a player's header: a star and what it was for.
class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.tertiary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: cs.onTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onTertiary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// One team member under a team card: average, highest visit and darts thrown.
///
/// The name stands on its own line and the three numbers underneath it, so a
/// long name and the spelled-out darts count no longer push each other out of
/// a single row.
class _MemberRow extends StatelessWidget {
  final String name;
  final List<DartThrow> throws;

  const _MemberRow({required this.name, required this.throws});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final stats = ThrowStats.fromThrows(throws);

    final summary = stats.totalDarts == 0
        ? l.noThrowData
        : 'Ø ${stats.average.toStringAsFixed(1)}'
              '  ·  ${l.highAbbr} ${stats.highestVisit}'
              '  ·  ${l.dartsN(stats.totalDarts)}';

    // Where the second line starts, so it lines up with the name rather than
    // with the avatar in front of it.
    const textIndent = 32.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: cs.surfaceContainerHighest,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: textIndent),
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
