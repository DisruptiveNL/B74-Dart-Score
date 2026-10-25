import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/checkout_ladder_game.dart';
import '../models/player.dart';
import '../providers/checkout_ladder_provider.dart';
import '../utils/game_labels.dart';
import '../utils/layout.dart';
import '../utils/player_label.dart';
import '../widgets/checkout_ladder_result.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import 'checkout_ladder_screen.dart';

/// Detailed view of a finished Checkout Ladder game from history, rebuilt by
/// replaying its stored darts through a fresh provider.
class CheckoutLadderHistorySummaryScreen extends StatefulWidget {
  final CheckoutLadderGame game;
  final List<Player> players;

  /// Whether this sits inside a pane that brings its own title bar, as the
  /// master detail layout of the history does on a tablet. Embedded it renders
  /// its content alone, without a screen around it.
  final bool embedded;

  const CheckoutLadderHistorySummaryScreen({
    super.key,
    required this.game,
    required this.players,
    this.embedded = false,
  });

  @override
  State<CheckoutLadderHistorySummaryScreen> createState() =>
      _CheckoutLadderHistorySummaryScreenState();
}

class _CheckoutLadderHistorySummaryScreenState
    extends State<CheckoutLadderHistorySummaryScreen> {
  /// Started once and kept, not started again on every build: a pane whose
  /// divider is being dragged rebuilds on every frame, and a read begun in
  /// `build` would fall back to its spinner for the length of the drag.
  late Future<CheckoutLadderProvider> _future = _load();

  @override
  void didUpdateWidget(CheckoutLadderHistorySummaryScreen oldWidget) {
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
          child: FutureBuilder<CheckoutLadderProvider>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final provider = snap.data;
              if (provider == null) {
                return Center(child: Text(context.l10n.noThrowData));
              }
              return _Body(
                  game: widget.game, players: widget.players, provider: provider);
            },
          ),
        ),
      ),
    );
  }

  /// Puts the screen around [content], or hands it over bare when this view is
  /// embedded in a pane that already has a title bar of its own.
  Widget _wrap(BuildContext context, Widget content) => widget.embedded
      ? content
      : Scaffold(
          appBar: AppBar(
            title: Text(DateFormat('dd.MM.yy  HH:mm').format(widget.game.createdAt)),
          ),
          body: content,
        );

  /// Replays the game's darts through a standalone provider, so the history
  /// reads the board the engine builds rather than a second reading of it.
  Future<CheckoutLadderProvider> _load() async {
    final provider = CheckoutLadderProvider();
    await provider.resumeGame(widget.game, widget.players);
    return provider;
  }
}

/// Renders the replayed game: its settings, then each slot's numbers.
class _Body extends StatelessWidget {
  final CheckoutLadderGame game;
  final List<Player> players;
  final CheckoutLadderProvider provider;

  const _Body({
    required this.game,
    required this.players,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final l      = context.l10n;
    final slots  = provider.slots;
    final banner = checkoutLadderBanner(context, slots, provider.winnerIndex);

    final rematch = RematchButton(
      modeName: l.modeCheckoutLadderName,
      details: checkoutLadderSettingRows(l, game),
      slots: slots
          .map((s) => s.isTeamSlot
              ? RematchSlot.team(s.label(l),
                  s.players.map((p) => RematchSlot.player(p.label(l))).toList())
              : RematchSlot.player(s.label(l)))
          .toList(),
      onRematch: () => context
          .read<CheckoutLadderProvider>()
          .startRematch(game, players),
      destination: (_) => const CheckoutLadderScreen(),
    );

    final list = ListView(
      // Fixed rather than measured: on a tablet this screen is rendered inside
      // a pane, and contentPadding measures the window.
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        if (banner != null) ...[banner, const SizedBox(height: 16)],
        GameInfoCard(dense: true, rows: [
          (l.gameLabel, l.modeCheckoutLadderName),
          ...checkoutLadderSettingRows(l, game),
          (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
        ]),
        CheckoutLadderResultCards(
            slots: slots, winnerIndex: provider.winnerIndex),
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
