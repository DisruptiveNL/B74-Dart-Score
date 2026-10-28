import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shanghai_game.dart';
import '../providers/shanghai_provider.dart';
import '../utils/layout.dart';
import '../utils/segment_color.dart';
import '../widgets/dartboard_target_painter.dart';
import '../utils/player_label.dart';
import '../utils/shanghai_stats.dart';
import '../utils/visit_darts.dart';
import '../widgets/visit_darts_row.dart';
import '../widgets/visit_pause.dart';
import 'mode_live_info_screen.dart';
import 'shanghai_summary_screen.dart';

/// Live Shanghai game screen. Watches the provider and routes to the summary
/// when the game ends, otherwise shows the play view.
class ShanghaiScreen extends StatelessWidget {
  const ShanghaiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ShanghaiProvider>(
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
              MaterialPageRoute(builder: (_) => const ShanghaiSummaryScreen()),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _ShanghaiGameView(provider: provider);
      },
    );
  }
}

// ── Main game view ────────────────────────────────────────────────────────────

/// The in-play layout: target dartboard, scoreboard, Shanghai hint, and input.
class _ShanghaiGameView extends StatelessWidget {
  final ShanghaiProvider provider;
  const _ShanghaiGameView({required this.provider});

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

    final scoreboard = _ShanghaiBoard(
      provider: provider,
      states: states,
      currentIdx: provider.currentPlayerIndex,
      dartsInVisit: provider.dartsInVisit,
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
          title: const Text('Shanghai'),
          actions: [
            if (provider.canUndo)
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                tooltip: l.undo,
                onPressed: () => provider.undoLastDart(),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l.shanghaiQuit,
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
                                slots: provider.visitDartLimit,
                                darts: [
                                  for (final t in provider.visitBuffer)
                                    visitDartFrom(t.target, t.multiplier, l),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _ShanghaiHint(provider: provider),
                      const SizedBox(height: 10),
                      _ShanghaiInput(provider: provider),
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

  /// Asks the user to confirm leaving the game, popping back if they accept.
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
                  context.read<ShanghaiProvider>().leaveGame();
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

// ── Active target dartboard ───────────────────────────────────────────────────

/// Dartboard highlighting the current round's target number.
class _TargetDartboard extends StatelessWidget {
  final ShanghaiProvider provider;
  const _TargetDartboard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = provider.activeTarget;

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: DartboardTargetPainter(
          target: target,
          highlightColor: cs.primary,
          onSurfaceColor: cs.onSurface,
        ),
      ),
    );
  }
}

// ── Scoreboard ────────────────────────────────────────────────────────────────

/// Scrollable scoreboard listing each player's score and round target,
/// auto-scrolling to keep the active player in view.
class _ShanghaiBoard extends StatefulWidget {
  final ShanghaiProvider provider;
  final List<ShanghaiPlayerState> states;
  final int currentIdx;
  final int dartsInVisit;

  const _ShanghaiBoard({
    required this.provider,
    required this.states,
    required this.currentIdx,
    required this.dartsInVisit,
  });

