import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/around_the_clock_game.dart';
import '../providers/around_the_clock_provider.dart';
import '../utils/layout.dart';
import '../utils/segment_color.dart';
import '../widgets/dartboard_target_painter.dart';
import '../utils/around_the_clock_rules.dart';
import '../utils/player_label.dart';
import '../utils/visit_darts.dart';
import '../widgets/visit_darts_row.dart';
import '../widgets/visit_pause.dart';
import 'mode_live_info_screen.dart';
import 'around_the_clock_summary_screen.dart';

/// Live Around the Clock game screen. Watches the provider and routes to the
/// summary when the game ends, otherwise shows the play view.
class AroundTheClockScreen extends StatelessWidget {
  const AroundTheClockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AroundTheClockProvider>(
      builder: (context, provider, _) {
        if (provider.game == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (provider.gameOver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AroundTheClockSummaryScreen(),
              ),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _AroundTheClockGameView(provider: provider);
      },
    );
  }
}

// ── Main game view ────────────────────────────────────────────────────────────

/// The in-play layout: target dartboard, scrollable scoreboard, and input area.
class _AroundTheClockGameView extends StatelessWidget {
  final AroundTheClockProvider provider;
  const _AroundTheClockGameView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final states = provider.playerStates;
    final current = provider.currentPlayerState;

    final tablet = isTabletLayout(context);
    final landscape =
        MediaQuery.sizeOf(context).width >= MediaQuery.sizeOf(context).height;

    final scoreboard = _AroundTheClockBoard(
      provider: provider,
      states: states,
      currentIdx: provider.currentPlayerIndex,
      throwCount: provider.dartsInVisit,
    );

    /// The player list on a tablet: standing in the middle of its box while it
    /// is short and scrolled once it is not.
    Widget listPane(EdgeInsets padding) => Center(
      child: SingleChildScrollView(padding: padding, child: scoreboard),
    );

