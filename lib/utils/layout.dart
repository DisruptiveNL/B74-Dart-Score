import 'dart:math' show max, min;
import 'package:flutter/material.dart';

/// Screen width threshold (dp) above which tablet layout is applied.
const double kTabletBreakpoint = 600;

/// Maximum content width on tablets and large screens.
///
/// A phone width of 440 is what this used to be, which held every screen to a
/// column the size of a phone with the rest of the tablet empty beside it. A
/// line of text stops reading comfortably somewhere past 700, so this sits
/// short of that: wide enough that the screen no longer looks like a phone in
/// a box, narrow enough that a settings row does not stretch its label and its
/// value to opposite ends of the room.
const double kMaxContentWidth = 620.0;

/// Maximum width for the game screen: slightly wider to fit scoreboard
/// and input comfortably on tablets.
const double kMaxGameWidth = 500.0;

// Legacy fraction constants kept for callers that pass them explicitly.
// They are no longer used by contentMaxWidth on phones; on tablets the
// kMax* constants take effect instead.
const double kContentWidthFraction = 0.85;
const double kGameWidthFraction = 0.95;

/// Widest the live stats read comfortably. Beyond this a label and its value
/// drift so far apart that the pair stops reading as one row.
const double kStatsPaneMaxWidth = 600.0;

/// Which side of the screen the score input sits on when a second pane shares
/// it with them.
///
/// The order is not the default and never was: [kDefaultInputSide] decides
/// that, and the values are stored by name, so this list stays free to grow.
enum InputSide { right, left }

/// The side the input starts on until the player says otherwise.
const InputSide kDefaultInputSide = InputSide.left;

/// Whether the window is wide enough for the two pane layouts.
///
/// Deliberately the same rule the orientation lock in `main.dart` applies, so
/// a window that is allowed to rotate is exactly a window that gets a tablet
/// layout. Reads the shortest side, not the width, so a rotation never changes
/// the answer.
bool isTabletLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint;

/// The screens that divide themselves into two panes. Each keeps its own
/// divider position, because each divides something different.
enum SplitPane { game, history, players }

/// Share of the width the pane holding the input starts with, and the range a
/// drag of the divider may move it to.
const double kDefaultSplitFraction = 0.5;
const double kMinSplitFraction = 0.3;
const double kMaxSplitFraction = 0.7;

/// Narrowest either pane may be dragged to, whatever the share says.
///
/// A share alone is not enough of a guard: 30 percent of a small tablet leaves
/// the input with 230 dp, where the number buttons fall to 37 dp wide and the
/// stats wrap every second label. This is the point where both panes stop
/// being usable, so it is where the drag stops.
const double kMinPaneWidth = 300.0;

/// The same floor for a pane that carries the scoreboard above the input. Two
/// score cards and a checkout hint need more width than the input alone.
const double kMinGamePaneWidth = 420.0;

/// How far the text size may be taken from what the system asks for, and where
/// it starts.
///
/// A tablet is held further away than a phone, but how much further is a matter
/// of the desk, the chair and the eyes of whoever reads it, so the size is the
/// reader's to set rather than something derived from the screen. The default
/// is exactly what the system asks for, and the range reaches a little below it
/// for a large tablet that fits more than it needs and well above it for one
/// read from across the room.
const double kMinTextScale = 0.8;
const double kMaxTextScale = 1.4;
const double kDefaultTextScale = 1.0;

/// Steps the text size slider snaps to, in units of the factor. Fine enough to
/// find a size that fits, coarse enough that the same one is found again.
const double kTextScaleStep = 0.05;

/// Number of steps between [kMinTextScale] and [kMaxTextScale], for the slider
/// that has to express the same range in divisions.
int get kTextScaleDivisions =>
    ((kMaxTextScale - kMinTextScale) / kTextScaleStep).round();

/// Multiplies the text of a subtree by [factor].
///
/// For a layout that has already worked out how much bigger it may draw, where
/// [TabletTextScale] reads that from the device instead. The factor lands on
/// top of the size the system asks for rather than replacing it.
class TextScaleBy extends StatelessWidget {
  final double factor;
  final Widget child;

