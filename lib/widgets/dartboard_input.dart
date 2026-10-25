import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/segment_color.dart';
import 'visit_pause.dart';

/// A single dart entered on the board input: which [field] was hit, the
/// [modifier] (single/double/triple) and the resulting [score].
class DartEntry {
  final int field;    // 1-20, 25=bull, 0=miss
  final int modifier; // 1=single, 2=double, 3=triple
  final int score;

  const DartEntry({required this.field, required this.modifier, required this.score});

  /// Short notation for this dart, e.g. `T20`, `D16`, `Bull`, `25` or `Miss`.
  String get label {
    if (field == 0) return 'Miss';
    if (field == 25) return modifier == 2 ? 'Bull' : '25';
    final prefix = modifier == 2 ? 'D' : modifier == 3 ? 'T' : '';
    return '$prefix$field';
  }
}

/// What [DartboardInput] reads and drives: the visit on the board, the lock
/// on the input, undo and redo, and the dart a tap enters.
///
/// The provider behind it owns every rule. It scores the dart, decides when the
/// visit is over and whether it busted, and holds a finished visit on show;
/// the input only reports the tap and draws what it is told.
abstract interface class DartboardInputSource implements Listenable {
  /// Whether no dart of the person's lands now: a bot on turn, or a finished
  /// visit still on show.
  bool get inputLocked;

  /// Whether a finished visit is on show, waiting out its pause.
  bool get visitPending;

  /// The darts of the visit on the board, oldest first.
  List<DartEntry> get currentVisitDarts;

  /// Whether the visit on the board has busted.
  bool get liveBust;

  /// Whether a dart can be taken back.
  bool get canUndoDart;

  /// Whether a dart taken back can be put on the board again.
  bool get canRedoDart;

  /// Enters a dart on [field] (0 = miss, 25 = bull) with [modifier]
  /// (1 single, 2 double, 3 triple).
  Future<void> tapField(int field, int modifier);

  /// Takes the last dart back.
  Future<void> undoLastDart();

  /// Puts the last dart taken back on the board again.
  Future<void> redoLastDart();

  /// Ends the pause of a finished visit at once.
  Future<void> flushHeldVisit();
}

/// Dartboard-style score entry for the modes scored like X01: a number grid
/// plus single/double/triple modifier, miss and bull. Reads the current
/// player's in-progress visit and undo/redo state from the provider of type
/// [T], which also enforces check-in/check-out rules and detects busts. Only
/// the active modifier is local UI state.
///
/// Two layouts, picked from the height the scoreboard leaves over. With room to
/// spare the rows keep their preferred size and the column is centred. Below
/// [_compactHeight] the grid instead takes exactly what the other rows leave,
/// so the Miss/Bull row stays on screen on a short phone no matter how far
/// the scoreboard above has grown.
///
/// [fillHeight] asks for the second behaviour whatever the height, which is
/// what a tablet pane wants: there the input is given far more height than it
/// needs, and a column that keeps its phone size would float in the middle of
/// it. The buttons then grow towards square rather than staying flat.
class DartboardInput<T extends DartboardInputSource> extends StatefulWidget {
  /// Whether the column should fill the height it is given rather than keep its
  /// preferred size.
  final bool fillHeight;

  const DartboardInput({super.key, this.fillHeight = false});

  /// Pane width from which the actions move beside the grid. Below it the
  /// column they would take comes straight off the width of the numbers.
  static const double _sideActionsMinWidth = 520;

  /// Whether a pane [width] wide is one where the actions sit beside the grid.
  ///
  /// Public because the layout around the input arranges itself differently in
  /// that case: with the actions beside the numbers the column is short enough
  /// to take the checkout hint on top of it.
  static bool usesSideActions(double width) => width >= _sideActionsMinWidth;

  @override
  State<DartboardInput<T>> createState() => _DartboardInputState<T>();
}

