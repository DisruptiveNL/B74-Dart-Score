import 'package:flutter/material.dart';

/// A label on the left and its bold value on the right, the building block of
/// every stat list in the app.
///
/// Both sides are flexible so a long name or a long value wraps or ellipsizes
/// instead of overflowing the row.
class StatRow extends StatelessWidget {
  final String label;
  final String value;

  /// Taller rows for lists that separate their entries with dividers, where
  /// the tighter spacing would crowd the lines.
  final bool spacious;

  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.spacious = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacious ? 7 : 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
