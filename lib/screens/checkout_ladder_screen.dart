import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/checkout_ladder_game.dart';
import '../providers/checkout_ladder_provider.dart';
import '../providers/tablet_layout_provider.dart';
import '../utils/layout.dart';
import '../utils/player_label.dart';
import '../utils/visit_darts.dart';
import '../widgets/dartboard_input.dart';
import '../widgets/finish_suggestion_widget.dart';
import 'checkout_ladder_summary_screen.dart';
import 'mode_live_info_screen.dart';

/// Live Checkout Ladder screen. Watches the provider and routes to the summary
/// when the game ends, otherwise shows the play view.
class CheckoutLadderScreen extends StatelessWidget {
  const CheckoutLadderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CheckoutLadderProvider>(
      builder: (context, provider, _) {
        if (provider.game == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (provider.gameOver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutLadderSummaryScreen()),
            );
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return _GameView(provider: provider);
      },
    );
  }
}

// ── Main game view ────────────────────────────────────────────────────────────

/// The in-play layout: the ladders of every slot, the rest of the attempt on
/// turn with its checkout route, and the X01 input.
///
/// A phone stacks the three. A tablet puts the input with the rest above it
/// beside the ladders, on the side the player picked for the input.
class _GameView extends StatelessWidget {
  final CheckoutLadderProvider provider;
  const _GameView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l      = context.l10n;
    final game   = provider.game!;
    final tablet = isTabletLayout(context);
    final layout = tablet ? context.watch<TabletLayoutProvider>() : null;

    final scoreboard = _Scoreboard(provider: provider);
    final restBlock  = _RestBlock(provider: provider);

    final sd    = provider.suddenDeathNumber;
    final title = !game.isRace
        ? l.ladderTrainingFrom(game.startNumber)
        : sd != null
            ? l.ladderSuddenDeath(sd)
            : l.ladderRaceTo(game.targetNumber!);