class _DartboardInputState<T extends DartboardInputSource>
    extends State<DartboardInput<T>> {
  int _modifier = 1;

  /// Available height below which the compact, fitted layout is used.
  static const double _compactHeight = 420;

  /// Width to height ratio of a field button when there is room for it.
  static const double _preferredAspectRatio = 1.4;

  /// The same ratio for a pane that hands the input more height than it needs.
  /// A button may grow past square there, because a tablet has the room and a
  /// taller button is an easier target.
  static const double _filledAspectRatio = 0.8;

  /// And further still in a pane too narrow for the actions to sit beside the
  /// grid: that pane is tall and thin, so without this the height the actions
  /// do not take would stand around as a hole under the numbers.
  static const double _narrowFilledAspectRatio = 0.62;

  /// Shortest a field button may get. If even that does not fit, the grid
  /// scrolls inside its box rather than pushing the action row off screen.
  static const double _minFieldHeight = 30;

  /// Field button height below which the buttons drop their second line.
  static const double _twoLineFieldHeight = 44;

  /// Horizontal padding around the grid and the action row.
  static const double _sidePadding = 10;

  /// Widest the modifier switch is drawn. It fills what a tablet pane gives it
  /// up to here, past which three segments start reading as three buttons that
  /// happen to touch rather than as one switch.
  static const double _maxSegmentWidth = 620;

  /// Share of a tablet pane the action row under the grid takes, and the range
  /// it may end up in. Left at its phone height the row reads small next to
  /// number buttons twice its size; the grid gives up the difference.
  static const double _actionRowHeightFactor = 0.13;
  static const double _minActionRowHeight = 72;
  static const double _maxActionRowHeight = 110;

  static const _fields = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  ];

  /// Registers a tap on [field] (0=miss, 25=bull) with the active modifier.
  void _tapField(int field) {
    if (context.read<T>().inputLocked) return;
    context.read<T>().tapField(field, _modifier);
    setState(() => _modifier = 1);
  }

  /// Miss and Bull, either as the row under the grid or as the column beside
  /// it. They take an equal share of it either way: both are darts like any
  /// number on the grid, and two buttons of the same size read as one control.
  ///
  /// There is no button that ends a visit: a visit ends when its third dart
  /// lands, or the moment the leg is checked out or busted, and the provider
  /// decides that on its own.
  Widget _actions({
    required bool vertical,
    required double verticalPadding,
    required double gridSpacing,
  }) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<T>();
    // Full, a bot's, or still being shown: no dart of the person's lands now.
    final dartCount = provider.inputLocked ? 3 : provider.currentVisitDarts.length;

    // While a finished visit is on show the two are locked anyway, so their
    // place goes to the one thing that can be done: moving on now. Under the
    // grid it is as wide as three of its five columns and centred, so it
    // sits under the 17, 18 and 19 rather than spanning the row.
    if (provider.visitPending) {
      final button = _ActionButton(
        label: context.l10n.continueNow,
        icon: Icons.skip_next_rounded,
        color: cs.primary,
        textColor: cs.onPrimary,
        disabled: false,
        verticalPadding: verticalPadding,
        onTap: provider.flushHeldVisit,
      );
      if (vertical) return button;
      return LayoutBuilder(
        builder: (context, box) => Center(
          child: SizedBox(
            width: (3 * box.maxWidth - 2 * gridSpacing) / 5,
            child: button,
          ),
        ),
      );
    }

    final miss = _ActionButton(
      label: context.l10n.miss,
      icon: Icons.close,
      color: cs.errorContainer,
      textColor: cs.onErrorContainer,
      disabled: dartCount >= 3,
      verticalPadding: verticalPadding,
      onTap: () => _tapField(0),
    );
    final bull = _ActionButton(
      label: context.l10n.bullLabel(_modifier == 2),
      icon: Icons.adjust,
      color: cs.secondaryContainer,
      textColor: cs.onSecondaryContainer,
      disabled: dartCount >= 3 || _modifier == 3,
      verticalPadding: verticalPadding,
      onTap: () => _tapField(25),
    );

    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: miss),
          const SizedBox(height: 6),
          Expanded(child: bull),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: miss),
        const SizedBox(width: 6),
        Expanded(child: bull),
      ],
    );
  }

  /// Background the number buttons take under the active modifier, and what
  /// the switch shows for it.
  ///
  /// Single names its grey rather than leaving the segmented button to its
  /// default, which is the theme's green and therefore the double's color.
  Color _modifierColor(BuildContext context) => switch (_modifier) {
        2 => Theme.of(context).colorScheme.secondaryContainer,
        3 => tripleContainerColor(context),
        _ => Theme.of(context).colorScheme.surfaceContainerHigh,
      };

  /// Foreground for [_modifierColor].
  Color _onModifierColor(BuildContext context) => switch (_modifier) {
        2 => Theme.of(context).colorScheme.onSecondaryContainer,
        3 => onTripleContainerColor(context),
        _ => Theme.of(context).colorScheme.onSurface,
      };

  /// The number grid at its preferred size, as tall as its aspect ratio makes it.
  Widget _grid({
    required double spacing,
    required double aspectRatio,
    required bool compactButtons,
    required bool disabled,
  }) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: aspectRatio,
      children: _fields.map((f) => _FieldButton(
        field: f,
        modifier: _modifier,
        disabled: disabled,
        compact: compactButtons,
        onTap: () => _tapField(f),
      )).toList(),
    );
  }

  /// How the grid divides a box: the size of one button, and whether even the
  /// shortest allowed row is taller than the box can hold.
  ({double buttonWidth, double rowHeight, bool scrolls}) _gridMetrics({
    required double width,
    required double height,
    required double spacing,
    required double maxAspectRatio,
  }) {
    final buttonWidth = (width - 4 * spacing) / 5;
    final leftover    = (height - 3 * spacing) / 4;
    final rowHeight   = leftover
        .clamp(_minFieldHeight, buttonWidth / maxAspectRatio)
        .toDouble();
    return (
      buttonWidth: buttonWidth,
      rowHeight: rowHeight,
      scrolls: rowHeight > leftover,
    );
  }

  /// The number grid sized to the box it is given, with the actions beside it
  /// when [sideActions] says the pane is wide enough for them.
  ///
  /// The result is exactly as tall as the grid turns out to be, never as tall
  /// as the box: a taller one would stretch the action column to a height the
  /// numbers next to it do not have, and hide the difference inside the grid.
  /// What the grid does not need belongs to the spacing of the column above.
  Widget _fittedGridArea({
    required double spacing,
    required bool disabled,
    required double maxAspectRatio,
    required bool sideActions,
    required double actionWidth,
    required double actionVPadding,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final gap = sideActions ? spacing + 2 : 0.0;
        final m = _gridMetrics(
          width: box.maxWidth - actionWidth - gap,
          height: box.maxHeight,
          spacing: spacing,
          maxAspectRatio: maxAspectRatio,
        );

        final grid = GridView.count(
          crossAxisCount: 5,
          shrinkWrap: !m.scrolls,
          physics: m.scrolls
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: m.buttonWidth / m.rowHeight,
          children: _fields.map((f) => _FieldButton(
            field: f,
            modifier: _modifier,
            disabled: disabled,
            compact: m.rowHeight < _twoLineFieldHeight,
            scale: (m.rowHeight / 48).clamp(1.0, 2.0).toDouble(),
            onTap: () => _tapField(f),
          )).toList(),
        );

        final height =
            m.scrolls ? box.maxHeight : 4 * m.rowHeight + 3 * spacing;

        return SizedBox(
          height: height,
          child: sideActions
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: grid),
                    SizedBox(width: gap),
                    SizedBox(
                      width: actionWidth,
                      child: _actions(
                        vertical: true,
                        verticalPadding: actionVPadding,
                        gridSpacing: spacing,
                      ),
                    ),
                  ],
                )
              : grid,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<T>();
    final darts = provider.currentVisitDarts;
    // A bot's visit fills the row as it flies, and a finished one stays on
    // show for its pause; neither takes a tap.
    final dartCount = provider.inputLocked ? 3 : darts.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short screens (e.g. iPhone SE) tighten the spacing and let the grid
        // absorb whatever the rows around it leave, so the layout fits by
        // construction instead of by a guessed row height.
        final compact = constraints.maxHeight < _compactHeight;
        // Both a short screen and a tall pane want the grid to take the height
        // that is left; they differ only in how far a button may grow.
        final fitted  = compact || widget.fillHeight;
        // Beside the grid the actions cost width, which only a wide pane has
        // to spare, and give back the height the row under the grid took.
        final sideActions =
            widget.fillHeight &&
                DartboardInput.usesSideActions(constraints.maxWidth);
        // A pane far taller than it is wide cannot spend its height on the
        // grid: four rows of five buttons would have to stretch out of shape.
        // The visit display and the modifier take it instead, where a tablet
        // gains something from the size anyway.
        final tallPane = widget.fillHeight &&
            constraints.maxHeight / constraints.maxWidth > 1.6;
        final rowScale = tallPane ? 1.35 : 1.0;
        final actionColumnWidth = sideActions
            ? (constraints.maxWidth * 0.2).clamp(100, 140).toDouble()
            : 0.0;
        final gridSpacing = compact ? 4.0 : 6.0;
        // Bigger where the pane is a tablet's: it sits between number buttons
        // twice their phone size, and at its phone size it reads as an
        // afterthought between them.
        final segmentVPadding = compact
            ? 4.0
            : tallPane
                ? 20.0
                : widget.fillHeight
                    ? 18.0
                    : 8.0;
        // One value for both sides of the switch, carried as its own padding so
        // that the leftover height a tall pane spreads over the column lands in
        // one gap above it and one below it. Two spacer children would take two
        // shares each and only stay even by accident.
        final segmentGap = compact ? 6.0 : (widget.fillHeight ? 14.0 : 11.0);
        final gapBeforeActions = compact ? 10.0 : 16.0;
        final actionVPadding = compact ? 7.0 : 11.0;
        final bottomPad = compact ? 8.0 : 14.0;

        final column = Column(
          mainAxisSize: fitted ? MainAxisSize.max : MainAxisSize.min,
          // A box taller than the input needs spreads what is left over the
          // gaps, keeping the dart row at the top and the actions at the
          // bottom where the hands are.
          mainAxisAlignment: fitted
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            // Dart progress row with undo/redo. A tap on it while a finished
            // visit is on show moves the game on without the wait.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: provider.visitPending ? provider.flushHeldVisit : null,
              child: _DartProgressRow(
                darts: darts,
                isNegative: provider.liveBust,
                canUndo: provider.canUndoDart,
                canRedo: provider.canRedoDart,
                compact: compact,
                scale: rowScale,
                onUndo: provider.undoLastDart,
                onRedo: provider.redoLastDart,
              ),
            ),
            const SizedBox(height: 4),
            // As wide as the visit row above it, which keeps a margin of its
            // own inside the column.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: VisitPauseBar(pending: provider.visitPending),
            ),
            // Modifier, centred over the visit row above it. It is a switch
            // for the whole input, not for one column of it, so it stays on
            // the middle line of the pane whatever the grid does, and fills
            // what the pane gives it up to a width past which three segments
            // stop reading as one switch. It sits halfway between the visit
            // row and the numbers at every pane size and text size.
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: _sidePadding, vertical: segmentGap),
              child: SizedBox(
                width: widget.fillHeight
                    ? min(constraints.maxWidth - 2 * _sidePadding,
                        _maxSegmentWidth)
                    : null,
                child: SegmentedButton<int>(
                  segments: [
                    // Scaled down rather than wrapped: dragging the divider can
                    // make this pane narrow enough that "Single" would
                    // otherwise break across two lines.
                    ButtonSegment(
                        value: 1, label: _SegmentLabel(context.l10n.single)),
                    ButtonSegment(
                        value: 2, label: _SegmentLabel(context.l10n.double_)),
                    ButtonSegment(
                        value: 3, label: _SegmentLabel(context.l10n.triple)),
                  ],
                  selected: {_modifier},
                  onSelectionChanged: (s) => setState(() => _modifier = s.first),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                        EdgeInsets.symmetric(vertical: segmentVPadding)),
                    textStyle: WidgetStateProperty.all(widget.fillHeight
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.labelMedium),
                    // The chosen segment wears the colour the number buttons
                    // are about to take, so the switch shows what it does
                    // rather than only naming it.
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? _modifierColor(context)
                            : null),
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? _onModifierColor(context)
                            : null),
                  ),
                ),
              ),
            ),
            // Number grid, with the actions beside it where the pane is wide
            // enough that moving them there does not cost the numbers width.
            if (fitted)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                  child: _fittedGridArea(
                    spacing: gridSpacing,
                    disabled: dartCount >= 3,
                    maxAspectRatio: !widget.fillHeight
                        ? _preferredAspectRatio
                        : sideActions
                            ? _filledAspectRatio
                            : _narrowFilledAspectRatio,
                    sideActions: sideActions,
                    actionWidth: actionColumnWidth,
                    actionVPadding: actionVPadding,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                child: _grid(
                  spacing: gridSpacing,
                  aspectRatio: _preferredAspectRatio,
                  compactButtons: false,
                  disabled: dartCount >= 3,
                ),
              ),
            if (!sideActions) ...[
              SizedBox(height: gapBeforeActions),
              // Miss | Bull | Fertig
              Padding(
                padding:
                    EdgeInsets.fromLTRB(_sidePadding, 0, _sidePadding, bottomPad),
                child: SizedBox(
                  height: widget.fillHeight
                      ? (constraints.maxHeight * _actionRowHeightFactor)
                          .clamp(_minActionRowHeight, _maxActionRowHeight)
                          .toDouble()
                      : null,
                  child: _actions(
                    vertical: false,
                    verticalPadding: actionVPadding,
                    gridSpacing: gridSpacing,
                  ),
                ),
              ),
            ] else
              SizedBox(height: bottomPad),
          ],
        );

        final sized = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.fillHeight ? 760 : 500),
            child: column,
          ),
        );

        // The fitted column already ends exactly at the bottom of its box. Only the
        // preferred layout can outgrow the space it was given, so only it scrolls.
        if (fitted) return sized;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: sized,
          ),
        );
      },
    );
  }
}

