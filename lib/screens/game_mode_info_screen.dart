import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/layout.dart';

/// The selectable game modes, used by the mode selection and info screens.
enum GameModeOption { x01, cricket, shanghai, aroundTheClock, checkoutLadder }

/// Explains the rules of a single game [mode] (title, description, variants).
class GameModeInfoScreen extends StatelessWidget {
  final GameModeOption mode;

  const GameModeInfoScreen({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (name, tagline, description, icon) = _content(l);

    return Scaffold(
      appBar: AppBar(title: Text(l.modeInfoTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 52, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Divider(color: cs.outlineVariant),
                  const SizedBox(height: 20),
                  Text(
                    description,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  Divider(color: cs.outlineVariant),
                  const SizedBox(height: 20),
                  Text(
                    l.modeBotTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.modeBotNote,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, String, String, IconData) _content(AppLocalizations l) {
    switch (mode) {
      case GameModeOption.x01:
        return (l.modeX01Name, l.modeX01Tagline, l.modeX01Description,
            Icons.filter_none_rounded);
      case GameModeOption.cricket:
        return (l.modeCricketName, l.modeCricketTagline,
            l.modeCricketDescription, Icons.sports_cricket_rounded);
      case GameModeOption.shanghai:
        return (l.modeShanghaiName, l.modeShanghaiTagline,
            l.modeShanghaiDescription, Icons.layers_rounded);
      case GameModeOption.aroundTheClock:
        return (l.modeAroundClockName, l.modeAroundClockTagline,
            l.modeAroundClockDescription, Icons.watch_later_outlined);
      case GameModeOption.checkoutLadder:
        return (l.modeCheckoutLadderName, l.modeCheckoutLadderTagline,
            l.modeCheckoutLadderDescription, Icons.stairs_rounded);
    }
  }
}
