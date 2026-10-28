import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shanghai_game.dart';
import '../models/player.dart';
import '../providers/shanghai_provider.dart';
import '../utils/game_labels.dart';
import '../utils/layout.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../utils/player_label.dart';
import 'shanghai_screen.dart';

/// Detailed view of a finished Shanghai game from history, rebuilt by replaying
/// its stored throws through a fresh provider.
class ShanghaiHistorySummaryScreen extends StatefulWidget {
  final ShanghaiGame game;
  final List<Player> players;

  /// Whether this sits inside a pane that brings its own title bar, as the
  /// master detail layout of the history does on a tablet. Embedded it renders
  /// its content alone, without a screen around it.
  final bool embedded;

  const ShanghaiHistorySummaryScreen({
    super.key,
    required this.game,
    required this.players,
    this.embedded = false,
  });

  @override
  State<ShanghaiHistorySummaryScreen> createState() =>
      _ShanghaiHistorySummaryScreenState();
}

class _ShanghaiHistorySummaryScreenState
    extends State<ShanghaiHistorySummaryScreen> {
  /// Started once and kept, not started again on every build.
  ///
  /// A read begun inside `build` is begun again by every rebuild, and a pane
  /// whose divider is being dragged rebuilds on every frame: the view would
  /// fall back to its spinner for the length of the drag and hammer the
  /// database while it lasted.
  late Future<ShanghaiProvider> _future = _load();

  @override
  void didUpdateWidget(ShanghaiHistorySummaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return _wrap(
      context,
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: FutureBuilder<ShanghaiProvider>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final provider = snap.data;
              if (provider == null) {
                return Center(child: Text(context.l10n.noThrowData));
              }
              return _Body(
                game: widget.game,
                players: widget.players,
                provider: provider,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Puts the screen around [content], or hands it over bare when this view is
  /// widget.embedded in a pane that already has a title bar of its own.
  Widget _wrap(BuildContext context, Widget content) => widget.embedded
      ? content
      : Scaffold(
          appBar: AppBar(
            title: Text(
              DateFormat('dd.MM.yy  HH:mm').format(widget.game.createdAt),
            ),
          ),
          body: content,
        );

  /// Replays the widget.game's throws via a standalone provider instance, reusing
  /// its variant-aware scoring/winner logic instead of duplicating it here.
  Future<ShanghaiProvider> _load() async {
    final provider = ShanghaiProvider();
    await provider.resumeGame(widget.game, widget.players);
    return provider;
  }
}

/// Renders the replayed game details: variant, players, and final scores.
class _Body extends StatelessWidget {
  final ShanghaiGame game;
  final List<Player> players;
  final ShanghaiProvider provider;

  const _Body({
    required this.game,
    required this.players,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final states = provider.playerStates;
    final winnerId = provider.winnerId;
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

    final rematch = RematchButton(
      modeName: l.modeShanghaiName,
      details: [(l.shanghaiVariant, shanghaiVariantLabel(l, game.variant))],
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
      onRematch: () =>
          context.read<ShanghaiProvider>().startRematch(game, players),
      destination: (_) => const ShanghaiScreen(),
    );

    final list = ListView(
      // Fixed rather than measured: on a tablet this screen is rendered inside
      // a pane, and contentPadding measures the window, so it would put the
      // margin of a whole screen on either side of half of one.
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        if (winnerSlot != null) ...[
          Center(
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
          ),
          const SizedBox(height: 16),
        ],

        // Game info
        GameInfoCard(
          dense: true,
          rows: [
            (l.gameLabel, l.modeShanghaiName),
            (l.shanghaiVariant, shanghaiVariantLabel(l, game.variant)),
            (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
          ],
        ),

        // ── Rematch ────────────────────────────────────────────────────────
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
                    padding: const EdgeInsets.only(bottom: 10),
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
                                  s.players.map((p) => p.label(l)).join(' & '),
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
                        Text(
                          '${s.score}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isWinner ? cs.primary : null,
                          ),
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
    );

    return Column(
      children: [
        Expanded(child: list),
        SummaryActionBar(actions: [rematch]),
      ],
    );
  }
}
