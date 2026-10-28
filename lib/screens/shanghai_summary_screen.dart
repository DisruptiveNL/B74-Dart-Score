import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shanghai_game.dart';
import '../providers/shanghai_provider.dart';
import '../utils/game_labels.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../utils/player_label.dart';
import 'shanghai_screen.dart';

/// Post-game summary for Shanghai: the winner and each player's final score,
/// ranked.
class ShanghaiSummaryScreen extends StatelessWidget {
  const ShanghaiSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ShanghaiProvider>();
    final game = provider.game!;
    final states = provider.playerStates;
    final winnerId = provider.winnerId;
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isSequential = game.variant == ShanghaiVariant.sequential;

    // The winning slot, looked up once. Null when the game has no winner, and
    // null too if the id names nobody on the board, which keeps a mismatch a
    // missing banner rather than an exception out of the middle of a build.
    final winnerSlot = states.where((s) => s.isWonBy(winnerId)).firstOrNull;

    final sorted = List.of(states)
      ..sort((a, b) {
        if (a.isWonBy(winnerId)) return -1;
        if (b.isWonBy(winnerId)) return 1;
        if (isSequential) {
          final fa = a.finishedAtDart ?? 1 << 30;
          final fb = b.finishedAtDart ?? 1 << 30;
          if (fa != fb) return fa.compareTo(fb);
        }
        return b.score.compareTo(a.score);
      });

    // Who won, which on two columns belongs over both of them
    // rather than in the half that happens to hold it.
    final winnerBanner = winnerSlot == null
        ? null
        : Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 52,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.shanghaiWinner(winnerSlot.label(l)),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(title: Text(l.shanghaiSummaryTitle)),
      body: SummaryBody(
        header: winnerBanner,
        top: 24,
        bottom: 24,
        result: [
          // ── Game info ────────────────────────────────────────────────────
          GameInfoCard(
            rows: [
              (l.gameLabel, l.modeShanghaiName),
              (l.shanghaiVariant, shanghaiVariantLabel(l, game.variant)),
              (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
            ],
          ),
        ],
        details: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.shanghaiSummaryTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ...sorted.map((s) {
                    final isWinner = s.isWonBy(winnerId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          if (isWinner)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.emoji_events_rounded, size: 18),
                            )
                          else
                            const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.label(l),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: isWinner
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isWinner ? cs.primary : null,
                                  ),
                                ),
                                if (s.isTeamSlot)
                                  Text(
                                    s.players
                                        .map((p) => p.label(l))
                                        .join(' & '),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                if (isSequential)
                                  Text(
                                    s.finishedAtDart != null
                                        ? l.shanghaiDartsUsed(s.finishedAtDart!)
                                        : '${l.shanghaiTarget}: ${s.progress}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${s.score}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isWinner ? cs.primary : null,
                                ),
                              ),
                              Text(
                                l.shanghaiTotalScore,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
        actions: [
          FilledButton.icon(
            onPressed: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
            label: Text(l.backToHome),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          RematchButton(
            modeName: l.modeShanghaiName,
            details: [
              (l.shanghaiVariant, shanghaiVariantLabel(l, game.variant)),
            ],
            slots: states
                .map(
                  (s) => s.isTeamSlot
                      ? RematchSlot.team(
                          s.label(l),
                          s.players
                              .map((p) => RematchSlot.player(p.label(l)))
                              .toList(),
                        )
                      : RematchSlot.player(s.label(l)),
                )
                .toList(),
            onRematch: () => provider.startRematch(
              game,
              states.expand((s) => s.players).toList(),
            ),
            destination: (_) => const ShanghaiScreen(),
          ),
        ],
      ),
    );
  }
}
