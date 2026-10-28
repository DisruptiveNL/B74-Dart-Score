import 'package:flutter/material.dart';
import '../utils/segment_color.dart';
import '../utils/visit_darts.dart';

/// The darts of a visit as a row of chips, one slot per dart the visit may
/// hold: a triple in the triple blue, a double in the double green, a single
/// on the plain surface, a miss dimmed, and an empty slot as an outline.
///
/// Replaces the three dots the target modes used to count darts with, so the
/// thrower sees what landed, and sees it still during the pause a finished
/// visit stays on the board for. Scaled down rather than wrapped when the
/// row is given less room than its chips want.
class VisitDartsRow extends StatelessWidget {
  final List<VisitDart> darts;

  /// How many darts the visit may hold: three, or seven in clockwise Shanghai.
  final int slots;

  const VisitDartsRow({super.key, required this.darts, this.slots = 3});

  @override
  Widget build(BuildContext context) {
    final tight = slots > 3;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < slots; i++) ...[
            if (i > 0) SizedBox(width: tight ? 3 : 5),
            _Chip(dart: i < darts.length ? darts[i] : null, tight: tight),
          ],
        ],
      ),
    );
  }
}

/// One dart of the row, or the outline of a slot still to be thrown.
class _Chip extends StatelessWidget {
  final VisitDart? dart;
  final bool tight;

  const _Chip({required this.dart, required this.tight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = dart;

    final (Color? background, Color foreground, Color border) = d == null
        ? (null, cs.outline, cs.outlineVariant)
        : d.miss
        ? (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
            cs.surfaceContainerHighest,
          )
        : d.multiplier == 3
        ? (
            tripleContainerColor(context),
            onTripleContainerColor(context),
            tripleContainerColor(context),
          )
        : d.multiplier == 2
        ? (
            doubleContainerColor(context),
            onDoubleContainerColor(context),
            doubleContainerColor(context),
          )
        : (cs.surfaceContainerHigh, cs.onSurface, cs.surfaceContainerHigh);

    return Container(
      constraints: BoxConstraints(minWidth: tight ? 30 : 40),
      padding: EdgeInsets.symmetric(horizontal: tight ? 5 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: Text(
        d?.label ?? '',
        maxLines: 1,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}