  const TextScaleBy({super.key, required this.factor, required this.child});

  @override
  Widget build(BuildContext context) {
    if (factor == 1.0) return child;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: _ScaledTextScaler(MediaQuery.textScalerOf(context), factor),
      ),
      child: child,
    );
  }
}

/// Multiplies a text scaler by a factor, on top of the size the system asks
/// for rather than instead of it.
class _ScaledTextScaler extends TextScaler {
  final TextScaler base;
  final double factor;

  const _ScaledTextScaler(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  // Still abstract on TextScaler, and still what a widget reads when it asks
  // for a plain factor, so it has to answer even though it is deprecated.
  @Deprecated('Superseded by scale, which TextScaler itself deprecated it for')
  @override
  double get textScaleFactor => scale(14) / 14;
}

/// Narrowest the list of a master detail layout may be dragged to. A list of
/// dates and names needs less room than what it opens, but not much less.
const double kMinListPaneWidth = 320.0;

/// Narrowest a column of the setup is worth showing.
///
/// A setup column is a stack of cards whose rows are a label beside a control,
/// so it needs about what a phone gives them. Below this the format chips wrap
/// to one per line and the legs and sets steppers stop fitting side by side.
const double kMinSetupPaneWidth = 360.0;

/// Narrowest a column of a summary is worth showing.
///
/// More than a setup column asks for: these cards carry rows of a label and a
/// number, and a throw log carries four columns of them, which start colliding
/// well before the card itself runs out of room. At this floor a tablet held
/// upright keeps its single column and only a landscape one divides.
const double kMinSummaryPaneWidth = 400.0;

/// Edge length of the target dartboard on a tablet held upright.
///
/// A phone reads the board at the width of its screen, which is also all the
/// width it has. A tablet has more width than a circle can use and more height
/// than the list under it needs, so the board takes half the height instead and
/// never more width than there is. The floor is what a phone already gave it.
double uprightTargetBoardEdge(BuildContext context) {
  final mq = MediaQuery.of(context);
  final body = mq.size.height - mq.padding.vertical - kToolbarHeight;
  return min(
    mq.size.width - 24,
    body * 0.5,
  ).clamp(kMaxGameWidth, 720).toDouble();
}

/// Whether [width] has room for two columns of [minPaneWidth] and the divider
/// between them.
///
/// A tablet is wide enough for two panes by the breakpoint long before it is
/// wide enough for two of a given kind: below this a screen is better off as
/// the single centred column a phone gets.
bool fitsTwoPanes(double width, double minPaneWidth) =>
    width >= 2 * minPaneWidth + kDividerHitWidth;

/// Width of the draggable divider between two panes. Wide enough to grab,
/// while the line drawn inside it stays hairline thin.
const double kDividerHitWidth = 16.0;

/// Identifies the divider between two panes, for tests that drag it.
const Key kPaneDividerKey = Key('pane-divider');

/// Places a pane of a given share beside a second one that takes the rest,
/// with a divider that can be dragged to rebalance the two.
///
/// The game names the sides after the input, because that is what the player
/// moves there; a screen with no input keeps the same [side] for the pane it
/// measures.
///
/// [fraction] is the share [primary] takes of the width. The divider reports a
/// new one through [onFractionChanged] while it is dragged and calls
/// [onFractionSettled] once the gesture ends, which is where a caller writes
/// the result down: a drag must not do that on every frame.
class SidePaneLayout extends StatelessWidget {
  /// The pane [fraction] measures. Sits on the chosen side.
  final Widget primary;

  /// The pane that gets whatever width [primary] leaves over.
  final Widget secondary;

  /// The side [primary] sits on.
  final InputSide side;

  /// Share of the width [primary] takes.
  final double fraction;

  /// Narrowest either pane may become, whatever [fraction] says.
  final double minPaneWidth;

  /// Called with the new share while the divider is dragged.
  final ValueChanged<double>? onFractionChanged;

  /// Called once the drag is over, with no value: the caller holds the current
  /// one already, and recomputing it here would read a width from a frame the
  /// drag has since moved past.
  final VoidCallback? onFractionSettled;

