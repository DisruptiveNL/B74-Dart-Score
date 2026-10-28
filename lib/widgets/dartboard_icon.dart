import 'dart:math';
import 'package:flutter/material.dart';

/// A classic dartboard drawn with CustomPainter.
/// Use [size] to control the diameter.
class DartboardIcon extends StatelessWidget {
  final double size;
  const DartboardIcon({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: DartboardPainter()),
    );
  }
}

/// Paints a full dartboard: 20 alternating segments with double/triple scoring
/// rings, the green outer bull and red bullseye, and the segment/ring wires.
///
/// The board ends at the outer edge of the double ring. There is no rim and no
/// single area behind the doubles, so the coloured ring carries the outline and
/// survives being scaled down to an icon.
class DartboardPainter extends CustomPainter {
  // Segment colours: alternating black / cream, red / green for scoring rings
  static const _black = Color(0xFF1A1A1A);
  static const _cream = Color(0xFFF5E6C8);
  static const _red = Color(0xFFC0392B);
  static const _green = Color(0xFF1E7A3C);
  static const _wire = Color(0xFFC2C9D1);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);

    // Radii as fractions of the full board radius. These are the classic
    // proportions scaled up by 1/0.940, because dropping the rim promotes the
    // outer edge of the double ring to the edge of the board. The last sliver
    // is left free so the ring wire is not cut in half by the widget bounds.
    final rBull = r * 0.058; // inner bull (red)
    final rBullOuter = r * 0.122; // outer bull (green)
    final rTriple1 = r * 0.498; // inner edge of triple ring
    final rTriple2 = r * 0.572; // outer edge of triple ring
    final rDouble1 = r * 0.889; // inner edge of double ring
    final rDouble2 = r * 0.995; // outer edge of double ring, the board edge

    const n = 20;
    const sweep = (2 * pi) / n;
    // Segments start at -90° (top) minus half a segment so the 20 is centred at top
    const startAngle = -pi / 2 - sweep / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    // ── 1. Black board background ────────────────────────────────────────
    // Sits under the segments so their arcs cannot leave antialiasing seams.
    paint.color = _black;
    canvas.drawCircle(Offset(cx, cy), rDouble2, paint);

    // ── 2. Segments – single / double / triple ───────────────────────────
    for (int i = 0; i < n; i++) {
      final angle = startAngle + i * sweep;
      final isEven = i % 2 == 0;

      // colours for this segment pair
      final baseColor = isEven ? _black : _cream;
      final scoringColor = isEven ? _red : _green;

      // Double ring: red/green
      _drawSector(
        canvas,
        cx,
        cy,
        rDouble1,
        rDouble2,
        angle,
        sweep,
        paint,
        scoringColor,
      );

      // Single inner (between triple outer and double inner): black/cream
      _drawSector(
        canvas,
        cx,
        cy,
        rTriple2,
        rDouble1,
        angle,
        sweep,
        paint,
        baseColor,
      );

      // Triple ring: red/green
      _drawSector(
        canvas,
        cx,
        cy,
        rTriple1,
        rTriple2,
        angle,
        sweep,
        paint,
        scoringColor,
      );

      // Single inner inner (between bull outer and triple inner): black/cream
      _drawSector(
        canvas,
        cx,
        cy,
        rBullOuter,
        rTriple1,
        angle,
        sweep,
        paint,
        baseColor,
      );
    }

    // ── 3. Outer bull (green) ────────────────────────────────────────────
    paint.color = _green;
    canvas.drawCircle(Offset(cx, cy), rBullOuter, paint);

    // ── 4. Inner bull / bullseye (red) ───────────────────────────────────
    paint.color = _red;
    canvas.drawCircle(Offset(cx, cy), rBull, paint);

    // ── 5. Wire lines between segments ───────────────────────────────────
    // Drawn thin and fully opaque: a translucent wire blurs the edge between a
    // cream and a black segment instead of cutting it, which is what made the
    // board look soft once it was scaled down.
    final wirePaint = Paint()
      ..color = _wire
      ..strokeWidth = r * 0.009
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < n; i++) {
      final angle = startAngle + i * sweep;
      final dx = cos(angle);
      final dy = sin(angle);
      canvas.drawLine(
        Offset(cx + dx * rBullOuter, cy + dy * rBullOuter),
        Offset(cx + dx * rDouble2, cy + dy * rDouble2),
        wirePaint,
      );
    }

    // Ring wires
    for (final rad in [rTriple1, rTriple2, rDouble1, rDouble2]) {
      canvas.drawCircle(Offset(cx, cy), rad, wirePaint);
    }

    // Bullseye wire
    canvas.drawCircle(Offset(cx, cy), rBullOuter, wirePaint);
    canvas.drawCircle(Offset(cx, cy), rBull, wirePaint);
  }

  /// Fills one annular sector (a single ring slice of one segment) spanning the
  /// radii [innerR]..[outerR] over the angular range [startAngle]..+[sweep].
  void _drawSector(
    Canvas canvas,
    double cx,
    double cy,
    double innerR,
    double outerR,
    double startAngle,
    double sweep,
    Paint paint,
    Color color,
  ) {
    paint.color = color;
    final path = Path()
      ..moveTo(cx + innerR * cos(startAngle), cy + innerR * sin(startAngle))
      ..lineTo(cx + outerR * cos(startAngle), cy + outerR * sin(startAngle))
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: outerR),
        startAngle,
        sweep,
        false,
      )
      ..lineTo(
        cx + innerR * cos(startAngle + sweep),
        cy + innerR * sin(startAngle + sweep),
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
        startAngle + sweep,
        -sweep,
        false,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
