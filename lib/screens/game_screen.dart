import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../providers/tablet_layout_provider.dart';
import '../widgets/dartboard_input.dart';
import '../widgets/b74_numeric_input.dart';
import '../widgets/finish_suggestion_widget.dart';
import '../models/game.dart';
import 'game_summary_screen.dart';
import 'live_player_stats_screen.dart';
import '../utils/layout.dart';
import '../utils/match_format.dart';
import '../utils/player_label.dart';

/// Live X01 game screen: scoreboard with live running score, dartboard/numpad
/// input, finish suggestions, and undo. Routes to the summary when the game ends.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        if (provider.game == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (provider.gameOver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const GameSummaryScreen()),
            );
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final game       = provider.game!;
        final states     = provider.playerStates;
        final currentIdx = provider.currentPlayerIndex;
        final current    = provider.currentPlayerState;
        final isSolo     = states.length == 1;
        final displayRemaining = provider.liveDisplayRemaining;
        final liveBust   = provider.liveBust;
        final liveDartsInVisit = provider.dartsInVisit;
        final handicaps  = provider.handicaps;

        // Check-In only applies in the very first leg of the game (leg 1, set 1).
        final checkInActive = provider.currentLeg == 1 && provider.currentSet == 1;

        // Per-player resolved modes (handicap overrides game defaults)
        List<GameMode> playerCheckIns = states
            .map((s) => checkInActive
                ? (handicaps[s.player.id]?.checkIn ?? game.gameMode)
                : GameMode.straightIn)
            .toList();
        List<CheckoutMode> playerCheckOuts = states
            .map((s) => handicaps[s.player.id]?.checkOut ?? game.checkoutMode)
            .toList();
        // hasCheckedIn: straight-in is always checked in; double-in/master-in require remaining < startScore
        List<bool> playerCheckedIn = states.asMap().entries.map((e) {
          final alreadyIn = playerCheckIns[e.key] == GameMode.straightIn ||
              e.value.remaining < game.startScore;
          // Live override: if the qualifying dart was thrown this visit, show as checked in immediately
          if (e.key == currentIdx) return alreadyIn || provider.checkedInThisVisit;
          return alreadyIn;
        }).toList();

        final currentCheckOut = playerCheckOuts[currentIdx];
        final currentHasCheckedIn = playerCheckedIn[currentIdx];

        final tablet    = isTabletLayout(context);
        final layout    = tablet ? context.watch<TabletLayoutProvider>() : null;
        final mq        = MediaQuery.of(context);
        final landscape = mq.size.width >= mq.size.height;

        // How much bigger than a phone the score card may be. The card shares
        // its column with the input, so what it may spend follows from the
        // height both have: a large tablet reads from across the room, a small
        // one in landscape has barely more room than a phone.
        final bodyHeight = mq.size.height -
            mq.padding.top -
            mq.padding.bottom -
            (tablet ? 56 : 44);
        final scale = tablet ? (bodyHeight / 560).clamp(1.0, 1.9) : 1.0;
        // The checkout hint grows with the card but more slowly: it is a line
        // of text, not a number read from the other side of the room.
        final hintScale = scale.clamp(1.0, 1.5).toDouble();

        final scoreboard = _Scoreboard(
              states: states,
              currentIdx: currentIdx,
              game: game,
              isSolo: isSolo,
              liveRemaining: displayRemaining,
              liveBust: liveBust,
              currentLeg: provider.currentLeg,
              currentSet: provider.currentSet,
              liveDartsInVisit: liveDartsInVisit,
              playerCheckIns: playerCheckIns,
              playerCheckOuts: playerCheckOuts,
              playerCheckedIn: playerCheckedIn,
          scale: scale,
          onSlotTap: (i) => Navigator.of(context)
              .push(LivePlayerStatsRoute<void>(slotIndex: i)),
        );

        // Fixed-height area for the checkout hint so buttons never shift
        final checkoutHint = SizedBox(
          height: 62 * hintScale,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: FinishSuggestionWidget(
              key: ValueKey(
                '${liveBust ? current.remaining : displayRemaining}_$liveDartsInVisit',
              ),
              remaining: liveBust ? current.remaining : displayRemaining,
              favoriteDouble: current.player.favoriteDouble,
              dartsThrown: liveDartsInVisit,
              checkoutMode: currentHasCheckedIn ? currentCheckOut : CheckoutMode.doubleOut,
              scale: hintScale,
            ),
          ),
        );

        // The hint belongs to the score, and travels with it unless a layout
        // finds it a better place.
        final scoreboardBlock = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            scoreboard,
            SizedBox(height: 6 * scale),
            checkoutHint,
          ],
        );

        return PopScope(
          // A running game must not be lost to a stray back gesture; the system
          // back asks the same question the close button in the app bar asks.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmQuit(context);
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              toolbarHeight: tablet ? 56 : 44,
              centerTitle: true,
              title: isSolo
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          game.legs > 1
                              ? '${context.l10n.openPlay} · ${game.startScore} · ${context.l10n.legLabel(provider.currentLeg)}'
                              : '${context.l10n.openPlay} · ${game.startScore}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: tablet ? 19 : 15),
                        ),
                        if (game.legs > 1)
                          Text(
                            context.l10n.legsSetsShort(game.legs, game.sets),
                            style: TextStyle(
                              fontSize: tablet ? 13 : 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${game.startScore} · ${context.l10n.legLabel(provider.currentLeg)} · ${context.l10n.setLabel(provider.currentSet)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: tablet ? 19 : 15),
                        ),
                        Text(
                          game.placementMode
                              ? context.l10n.placementFormatLabel(game.legs)
                              : '${context.l10n.matchFormatLabel(MatchFormatLookup.fromValues(game.legs, game.sets))}'
                                ' (${context.l10n.legsSetsShort(game.legs, game.sets)})',
                          style: TextStyle(
                            fontSize: tablet ? 13 : 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
              actions: [
                // Which hand holds the tablet changes between games and even
                // between players, so the swap belongs here rather than three
                // screens away in the settings.
                if (layout != null)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 26),
                    tooltip: context.l10n.swapInputSide,
                    onPressed: () => layout.setSide(
                      layout.side == InputSide.left
                          ? InputSide.right
                          : InputSide.left,
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: tablet ? 26 : 22),
                  tooltip: context.l10n.quitGame,
                  onPressed: () => _confirmQuit(context),
                ),
              ],
            ),
            // The bottom inset has to be consumed here, at the bottom of the
            // screen. Left to the scroll views further down, a GridView takes
            // it for its own padding, which on a phone with a home indicator
            // opens a gap above the action row instead of below it.
            body: SafeArea(
              top: false,
              child: tablet
                  ? _TabletBody(
                      scoreboardBlock: scoreboardBlock,
                      scoreboard: scoreboard,
                      checkoutHint: checkoutHint,
                      scoreboardGap: 6 * scale,
                      currentIdx: currentIdx,
                      landscape: landscape,
                    )
                  : _PhoneBody(scoreboardBlock: scoreboardBlock),
            ),
          ),
        );
      },
    );
  }

  /// Asks the user to confirm leaving the game, returning to the screen they
  /// came from if they accept.
  void _confirmQuit(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        final l = context.l10n;
        return Center(
          child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: AlertDialog(
            title: Text(l.quitTitle),
            content: Text(l.quitBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () {
                  context.read<GameProvider>().leaveGame();
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: Text(l.leave),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

// ── Bodies ────────────────────────────────────────────────────────────────────

/// The phone layout: scoreboard on top, input filling what is left below it.
class _PhoneBody extends StatelessWidget {
  final Widget scoreboardBlock;

  const _PhoneBody({required this.scoreboardBlock});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: contentMaxWidth(context,
              fraction: kGameWidthFraction, maxWidth: kMaxGameWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: scoreboardBlock,
              ),
            ),
            const Expanded(child: B74NumericInput()),
          ],
        ),
      ),
    );
  }
}