/// One label of the modifier switch, kept on a single line at whatever width
/// the pane leaves it.
class _SegmentLabel extends StatelessWidget {
  final String text;

  const _SegmentLabel(this.text);

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );
}

// ── Dart progress row ────────────────────────────────────────────────────────

/// The three-dart progress strip with undo/redo buttons shown above the grid.
///
/// [compact] lays each slot out on one line instead of three, which is the
/// cheapest 25 dp a short screen can give back to the number grid. [scale] does
/// the opposite where a pane has height to spare.
class _DartProgressRow extends StatelessWidget {
  final List<DartEntry> darts;
  final bool isNegative;
  final bool canUndo;
  final bool canRedo;
  final bool compact;
  final double scale;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const _DartProgressRow({
    required this.darts,
    required this.isNegative,
    required this.canUndo,
    required this.canRedo,
    required this.compact,
    required this.onUndo,
    required this.onRedo,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(10, compact ? 6 : 8, 10, 0),
      padding: EdgeInsets.fromLTRB(
          6, (compact ? 4 : 5) * scale, 4, (compact ? 4 : 5) * scale),
      decoration: BoxDecoration(
        color: isNegative ? cs.errorContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Undo button
          _UndoRedoBtn(
            icon: Icons.undo_rounded,
            enabled: canUndo,
            scale: scale,
            onTap: onUndo,
          ),
          // Three dart slots
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: _DartSlot(
                index: i,
                entry: i < darts.length ? darts[i] : null,
                isActive: i == darts.length,
                isNegative: isNegative,
                compact: compact,
                scale: scale,
              ),
            ),
            if (i < 2)
              Container(
                width: 1,
                height: (compact ? 18 : 26) * scale,
                color: cs.outlineVariant,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
          // Redo button
          _UndoRedoBtn(
            icon: Icons.redo_rounded,
            enabled: canRedo,
            scale: scale,
            onTap: onRedo,
          ),
        ],
      ),
    );
  }
}