    return PopScope(
      // A running game must not be lost to a stray back gesture; the system
      // back asks the same question the close button in the app bar asks.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit(context);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: tablet ? 56 : 44,
          centerTitle: true,
          title: Text(
            title,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: tablet ? 19 : 15),
          ),
          actions: [
            if (layout != null)
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, size: 26),
                tooltip: l.swapInputSide,
                onPressed: () => layout.setSide(
                  layout.side == InputSide.left
                      ? InputSide.right
                      : InputSide.left,
                ),
              ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: tablet ? 26 : 22),
              tooltip: l.quitGame,
              onPressed: () => _confirmQuit(context),
            ),
          ],
        ),
        // The bottom inset is consumed here, at the bottom of the screen, for
        // the reason the X01 screen gives: left to the input's grid it opens a
        // gap above the action row instead of below it.
        body: SafeArea(
          top: false,
          child: layout != null
              ? SidePaneLayout(
                  side: layout.side,
                  primary: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      restBlock,
                      const Expanded(
                        child: DartboardInput<CheckoutLadderProvider>(
                            fillHeight: true),
                      ),
                    ],
                  ),
                  secondary: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: scoreboard,
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: contentMaxWidth(context,
                          fraction: kGameWidthFraction,
                          maxWidth: kMaxGameWidth),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The ladders scroll inside a share of the screen,
                          // so a game of five never pushes the input off it.
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxHeight: box.maxHeight * 0.36),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                              child: scoreboard,
                            ),
                          ),
                          restBlock,
                          const Expanded(
                              child: DartboardInput<CheckoutLadderProvider>()),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Asks the user how to leave. A race can only be left, to be resumed from
  /// the history. A training can be left the same way or ended, which stores
  /// it as finished and shows the summary.
  void _confirmQuit(BuildContext context) {
    final l        = context.l10n;
    final provider = context.read<CheckoutLadderProvider>();
    final training = !provider.game!.isRace;

    showDialog(
      context: context,
      builder: (dialogContext) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: AlertDialog(
            title: Text(training ? l.ladderLeaveTitle : l.quitTitle),
            content: Text(training ? l.ladderLeaveBody : l.quitBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l.cancel),
              ),
              if (training) ...[
                TextButton(
                  onPressed: () {
                    provider.leaveGame();
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                  child: Text(l.ladderContinueLater),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    provider.endTraining();
                  },
                  child: Text(l.ladderEndTraining),
                ),
              ] else
                FilledButton(
                  onPressed: () {
                    provider.leaveGame();
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                  child: Text(l.leave),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rest of the attempt ───────────────────────────────────────────────────────

/// The rest the slot on turn still has to check in this attempt, with the
/// route [FinishSuggestionWidget] suggests for the darts its visit has left.
class _RestBlock extends StatelessWidget {
  final CheckoutLadderProvider provider;
  const _RestBlock({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l        = context.l10n;
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final slot     = provider.currentSlot;
    final position = slot.position;
    final darts    = position.dartsInVisit;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  slot.isTeamSlot
                      ? '${slot.label(l)} · ${slot.player.label(l)}'
                      : slot.label(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              Text(
                l.ladderRest,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Text(
                '${position.rest}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // Fixed height, so the input under it never shifts with the route.
          SizedBox(
            height: 62,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: FinishSuggestionWidget(
                key: ValueKey('${position.rest}_$darts'),
                remaining: position.rest,
                favoriteDouble: slot.player.favoriteDouble,
                dartsThrown: darts,
                checkoutMode: provider.game!.checkOut,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scoreboard ────────────────────────────────────────────────────────────────

/// One card per slot: the number its attempt is on, where it is heading,
/// its floor, and the darts of the attempt it has used.
class _Scoreboard extends StatelessWidget {
  final CheckoutLadderProvider provider;
  const _Scoreboard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final slots = provider.slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _SlotCard(
              slot:   slots[i],
              game:   provider.game!,
              active: i == provider.currentSlotIndex,
              suddenDeath: provider.suddenDeathNumber != null,
              onTap: () => openCheckoutLadderSlotInfo(context, i),
            ),
          ),
      ],
    );
  }
}

/// The card of one slot on the scoreboard.
class _SlotCard extends StatelessWidget {
  final CheckoutLadderSlotState slot;
  final CheckoutLadderGame game;
  final bool active;
  /// Whether the race is in sudden death, where only the level slots play.
  final bool suddenDeath;
  /// Opens the live info of this slot.
  final VoidCallback onTap;

  const _SlotCard({
    required this.slot,
    required this.game,
    required this.active,
    required this.suddenDeath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l        = context.l10n;
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final ladder   = slot.ladder;
    final position = slot.position;

    // A slot that has nothing left to throw says why, instead of a direction
    // and an attempt that no longer mean anything.
    final String? done = position.completed
        ? l.ladderCompleted
        : suddenDeath && !ladder.inSuddenDeath
            ? l.ladderOut
            : !suddenDeath && ladder.reachedTargetAt != null
                ? l.ladderTargetChecked
                : null;

    final tags = <Widget>[
      if (done != null)
        _Tag(label: done, color: cs.primary)
      else ...[
        if (!position.onFloor)
          _Tag(
            label: position.climbing ? l.ladderClimbing : l.ladderFalling,
            color: position.climbing ? cs.primary : cs.error,
            icon: position.climbing
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
          ),
        if (!position.onFloor)
          _Tag(
            label: position.climbing && position.attempt == 1
                ? l.ladderAttemptOf(1, 2)
                : l.ladderLastAttempt,
            color: cs.onSurfaceVariant,
          ),
      ],
      _Tag(
        label: l.ladderFloor(position.floor),
        // A floor above the start number was built by a safehouse.
        color: position.floor > game.startNumber ? cs.tertiary : cs.onSurfaceVariant,
        icon: position.floor > game.startNumber ? Icons.home_rounded : null,
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? cs.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.label(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: active ? cs.primary : cs.onSurface,
                      ),
                    ),
                    if (slot.isTeamSlot)
                      Text(
                        slot.player.label(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: tags),
                    if (done == null) ...[
                      const SizedBox(height: 8),
                      _AttemptPips(
                        used:  position.dartsInAttempt,
                        total: game.dartsFor(position.number),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${position.number}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: done != null ? cs.onSurfaceVariant : cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small outlined label on a slot card, with an optional leading icon.
class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Tag({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}

/// The darts of an attempt as short bars, grouped by visit: filled for the
/// darts used up, empty for the ones left. A bust uses up its whole visit.
class _AttemptPips extends StatelessWidget {
  final int used;
  final int total;
  const _AttemptPips({required this.used, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            // A wider gap between visits than between the darts of one.
            padding: EdgeInsets.only(left: i > 0 && i % 3 == 0 ? 6 : 0),
            child: Container(
              width: 14,
              height: 6,
              decoration: BoxDecoration(
                color: i < used ? cs.onSurface : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Live info ─────────────────────────────────────────────────────────────────

/// Opens the live info of the Checkout Ladder slot at [slotIndex]: its last
/// three visits with how each ended, and the numbers its ladder stands on.
///
/// The visits come from the engine, which closes a visit on a check or a bust
/// as well as after three darts, so nothing here counts darts in threes. The
/// visit still being thrown is listed first while it is open.
void openCheckoutLadderSlotInfo(BuildContext context, int slotIndex) {
  final provider = context.read<CheckoutLadderProvider>();
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ModeLiveInfoScreen(
      listenable: provider,
      data: (context) {
        final l      = context.l10n;
        final s      = provider.slots[slotIndex];
        final ladder = s.ladder;
        final rate   = ladder.checkRate;
        final perCheck = ladder.dartsPerCheck;

        final open = slotIndex == provider.currentSlotIndex &&
                s.position.dartsInVisit > 0
            ? provider.currentVisitDarts
            : const <DartEntry>[];
        final done = ladder.visits;
        final from = done.length <= 3 ? 0 : done.length - 3;
        final recent = <VisitSummary>[
          if (open.isNotEmpty)
            (
              darts: [for (final d in open) visitDartFrom(d.field, d.field == 0 ? 0 : d.modifier, l)],
              yield: l.ladderVisitRest(s.position.rest),
            ),
          for (var i = done.length - 1; i >= from; i--)
            (
              darts: [
                for (final d in done[i].darts)
                  visitDartFrom(d.field, d.multiplier, l),
              ],
              yield: done[i].checked
                  ? l.ladderVisitChecked(done[i].number)
                  : done[i].bust
                      ? l.ladderVisitBust
                      : l.ladderVisitRest(done[i].restAfter),
            ),
        ];

        return (
          title:    s.label(l),
          subtitle: s.isTeamSlot ? s.player.label(l) : null,
          visitSlots: 3,
          recentVisits: recent.take(3).toList(),
          stats: [
            (l.ladderNumber, s.position.completed
                ? l.ladderCompleted
                : '${s.position.number}'),
            (l.ladderFloorLabel, '${s.position.floor}'),
            (l.ladderHighestChecked, ladder.highestChecked?.toString() ?? '—'),
            (l.ladderChecksAttempts,
                '${ladder.checks} / ${ladder.attemptsCompleted}'),
            (l.ladderCheckRate,
                rate == null ? '—' : '${(rate * 100).round()} %'),
            (l.ladderDartsPerCheck,
                perCheck == null ? '—' : perCheck.toStringAsFixed(1)),
            (l.ladderSafehouses, '${ladder.safehouses}'),
            (l.ladderDrops, '${ladder.drops}'),
            (l.ladderBusts, '${ladder.busts}'),
            (l.dartsThrown, '${ladder.darts}'),
          ],
        );
      },
    ),
  ));
}
