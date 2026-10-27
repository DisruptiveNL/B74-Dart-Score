import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/dart_throw.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../utils/game_labels.dart';
import '../utils/b74_checkout_opportunities.dart';
import '../utils/layout.dart';
import '../utils/throw_stats.dart';
import '../widgets/finish_suggestion_widget.dart';
import '../widgets/stat_row.dart';
import '../widgets/throw_row.dart';
import '../utils/player_label.dart';

/// Route that slides the live info screen in from the right on both platforms
/// and keeps the iOS edge swipe back gesture, which a plain [PageRouteBuilder]
/// does not provide. The duration is shortened from the Cupertino default so
/// the transition matches the pace of the rest of the app.
class LivePlayerStatsRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  /// Index into [GameProvider.playerStates] the screen opens on.
  final int slotIndex;

  LivePlayerStatsRoute({required this.slotIndex});

  @override
  Widget buildContent(BuildContext context) =>
      LivePlayerStatsScreen(initialSlotIndex: slotIndex);

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);
}

/// Live info for one X01 slot: the tapped player or team with its running
/// statistics, the current leg, the check-in/check-out rules that apply, and,
/// for a team, every member in upcoming throwing order. Pages horizontally
/// through the other slots in throwing order.
///
/// The screen only reads from [GameProvider]; the running game is untouched and
/// resumes as soon as the route is popped.
class LivePlayerStatsScreen extends StatefulWidget {
  /// Index into [GameProvider.playerStates] the screen opens on.
  final int initialSlotIndex;

  const LivePlayerStatsScreen({super.key, required this.initialSlotIndex});

  @override
  State<LivePlayerStatsScreen> createState() => _LivePlayerStatsScreenState();
}