/// The tablet layout: score and input stay together in one column, the way a
/// player already knows them, and the width that is won goes to the live stats
/// of whoever is throwing.
///
/// Landscape stands that column beside the stats. Portrait keeps the scoreboard
/// across the full width, where it reads from across the room, and splits only
/// the space below it, because half of a portrait tablet is too narrow for a
/// score card that size.
class _TabletBody extends StatelessWidget {
  final Widget scoreboardBlock;
  /// The two halves of that block, for the portrait layout that separates them.
  final Widget scoreboard;
  final Widget checkoutHint;
  final double scoreboardGap;
  final int currentIdx;
  final bool landscape;

  const _TabletBody({
    required this.scoreboardBlock,
    required this.scoreboard,
    required this.checkoutHint,
    required this.scoreboardGap,
    required this.currentIdx,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TabletLayoutProvider>();
    final side   = layout.side;
    // No header: the score card right above it already says who is throwing,
    // what they need and what they average, and a second copy of that in the
    // pane next to it is noise rather than information.
    final stats = LivePlayerStatsPanel(slotIndex: currentIdx, showHeader: false);

    if (landscape) {
      return SidePaneLayout(
        side: side,
        fraction: layout.splitFraction(SplitPane.game, landscape: true),
        // This pane carries the scoreboard as well, so it needs more width
        // before it stops being worth looking at.
        minPaneWidth: kMinGamePaneWidth,
        onFractionChanged: (f) =>
            layout.setSplitFraction(SplitPane.game, f, landscape: true),
        onFractionSettled: () {
          layout.persistSplitFraction(SplitPane.game, landscape: true);
        },
        primary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            scoreboardBlock,
            const Expanded(child: B74NumericInput()),
          ],
        ),
        secondary: stats,
      );
    }

