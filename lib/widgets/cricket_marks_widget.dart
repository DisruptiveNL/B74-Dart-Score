import 'package:flutter/material.dart';

/// Displays Cricket marks for a single field: nothing / slash / X / circle-X.
class CricketMarksWidget extends StatelessWidget {
  final int marks;

  /// Edge length of the square the mark is drawn in. The painters work off the
  /// size they are given, so a board with taller rows only has to say so.
  final double size;

  const CricketMarksWidget({super.key, required this.marks, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (marks == 0) return SizedBox(width: size, height: size);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: marks >= 3
            ? _ClosedPainter(color: cs.primary)
            : _MarksPainter(marks: marks, color: cs.onSurface),
      ),
    );
  }
}

/// Paints 1-2 Cricket marks as a slash (1) and a crossing slash forming an X (2).
class _MarksPainter extends CustomPainter {
  final int marks;
  final Color color;
  const _MarksPainter({required this.marks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      // The stroke follows the box, so a mark drawn twice the size does not
      // come out twice as thin.
      ..strokeWidth = size.width / 14.4
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.38;

    canvas.drawLine(Offset(cx - r, cy + r), Offset(cx + r, cy - r), paint);
    if (marks >= 2) {
      canvas.drawLine(Offset(cx - r, cy - r), Offset(cx + r, cy + r), paint);
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      old.marks != marks || old.color != color;
}

/// Paints a closed Cricket field (3+ marks) as a circled X.
class _ClosedPainter extends CustomPainter {
  final Color color;
  const _ClosedPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 14.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;

    canvas.drawCircle(Offset(cx, cy), r, paint);
    final xi = r * 0.6;
    canvas.drawLine(Offset(cx - xi, cy + xi), Offset(cx + xi, cy - xi), paint);
    canvas.drawLine(Offset(cx - xi, cy - xi), Offset(cx + xi, cy + xi), paint);
  }

  @override
  bool shouldRepaint(_ClosedPainter old) => old.color != color;
}
