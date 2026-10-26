import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/donation_provider.dart';

/// import '../widgets/dartboard_icon.dart';
import 'players_screen.dart';
import 'game_mode_selection_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import '../utils/layout.dart';

/// App home screen with navigation to game setup, history, players, and settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final isSupporter = context.watch<DonationProvider>().isSupporter;
    final tablet = isTabletLayout(context);

    final secondary = [
      _HomeButton(
        stacked: tablet,
        icon: Icons.people_outlined,
        label: l.managePlayers,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlayersScreen()),
        ),
      ),
      _HomeButton(
        stacked: tablet,
        icon: Icons.history_rounded,
        label: l.gameHistory,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ),
      ),
      _HomeButton(
        stacked: tablet,
        icon: Icons.settings_outlined,
        label: l.settings,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: tablet ? 260 : 190,
                      height: tablet ? 260 : 190,
                      fit: BoxFit.contain,
                      semanticLabel: 'B74 Dart Score',
                    ),
                  ),
                  if (isSupporter) ...[
                    const SizedBox(height: 6),
                    Icon(Icons.favorite_rounded, size: 16, color: cs.primary),
                  ],
                  const SizedBox(height: 48),
                  _HomeButton(
                    icon: Icons.play_arrow_rounded,
                    label: l.newGame,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GameModeSelectionScreen(),
                      ),
                    ),
                    primary: true,
                  ),
                  const SizedBox(height: 14),
                  // The three that are not starting a game sit side by side
                  // where there is width for it, so the column does not read
                  // as a phone screen stretched tall.
                  if (tablet)
                    Row(
                      children: [
                        for (final entry in secondary) ...[
                          if (entry != secondary.first)
                            const SizedBox(width: 14),
                          Expanded(child: entry),
                        ],
                      ],
                    )
                  else
                    for (final entry in secondary) ...[
                      entry,
                      if (entry != secondary.last) const SizedBox(height: 14),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A large labeled icon button on the home screen.
///
/// [stacked] puts the icon above the label instead of beside it, which is what
/// lets three of them share a row: the labels are long enough that side by side
/// they would each need most of a phone width.
class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool stacked;

  const _HomeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stacked) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          textStyle: theme.textTheme.titleLarge,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        textStyle: theme.textTheme.titleMedium,
      ),
    );
  }
}