/// A small undo or redo icon button, dimmed when disabled.
class _UndoRedoBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final double scale;
  final VoidCallback onTap;

  const _UndoRedoBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
          child: Icon(
            icon,
            size: 20 * scale,
            color: enabled
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

// ── Dart slot ────────────────────────────────────────────────────────────────

/// One of the three dart slots in the progress strip, showing the thrown dart's
/// label and points or a placeholder for the active/empty slot.
///
/// [compact] drops the points the dart scored and puts what is left on a single
/// line. The score itself is not lost to the player: the card above counts down
/// with every dart.
class _DartSlot extends StatelessWidget {
  final int index;
  final DartEntry? entry;
  final bool isActive;
  final bool isNegative;
  final bool compact;
  final double scale;

  const _DartSlot({
    required this.index,
    this.entry,
    required this.isActive,
    required this.isNegative,
    required this.compact,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Color accent = isNegative
        ? cs.onErrorContainer
        : (isActive ? cs.primary : cs.onSurfaceVariant);
    final valueColor = entry != null
        ? (entry!.field == 0 ? cs.error : cs.onSurface)
        : accent;

    if (compact) {
      // Scaled down rather than wrapped: a long label at a large text scale
      // must not push the row onto a second line, which is what this layout
      // exists to avoid.
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dart ${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent.withValues(alpha: isActive ? 1.0 : 0.55),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              entry?.label ?? (isActive ? '▶' : '—'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
    }

    /// The phone size of [style], grown by [scale].
    TextStyle? sized(TextStyle? style) =>
        style?.copyWith(fontSize: (style.fontSize ?? 12) * scale);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Dart ${index + 1}',
          style: sized(theme.textTheme.labelSmall)?.copyWith(
            color: accent.withValues(alpha: isActive ? 1.0 : 0.55),
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        SizedBox(height: 1 * scale),
        Text(
          entry?.label ?? (isActive ? '▶' : '—'),
          style: sized(theme.textTheme.titleSmall)?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        Text(
          entry != null ? '+${entry!.score}' : ' ',
          style: sized(theme.textTheme.labelSmall)
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Field button ─────────────────────────────────────────────────────────────

/// A single number button (1-20) in the grid, colored by the active modifier
/// and showing the resulting score for doubles/triples.
class _FieldButton extends StatelessWidget {
  final int field;
  final int modifier;
  final bool disabled;
  final bool compact;
  /// How much larger than on a phone the label renders, following the size of
  /// the button itself.
  final double scale;
  final VoidCallback onTap;

  const _FieldButton({
    required this.field,
    required this.modifier,
    required this.disabled,
    this.compact = false,
    this.scale = 1.0,
    required this.onTap,
  });

  /// Background color for the current modifier and disabled state.
  Color _bg(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (disabled) return cs.surfaceContainerLow;
    return switch (modifier) {
      2 => cs.secondaryContainer,
      3 => tripleContainerColor(context),
      _ => cs.surfaceContainerHigh,
    };
  }

  /// Foreground color for the current modifier and disabled state.
  Color _fg(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (disabled) return cs.onSurface.withValues(alpha: 0.35);
    return switch (modifier) {
      2 => cs.onSecondaryContainer,
      3 => onTripleContainerColor(context),
      _ => cs.onSurface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final prefix = modifier == 2 ? 'D' : modifier == 3 ? 'T' : '';

    final score = field * modifier;
    final notation = '$prefix$field';

    return Material(
      color: _bg(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: disabled ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (compact)
              // Compact: single line: notation (e.g. T20) or just the number
              Text(
                modifier > 1 ? notation : '$field',
                style: t.titleMedium?.copyWith(
                  fontSize: (t.titleMedium?.fontSize ?? 16) * scale,
                  fontWeight: FontWeight.bold,
                  color: _fg(context),
                ),
              )
            else ...[
              // Normal: field number + score for doubles/triples
              Text(
                '$field',
                style: t.titleMedium?.copyWith(
                  fontSize: (t.titleMedium?.fontSize ?? 16) * scale,
                  fontWeight: FontWeight.bold,
                  color: _fg(context),
                ),
              ),
              if (modifier > 1)
                Text(
                  '$score',
                  style: t.labelSmall?.copyWith(
                    fontSize: (t.labelSmall?.fontSize ?? 11) * scale,
                    color: _fg(context).withValues(alpha: 0.65),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

/// A labeled icon button used for the Miss / Bull row below the grid.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final bool disabled;
  final double verticalPadding;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.disabled,
    this.verticalPadding = 11,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final effectiveColor = disabled ? cs.surfaceContainerLow : color;
    final effectiveFg = disabled ? cs.onSurface.withValues(alpha: 0.35) : textColor;

    return Material(
      color: effectiveColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            // Given a height rather than taking one from its content, the
            // button reads its size off that: label and icon in the middle
            // rather than at the top edge, and both grown to match.
            final tall = box.hasBoundedHeight && box.maxHeight > 64;
            final scale =
                tall ? (box.maxHeight / 54).clamp(1.0, 1.9).toDouble() : 1.0;

            return Padding(
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Icon(icon, size: 17 * scale, color: effectiveFg),
                  SizedBox(height: 2 * scale),
                  // Scaled down rather than wrapped: the widest label is
                  // "Bull (50)", and a second line is what pushed this button
                  // past its own height.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: t.labelSmall?.copyWith(
                        fontSize: (t.labelSmall?.fontSize ?? 11) * scale,
                        color: effectiveFg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
