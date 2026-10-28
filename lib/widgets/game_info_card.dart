import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'stat_row.dart';

/// One label/value line of a [GameInfoCard].
typedef GameInfoRow = (String label, String value);

/// Card listing the settings a finished game was played with, so the post-game
/// summary and the history detail describe a game the same way and in the same
/// shape as the surrounding stat cards.
///
/// Set [dense] on the history screens, whose heading reads at a smaller size.
/// It is the type that changes, not the box: every card of a summary carries
/// the same margin and the same padding, or a column of them comes out ragged.
class GameInfoCard extends StatelessWidget {
  final List<GameInfoRow> rows;
  final bool dense;

  const GameInfoCard({super.key, required this.rows, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The same margin, padding and divided header the stat cards it stands
    // among carry, so a column of cards reads as one column.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.gameInfo,
              style:
                  (dense
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...rows.map((r) => StatRow(label: r.$1, value: r.$2)),
          ],
        ),
      ),
    );
  }
}