    final fraction = layout.splitFraction(SplitPane.game, landscape: false);

    return LayoutBuilder(
      builder: (context, box) {
        // Dragged wide enough, the input puts its actions beside the grid and
        // the column above them is short enough to carry the checkout hint. It
        // reads better there, right over the field the player is aiming at,
        // than across the top of the screen.
        final paneWidth = paneWidthFor(
          total: box.maxWidth,
          fraction: fraction,
          minPaneWidth: kMinPaneWidth,
        );
        final hintOverInput = DartboardInput.usesSideActions(paneWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hintOverInput) scoreboard else scoreboardBlock,
            // Everything below the scoreboard hangs off it at the same
            // distance: the input, the stats and the divider between them.
            SizedBox(height: scoreboardGap),
            Expanded(
              child: SidePaneLayout(
                side: side,
                fraction: fraction,
                onFractionChanged: (f) => layout
                    .setSplitFraction(SplitPane.game, f, landscape: false),
                onFractionSettled: () {
                  layout.persistSplitFraction(SplitPane.game,
                      landscape: false);
                },
                primary: hintOverInput
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          checkoutHint,
                          const Expanded(
                              child: B74NumericInput()),
                        ],
                      )
                    : const B74NumericInput(),
                secondary: stats,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Scoreboard ────────────────────────────────────────────────────────────────

/// The X01 scoreboard: one card per player/team showing remaining score (live
/// for the active player), legs/sets, average, and check-in/out badges.
class _Scoreboard extends StatelessWidget {
  final List<PlayerState> states;
  final int currentIdx;
  final Game game;
  final bool isSolo;
  final int liveRemaining;
  final bool liveBust;
  final int currentLeg;
  final int currentSet;
  final int liveDartsInVisit;
  final List<GameMode> playerCheckIns;
  final List<CheckoutMode> playerCheckOuts;
  final List<bool> playerCheckedIn;
  /// How much larger than on a phone the card renders. A tablet is read from
  /// across the room rather than at arm's length, and how much room the card
  /// may spend on that depends on the height it shares with the input.
  final double scale;
  /// Opens the live info view for the slot at the given index.
  final void Function(int slotIndex) onSlotTap;

  const _Scoreboard({
    required this.states,
    required this.currentIdx,
    required this.game,
    required this.isSolo,
    required this.liveRemaining,
    required this.liveBust,
    required this.currentLeg,
    required this.currentSet,
    required this.liveDartsInVisit,
    required this.playerCheckIns,
    required this.playerCheckOuts,
    required this.playerCheckedIn,
    required this.scale,
    required this.onSlotTap,
  });

  /// Builds one player score card.
  Widget _buildCard({
    required BuildContext context,
    required int i,
    required bool isCurrent,
  }) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final s     = states[i];

    final displayValue = isCurrent
        ? (liveBust ? s.remaining : liveRemaining)
        : s.remaining;
    final showBust = isCurrent && liveBust;

    // Perfect-game live badge
    final minDarts      = minimumDartsForScore[game.startScore];
    final committedDarts = s.throws
        .where((t) => t.leg == currentLeg && t.set == currentSet)
        .fold(0, (sum, t) => sum + t.dartsUsed);
    final totalDarts    = committedDarts + (isCurrent ? liveDartsInVisit : 0);
    final checkRemaining = isCurrent ? liveRemaining : s.remaining;
    final remainingDarts = minDarts != null ? minDarts - totalDarts : 0;
    final maxAchievable  = remainingDarts > 0 ? (remainingDarts - 1) * 60 + 50 : 0;
    final perfectStillPossible = minDarts != null &&
        totalDarts < minDarts &&
        checkRemaining > 0 &&
        checkRemaining <= maxAchievable;

    final cardColor = showBust
        ? cs.errorContainer
        : isCurrent
            ? cs.primary
            : cs.surfaceContainerHigh;
    final onCard     = showBust
        ? cs.onErrorContainer
        : isCurrent
            ? cs.onPrimary
            : cs.onSurface;
    final onCardMuted = onCard.withValues(alpha: 0.65);

    final radius = 16.0 * scale;
    /// The phone size of [style], grown by [scale].
    TextStyle? sized(TextStyle? style) =>
        style?.copyWith(fontSize: (style.fontSize ?? 14) * scale);

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: 4 * scale),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        // The ink has to sit inside the opaque container, otherwise the splash
        // is painted underneath the card colour and stays invisible.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () => onSlotTap(i),
            child: Padding(
          padding: EdgeInsets.fromLTRB(
              12 * scale, 14 * scale, 12 * scale, 12 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name: team name (big) + current player (small) for teams
              Text(
                s.label(context.l10n),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: sized(theme.textTheme.titleSmall)?.copyWith(
                  color: onCard,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (s.isTeamSlot)
                Text(
                  s.player.label(context.l10n),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: sized(theme.textTheme.labelSmall)?.copyWith(
                    color: onCard.withValues(alpha: 0.75),
                  ),
                ),
              // Mode badge (check-in required OR in checkout range)
              Center(
                child: _ModeBadge(
                  remaining: displayValue,
                  checkIn: playerCheckIns[i],
                  checkOut: playerCheckOuts[i],
                  checkedIn: playerCheckedIn[i],
                  onCard: onCard,
                  scale: scale,
                ),
              ),
              const SizedBox(height: 2),
              // Big score
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 110),
                child: Text(
                  showBust ? 'BUST' : '$displayValue',
                  key: ValueKey('$i-$displayValue-$showBust'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 52 * scale,
                    fontWeight: FontWeight.bold,
                    color: onCard,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Stats + perfect-game badge
              Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.bar_chart_rounded,
                      size: 14 * scale,
                      color: onCardMuted,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!isSolo || game.legs > 1)
                        Text(
                          game.sets > 1
                              ? '${context.l10n.setsAbbr} ${s.setsWon}  ${context.l10n.legsAbbr} ${s.legsWon}'
                              : '${context.l10n.legs}: ${s.legsWon}',
                          style: sized(theme.textTheme.bodySmall)
                              ?.copyWith(color: onCardMuted),
                        ),
                      Text(
                        'Ø ${s.average.toStringAsFixed(1)}',
                        style: sized(theme.textTheme.bodySmall)
                            ?.copyWith(color: onCardMuted),
                      ),
                    ],
                  ),
                  if (perfectStillPossible)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 7 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300),
                          borderRadius: BorderRadius.circular(6 * scale),
                        ),
                        child: Text(
                          '$minDarts',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    // Placement mode: slots that already checked out this leg are shown only
    // as a small chip (with their finishing place) and never as a big card.
    final allIndices = List.generate(states.length, (i) => i);
    final finishedIndices = game.placementMode
        ? allIndices.where((i) => states[i].legPlacement != null).toList()
        : <int>[];
    final activeIndices =
        allIndices.where((i) => !finishedIndices.contains(i)).toList();

    // With 3+ active players: show only current + next.  ≤2: show all.
    final showAll = activeIndices.length <= 2;
    int nextIdx = currentIdx;
    if (activeIndices.length > 1) {
      final pos = activeIndices.indexOf(currentIdx);
      nextIdx = activeIndices[(pos + 1) % activeIndices.length];
    }
    final mainIndices = showAll ? activeIndices : [currentIdx, nextIdx];
    final otherIndices = [
      if (!showAll)
        ...activeIndices.where((i) => i != currentIdx && i != nextIdx),
      ...finishedIndices,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Main cards (current + next) ────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: mainIndices.map((i) => _buildCard(
                context: context,
                i: i,
                isCurrent: i == currentIdx,
              )).toList(),
            ),
          ),

          // ── Other players: compact score strip ────────────────────
          if (otherIndices.isNotEmpty) ...[
            SizedBox(height: 6 * scale),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: otherIndices.map((i) {
                  final s = states[i];
                  final finished =
                      game.placementMode && s.legPlacement != null;
                  final chipBg =
                      finished ? cs.secondaryContainer : cs.surfaceContainerHigh;
                  final chipFg =
                      finished ? cs.onSecondaryContainer : cs.onSurface;
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 4 * scale),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => onSlotTap(i),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10 * scale, vertical: 4 * scale),
                          child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 9 * scale,
                          backgroundColor: cs.outline.withValues(alpha: 0.3),
                          child: Text(
                            s.player.label(context.l10n).isNotEmpty
                                ? s.player.label(context.l10n)[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 9 * scale,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        SizedBox(width: 5 * scale),
                        Text(
                          // A person's first name; a bot's whole label, or
                          // the number that tells two of a tier apart is lost.
                          !s.isTeamSlot && s.player.isBot
                              ? s.label(context.l10n)
                              : s.label(context.l10n).split(' ').first,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(
                            fontSize:
                                (theme.textTheme.labelSmall?.fontSize ?? 11) * scale,
                            color: finished
                                ? chipFg.withValues(alpha: 0.85)
                                : cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(width: 6 * scale),
                        Text(
                          finished
                              ? context.l10n.placementBadge(s.legPlacement!)
                              : '${s.remaining}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(
                            fontSize:
                                (theme.textTheme.labelMedium?.fontSize ?? 12) * scale,
                            fontWeight: FontWeight.bold,
                            color: chipFg,
                          ),
                        ),
                      ],
                    ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Mode badge ────────────────────────────────────────────────────────────────
// Shown below the player name in the scoreboard card.
// • "DOUBLE IN" (amber): when double-in is required and player hasn't checked in
// • "D-Out / M-Out / S-Out" (subtle): when in checkout range (remaining ≤ 170)
// • Nothing: normal scoring range, already checked in, no special action needed

/// Small status badge under a player's name showing a required check-in or the
/// active checkout rule, or nothing during normal scoring.
class _ModeBadge extends StatelessWidget {
  final int remaining;
  final GameMode checkIn;
  final CheckoutMode checkOut;
  final bool checkedIn;
  final Color onCard;
  /// How much larger than on a phone the badge renders, matching its card.
  final double scale;

  const _ModeBadge({
    required this.remaining,
    required this.checkIn,
    required this.checkOut,
    required this.checkedIn,
    required this.onCard,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    // Priority 1: Double-In / Master-In not yet done
    if ((checkIn == GameMode.doubleIn || checkIn == GameMode.masterIn) && !checkedIn) {
      final label = checkIn == GameMode.masterIn ? 'MASTER IN' : 'DOUBLE IN';
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 8 * scale, vertical: 2 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB300).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }

    // Priority 2: In checkout range, show checkout mode
    if (remaining <= 170 && remaining > 1) {
      final label = switch (checkOut) {
        CheckoutMode.doubleOut  => 'D-Out',
        CheckoutMode.masterOut  => 'M-Out',
        CheckoutMode.straightOut => 'S-Out',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          '→ $label',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10 * scale,
            fontWeight: FontWeight.w600,
            color: onCard.withValues(alpha: 0.7),
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
