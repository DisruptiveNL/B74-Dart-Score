import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/starting_order.dart';

/// One draggable entry of a [StartingOrderSection]: a single player, or a whole
/// team in a team game.
class StartingOrderEntry {
  /// Identity of the entry, stable across reorders so the drag animation
  /// follows the moved item rather than its position.
  final Key key;
  final String label;

  /// Team accent color, or null in an individual game.
  final Color? color;

  const StartingOrderEntry({
    required this.key,
    required this.label,
    this.color,
  });
}

/// Section to pick how the throwing order is determined: drawn randomly at the
/// start, or fixed by hand, traditionally after throwing for the bull. Shared
/// by every game mode's setup screen.
///
/// In a team game [entries] are the teams, because only their order matters;
/// the order of the members inside a team does not.
class StartingOrderSection extends StatelessWidget {
  final StartingOrder order;
  final List<StartingOrderEntry> entries;
  final bool teamMode;
  final ValueChanged<StartingOrder> onOrderChanged;

  /// Reports a completed drag with indices already normalized for the removal,
  /// so the caller can simply remove at [oldIndex] and insert at [newIndex].
  final void Function(int oldIndex, int newIndex) onReorder;

  const StartingOrderSection({
    super.key,
    required this.order,
    required this.entries,
    required this.teamMode,
    required this.onOrderChanged,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.startingOrder,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<StartingOrder>(
                segments: [
                  ButtonSegment(
                    value: StartingOrder.fixed,
                    icon: const Icon(Icons.format_list_numbered, size: 18),
                    label: Text(l.startingOrderFixed),
                  ),
                  ButtonSegment(
                    value: StartingOrder.random,
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: Text(l.startingOrderRandom),
                  ),
                ],
                selected: {order},
                onSelectionChanged: (s) => onOrderChanged(s.first),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              order == StartingOrder.random
                  ? l.startingOrderRandomHint
                  : (teamMode
                        ? l.startingOrderTeamHint
                        : l.startingOrderFixedHint),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (order == StartingOrder.fixed) ...[
              const SizedBox(height: 4),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: entries.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (newIndex != oldIndex) onReorder(oldIndex, newIndex);
                },
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final accent = e.color ?? cs.primary;
                  return Padding(
                    key: e.key,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: accent.withValues(alpha: 0.2),
                          child: Text(
                            e.label.isNotEmpty ? e.label[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.label,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.drag_handle,
                              size: 22,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
