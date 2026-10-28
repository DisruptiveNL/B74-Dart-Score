import 'package:flutter/material.dart';

/// A ladder, the symbol of the Checkout Ladder: two rails and four rungs,
/// drawn because Material has no ladder icon, only stairs.
///
/// Laid out like an [Icon] of the same [size]: the strokes keep the margin and
/// the weight of the rounded Material set, so it stands beside the other mode
/// icons without looking borrowed. [color] defaults to the ambient
/// [IconTheme], as an [Icon] does.
class LadderIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const LadderIcon({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LadderPainter(color ?? iconTheme.color ?? Colors.black),
      ),
    );
  }
}

/// Paints the ladder on the 24 unit grid Material icons are drawn on.
class _LadderPainter extends CustomPainter {
  final Color color;
  const _LadderPainter(this.color);

  /// Where the rails stand and how far they reach, in grid units.
  static const _left = 5.5;
  static const _right = 18.5;
  static const _top = 2.5;
  static const _bottom = 21.5;

  /// The rungs, evenly spread between the ends of the rails.
  static const _rungs = [6.3, 10.1, 13.9, 17.7];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2 * unit;

    Offset at(double x, double y) => Offset(x * unit, y * unit);

    canvas.drawLine(at(_left, _top), at(_left, _bottom), paint);
    canvas.drawLine(at(_right, _top), at(_right, _bottom), paint);
    for (final y in _rungs) {
      canvas.drawLine(at(_left, y), at(_right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LadderPainter old) => old.color != color;
}