    return PopScope(
      // A running game must not be lost to a stray back gesture; the system
      // back asks the same question the close button in the app bar asks.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Around the Clock'),
          actions: [
            if (provider.canUndo)
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                tooltip: l.undo,
                onPressed: () => provider.undoLastDart(),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l.aroundClockQuit,
              onPressed: () => _confirmQuit(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Target dartboard and player list ──────────────────────────────
            if (tablet && landscape)
              // Two columns: the board is worth the height of the screen, and
              // the list beside it no longer waits under a board that took it.
              Expanded(
                child: SidePaneLayout(
                  side: InputSide.left,
                  primary: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Center(child: _TargetDartboard(provider: provider)),
                  ),
                  secondary: listPane(const EdgeInsets.fromLTRB(8, 8, 12, 8)),
                ),
              )
            else ...[
              Padding(
                padding: tablet
                    ? const EdgeInsets.fromLTRB(12, 8, 12, 0)
                    : contentPadding(
                        context,
                        fraction: kGameWidthFraction,
                        maxWidth: kMaxGameWidth,
                        top: 8,
                        innerH: 12,
                      ),
                child: Column(
                  children: [
                    SizedBox(
                      // Upright a tablet gives the board half the height it has
                      // rather than the width a phone reads it at.
                      width: tablet
                          ? uprightTargetBoardEdge(context)
                          : double.infinity,
                      child: _TargetDartboard(provider: provider),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tablet
                    ? listPane(const EdgeInsets.fromLTRB(12, 12, 12, 8))
                    : SingleChildScrollView(
                        padding: contentPadding(
                          context,
                          fraction: kGameWidthFraction,
                          maxWidth: kMaxGameWidth,
                          top: 12,
                          bottom: 8,
                          innerH: 12,
                        ),
                        child: scoreboard,
                      ),
              ),
            ],
            // ── Input area ────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                current.label(l),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                              if (current.isTeamSlot)
                                Text(
                                  current.player.label(l),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            // A tap on the chips while a finished visit is
                            // on show moves the game on without the wait.
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: provider.visitPending
                                  ? provider.flushHeldVisit
                                  : null,
                              child: VisitDartsRow(
                                darts: [
                                  for (final t in provider.visitBuffer)
                                    visitDartFrom(t.field, t.multiplier, l),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      _AroundTheClockHint(provider: provider),
                      const SizedBox(height: 10),
                      _AroundTheClockInput(provider: provider),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks the user to confirm leaving the game, popping back to the previous
  /// screen if they accept.
  void _confirmQuit(BuildContext context) {
    final l = context.l10n;
    showDialog(
      context: context,
      builder: (_) => Center(
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
                  context.read<AroundTheClockProvider>().leaveGame();
                  Navigator.pop(context);
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

// ── Target dartboard ──────────────────────────────────────────────────────────

/// Dartboard highlighting the current player's active target (and, in the
/// full-segments variant, only the multipliers still needed).
class _TargetDartboard extends StatelessWidget {
  final AroundTheClockProvider provider;
  const _TargetDartboard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = provider.activeTarget;

    // In the full-segments variant only the multipliers still missing for
    // the active target are highlighted; every other variant treats any
    // hit on the target as valid, so the whole field lights up.
    Set<int>? highlightMultipliers;
    if (provider.game!.variant == AroundTheClockVariant.fullSegments) {
      final needed = provider.neededSegments;
      if (needed != null) highlightMultipliers = needed.toSet();
    }

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: DartboardTargetPainter(
          target: target,
          highlightMultipliers: highlightMultipliers,
          highlightColor: cs.primary,
          onSurfaceColor: cs.onSurface,
        ),
      ),
    );
  }
}

// ── Scoreboard ────────────────────────────────────────────────────────────────

/// Scrollable scoreboard listing each player's target and progress, auto-
/// scrolling to keep the active player in view.
class _AroundTheClockBoard extends StatefulWidget {
  final AroundTheClockProvider provider;
  final List<AroundTheClockPlayerState> states;
  final int currentIdx;
  final int throwCount;

  const _AroundTheClockBoard({
    required this.provider,
    required this.states,
    required this.currentIdx,
    required this.throwCount,
  });

  @override
  State<_AroundTheClockBoard> createState() => _AroundTheClockBoardState();
}

class _AroundTheClockBoardState extends State<_AroundTheClockBoard> {
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.states.length, (_) => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant _AroundTheClockBoard old) {
    super.didUpdateWidget(old);
    if (old.states.length != widget.states.length) {
      _keys = List.generate(widget.states.length, (_) => GlobalKey());
    }
    if (old.currentIdx != widget.currentIdx ||
        old.throwCount != widget.throwCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  /// Smoothly scrolls the active player's row to the center of the viewport.
  void _scrollToCurrent() {
    final key = _keys[widget.currentIdx];
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final total = aroundTheClockOrder.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: widget.states.indexed.map((e) {
            final i = e.$1;
            final s = e.$2;
            final isActive = i == widget.currentIdx;
            final hit = s.progress.clamp(0, total);
            final targetLabel = s.currentTarget == 25
                ? l.bull
                : '${s.currentTarget}';
            return Padding(
              key: _keys[i],
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: InkWell(
                onTap: () => openAroundTheClockSlotInfo(context, i),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.label(l),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isActive ? cs.primary : cs.onSurface,
                            ),
                          ),
                          if (s.isTeamSlot)
                            Text(
                              s.player.label(l),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isActive
                                    ? cs.primary.withValues(alpha: 0.75)
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!s.isFinished)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '→ $targetLabel',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Text(
                      s.isFinished
                          ? l.aroundClockDartsUsed(s.finishedAtDart!)
                          : '$hit/$total',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isActive ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Dart dot indicator ────────────────────────────────────────────────────────

// ── Hint (full-segments variant) ──────────────────────────────────────────────

/// Full-segments-only hint showing which single/double/triple of the target
/// are still needed to advance.
class _AroundTheClockHint extends StatelessWidget {
  final AroundTheClockProvider provider;
  const _AroundTheClockHint({required this.provider});

  static const _labels = {1: 'S', 2: 'D', 3: 'T'};

  @override
  Widget build(BuildContext context) {
    if (provider.game?.variant != AroundTheClockVariant.fullSegments) {
      return const SizedBox.shrink();
    }

    final target = provider.activeTarget;
    final hit = provider.currentPlayerState.hitSegments;

    // Bull has no Triple: only S and D chips.
    final multipliers = target == 25 ? const [1, 2] : const [1, 2, 3];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in multipliers) ...[
            if (m != multipliers.first) const SizedBox(width: 6),
            _SegmentChip(
              label: target == 25
                  ? (m == 2 ? 'D-Bull' : 'Bull')
                  : '${_labels[m]}$target',
              done: hit.contains(m),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single segment hint chip, struck through once that segment has been hit.
class _SegmentChip extends StatelessWidget {
  final String label;
  final bool done;
  const _SegmentChip({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final activeBg = tripleContainerColor(context);
    final activeFg = onTripleContainerColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: done ? cs.surfaceContainerHighest : activeBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: done ? cs.onSurface.withValues(alpha: 0.35) : activeFg,
          decoration: done ? TextDecoration.lineThrough : null,
          decorationColor: cs.onSurface.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// ── Input ─────────────────────────────────────────────────────────────────────

/// Input row of single/double/triple (plus Bull joker in the skip variant and
/// miss) buttons that record a dart for the active target.
class _AroundTheClockInput extends StatelessWidget {
  final AroundTheClockProvider provider;
  const _AroundTheClockInput({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final target = provider.activeTarget;

    final showJoker =
        provider.game!.variant == AroundTheClockVariant.skipRules &&
        target != 25;
    final showTriple = target != 25;

    // Number of buttons that should fit in one row
    final btnCount = 2 + (showTriple ? 1 : 0) + (showJoker ? 1 : 0) + 1;
    const spacing = 10.0;

    // Dimmed and deaf while a bot throws or a finished visit is still on
    // show; the provider refuses the dart either way, this only says so.
    final locked = provider.inputLocked;
    return LayoutBuilder(
      builder: (context, constraints) {
        final btnW =
            ((constraints.maxWidth - spacing * (btnCount - 1)) / btnCount)
                .clamp(48.0, 72.0);
        final btnH = (btnW * 64 / 72).clamp(44.0, 64.0);

        if (provider.visitPending) {
          // Three of the buttons this row would hold, and their two gaps.
          return ContinueButton(
            onPressed: provider.flushHeldVisit,
            width: 3 * btnW + 2 * spacing,
            height: btnH,
          );
        }

        return IgnorePointer(
          ignoring: locked,
          child: Opacity(
            opacity: locked ? 0.5 : 1,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _MultBtn(
                  label: l.single,
                  sub: '×1',
                  multiplier: 1,
                  width: btnW,
                  height: btnH,
                  onTap: () => provider.recordDart(target, 1),
                ),
                _MultBtn(
                  label: l.double_,
                  sub: '×2',
                  multiplier: 2,
                  width: btnW,
                  height: btnH,
                  onTap: () => provider.recordDart(target, 2),
                ),
                if (showTriple)
                  _MultBtn(
                    label: l.triple,
                    sub: '×3',
                    multiplier: 3,
                    width: btnW,
                    height: btnH,
                    onTap: () => provider.recordDart(target, 3),
                  ),
                if (showJoker)
                  _JokerBtn(
                    label: l.aroundClockJoker,
                    sub: 'Bull',
                    width: btnW,
                    height: btnH,
                    onTap: () => provider.recordDart(25, 2),
                  ),
                _MissBtn(
                  label: l.aroundClockMiss,
                  width: btnW,
                  height: btnH,
                  onTap: () => provider.recordDart(0, 0),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A single/double/triple input button, colored to match its multiplier.
class _MultBtn extends StatelessWidget {
  final String label;
  final String sub;
  final int multiplier;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _MultBtn({
    required this.label,
    required this.sub,
    required this.multiplier,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    switch (multiplier) {
      case 2:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 3:
        bg = tripleContainerColor(context);
        fg = onTripleContainerColor(context);
        break;
      default:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurface;
    }
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
              Text(
                sub,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Bull joker button (skip-rules variant) that advances past the current target.
class _JokerBtn extends StatelessWidget {
  final String label;
  final String sub;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _JokerBtn({
    required this.label,
    required this.sub,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF1A1A1A);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: const Color(0xFFF9A825),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
              Text(
                sub,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The miss button that records a non-scoring dart.
class _MissBtn extends StatelessWidget {
  final String label;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _MissBtn({
    required this.label,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the live info of the Around the Clock slot at [slotIndex]: its last
/// three visits and the numbers the mode is played by.
void openAroundTheClockSlotInfo(BuildContext context, int slotIndex) {
  final provider = context.read<AroundTheClockProvider>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ModeLiveInfoScreen(
        listenable: provider,
        data: (context) {
          final l = context.l10n;
          final s = provider.playerStates[slotIndex];
          final ids = s.players.map((p) => p.id).toSet();
          final throws = provider.throwHistory
              .where((t) => ids.contains(t.playerId))
              .toList();
          final variant = provider.game!.variant;
          final stats = AroundTheClockStats.of(throws, variant);
          final visits = aroundTheClockVisits(throws);
          final hits = stats.visitHits;
          final from = visits.length <= 3 ? 0 : visits.length - 3;
          return (
            title: s.label(l),
            subtitle: s.isTeamSlot ? s.player.label(l) : null,
            visitSlots: 3,
            recentVisits: [
              for (var i = visits.length - 1; i >= from; i--)
                (
                  darts: [
                    for (final t in visits[i])
                      visitDartFrom(t.field, t.multiplier, l),
                  ],
                  yield: l.hitsN(hits[i].where((h) => h).length),
                ),
            ],
            stats: [
              (
                l.aroundClockProgress,
                l.aroundClockProgressN(
                  s.progress.clamp(0, aroundTheClockOrder.length),
                  aroundTheClockOrder.length,
                ),
              ),
              (l.dartsThrown, '${stats.darts}'),
              (l.dartsPerTarget, stats.dartsPerTarget.toStringAsFixed(1)),
              (l.hitRate, '${(stats.hitRate * 100).round()} %'),
              (l.longestStreak, '${stats.longestStreak}'),
              if (variant == AroundTheClockVariant.skipRules)
                (l.fieldsSkipped, '${stats.fieldsSkipped}'),
            ],
          );
        },
      ),
    ),
  );
}
