import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/checkout_ladder_provider.dart';
import '../utils/game_labels.dart';
import '../utils/player_label.dart';
import '../widgets/checkout_ladder_result.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import 'checkout_ladder_screen.dart';

/// Post-game summary for the Checkout Ladder: the winner of a race, or how
/// high a training got, then each slot's numbers.
class CheckoutLadderSummaryScreen extends StatelessWidget {
  const CheckoutLadderSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CheckoutLadderProvider>();
    final game = provider.game!;
    final slots = provider.slots;
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.ladderSummaryTitle)),
      body: SummaryBody(
        header: checkoutLadderBanner(context, slots, provider.winnerIndex),
        top: 24,
        bottom: 24,
        result: [
          GameInfoCard(
            rows: [
              (l.gameLabel, l.modeCheckoutLadderName),
              ...checkoutLadderSettingRows(l, game),
              (l.startingOrder, startingOrderLabel(l, game.startingOrder)),
            ],
          ),
        ],
        details: [
          CheckoutLadderResultCards(
            slots: slots,
            winnerIndex: provider.winnerIndex,
          ),
        ],
        actions: [
          FilledButton.icon(
            onPressed: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
            label: Text(l.backToHome),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          RematchButton(
            modeName: l.modeCheckoutLadderName,
            details: checkoutLadderSettingRows(l, game),
            slots: slots
                .map(
                  (s) => s.isTeamSlot
                      ? RematchSlot.team(
                          s.label(l),
                          s.players
                              .map((p) => RematchSlot.player(p.label(l)))
                              .toList(),
                        )
                      : RematchSlot.player(s.label(l)),
                )
                .toList(),
            onRematch: () => provider.startRematch(
              game,
              slots.expand((s) => s.players).toList(),
            ),
            destination: (_) => const CheckoutLadderScreen(),
          ),
        ],
      ),
    );
  }
}
