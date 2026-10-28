import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/cricket_game.dart';
import '../models/player.dart';
import '../providers/cricket_provider.dart';
import '../utils/game_labels.dart';
import '../utils/layout.dart';
import '../widgets/cricket_marks_widget.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../utils/player_label.dart';
import 'cricket_screen.dart';

/// Detailed view of a finished Cricket game from history, with final marks and
/// scores reconstructed from its stored throws.
class CricketHistorySummaryScreen extends StatefulWidget {
  final CricketGame game;
  final List<Player> players;

  /// Whether this sits inside a pane that brings its own title bar, as the
  /// master detail layout of the history does on a tablet. Embedded it renders
  /// its content alone, without a screen around it.
  final bool embedded;

  const CricketHistorySummaryScreen({
    super.key,
    required this.game,
    required this.players,
    this.embedded = false,
  });

  @override
  State<CricketHistorySummaryScreen> createState() =>
      _CricketHistorySummaryScreenState();
}

class _CricketHistorySummaryScreenState
    extends State<CricketHistorySummaryScreen> {
  /// Started once and kept, not started again on every build.
  ///
  /// A read begun inside `build` is begun again by every rebuild, and a pane
  /// whose divider is being dragged rebuilds on every frame: the view would
  /// fall back to its spinner for the length of the drag and hammer the
  /// database while it lasted.
  late Future<CricketProvider> _future = _load();

  @override
  void didUpdateWidget(CricketHistorySummaryScreen oldWidget) {
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
          child: FutureBuilder<CricketProvider>(
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

  /// Replays the widget.game's throws via a standalone provider instance,
  /// reusing its marks, scoring and winner logic instead of duplicating it
  /// here, exactly as the Shanghai and Around the Clock history views do.
  Future<CricketProvider> _load() async {
    final provider = CricketProvider();
    await provider.resumeGame(widget.game, widget.players);
    return provider;
  }
}

/// Renders the reconstructed game details: variant, marks grid, and scores.
class _Body extends StatelessWidget {
  final CricketGame game;
  final List<Player> players;
  final CricketProvider provider;

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
    final isCT = game.variant == CricketVariant.cutThroat;
    final states = provider.playerStates;
    final winnerId = provider.winnerId;

    // The winning slot, looked up once. Null when the game has no winner, and
    // null too if the id names nobody on the board, which keeps a mismatch a
    // missing banner rather than an exception out of the middle of a build.
    final winnerSlot = states.where((s) => s.isWonBy(winnerId)).firstOrNull;

    final sorted = List.of(states)
      ..sort((a, b) {
        if (a.isWonBy(winnerId)) return -1;
        if (b.isWonBy(winnerId)) return 1;
        return isCT ? a.score.compareTo(b.score) : b.score.compareTo(a.score);
      });

    final rematch = RematchButton(
      modeName: l.modeCricketName,
      details: [
        (l.cricketVariant, cricketVariantLabel(l, game.variant)),
        (l.cricketScoringMode, cricketScoringModeLabel(l, game.scoringMode)),
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
      onRematch: () =>
          context.read<CricketProvider>().startRematch(game, players),
      destination: (_) => const CricketScreen(),
    );

    final list = ListView(
      // Fixed rather than measured: on a tablet this screen is rendered inside
      // a pane, and contentPadding measures the window, so it would put the
      // margin of a whole screen on either side of half of one.
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        // Winner banner
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
                  l.cricketWinner(winnerSlot.label(l)),
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
            (l.gameLabel, l.modeCricketName),
            (l.cricketVariant, cricketVariantLabel(l, game.variant)),
            (
              l.cricketScoringMode,
              cricketScoringModeLabel(l, game.scoringMode),
            ),
            (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
          ],
        ),

        // ── Rematch ────────────────────────────────────────────────────────

        // Per-player score cards
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
                ...sorted.map((slot) {
                  final isWinner = slot.isWonBy(winnerId);
                  final closed = cricketFields
                      .where(slot.hasClosedField)
                      .length;
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
                                slot.label(l),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: isWinner
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isWinner ? cs.primary : null,
                                ),
                              ),
                              if (slot.isTeamSlot)
                                Text(
                                  slot.players
                                      .map((p) => p.label(l))
                                      .join(' & '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              Text(
                                '$closed/7 ${l.cricketFieldsClosed}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${slot.score}',
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

        // Field marks overview
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
                Row(
                  children: [
                    const SizedBox(width: 52),
                    ...sorted.map(
                      (slot) => Expanded(
                        child: Column(
                          children: [
                            Text(
                              slot.label(l),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                            if (slot.isTeamSlot)
                              Text(
                                slot.players.map((p) => p.label(l)).join(' & '),
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
                        ...sorted.map((slot) {
                          final m = slot.marks[field] ?? 0;
                          return Expanded(
                            child: Center(child: CricketMarksWidget(marks: m)),
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
    );

    return Column(
      children: [
        Expanded(child: list),
        SummaryActionBar(actions: [rematch]),
      ],
    );
  }
}
