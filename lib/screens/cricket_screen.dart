import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/cricket_game.dart';
import '../providers/cricket_provider.dart';
import '../utils/layout.dart';
import '../utils/segment_color.dart';
import '../widgets/cricket_marks_widget.dart';
import '../utils/cricket_stats.dart';
import '../utils/player_label.dart';
import '../utils/visit_darts.dart';
import '../widgets/visit_darts_row.dart';
import '../widgets/visit_pause.dart';
import 'mode_live_info_screen.dart';
import 'cricket_summary_screen.dart';

/// Live Cricket game screen. Watches the provider and routes to the summary
/// when the game ends, otherwise shows the play view.
class CricketScreen extends StatelessWidget {
  const CricketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CricketProvider>(
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
              MaterialPageRoute(builder: (_) => const CricketSummaryScreen()),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _CricketGameView(provider: provider);
      },
    );
  }
}

// ── Main game view ────────────────────────────────────────────────────────────

/// The in-play layout: the marks/score board plus the dart input area.
class _CricketGameView extends StatelessWidget {
  final CricketProvider provider;
  const _CricketGameView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final game = provider.game!;
    final states = provider.playerStates;
    final currentIdx = provider.currentPlayerIndex;
    final current = provider.currentPlayerState;

    final board = _CricketBoard(
      states: states,
      currentIdx: currentIdx,
      throwCount: provider.throwCount,
      game: game,
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
          title: const Text('Cricket'),
          actions: [
            if (provider.canUndo)
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                tooltip: l.undo,
                onPressed: () => provider.undoLastDart(),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l.cricketQuit,
              onPressed: () => _confirmQuit(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Scoreboard ────────────────────────────────────────────────────
            Expanded(
              // A tablet hands the board the whole box above the input and lets
              // it fill it. A phone keeps the column a phone screen reads at and
              // scrolls the board inside it.
              child: isTabletLayout(context)
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: board,
                    )
                  : SingleChildScrollView(
                      padding: contentPadding(
                        context,
                        top: 8,
                        bottom: 8,
                        innerH: 12,
                      ),
                      child: board,
                    ),
            ),
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
                      // Current player/team + dart counter
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
                      const SizedBox(height: 10),
                      _CricketInput(
                        provider: provider,
                        scoringMode: game.scoringMode,
                      ),
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
                  context.read<CricketProvider>().leaveGame();
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

// ── Cricket Board ─────────────────────────────────────────────────────────────

const double _kLabelColumnWidth = 52;
const double _kPlayerColumnWidth = 92;
const double _kHeaderHeight = 52;
const double _kRowHeight = 40;

/// Widest a player column is allowed to grow on a tablet. Past this the board
/// stops spreading and stands centred instead: a mark alone in a column half a
/// screen wide stops reading as a column.
const double _kMaxPlayerColumnWidth = 200;

/// Tallest a field row may grow. Seven rows of this plus the header is about a
/// tablet's worth of height, and a row taller than this only pushes the seven
/// fields apart.
const double _kMaxRowHeight = 88;

/// The vertical padding a field row carries, above and below together.
const double _kRowGap = 6;

/// The card's own padding, on both sides and top and bottom together.
const double _kCardPadding = 24;

/// The margin a Card carries outside that padding, again for both sides. Left
/// out of the budget, it is exactly what a board that fills its box overflows
/// by.
const double _kCardMargin = 8;

/// The divider between the header and the field rows, with its two gaps.
const double _kHeaderDivider = 13;

/// How large a Cricket board draws itself in the box it was handed.
///
/// A phone keeps the fixed sizes the board has always had and scrolls when they
/// do not fit. A tablet spends the box instead: the columns share the width up
/// to a cap, the rows share the height, and the text and marks follow the rows
/// so a taller board is not the same board with more air in it.
class _BoardMetrics {
  final double columnWidth;
  final double rowHeight;
  final double headerHeight;
  final double markSize;
  final double textFactor;

  /// Width of the card itself, which on a tablet is only as wide as its columns
  /// need. Infinite where the card takes whatever width it is given.
  final double boardWidth;

  /// Whether the rows fit the box at the height they were given. A board that
  /// does not fit is scrolled rather than squeezed.
  final bool fits;

  const _BoardMetrics({
    required this.columnWidth,
    required this.rowHeight,
    required this.headerHeight,
    required this.markSize,
    required this.textFactor,
    required this.boardWidth,
    required this.fits,
  });

  /// Works the sizes out for [constraints], for a board of [players] columns.
  ///
  /// [teamGame] adds the second line each header carries for a team, and
  /// [tablet] decides whether anything is spent at all: on a phone this returns
  /// exactly the fixed board.
  factory _BoardMetrics.of(
    BoxConstraints constraints, {
    required bool tablet,
    required int players,
    required bool teamGame,
  }) {
    final baseHeader = teamGame ? _kHeaderHeight + 14 : _kHeaderHeight;

    if (!tablet || !constraints.maxHeight.isFinite) {
      return _BoardMetrics(
        columnWidth: _kPlayerColumnWidth,
        rowHeight: _kRowHeight,
        headerHeight: baseHeader,
        markSize: 36,
        textFactor: 1.0,
        boardWidth: double.infinity,
        fits: true,
      );
    }

    // Height left for the seven rows once the card, the header and the divider
    // under it have taken theirs. The header is measured twice because it grows
    // with the text, and the text grows with the rows it stands over.
    double rowsFor(double header) =>
        (constraints.maxHeight -
                _kCardMargin -
                _kCardPadding -
                header -
                _kHeaderDivider) /
            7 -
        _kRowGap;

    final textFactor = (rowsFor(baseHeader * 1.3) / _kRowHeight)
        .clamp(1.0, 1.3)
        .toDouble();
    final headerHeight = baseHeader * textFactor;
    final rowHeight = rowsFor(
      headerHeight,
    ).clamp(_kRowHeight, _kMaxRowHeight).toDouble();

    final columnWidth =
        ((constraints.maxWidth -
                    _kCardMargin -
                    _kCardPadding -
                    _kLabelColumnWidth) /
                players)
            .clamp(_kPlayerColumnWidth, _kMaxPlayerColumnWidth)
            .toDouble();

    return _BoardMetrics(
      columnWidth: columnWidth,
      rowHeight: rowHeight,
      headerHeight: headerHeight,
      // The mark keeps a margin inside its row, and never grows past the column
      // it sits in.
      markSize: (rowHeight * 0.9).clamp(36, columnWidth - 8).toDouble(),
      textFactor: textFactor,
      boardWidth:
          _kCardMargin +
          _kCardPadding +
          _kLabelColumnWidth +
          columnWidth * players,
      fits: rowsFor(headerHeight) >= _kRowHeight,
    );
  }
}

/// Horizontally scrollable grid of Cricket fields by player, showing marks and
/// scores and auto-scrolling to keep the active player's column in view.
class _CricketBoard extends StatefulWidget {
  final List<CricketPlayerState> states;
  final int currentIdx;
  final int throwCount;
  final CricketGame game;

  const _CricketBoard({
    required this.states,
    required this.currentIdx,
    required this.throwCount,
    required this.game,
  });

  @override
  State<_CricketBoard> createState() => _CricketBoardState();
}

class _CricketBoardState extends State<_CricketBoard> {
  final ScrollController _hController = ScrollController();

  /// Width of one player column as the last build worked it out. The scroll to
  /// the active player runs after that frame and has to measure in the same
  /// columns it is scrolling past.
  double _columnWidth = _kPlayerColumnWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCurrentPlayer());
  }

  @override
  void didUpdateWidget(covariant _CricketBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refocus on every turn change AND every recorded dart (including undo),
    // so the active player's column is always scrolled into view.
    if (oldWidget.currentIdx != widget.currentIdx ||
        oldWidget.throwCount != widget.throwCount) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusCurrentPlayer(),
      );
    }
  }

  @override
  void dispose() {
    _hController.dispose();
    super.dispose();
  }

  /// Smoothly scrolls the active player's column to the center of the viewport.
  void _focusCurrentPlayer() {
    if (!_hController.hasClients) return;

    final viewport = _hController.position.viewportDimension;
    final columnLeft = widget.currentIdx * _columnWidth;
    final target = (columnLeft - (viewport - _columnWidth) / 2).clamp(
      0.0,
      _hController.position.maxScrollExtent,
    );

    _hController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = _BoardMetrics.of(
          constraints,
          tablet: isTabletLayout(context),
          players: widget.states.length,
          teamGame: widget.game.isTeamGame,
        );
        _columnWidth = m.columnWidth;

        final card = TextScaleBy(
          factor: m.textFactor,
          child: _card(context, m),
        );
        if (m.boardWidth.isInfinite) return card;

        // Only as wide as its columns, and standing in the middle of what is
        // left. Taller than the box, it is scrolled rather than squeezed.
        final centred = Center(
          child: SizedBox(width: m.boardWidth, child: card),
        );
        return m.fits ? centred : SingleChildScrollView(child: centred);
      },
    );
  }

  /// The board itself at the sizes [m] worked out.
  Widget _card(BuildContext context, _BoardMetrics m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final states = widget.states;
    final currentIdx = widget.currentIdx;
    final headerHeight = m.headerHeight;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fixed field-label column ────────────────────────────────────
            SizedBox(
              width: _kLabelColumnWidth,
              child: Column(
                children: [
                  SizedBox(height: headerHeight), // header spacer
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  ...cricketFields.map((field) {
                    final allClosed = states.every(
                      (s) => s.hasClosedField(field),
                    );
                    final label = field == 25 ? l.bull : '$field';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: SizedBox(
                        height: m.rowHeight,
                        child: Center(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: allClosed
                                  ? cs.onSurface.withValues(alpha: 0.3)
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            // ── Scrollable player columns (focused on the active player) ────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = (m.columnWidth * states.length).clamp(
                    constraints.maxWidth,
                    double.infinity,
                  );
                  return SingleChildScrollView(
                    controller: _hController,
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: player names + scores
                        Row(
                          children: states.indexed.map((e) {
                            final i = e.$1;
                            final s = e.$2;
                            final isActive = i == currentIdx;
                            return SizedBox(
                              width: m.columnWidth,
                              height: headerHeight,
                              child: InkWell(
                                onTap: () => openCricketSlotInfo(context, i),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      s.label(l),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            fontWeight: isActive
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isActive
                                                ? cs.primary
                                                : cs.onSurface,
                                          ),
                                    ),
                                    if (s.isTeamSlot)
                                      Text(
                                        s.player.label(l),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: isActive
                                                  ? cs.primary.withValues(
                                                      alpha: 0.75,
                                                    )
                                                  : cs.onSurfaceVariant,
                                            ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${s.score}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isActive ? cs.primary : null,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: gridWidth,
                          child: const Divider(height: 1),
                        ),
                        const SizedBox(height: 4),
                        // Field rows
                        ...cricketFields.map((field) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: states.map((s) {
                                final marks = s.marks[field] ?? 0;
                                return SizedBox(
                                  width: m.columnWidth,
                                  height: m.rowHeight,
                                  child: Center(
                                    child: CricketMarksWidget(
                                      marks: marks,
                                      size: m.markSize,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Marks widget: shows /, X, or ⊗ ──────────────────────────────────────────

// ── Cricket Input ─────────────────────────────────────────────────────────────

/// Cricket dart input: a field grid where, in standard scoring, tapping a field
/// reveals a single/double/triple selector; simple scoring records a single hit
/// directly. Includes a miss button.
class _CricketInput extends StatefulWidget {
  final CricketProvider provider;
  final CricketScoringMode scoringMode;

  const _CricketInput({required this.provider, required this.scoringMode});

  @override
  State<_CricketInput> createState() => _CricketInputState();
}

class _CricketInputState extends State<_CricketInput> {
  int? _selectedField;

  bool get _isStandard => widget.scoringMode == CricketScoringMode.standard;

  /// Handles a field tap: records a single in simple mode, or opens the
  /// multiplier selector in standard mode.
  Future<void> _onFieldTap(int field) async {
    if (!_isStandard) {
      // Simple mode: always single
      await widget.provider.recordDart(field, 1);
      setState(() => _selectedField = null);
    } else {
      setState(() => _selectedField = field);
    }
  }

  /// Records the selected field with the chosen multiplier (standard mode).
  Future<void> _onMultiplierTap(int multiplier) async {
    if (_selectedField == null) return;
    final field = _selectedField!;
    setState(() => _selectedField = null);
    await widget.provider.recordDart(field, multiplier);
  }

  /// Records a missed dart and clears any field selection.
  Future<void> _onMiss() async {
    setState(() => _selectedField = null);
    await widget.provider.recordDart(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final states = widget.provider.playerStates;
    final l = context.l10n;

    if (widget.provider.visitPending) {
      // Three field buttons and their two gaps.
      return ContinueButton(
        onPressed: widget.provider.flushHeldVisit,
        width: 3 * 56 + 2 * 8,
      );
    }

    if (_selectedField != null && _isStandard) {
      // Show multiplier selector
      return _MultiplierRow(
        field: _selectedField!,
        onSelected: _onMultiplierTap,
        onCancel: () => setState(() => _selectedField = null),
        l: l,
      );
    }

    // Show field grid. Dimmed and deaf while a bot throws or a finished
    // visit is still on show; the provider refuses the dart either way, this
    // only says so.
    final locked = widget.provider.inputLocked;
    return IgnorePointer(
      ignoring: locked,
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ...cricketFields.map((field) {
                  final allClosed = states.every(
                    (s) => s.hasClosedField(field),
                  );
                  final label = field == 25 ? l.bull : '$field';
                  return _FieldButton(
                    label: label,
                    allClosed: allClosed,
                    onTap: allClosed ? null : () => _onFieldTap(field),
                  );
                }),
                _MissButton(onTap: _onMiss, l: l),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A Cricket field button, disabled and dimmed once every player has closed it.
class _FieldButton extends StatelessWidget {
  final String label;
  final bool allClosed;
  final VoidCallback? onTap;

  const _FieldButton({
    required this.label,
    required this.allClosed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: allClosed
            ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
            : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: allClosed
                    ? cs.onSurface.withValues(alpha: 0.3)
                    : cs.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The miss button that records a non-scoring dart.
class _MissButton extends StatelessWidget {
  final VoidCallback onTap;
  final AppLocalizations l;
  const _MissButton({required this.onTap, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 56,
      child: Material(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              l.cricketMiss,
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

/// Single/double/triple selector shown after a field is tapped in standard mode.
class _MultiplierRow extends StatelessWidget {
  final int field;
  final void Function(int) onSelected;
  final VoidCallback onCancel;
  final AppLocalizations l;

  const _MultiplierRow({
    required this.field,
    required this.onSelected,
    required this.onCancel,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = field == 25 ? l.bull : '$field';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MultBtn(
              label: l.single,
              sub: '×1',
              multiplier: 1,
              onTap: () => onSelected(1),
            ),
            const SizedBox(width: 10),
            _MultBtn(
              label: l.double_,
              sub: '×2',
              multiplier: 2,
              onTap: () => onSelected(2),
            ),
            const SizedBox(width: 10),
            if (field != 25) // Bull has no triple
              _MultBtn(
                label: l.triple,
                sub: '×3',
                multiplier: 3,
                onTap: () => onSelected(3),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: onCancel, child: Text(l.cancel)),
      ],
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
      width: 80,
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

/// Opens the live info of the Cricket slot at [slotIndex]: its last three
/// visits and the numbers Cricket is played by.
void openCricketSlotInfo(BuildContext context, int slotIndex) {
  final provider = context.read<CricketProvider>();
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
          final scoring = provider.game!.scoringMode;
          final stats = CricketStats.of(throws, scoring);
          final visits = cricketVisits(throws);
          final recent = visits.length <= 3
              ? visits
              : visits.sublist(visits.length - 3);
          final closed = cricketFields.where(s.hasClosedField).length;
          return (
            title: s.label(l),
            subtitle: s.isTeamSlot ? s.player.label(l) : null,
            visitSlots: 3,
            recentVisits: [
              for (final v in recent.reversed)
                (
                  darts: [
                    for (final t in v) visitDartFrom(t.field, t.multiplier, l),
                  ],
                  yield: l.marksN(cricketMarksOfVisit(v, scoring)),
                ),
            ],
            stats: [
              (l.marksPerRound, stats.marksPerRound.toStringAsFixed(1)),
              (l.hitRate, '${(stats.hitRate * 100).round()} %'),
              (l.fieldsClosed, l.nOfM(closed, cricketFields.length)),
              if (scoring == CricketScoringMode.standard)
                (l.points, '${s.score}'),
              (l.dartsThrown, '${stats.darts}'),
              (l.bestVisit, l.marksN(stats.bestVisitMarks)),
            ],
          );
        },
      ),
    ),
  );
}
