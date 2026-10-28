import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/game.dart';
import '../utils/finish_calculator.dart';
import '../utils/segment_color.dart';

/// Shows the checkout hint for the current X01 score: a primary route (and an
/// optional alternative) honoring the player's favorite double and checkout
/// mode, or a "no checkout possible" message when none exists.
class FinishSuggestionWidget extends StatelessWidget {
  final int remaining;
  final String? favoriteDouble;

  /// Darts already thrown in the current visit (0, 1, or 2).
  final int dartsThrown;

  /// Checkout rule for the current player.
  final CheckoutMode checkoutMode;

  /// How much larger than on a phone the hint renders. A tablet is read from
  /// across the room, and the route to the double is one of the two things on
  /// the screen a player actually looks up mid visit.
  final double scale;

  const FinishSuggestionWidget({
    super.key,
    required this.remaining,
    this.favoriteDouble,
    this.dartsThrown = 0,
    this.checkoutMode = CheckoutMode.doubleOut,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (remaining <= 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Determine if a checkout is possible at all
    final bool noCheckout =
        remaining > 170 ||
        (remaining == 1 && checkoutMode != CheckoutMode.straightOut);

    if (!noCheckout) {
      final maxDarts = (3 - dartsThrown).clamp(1, 3);
      final routes = FinishCalculator.getRoutes(
        remaining,
        favoriteDouble,
        maxDarts: maxDarts,
        checkoutMode: checkoutMode,
      );

      if (routes.primary != null) {
        final bgColor = tripleContainerColor(context);
        final fgColor = onTripleContainerColor(context);
        return Container(
          margin: EdgeInsets.fromLTRB(12, 4 * scale, 12, 0),
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Primary route ────────────────────────────────────────
              _RouteRow(
                route: routes.primary!,
                color: fgColor,
                bold: true,
                scale: scale,
              ),
              // ── Alternative route ────────────────────────────────────
              if (routes.alternative != null) ...[
                SizedBox(height: 4 * scale),
                _RouteRow(
                  route: routes.alternative!,
                  color: fgColor.withValues(alpha: 0.65),
                  bold: false,
                  scale: scale,
                ),
              ],
            ],
          ),
        );
      }

      // No checkout possible with the remaining darts this turn, but a route
      // toward the favorite double exists for the next visit.
      if (routes.alternative != null) {
        return Container(
          margin: EdgeInsets.fromLTRB(12, 4 * scale, 12, 0),
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.noCheckoutPossible,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * scale,
                  color: cs.onTertiaryContainer,
                ),
              ),
              SizedBox(height: 4 * scale),
              _RouteRow(
                route: routes.alternative!,
                color: cs.onTertiaryContainer.withValues(alpha: 0.75),
                bold: false,
                scale: scale,
              ),
            ],
          ),
        );
      }
    }

    // No checkout possible: same red container as checkout hint, same sizing behaviour
    return Container(
      margin: EdgeInsets.fromLTRB(12, 4 * scale, 12, 0),
      padding: EdgeInsets.symmetric(
        horizontal: 12 * scale,
        vertical: 8 * scale,
      ),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10 * scale),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.noCheckoutPossible,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * scale,
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single centered checkout route displayed as dart chips with arrows.
class _RouteRow extends StatelessWidget {
  final List<String> route;
  final Color color;
  final bool bold;
  final double scale;

  const _RouteRow({
    required this.route,
    required this.color,
    required this.bold,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < route.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * scale),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 13 * scale,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          _DartChip(
            label: route[i],
            color: color,
            isLast: i == route.length - 1,
            bold: bold,
            theme: theme,
            scale: scale,
          ),
        ],
      ],
    );
  }
}

/// A single dart label in a checkout route; the finishing dart is underlined.
class _DartChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLast;
  final bool bold;
  final ThemeData theme;
  final double scale;

  const _DartChip({
    required this.label,
    required this.color,
    required this.isLast,
    required this.bold,
    required this.theme,
    this.scale = 1.0,
  });

  /// How [label] reads in a route. The tables write the bull's eye as `Bull`
  /// and the outer bull as `25`, which reads as one and the same bull to a
  /// player, so both are spelled out with their ring the way `D16` is.
  String _shown(AppLocalizations l10n) => switch (label) {
    'Bull' => l10n.routeDoubleBull,
    '25' => l10n.routeSingleBull,
    _ => label,
  };

  @override
  Widget build(BuildContext context) {
    // Checkout dart (last) gets a subtle underline to distinguish it
    return Text(
      _shown(AppLocalizations.of(context)),
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * scale,
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        decoration: isLast ? TextDecoration.underline : null,
        decorationColor: color,
      ),
    );
  }
}