class _LivePlayerStatsScreenState extends State<LivePlayerStatsScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.initialSlotIndex,
  );

  /// The page in view. A page holds one slot, or two where the screen is wide
  /// enough for both, so this is not a slot index.
  late int _page = widget.initialSlotIndex;

  /// Whether the last build put two slots on a page. A rotation changes what a
  /// page holds, and the same player has to stay in view across it.
  bool? _twoUp;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Moves the controller onto the page the slot in view now lives on, after a
  /// rotation changed how many slots a page holds.
  void _repage(bool twoUp) {
    final slot = _twoUp! ? _page * 2 : _page;
    _page = twoUp ? slot ~/ 2 : slot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) _controller.jumpToPage(_page);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        final game = provider.game;
        if (game == null || provider.gameOver) {
          return const Scaffold(body: SizedBox.shrink());
        }

        final theme = Theme.of(context);
        final l = context.l10n;
        final states = provider.playerStates;
        final nextIdx = provider.nextSlotIndex;

        final tablet = isTabletLayout(context);
        final landscape =
            MediaQuery.sizeOf(context).width >=
            MediaQuery.sizeOf(context).height;
        // On its side a tablet has room for two of these beside each other, so
        // it shows two and pages in twos rather than leaving half the screen to
        // the margin of a single column.
        final twoUp = tablet && landscape && states.length > 1;
        final pageCount = twoUp ? (states.length + 1) ~/ 2 : states.length;

        if (_twoUp != null && _twoUp != twoUp) _repage(twoUp);
        _twoUp = twoUp;

        final firstSlot = (twoUp ? _page * 2 : _page).clamp(
          0,
          states.length - 1,
        );
        final lastSlot = twoUp
            ? (firstSlot + 1).clamp(0, states.length - 1)
            : firstSlot;

        /// One slot, at the size the screen it is on reads at. A tablet gets
        /// the same panel its game screen keeps beside the input, which brings
        /// its own width and text size; a phone keeps the page it always had.
        Widget slotPage(int i) => tablet
            ? LivePlayerStatsPanel(slotIndex: i)
            : _SlotStatsPage(
                state: states[i],
                game: game,
                isActiveSlot: i == provider.currentPlayerIndex,
                isNextSlot: i != provider.currentPlayerIndex && i == nextIdx,
                currentLeg: provider.currentLeg,
                currentSet: provider.currentSet,
                liveRemaining: provider.liveDisplayRemaining,
                liveBust: provider.liveBust,
                dartsInVisit: provider.dartsInVisit,
              );

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface,
            toolbarHeight: tablet ? 56 : 44,
            centerTitle: true,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  [
                    for (var i = firstSlot; i <= lastSlot; i++)
                      states[i].label(context.l10n),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: tablet ? 19 : 15,
                  ),
                ),
                Text(
                  '${l.legLabel(provider.currentLeg)} · ${l.setLabel(provider.currentSet)}',
                  style: TextStyle(
                    fontSize: tablet ? 13 : 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pageCount,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      if (!twoUp) return slotPage(i);
                      final left = i * 2;
                      final right = left + 1;
                      // An odd player out keeps the middle of the page rather
                      // than half of it with nothing beside it.
                      if (right >= states.length) {
                        return Center(
                          child: SizedBox(
                            width: kStatsPaneMaxWidth,
                            child: slotPage(left),
                          ),
                        );
                      }
                      return SidePaneLayout(
                        side: InputSide.left,
                        primary: slotPage(left),
                        secondary: slotPage(right),
                      );
                    },
                  ),
                ),
                if (pageCount > 1)
                  _PageDots(
                    count: pageCount,
                    index: _page,
                    label: l.playerOfTotal(firstSlot + 1, states.length),
                    onTap: (i) => _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Embeddable panel ──────────────────────────────────────────────────────────

/// The live info of a single slot without the screen around it.
///
/// The tablet layout of the game screen keeps this beside the input, where a
/// phone has no room and opens [LivePlayerStatsRoute] on top of the game
/// instead. Both render the same page, so the two never drift apart.
class LivePlayerStatsPanel extends StatelessWidget {
  /// The slot to describe. The tablet layout passes the slot that is throwing,
  /// so the panel follows the turn on its own.
  final int slotIndex;

  /// Whether to keep the header card that repeats name, score and checkout.
  /// A layout that already shows the score card beside this panel turns it off.
  final bool showHeader;

  const LivePlayerStatsPanel({
    super.key,
    required this.slotIndex,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        final game = provider.game;
        if (game == null || provider.gameOver) return const SizedBox.shrink();

        final states = provider.playerStates;
        final index = slotIndex.clamp(0, states.length - 1);

        return LayoutBuilder(
          builder: (context, box) {
            // Measured against the pane, not the window: a wide pane keeps the
            // rows together in the middle instead of stretching them.
            final side = ((box.maxWidth - kStatsPaneMaxWidth) / 2).clamp(
              12.0,
              200.0,
            );

            return _SlotStatsPage(
              padding: EdgeInsets.fromLTRB(side, 8, side, 20),
              showHeader: showHeader,
              state: states[index],
              game: game,
              isActiveSlot: index == provider.currentPlayerIndex,
              isNextSlot:
                  index != provider.currentPlayerIndex &&
                  index == provider.nextSlotIndex,
              currentLeg: provider.currentLeg,
              currentSet: provider.currentSet,
              liveRemaining: provider.liveDisplayRemaining,
              liveBust: provider.liveBust,
              dartsInVisit: provider.dartsInVisit,
            );
          },
        );
      },
    );
  }
}

// ── Slot page ─────────────────────────────────────────────────────────────────

/// One page of the live info screen: everything known about a single slot.
class _SlotStatsPage extends StatelessWidget {
  final PlayerState state;
  final Game game;

  /// Whether this slot currently holds the turn.
  final bool isActiveSlot;

  /// Whether this slot throws right after the active one.
  final bool isNextSlot;
  final int currentLeg;
  final int currentSet;

  /// Remaining score including the darts of the in-progress visit; only
  /// meaningful for the active slot.
  final int liveRemaining;
  final bool liveBust;
  final int dartsInVisit;

  /// Padding around the list. The full screen centres its column with
  /// [contentPadding], which measures the whole window and would therefore
  /// overshoot inside a pane that is only a part of it.
  final EdgeInsetsGeometry? padding;

  /// Whether the header card is part of the page.
  final bool showHeader;