  const SidePaneLayout({
    super.key,
    required this.primary,
    required this.secondary,
    required this.side,
    this.fraction = kDefaultSplitFraction,
    this.minPaneWidth = kMinPaneWidth,
    this.onFractionChanged,
    this.onFractionSettled,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final width = paneWidthFor(
          total: total,
          fraction: fraction,
          minPaneWidth: minPaneWidth,
        );

        // A drag moves the divider itself, so the sign follows the side the
        // input is on: dragging right grows a pane on the left and shrinks one
        // on the right.
        void onDrag(double dx) {
          final delta = side == InputSide.left ? dx : -dx;
          onFractionChanged?.call((width + delta) / total);
        }

        final fixedPane = SizedBox(width: width, child: primary);
        final restPane = Expanded(child: secondary);
        final divider = _PaneDivider(
          key: kPaneDividerKey,
          onDrag: onFractionChanged == null ? null : onDrag,
          onDragEnd: onFractionSettled,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: side == InputSide.right
              ? [restPane, divider, fixedPane]
              : [fixedPane, divider, restPane],
        );
      },
    );
  }
}

/// How wide the first pane of a [SidePaneLayout] ends up, for a caller that
/// has to know before the layout runs.
///
/// The share alone does not answer it: neither pane may fall below
/// [minPaneWidth], and the divider takes its own width out of what is left, so
/// what one pane leaves the other is the rest minus that.
double paneWidthFor({
  required double total,
  required double fraction,
  required double minPaneWidth,
}) {
  // On a window too narrow for two full panes the dp floor would cross itself,
  // so it never claims more than half of what the two panes actually get: half
  // the window is already too much, because the divider is taken out of the
  // same width and the floor would then exceed what is left for the other side.
  final floor = min(minPaneWidth, (total - kDividerHitWidth) / 2);
  return (total * fraction)
      .clamp(
        max(total * kMinSplitFraction, floor),
        min(total * kMaxSplitFraction, total - floor - kDividerHitWidth),
      )
      .toDouble();
}

/// The line between two panes, and the grip that drags it.
///
/// The touch target is [kDividerHitWidth] wide because a hairline is not
/// something a finger can find; the line inside it stays one pixel.
class _PaneDivider extends StatelessWidget {
  /// Reports the horizontal movement of the drag. Null leaves the divider as a
  /// plain line.
  final ValueChanged<double>? onDrag;

  /// Reports that the drag is over.
  final VoidCallback? onDragEnd;

  const _PaneDivider({super.key, this.onDrag, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final line = Center(child: Container(width: 1, color: cs.outlineVariant));

    if (onDrag == null) {
      return SizedBox(width: kDividerHitWidth, child: line);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag!(d.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd?.call(),
        child: SizedBox(
          width: kDividerHitWidth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              line,
              // The grip, so the divider looks like something that can be moved.
              Container(
                width: 4,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Max content width in dp for the current screen.
/// On phones (< 600 dp) the full screen width is used.
/// On tablets the width is capped at [maxWidth] to preserve a phone-portrait
/// feel and avoid overly wide content columns.
double contentMaxWidth(
  BuildContext context, {
  double fraction = kContentWidthFraction, // ignored on tablets
  double maxWidth = kMaxContentWidth,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < kTabletBreakpoint) return w;
  return min(w * fraction, maxWidth);
}

/// Symmetric horizontal padding so a full-width ListView centres its content.
/// On phones the padding equals [innerH] only (no extra side margins).
EdgeInsets contentPadding(
  BuildContext context, {
  double fraction = kContentWidthFraction,
  double maxWidth = kMaxContentWidth,
  double top = 0,
  double bottom = 0,
  double innerH = 0,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < kTabletBreakpoint) {
    return EdgeInsets.fromLTRB(innerH, top, innerH, bottom);
  }
  final contentW = min(w * fraction, maxWidth);
  final side = ((w - contentW) / 2).clamp(0.0, double.infinity);
  return EdgeInsets.fromLTRB(side + innerH, top, side + innerH, bottom);
}
