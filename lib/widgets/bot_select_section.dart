import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/player.dart';
import '../utils/bot_thrower.dart';

/// How many bots of one tier a game can hold; the plus of a row that has
/// reached it goes off. Five keeps the counter to one digit and is more of
/// one strength than any round needs.
const int kMaxBotsPerTier = 5;

/// The card under the roster that adds computer opponents to a game: a
/// switch in the header like the handicap and team cards, and once it is on,
/// one row per tier with the tier's name, roughly how well it throws and a
/// counter with a minus and a plus, and under the rows one line saying which
/// slots the bots throw in.
///
/// Shared by all four setup screens. Plus adds one more bot of that tier, so
/// a game can hold two of the same strength, up to [kMaxBotsPerTier]; minus
/// takes away the bot of that
/// tier that throws last, so the others keep their slots. Every tier is always
/// listed, which is what keeps the card the same height however many bots are
/// in the game. [selectedPlayers] is the whole selection in throwing order,
/// people included, so the slot numbers are the ones the bots will really
/// throw in. Switching the card off drops every bot from the selection, which
/// the caller does in [onEnabledChanged].
class BotSelectSection extends StatelessWidget {
  final bool enabled;
  final List<Player> selectedPlayers;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<BotLevel> onAdd;
  final ValueChanged<Player> onRemove;

  const BotSelectSection({
    super.key,
    required this.enabled,
    required this.selectedPlayers,
    required this.onEnabledChanged,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final byTier = <BotLevel, List<Player>>{};
    final slots = <int>[];
    for (var i = 0; i < selectedPlayers.length; i++) {
      final level = selectedPlayers[i].botLevel;
      if (level == null) continue;
      (byTier[level] ??= []).add(selectedPlayers[i]);
      slots.add(i + 1);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.botOpponent,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch(value: enabled, onChanged: onEnabledChanged),
              ],
            ),
            if (enabled) ...[
              for (final level in BotLevel.values)
                _tierRow(context, level, byTier[level] ?? const []),
              if (slots.isEmpty)
                const SizedBox(height: 8)
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    l.botSlotsHint(slots),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// One tier's row: its name and expected average on the left, and on the
  /// right the counter with the minus, which is off while the tier has no
  /// bot in the game, and the plus, which is off once it holds
  /// [kMaxBotsPerTier]. [bots] are this tier's bots in throwing order, so
  /// minus hands the last of them to [onRemove].
  Widget _tierRow(BuildContext context, BotLevel level, List<Player> bots) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final none = bots.isEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        l.botTier(level),
        style: none ? TextStyle(color: cs.onSurfaceVariant) : null,
      ),
      subtitle: Text(l.botAverageHint(expectedAverageOf(level))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            tooltip: l.removeBot(level),
            visualDensity: VisualDensity.compact,
            onPressed: none ? null : () => onRemove(bots.last),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '${bots.length}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: none ? cs.outlineVariant : cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            tooltip: l.addBot(level),
            color: cs.primary,
            visualDensity: VisualDensity.compact,
            onPressed: bots.length >= kMaxBotsPerTier
                ? null
                : () => onAdd(level),
          ),
        ],
      ),
    );
  }
}
