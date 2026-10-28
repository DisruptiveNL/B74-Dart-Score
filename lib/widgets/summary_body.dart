import 'package:flutter/material.dart';

import '../utils/layout.dart';

/// The body of a post-game summary: how the game ended on one side, the numbers
/// behind it on the other, and the way out under both.
///
/// A phone, and a tablet too narrow to divide, get the single column the four
/// summaries have always been: [header], [result], [details] in that order, at
/// the one spacing the cards themselves carry.
///
/// The divider stands in the middle and stays there. Both columns hold cards of
/// the same kind, so there is nothing to rebalance between them.
class SummaryBody extends StatelessWidget {
  /// Who won, which belongs to the whole screen rather than to one half of it:
  /// on two columns it stands over both, upright it opens the column.
  final Widget? header;

  /// How the game ended: the winner, the rematch, and what was played.
  final List<Widget> result;

  /// The numbers behind it: the per player cards and whatever a mode keeps
  /// beside them, which is the longer of the two columns.
  final List<Widget> details;

  /// What the screen offers once the game is read: the way home and the way
  /// into the next game. They stand side by side on a bar of their own, which
  /// stays put while everything above it scrolls, so the two things a player
  /// reaches for are never a page away.
  final List<Widget> actions;

  /// Padding above and below the columns. X01 sits closer to its app bar than
  /// the three modes whose summary opens on a winner banner.
  final double top;
  final double bottom;

  const SummaryBody({
    super.key,
    this.header,
    required this.result,
    required this.details,
    required this.actions,
    this.top = 16,
    this.bottom = 16,
  });

  /// Whether a summary on this screen stands in two columns.
  ///
  /// Public because a screen has to know before it hands its cards over: what
  /// belongs beside the numbers on a tablet may belong right under the winner
  /// in a single column.
  static bool twoColumnsOn(BuildContext context) =>
      isTabletLayout(context) &&
      fitsTwoPanes(MediaQuery.sizeOf(context).width, kMinSummaryPaneWidth);

  @override
  Widget build(BuildContext context) {
    final twoColumns = twoColumnsOn(context);

    return Column(
      children: [
        if (header != null && twoColumns)
          Padding(
            // Standing over both columns, it needs room under it, or the
            // divider reads as if it came out of the banner.
            padding: EdgeInsets.fromLTRB(16, top, 16, 16),
            child: header,
          ),
        Expanded(
          child: twoColumns
              ? SidePaneLayout(
                  side: InputSide.left,
                  minPaneWidth: kMinSummaryPaneWidth,
                  primary: ListView(
                    padding: EdgeInsets.fromLTRB(16, top, 8, bottom),
                    children: result,
                  ),
                  secondary: ListView(
                    padding: EdgeInsets.fromLTRB(8, top, 16, bottom),
                    children: details,
                  ),
                )
              : ListView(
                  padding: contentPadding(
                    context,
                    top: top,
                    bottom: bottom,
                    innerH: 16,
                  ),
                  children: [
                    if (header != null) ...[
                      header!,
                      const SizedBox(height: 20),
                    ],
                    // No gap between the two blocks: every card carries its
                    // own margin, and a second one here would set the last
                    // card of one block further from the next than any two
                    // cards inside a block.
                    ...result,
                    ...details,
                  ],
                ),
        ),
        SummaryActionBar(actions: actions),
      ],
    );
  }
}

/// The bar a summary ends on: the same background as the page it sits under,
/// parted from it by a hairline rather than by a shadow, because it is where
/// the page stops rather than something laid over it.
///
/// Used on its own by the history details, which have one thing to offer
/// rather than two but end the same way.
class SummaryActionBar extends StatelessWidget {
  /// The buttons, side by side and equally wide.
  final List<Widget> actions;

  const SummaryActionBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tablet = isTabletLayout(context);

    // The room around the buttons is fixed, and the system's own inset only
    // ever adds to it underneath, never decides it.
    //
    // It used to be the other way round: almost the whole gap was the home
    // indicator's inset, halved. That reads correctly on an iPhone by
    // coincidence and nowhere else. Android reports no bottom inset here at
    // all, whether it is driven by gestures or by three buttons, which left
    // three pixels around the buttons.
    final gap = tablet ? 28.0 : 20.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        // Underneath, whichever is larger: the gap, or the room the system
        // asks for. A home indicator is drawn inside that room rather than
        // below it, so the two do not add up to a bottom heavy bar.
        minimum: EdgeInsets.symmetric(vertical: gap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            // Side by side and equally wide, and no wider together than they
            // can still be read as two buttons rather than as a toolbar.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
