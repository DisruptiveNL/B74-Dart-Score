import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../utils/dartboard_geometry.dart';

export '../utils/dartboard_geometry.dart' show dartboardSegmentOrder;

/// Radius of the inner (double) bullseye, as a fraction of the board radius.
const dartboardBullInnerRadius = 0.050;

/// Outer radius of the single bull (the "25" ring), as a fraction of the
/// board radius. Shared with the favorite-double picker, which treats any tap
/// within this radius as the bull.
const dartboardBullOuterRadius = 0.110;

/// Inner radius of the outer single ring (i.e. the outer edge of the triple
/// ring), as a fraction of the board radius. Shared with the favorite-double
/// picker, which treats taps in the outer single ring as hitting the double
/// of that segment for a larger hitbox.
const dartboardOuterSingleRingInner = 0.505;

/// Inner and outer radius of the double ring, as a fraction of the board
/// radius. Shared with the favorite-double picker for hit testing.
const dartboardDoubleRingInner = 0.705;
const dartboardDoubleRingOuter = 0.780;

/// Paints a dartboard with the given [target] segment highlighted.
///
/// When [highlightMultipliers] is null, all rings of the target segment are
/// highlighted. When provided, only the listed multipliers (1=single,
/// 2=double, 3=triple) are highlighted: used for the full-segments variant.
class DartboardTargetPainter extends CustomPainter {
  final int target;
  final Set<int>? highlightMultipliers;
  final Color highlightColor;
  final Color onSurfaceColor;

  const DartboardTargetPainter({
    required this.target,
    required this.highlightColor,
    required this.onSurfaceColor,
    this.highlightMultipliers,
  });

  /// Whether the given [multiplier] ring should be highlighted (all rings when
  /// [highlightMultipliers] is null, otherwise only the listed ones).
  bool _highlighted(int multiplier) =>
      highlightMultipliers == null ||
      highlightMultipliers!.contains(multiplier);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);
    final center = Offset(cx, cy);

    final rBullInner = r * dartboardBullInnerRadius;
    final rBull = r * dartboardBullOuterRadius;
    final rTriple1 = r * 0.445;
    final rTriple2 = r * dartboardOuterSingleRingInner;
    final rDouble1 = r * dartboardDoubleRingInner;
    final rDouble2 = r * dartboardDoubleRingOuter;

    final segCount = dartboardSegmentOrder.length;
    final angleStep = (2 * pi) / segCount;
    final halfStep = angleStep / 2;
    final startAngle = -pi / 2 - halfStep;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final wirePaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.01;

    void drawRing(double r1, double r2, double a0, double sweep, Color fill) {
      final path = Path();
      path.moveTo(center.dx + r1 * cos(a0), center.dy + r1 * sin(a0));
      path.arcTo(Rect.fromCircle(center: center, radius: r2), a0, sweep, false);
      path.arcTo(
        Rect.fromCircle(center: center, radius: r1),
        a0 + sweep,
        -sweep,
        false,
      );
      path.close();
      fillPaint.color = fill;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, wirePaint);
    }

    for (var i = 0; i < segCount; i++) {
      final field = dartboardSegmentOrder[i];
      final a0 = startAngle + i * angleStep;
      final isTargetField = field == target && target != 25;
      final base = onSurfaceColor.withValues(alpha: i.isEven ? 0.08 : 0.03);

      Color ringColor(int multiplier) {
        if (!isTargetField || !_highlighted(multiplier)) return base;
        return highlightColor.withValues(alpha: 0.55);
      }

      drawRing(rBull, rTriple1, a0, angleStep, ringColor(1));
      drawRing(rTriple1, rTriple2, a0, angleStep, ringColor(3));
      drawRing(rTriple2, rDouble1, a0, angleStep, ringColor(1));
      drawRing(rDouble1, rDouble2, a0, angleStep, ringColor(2));
    }

    final bullIsTarget = target == 25;
    fillPaint.color = (bullIsTarget && _highlighted(1))
        ? highlightColor.withValues(alpha: 0.55)
        : onSurfaceColor.withValues(alpha: 0.08);
    canvas.drawCircle(center, rBull, fillPaint);
    canvas.drawCircle(center, rBull, wirePaint);
    fillPaint.color = (bullIsTarget && _highlighted(2))
        ? highlightColor.withValues(alpha: 0.8)
        : onSurfaceColor.withValues(alpha: 0.16);
    canvas.drawCircle(center, rBullInner, fillPaint);
    canvas.drawCircle(center, rBullInner, wirePaint);

    canvas.drawCircle(center, rDouble2, wirePaint);

    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < segCount; i++) {
      final field = dartboardSegmentOrder[i];
      final isTargetNum = field == target;
      final angle = startAngle + i * angleStep + halfStep;
      final labelR = r * 0.93;
      final lx = cx + labelR * cos(angle);
      final ly = cy + labelR * sin(angle);

      tp.text = TextSpan(
        text: '$field',
        style: TextStyle(
          fontSize: r * (isTargetNum ? 0.135 : 0.10),
          fontWeight: isTargetNum ? FontWeight.bold : FontWeight.w500,
          color: isTargetNum
              ? highlightColor
              : onSurfaceColor.withValues(alpha: 0.7),
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant DartboardTargetPainter old) =>
      old.target != target ||
      old.highlightMultipliers != highlightMultipliers ||
      old.highlightColor != highlightColor;
}
