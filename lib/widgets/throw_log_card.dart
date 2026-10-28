import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/dart_throw.dart';
import 'throw_row.dart';

/// The complete throw log of a finished X01 game, shared by the post-game
/// summary and the history detail screen so both read the same way.
class ThrowLogCard extends StatelessWidget {
  /// Every visit of the game in throwing order.
  final List<DartThrow> throws;

  /// Resolves a visit's player id to the name shown in front of the row.
  final String Function(int playerId) playerName;

  /// Whether to name the set as well; pointless in a single-set game.
  final bool showSet;

  const ThrowLogCard({
    super.key,
    required this.throws,
    required this.playerName,
    this.showSet = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              context.l10n.allThrows,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final t in throws)
              ThrowRow(
                t: t,
                playerName: playerName(t.playerId),
                showSet: showSet,
              ),
          ],
        ),
      ),
    );
  }
}