  @override
  State<_ShanghaiBoard> createState() => _ShanghaiBoardState();
}

class _ShanghaiBoardState extends State<_ShanghaiBoard> {
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.states.length, (_) => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant _ShanghaiBoard old) {
    super.didUpdateWidget(old);
    if (old.states.length != widget.states.length) {
      _keys = List.generate(widget.states.length, (_) => GlobalKey());
    }
    if (old.currentIdx != widget.currentIdx ||
        old.dartsInVisit != widget.dartsInVisit) {
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
    final isSequential =
        widget.provider.game!.variant == ShanghaiVariant.sequential;
    final currentIdx = widget.currentIdx;
    final pendingIdx = widget.provider.pendingShanghaiIdx;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: widget.states.indexed.map((e) {
            final i = e.$1;
            final s = e.$2;
            final isActive = i == currentIdx;
            return Padding(
              key: _keys[i],
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: InkWell(
                onTap: () => openShanghaiSlotInfo(context, i),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
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
                          if (i == pendingIdx) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: l.shanghaiPending,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'S',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isSequential)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '→ ${s.progress > 20 ? '✓' : s.progress}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Text(
                      '${s.score}',
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

// ── Shanghai hint ─────────────────────────────────────────────────────────────

/// Hint showing what is still needed this visit to complete a Shanghai.
class _ShanghaiHint extends StatelessWidget {
  final ShanghaiProvider provider;
  const _ShanghaiHint({required this.provider});

  static const _multiplierLabels = {1: 'S', 2: 'D', 3: 'T'};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bg = tripleContainerColor(context);
    final fg = onTripleContainerColor(context);

    final needed = provider.shanghaiNeededMultipliers;
    final streakNeeded = provider.shanghaiStreakNeeded;

    Widget? content;
    if (needed != null && needed.isNotEmpty) {
      final target = provider.activeTarget;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < needed.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            Text(
              '${_multiplierLabels[needed[i]]}$target',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      );
    } else if (streakNeeded != null && streakNeeded > 0) {
      content = Text(
        l.shanghaiHintStreak(streakNeeded),
        style: theme.textTheme.bodySmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (content == null) return const SizedBox.shrink();

    // The same room above as below, so the hint sits halfway between the
    // name and the buttons.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.shanghaiHintTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          content,
        ],
      ),
    );
  }
}

// ── Input ─────────────────────────────────────────────────────────────────────

/// Input row of single/double/triple and miss buttons that record a dart for
/// the active target.
class _ShanghaiInput extends StatelessWidget {
  final ShanghaiProvider provider;
  const _ShanghaiInput({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final target = provider.activeTarget;

    if (provider.visitPending) {
      // Three ring buttons and their two gaps.
      return ContinueButton(
        onPressed: provider.flushHeldVisit,
        width: 3 * 72 + 2 * 10,
        height: 64,
      );
    }

    // Dimmed and deaf while a bot throws or a finished visit is still on
    // show; the provider refuses the dart either way, this only says so.
    final locked = provider.inputLocked;
    return IgnorePointer(
      ignoring: locked,
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MultBtn(
              label: l.single,
              sub: '×1',
              multiplier: 1,
              onTap: () => provider.recordDart(1),
            ),
            const SizedBox(width: 10),
            _MultBtn(
              label: l.double_,
              sub: '×2',
              multiplier: 2,
              onTap: () => provider.recordDart(2),
            ),
            const SizedBox(width: 10),
            if (target != 25)
              _MultBtn(
                label: l.triple,
                sub: '×3',
                multiplier: 3,
                onTap: () => provider.recordDart(3),
              ),
            const SizedBox(width: 10),
            _MissBtn(
              label: l.shanghaiMiss,
              onTap: () => provider.recordDart(0),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single/double/triple input button, colored to match its multiplier.
class _MultBtn extends StatelessWidget {
  final String label;
  final String sub;
  final int multiplier;
  final VoidCallback onTap;
  const _MultBtn({
    required this.label,
    required this.sub,
    required this.multiplier,
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
      width: 72,
      height: 64,
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

/// The miss button that records a non-scoring dart.
class _MissBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MissBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 64,
      child: Material(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

/// Opens the live info of the Shanghai slot at [slotIndex]: its last three
/// visits and the numbers Shanghai is played by.
void openShanghaiSlotInfo(BuildContext context, int slotIndex) {
  final provider = context.read<ShanghaiProvider>();
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
          final limit = provider.visitDartLimit;
          final stats = ShanghaiStats.of(throws, variant, limit);
          final visits = shanghaiVisits(throws, limit);
          final recent = visits.length <= 3
              ? visits
              : visits.sublist(visits.length - 3);
          return (
            title: s.label(l),
            subtitle: s.isTeamSlot ? s.player.label(l) : null,
            visitSlots: limit,
            recentVisits: [
              for (final v in recent.reversed)
                (
                  darts: [
                    for (final t in v) visitDartFrom(t.target, t.multiplier, l),
                  ],
                  yield: l.pointsN(shanghaiPointsOfVisit(v)),
                ),
            ],
            stats: [
              (l.points, '${s.score}'),
              (l.pointsPerRound, stats.pointsPerRound.toStringAsFixed(1)),
              (l.hitRate, '${(stats.hitRate * 100).round()} %'),
              (l.bestVisit, l.pointsN(stats.bestVisitPoints)),
              (l.shanghaisThrown, '${stats.shanghais}'),
              if (variant == ShanghaiVariant.sequential)
                (l.shanghaiTarget, '${s.progress}'),
              (l.dartsThrown, '${stats.darts}'),
            ],
          );
        },
      ),
    ),
  );
}
