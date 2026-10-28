import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/dart_throw.dart';
import '../providers/game_provider.dart';
import '../utils/game_winner.dart';
import '../utils/game_labels.dart';
import '../utils/layout.dart';
import '../utils/throw_stats.dart';
import '../widgets/final_ranking_card.dart';
import '../widgets/game_info_card.dart';
import '../utils/placement.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../widgets/summary_player_card.dart';
import '../widgets/throw_log_card.dart';
import '../utils/player_label.dart';
import 'game_screen.dart';

/// Detailed view of a finished X01 game from history: per-player stats and the
/// full throw log, loaded from the stored throws.
class HistoryGameSummaryScreen extends StatefulWidget {
  final Game game;
  final List<Player> players;

  /// Whether this sits inside a pane that brings its own title bar, as the
  /// master detail layout of the history does on a tablet. Embedded it renders
  /// its content alone, without a screen around it.
  final bool embedded;

  const HistoryGameSummaryScreen({
    super.key,
    required this.game,
    required this.players,
    this.embedded = false,
  });

  @override
  State<HistoryGameSummaryScreen> createState() =>
      _HistoryGameSummaryScreenState();
}

class _HistoryGameSummaryScreenState extends State<HistoryGameSummaryScreen> {
  /// Started once and kept, not started again on every build.
  ///
  /// A read begun inside `build` is begun again by every rebuild, and a pane
  /// whose divider is being dragged rebuilds on every frame: the view would
  /// fall back to its spinner for the length of the drag and hammer the
  /// database while it lasted.
  late Future<_GameData> _future = _load();

