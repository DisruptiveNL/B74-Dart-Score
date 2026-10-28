import 'dart:math';
import 'package:flutter/material.dart';
import 'dartboard_target_painter.dart';

/// Interactive dartboard for picking a player's favorite double.
///
/// Highlights the currently selected double segment (or the bull) and lets
/// the user tap directly on a double ring or the inner bull to choose a new
/// one. [value] is one of `D1`..`D20` or `Bull`; `null` shows no highlight.
/// Taps outside the double rings and the inner bull are ignored.
class FavoriteDoublePicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;

  const FavoriteDoublePicker({super.key, this.value, required this.onChanged});

  /// Converts [value] to the painter's target field: 1-20, 25 for `Bull`, or
  /// -1 when nothing is selected.
  int get _target {
    final v = value;
    if (v == null) return -1;
    if (v == 'Bull') return 25;
    return int.parse(v.substring(1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: DartboardTargetPainter(
                target: _target,
                highlightMultipliers: const {2},
                highlightColor: cs.primary,
                onSurfaceColor: cs.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Maps a tap at [position] within a board of [size] to a favorite double
  /// and invokes [onChanged]. To keep the hitboxes generous, a tap anywhere
  /// within the single bull also selects the bull, and a tap in the outer
  /// single ring of a segment also selects that segment's double. Taps
  /// outside those areas are ignored.
  void _handleTap(Offset position, Size size) {
    final r = min(size.width, size.height) / 2;
    final dx = position.dx - size.width / 2;
    final dy = position.dy - size.height / 2;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist <= r * dartboardBullOuterRadius) {
      onChanged('Bull');
      return;
    }
    if (dist < r * dartboardOuterSingleRingInner ||
        dist > r * dartboardDoubleRingOuter) {
      return;
    }

    const segCount = 20;
    const angleStep = 2 * pi / segCount;
    const startAngle = -pi / 2 - angleStep / 2;

    var rel = (atan2(dy, dx) - startAngle) % (2 * pi);
    if (rel < 0) rel += 2 * pi;
    final field = dartboardSegmentOrder[(rel / angleStep).floor() % segCount];
    onChanged('D$field');
  }
}
