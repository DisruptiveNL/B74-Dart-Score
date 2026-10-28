import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/cricket_game.dart';
import '../providers/cricket_provider.dart';
import '../utils/game_labels.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../utils/player_label.dart';
import 'cricket_screen.dart';

/// Post-game summary for Cricket: the winner plus each player's final marks and
/// score.
class CricketSummaryScreen extends StatelessWidget {
  const CricketSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CricketProvider>();
    final game = provider.game!;
    final states = provider.playerStates;
    final winnerId = provider.winnerId;
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isCutThroat = game.variant == CricketVariant.cutThroat;

    // The winning slot, looked up once. Null when the game has no winner, and
    // null too if the id names nobody on the board, which keeps a mismatch a
    // missing banner rather than an exception out of the middle of a build.
    final winnerSlot = states.where((s) => s.isWonBy(winnerId)).firstOrNull;

    // Sort for display: winner first, then by score (asc for CT, desc for normal)
    final sorted = List.of(states)
      ..sort((a, b) {
        if (a.isWonBy(winnerId)) return -1;
        if (b.isWonBy(winnerId)) return 1;
        return isCutThroat
            ? a.score.compareTo(b.score)
            : b.score.compareTo(a.score);
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
                  l.cricketWinner(winnerSlot.label(l)),
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
      appBar: AppBar(title: Text(l.cricketSummaryTitle)),
      body: SummaryBody(
        header: winnerBanner,
        top: 24,
        bottom: 24,
        result: [
          // ── Game info ────────────────────────────────────────────────────
          GameInfoCard(
            rows: [
              (l.gameLabel, l.modeCricketName),
              (l.cricketVariant, cricketVariantLabel(l, game.variant)),
              (
                l.cricketScoringMode,
                cricketScoringModeLabel(l, game.scoringMode),
              ),
              (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
            ],
          ),
        ],
        details: [
          // ── Player results ───────────────────────────────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.cricketSummaryTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ...sorted.map((s) {
                    final isWinner = s.isWonBy(winnerId);
                    final fieldsClosed = cricketFields
                        .where((f) => s.hasClosedField(f))
                        .length;
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
                                Text(
                                  '$fieldsClosed/7 ${l.cricketFieldsClosed}',
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
                                l.cricketTotalScore,
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

          // ── Final field status ───────────────────────────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.cricketMarks,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  // Header
                  Row(
                    children: [
                      const SizedBox(width: 52),
                      ...sorted.map(
                        (s) => Expanded(
                          child: Column(
                            children: [
                              Text(
                                s.label(l),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall,
                              ),
                              if (s.isTeamSlot)
                                Text(
                                  s.players.map((p) => p.label(l)).join(' & '),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...cricketFields.map((field) {
                    final label = field == 25 ? l.bull : '$field';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...sorted.map((s) {
                            final marks = s.marks[field] ?? 0;
                            return Expanded(
                              child: Center(
                                child: _SummaryMark(closed: marks >= 3),
                              ),
                            );
                          }),
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
            modeName: l.modeCricketName,
            details: [
              (l.cricketVariant, cricketVariantLabel(l, game.variant)),
              (
                l.cricketScoringMode,
                cricketScoringModeLabel(l, game.scoringMode),
              ),
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
            destination: (_) => const CricketScreen(),
          ),
        ],
      ),
    );
  }
}

/// A compact open/closed indicator for one Cricket field in the summary grid.
class _SummaryMark extends StatelessWidget {
  final bool closed;
  const _SummaryMark({required this.closed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Icon(
      closed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      size: 20,
      color: closed ? cs.primary : cs.outlineVariant,
    );
  }
}
