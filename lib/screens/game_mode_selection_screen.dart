import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/layout.dart';
import 'game_mode_info_screen.dart';
import 'game_setup_screen.dart';
import 'cricket_setup_screen.dart';
import 'shanghai_setup_screen.dart';
import 'around_the_clock_setup_screen.dart';
import 'checkout_ladder_setup_screen.dart';

/// Lets the user pick a game mode (X01, Cricket, Shanghai, Around the Clock,
/// Checkout Ladder),
/// opening its setup screen or an info screen explaining the rules.
class GameModeSelectionScreen extends StatelessWidget {
  const GameModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.selectGameMode)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ModeCard(
                    mode: GameModeOption.x01,
                    name: l.modeX01Name,
                    tagline: l.modeX01Tagline,
                    available: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GameSetupScreen()),
                    ),
                    onInfo: () => _openInfo(context, GameModeOption.x01),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    mode: GameModeOption.cricket,
                    name: l.modeCricketName,
                    tagline: l.modeCricketTagline,
                    available: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CricketSetupScreen()),
                    ),
                    onInfo: () => _openInfo(context, GameModeOption.cricket),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    mode: GameModeOption.shanghai,
                    name: l.modeShanghaiName,
                    tagline: l.modeShanghaiTagline,
                    available: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ShanghaiSetupScreen()),
                    ),
                    onInfo: () => _openInfo(context, GameModeOption.shanghai),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    mode: GameModeOption.aroundTheClock,
                    name: l.modeAroundClockName,
                    tagline: l.modeAroundClockTagline,
                    available: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AroundTheClockSetupScreen()),
                    ),
                    onInfo: () => _openInfo(context, GameModeOption.aroundTheClock),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    mode: GameModeOption.checkoutLadder,
                    name: l.modeCheckoutLadderName,
                    tagline: l.modeCheckoutLadderTagline,
                    available: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CheckoutLadderSetupScreen()),
                    ),
                    onInfo: () => _openInfo(context, GameModeOption.checkoutLadder),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the rules/info screen for the given game [mode].
  void _openInfo(BuildContext context, GameModeOption mode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameModeInfoScreen(mode: mode),
      ),
    );
  }
}

/// A selectable game-mode card with icon, name, tagline, and an info button.
class _ModeCard extends StatelessWidget {
  final GameModeOption mode;
  final String name;
  final String tagline;
  final bool available;
  final VoidCallback? onTap;
  final VoidCallback onInfo;

  const _ModeCard({
    required this.mode,
    required this.name,
    required this.tagline,
    required this.available,
    required this.onInfo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final contentColor = available
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.45);
    final iconColor = available ? cs.primary : cs.onSurface.withValues(alpha: 0.35);

    return Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: available ? cs.outlineVariant : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: available ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              gameModeIcon(mode, size: 36, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: contentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: contentColor.withValues(alpha: 0.8),
                      ),
                    ),
                    if (!available) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l.comingSoon,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onInfo,
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: available ? cs.primary : cs.onSurface.withValues(alpha: 0.4),
                ),
                tooltip: l.modeInfoTitle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