  @override
  void didUpdateWidget(HistoryGameSummaryScreen oldWidget) {
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
          child: FutureBuilder<_GameData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data;
              if (data == null || data.allThrows.isEmpty) {
                return Center(child: Text(context.l10n.noThrowData));
              }
              return _SummaryBody(
                game: widget.game,
                data: data,
                players: widget.players,
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

  /// Loads the widget.game's throws and groups them by player.
  ///
  /// The map is seeded from the line-up rather than built from the throws
  /// alone, so a participant who never got to throw is present with an empty
  /// list. The placement helpers read the participant count off the keys they
  /// are handed, and a missing key both drops that player from the ranking and
  /// scores everyone else against one participant too few.
  Future<_GameData> _load() async {
    final db = DbHelper.instance;
    final allThrows = await db.getThrowsForGame(widget.game.id!);
    final Map<int, List<DartThrow>> byPlayer = {
      for (final p in widget.players) p.id!: <DartThrow>[],
    };
    for (final t in allThrows) {
      byPlayer.putIfAbsent(t.playerId, () => []).add(t);
    }
    return _GameData(playerThrows: byPlayer, allThrows: allThrows);
  }
}

/// Loaded throws for a historical game: grouped by player and as a flat list.
class _GameData {
  /// Every participant of the game, including the ones who never threw.
  final Map<int, List<DartThrow>> playerThrows;
  final List<DartThrow> allThrows;
  const _GameData({required this.playerThrows, required this.allThrows});
}

/// The name the winner banner announces, given the ids [winningPlayerIds]
/// named, or null when the game has no winner.
///
/// A team game announces the team rather than whoever hit the last double, the
/// same way the post-game summary does: the shared rule hands back every member
/// of the winning side, and the side is what won.
String? _winnerName(
  AppLocalizations l,
  Game game,
  List<Player> players,
  Set<int> winnerIds,
) {
  if (winnerIds.isEmpty) return null;

  if (game.isTeamGame) {
    for (final team in game.teams!) {
      if (team.playerIds.any(winnerIds.contains)) return team.name;
    }
    return null;
  }

  for (final p in players) {
    if (winnerIds.contains(p.id)) return p.label(l);
  }
  return null;
}

/// Renders the game info, per-player stat cards, and the combined throw log.
class _SummaryBody extends StatelessWidget {
  final Game game;
  final _GameData data;
  final List<Player> players;

  const _SummaryBody({
    required this.game,
    required this.data,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Who won is the shared rule's to answer, so this screen, the ranking card
    // under it and the lifetime games won on the statistics screen cannot name
    // three different winners. It is not always the last checkout: a placement
    // game is played for points and goes to the best ranked.
    final winnerIds = winningPlayerIds(
      game,
      data.allThrows,
      participantIds: [
        for (final p in players)
          if (p.id != null) p.id!,
      ],
    );
    final String? winnerName = _winnerName(
      context.l10n,
      game,
      players,
      winnerIds,
    );

    // Team configs only store player ids, so the rematch dialog needs a name
    // lookup to list a team's members.
    final namesById = {for (final p in players) p.id: p.label(context.l10n)};

    final rematch = RematchButton(
      modeName: context.l10n.modeX01Name,
      details: [
        (
          context.l10n.matchFormat,
          game.placementMode
              ? context.l10n.placementMode
              : context.l10n.standardMode,
        ),
        (
          context.l10n.gameMode_,
          context.l10n.gameSummaryInfo(
            game.startScore,
            game.legs,
            game.sets,
            placementMode: game.placementMode,
          ),
        ),
        // With handicaps the game defaults say little, so the per-player
        // rows below carry the rules instead.
        if (!game.hasHandicaps) ...[
          (context.l10n.checkIn, checkInLabel(context.l10n, game.gameMode)),
          (
            context.l10n.checkOut,
            checkOutLabel(context.l10n, game.checkoutMode),
          ),
        ],
      ],
      slots: game.isTeamGame
          ? game.teams!
                .map(
                  (t) => RematchSlot.team(t.name, [
                    for (final id in t.playerIds)
                      if (namesById[id] != null)
                        RematchSlot.player(
                          namesById[id]!,
                          rules: handicapRulesLabel(context.l10n, game, id),
                        ),
                  ]),
                )
                .toList()
          : players
                .map(
                  (p) => RematchSlot.player(
                    p.label(context.l10n),
                    rules: handicapRulesLabel(context.l10n, game, p.id),
                  ),
                )
                .toList(),
      onRematch: () => context.read<GameProvider>().startRematch(game, players),
      destination: (_) => const GameScreen(),
    );

    final list = ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        // Winner banner
        if (winnerName != null)
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
                  context.l10n.wins(winnerName),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        // Game info
        GameInfoCard(
          dense: true,
          rows: [
            (context.l10n.gameLabel, context.l10n.modeX01Name),
            (
              context.l10n.matchFormat,
              game.placementMode
                  ? context.l10n.placementMode
                  : context.l10n.standardMode,
            ),
            (
              context.l10n.gameMode_,
              context.l10n.gameSummaryInfo(
                game.startScore,
                game.legs,
                game.sets,
                placementMode: game.placementMode,
              ),
            ),
            // A solo game has nobody to be ordered against.
            if (game.isTeamGame || players.length > 1)
              (
                context.l10n.startingOrder,
                startingOrderLabel(context.l10n, game.startingOrder),
              ),
          ],
        ),
        // Final ranking (placement mode only). Slots are keyed by team index in
        // a team game and by player id otherwise, matching how the placement
        // helpers group the throws.
        if (game.placementMode) ...[
          FinalRankingCard(
            throwsById: game.isTeamGame
                ? {
                    for (var ti = 0; ti < game.teams!.length; ti++)
                      ti:
                          (data.allThrows
                              .where(
                                (t) => game.teams![ti].playerIds.contains(
                                  t.playerId,
                                ),
                              )
                              .toList()
                            ..sort((a, b) => a.thrownAt.compareTo(b.thrownAt))),
                  }
                : {
                    for (final p in players)
                      p.id!: data.playerThrows[p.id] ?? const <DartThrow>[],
                  },
            namesById: game.isTeamGame
                ? {
                    for (var ti = 0; ti < game.teams!.length; ti++)
                      ti: game.teams![ti].name,
                  }
                : {for (final p in players) p.id!: p.label(context.l10n)},
          ),
        ],
        // Per-team or per-player stats
        if (game.isTeamGame)
          ...game.teams!.map((team) {
            final members = [
              for (final id in team.playerIds)
                (
                  namesById[id] ?? '',
                  data.playerThrows[id] ?? const <DartThrow>[],
                ),
            ];
            // The team's own throw list, back in the order the team threw them.
            final teamThrows = [for (final m in members) ...m.$2]
              ..sort((a, b) => a.thrownAt.compareTo(b.thrownAt));
            return SummaryPlayerCard(
              name: team.name,
              throws: teamThrows,
              legsWon: legsWonFromThrows(teamThrows),
              members: members,
            );
          })
        else
          ...players.map((p) {
            final throws = data.playerThrows[p.id] ?? const <DartThrow>[];
            // In placement mode every slot checks out every leg, so legs won
            // must come from placementRanking() rather than counting checkout
            // throws.
            final legsWonOverride = game.placementMode
                ? (placementRanking(
                    data.playerThrows,
                    data.allThrows.isEmpty
                        ? 0
                        : data.allThrows
                              .map((t) => t.leg)
                              .reduce((a, b) => a > b ? a : b),
                    1,
                  ).legsWon[p.id!])
                : null;
            return SummaryPlayerCard(
              name: p.label(context.l10n),
              throws: throws,
              legsWon: legsWonOverride ?? legsWonFromThrows(throws),
            );
          }),
        ThrowLogCard(
          throws: data.allThrows,
          playerName: (id) => namesById[id] ?? '',
          showSet: game.sets > 1,
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