  const _SlotStatsPage({
    required this.state,
    required this.game,
    required this.isActiveSlot,
    required this.isNextSlot,
    required this.currentLeg,
    required this.currentSet,
    required this.liveRemaining,
    required this.liveBust,
    required this.dartsInVisit,
    this.padding,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final match = ThrowStats.fromThrows(state.throws);
    final theoretical = B74CheckoutStats.fromThrows(state.throws);
    final leg = ThrowStats.fromThrows(
      throwsInLeg(state.throws, currentLeg, currentSet),
    );

    return ListView(
      padding:
          padding ?? contentPadding(context, top: 8, bottom: 24, innerH: 12),
      children: [
        if (showHeader) ...[
          _HeaderCard(
            state: state,
            game: game,
            isActiveSlot: isActiveSlot,
            isNextSlot: isNextSlot,
            liveRemaining: liveRemaining,
            liveBust: liveBust,
            dartsInVisit: dartsInVisit,
          ),
          const SizedBox(height: 10),
        ] else ...[
          _PanelTitle(
            state: state,
            game: game,
            isActiveSlot: isActiveSlot,
            isNextSlot: isNextSlot,
          ),
          const SizedBox(height: 10),
        ],
        _RecentVisitsCard(state: state, game: game),
        const SizedBox(height: 10),
        _RulesCard(state: state, game: game),
        const SizedBox(height: 10),
        _SectionCard(
          title: l.thisLeg,
          rows: [
            (l.legAverage, leg.average.toStringAsFixed(2)),
            (l.dartsThisLeg, '${leg.totalDarts}'),
            (l.visitsThisLeg, '${leg.totalVisits}'),
            (l.bestVisitThisLeg, '${leg.highestVisit}'),
          ],
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: l.matchSoFar,
          rows: [
            (l.threeDartAvg, match.average.toStringAsFixed(2)),
            (l.first9Average, match.first9Average.toStringAsFixed(2)),
            (l.totalDarts, '${match.totalDarts}'),
            (l.visits, '${match.totalVisits}'),
            (l.highestVisit, '${match.highestVisit}'),
            (l.highestCheckout, '${match.highestCheckout}'),
            (
              l.checkoutsHit,
              '${match.checkoutSuccesses} / ${match.checkoutAttempts}',
            ),
            (l.checkoutRate, '${match.checkoutRate.toStringAsFixed(1)} %'),
            (
              'B74 theoretische finishkansen',
              '${theoretical.finishes} / ${theoretical.opportunities}',
            ),
            (
              'B74 finishpercentage (theoretisch)',
              '${theoretical.rate.toStringAsFixed(1)} %',
            ),
            (l.dartsAtFinish, '${match.checkoutDarts}'),
            (l.doubleRate, '${match.doubleRate.toStringAsFixed(1)} %'),
            (
              l.busts,
              '${match.busts} (${match.bustRate.toStringAsFixed(0)} %)',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _HighlightsRow(stats: match),
        if (state.isTeam) ...[
          const SizedBox(height: 10),
          _TeamMembersCard(
            state: state,
            game: game,
            isActiveSlot: isActiveSlot,
            isNextSlot: isNextSlot,
          ),
        ],
      ],
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

/// Name, turn status, remaining score, legs/sets and the checkout hint.
class _HeaderCard extends StatelessWidget {
  final PlayerState state;
  final Game game;
  final bool isActiveSlot;
  final bool isNextSlot;
  final int liveRemaining;
  final bool liveBust;
  final int dartsInVisit;

  const _HeaderCard({
    required this.state,
    required this.game,
    required this.isActiveSlot,
    required this.isNextSlot,
    required this.liveRemaining,
    required this.liveBust,
    required this.dartsInVisit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final showBust = isActiveSlot && liveBust;
    final remaining = isActiveSlot && !liveBust
        ? liveRemaining
        : state.remaining;
    // Placement mode keeps its own leg counter, because there every slot checks
    // out every leg.
    final legsWon = game.placementMode
        ? state.legsWon
        : legsWonFromThrows(state.throws);

    return Card(
      color: showBust ? cs.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              state.label(context.l10n),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (state.isTeam)
              Text(
                state.player.label(context.l10n),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 6),
            _StatusChip(
              state: state,
              game: game,
              isActiveSlot: isActiveSlot,
              isNextSlot: isNextSlot,
            ),
            const SizedBox(height: 6),
            Text(
              showBust ? l.bust.toUpperCase() : '$remaining',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.bold,
                height: 1,
                color: showBust ? cs.onErrorContainer : cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.setsLegsWon(state.setsWon, legsWon),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            FinishSuggestionWidget(
              remaining: showBust ? state.remaining : remaining,
              favoriteDouble: state.player.favoriteDouble,
              dartsThrown: isActiveSlot ? dartsInVisit : 0,
              checkoutMode: game.checkOutFor(state.player.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// Names the slot the panel describes, for a layout that shows the score card
/// itself elsewhere.
///
/// Everything the header card carries beyond the name is on that card already,
/// so this keeps only what the stats below it would otherwise be missing: whose
/// numbers these are, and whether they are the ones at the board.
class _PanelTitle extends StatelessWidget {
  final PlayerState state;
  final Game game;
  final bool isActiveSlot;
  final bool isNextSlot;

  const _PanelTitle({
    required this.state,
    required this.game,
    required this.isActiveSlot,
    required this.isNextSlot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.label(context.l10n),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (state.isTeam)
                  Text(
                    state.player.label(context.l10n),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusChip(
            state: state,
            game: game,
            isActiveSlot: isActiveSlot,
            isNextSlot: isNextSlot,
          ),
        ],
      ),
    );
  }
}

/// Turn status of a slot: throwing now, throwing next, or the placement it
/// already secured in this leg.
class _StatusChip extends StatelessWidget {
  final PlayerState state;
  final Game game;
  final bool isActiveSlot;
  final bool isNextSlot;

  const _StatusChip({
    required this.state,
    required this.game,
    required this.isActiveSlot,
    required this.isNextSlot,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;

    final String label;
    final Color background;
    final Color foreground;
    if (game.placementMode && state.legPlacement != null) {
      label = l.placementBadge(state.legPlacement!);
      background = cs.secondaryContainer;
      foreground = cs.onSecondaryContainer;
    } else if (isActiveSlot) {
      label = l.throwingNow;
      background = cs.primary;
      foreground = cs.onPrimary;
    } else if (isNextSlot) {
      label = l.throwsNext;
      background = cs.surfaceContainerHighest;
      foreground = cs.onSurfaceVariant;
    } else {
      return const SizedBox.shrink();
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// The check-in and check-out rules in force for this slot. Shown even without
/// handicaps, because during a live game the rule that applies right now is the
/// point, not whether it differs from the game default.
class _RulesCard extends StatelessWidget {
  final PlayerState state;
  final Game game;

  const _RulesCard({required this.state, required this.game});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    if (!state.isTeam) {
      final id = state.player.id;
      return _SectionCard(
        title: l.rulesLabel,
        rows: [
          (l.checkIn, checkInLabel(l, game.checkInFor(id))),
          (l.checkOut, checkOutLabel(l, game.checkOutFor(id))),
        ],
      );
    }

    return _SectionCard(
      title: l.rulesLabel,
      rows: [
        for (final p in state.throwingOrder)
          (
            p.label(context.l10n),
            checkInOutLabel(l, game.checkInFor(p.id), game.checkOutFor(p.id)),
          ),
      ],
    );
  }
}

/// A titled card of label/value rows.
class _SectionCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _SectionCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            for (final row in rows) StatRow(label: row.$1, value: row.$2),
          ],
        ),
      ),
    );
  }
}

/// The last three visits of the slot, newest last, so a thrower can check
/// what was just entered after it has left the board. Names the member in a
/// team slot, where the three may come from different people.
class _RecentVisitsCard extends StatelessWidget {
  final PlayerState state;
  final Game game;

  const _RecentVisitsCard({required this.state, required this.game});

  /// How many visits the card shows.
  static const _count = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;

    final ordered = List<DartThrow>.of(state.throws)
      ..sort((a, b) {
        final byTime = a.thrownAt.compareTo(b.thrownAt);
        return byTime != 0 ? byTime : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    final recent = ordered.length <= _count
        ? ordered
        : ordered.sublist(ordered.length - _count);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.lastVisits,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (recent.isEmpty)
              Text(
                l.noVisitsYet,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final t in recent)
                ThrowRow(
                  t: t,
                  playerName: state.isTeam
                      ? state.players
                            .firstWhere((p) => p.id == t.playerId)
                            .label(l)
                      : null,
                  showSet: game.sets > 1,
                ),
          ],
        ),
      ),
    );
  }
}

/// The 180 / 140+ / 100+ counters as three tiles.
class _HighlightsRow extends StatelessWidget {
  final ThrowStats stats;

  const _HighlightsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Padding(
      // Same inset a Card applies by default, so the row lines up with the
      // stat cards above and below instead of sticking out.
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _HighlightTile(label: l.count180, value: stats.count180),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _HighlightTile(
              label: l.count140plus,
              value: stats.count140plus,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _HighlightTile(
              label: l.count100plus,
              value: stats.count100plus,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single highlight tile: a big count above its label.
class _HighlightTile extends StatelessWidget {
  final String label;
  final int value;

  const _HighlightTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: value > 0 ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every member of a team slot in upcoming throwing order, each with the
/// numbers they contributed themselves.
class _TeamMembersCard extends StatelessWidget {
  final PlayerState state;
  final Game game;
  final bool isActiveSlot;
  final bool isNextSlot;

  const _TeamMembersCard({
    required this.state,
    required this.game,
    required this.isActiveSlot,
    required this.isNextSlot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final order = state.throwingOrder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.throwingOrderLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < order.length; i++)
              _MemberRow(
                player: order[i],
                throws: throwsOfPlayer(state.throws, order[i].id ?? -1),
                // Only the first member is at the oche, and only while the
                // whole slot holds the turn.
                statusLabel: i != 0
                    ? null
                    : isActiveSlot
                    ? l.throwingNow
                    : isNextSlot
                    ? l.throwsNext
                    : null,
                initiallyExpanded: i == 0 && isActiveSlot,
              ),
          ],
        ),
      ),
    );
  }
}

/// One team member: name, optional turn status and a one-line summary of their
/// own numbers, expandable to the full set.
///
/// The numbers cover the whole match, not the current leg: remaining score and
/// leg wins belong to the team, and within a leg a member rarely throws often
/// enough for a separate leg average to say much. First 9 is left out for the
/// same reason, a member never throws three visits in a row.
class _MemberRow extends StatelessWidget {
  final Player player;
  final List<DartThrow> throws;
  final String? statusLabel;

  /// Whether the details start out open, used for the member at the oche.
  final bool initiallyExpanded;

  const _MemberRow({
    required this.player,
    required this.throws,
    required this.statusLabel,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final stats = ThrowStats.fromThrows(throws);
    final hasThrown = stats.totalDarts > 0;

    final avatar = CircleAvatar(
      radius: 12,
      backgroundColor: cs.primaryContainer,
      child: Text(
        player.label(context.l10n).isNotEmpty
            ? player.label(context.l10n)[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: cs.onPrimaryContainer,
        ),
      ),
    );

    final title = Row(
      children: [
        Flexible(
          child: Text(
            player.label(context.l10n),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (statusLabel != null) ...[
          const SizedBox(width: 6),
          Text(
            statusLabel!,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
          ),
        ],
      ],
    );

    final summary = Text(
      hasThrown
          ? 'Ø ${stats.average.toStringAsFixed(1)}'
                '  ·  ${l.highAbbr} ${stats.highestVisit}'
                '  ·  ${l.dartsN(stats.totalDarts)}'
          : l.noThrowData,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    );

    // Nothing to unfold before the member has thrown.
    if (!hasThrown) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, summary],
              ),
            ),
          ],
        ),
      );
    }

    return Theme(
      // The card already groups the members; the tile's own dividers would
      // only add lines on top of that.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 32, bottom: 6),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: avatar,
        title: title,
        subtitle: summary,
        children: [
          StatRow(
            label: l.threeDartAvg,
            value: stats.average.toStringAsFixed(2),
          ),
          StatRow(label: l.totalDarts, value: '${stats.totalDarts}'),
          StatRow(label: l.visits, value: '${stats.totalVisits}'),
          StatRow(label: l.highestVisit, value: '${stats.highestVisit}'),
          StatRow(label: l.highestCheckout, value: '${stats.highestCheckout}'),
          StatRow(
            label: l.checkoutsHit,
            value: '${stats.checkoutSuccesses} / ${stats.checkoutAttempts}',
          ),
          StatRow(
            label: l.checkoutRate,
            value: '${stats.checkoutRate.toStringAsFixed(1)} %',
          ),
          StatRow(label: l.dartsAtFinish, value: '${stats.checkoutDarts}'),
          StatRow(
            label: l.doubleRate,
            value: '${stats.doubleRate.toStringAsFixed(1)} %',
          ),
          StatRow(
            label: l.busts,
            value: '${stats.busts} (${stats.bustRate.toStringAsFixed(0)} %)',
          ),
          StatRow(label: l.count180, value: '${stats.count180}'),
          StatRow(label: l.count140plus, value: '${stats.count140plus}'),
          StatRow(label: l.count100plus, value: '${stats.count100plus}'),
        ],
      ),
    );
  }
}

// ── Page indicator ────────────────────────────────────────────────────────────

/// Dots showing which slot is on screen; tapping one jumps to that slot.
class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  /// What the row of dots says out loud. Passed in because a dot stands for a
  /// page, and a page does not always hold exactly one player.
  final String label;
  final void Function(int index) onTap;

  const _PageDots({
    required this.count,
    required this.index,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final selected = i == index;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}
