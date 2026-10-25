import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../providers/checkout_ladder_provider.dart';
import '../utils/player_label.dart';
import 'ladder_icon.dart';
import 'stat_row.dart';

/// The result of a Checkout Ladder game, one card per slot, shared by the
/// post-game summary and the history detail so the two read the same.
///
/// The winner of a race comes first, then the slots that checked the target
/// in fewer attempts, then the higher ladders.
class CheckoutLadderResultCards extends StatelessWidget {
  final List<CheckoutLadderSlotState> slots;
  /// The slot that won the race, null in training.
  final int? winnerIndex;

  const CheckoutLadderResultCards({
    super.key,
    required this.slots,
    required this.winnerIndex,
  });

  @override
  Widget build(BuildContext context) {
    final order = [for (var i = 0; i < slots.length; i++) i]
      ..sort((a, b) {
        if (a == winnerIndex) return -1;
        if (b == winnerIndex) return 1;
        final ra = slots[a].ladder.reachedTargetAt ?? 1 << 30;
        final rb = slots[b].ladder.reachedTargetAt ?? 1 << 30;
        if (ra != rb) return ra.compareTo(rb);
        final ha = slots[a].ladder.highestChecked ?? 0;
        final hb = slots[b].ladder.highestChecked ?? 0;
        if (ha != hb) return hb.compareTo(ha);
        return slots[b].position.number.compareTo(slots[a].position.number);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in order)
          _SlotResultCard(slot: slots[i], isWinner: i == winnerIndex),
      ],
    );
  }
}

/// The numbers of one slot: where it ended, how high it got and how it got
/// there.
class _SlotResultCard extends StatelessWidget {
  final CheckoutLadderSlotState slot;
  final bool isWinner;
  const _SlotResultCard({required this.slot, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    final l      = context.l10n;
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;
    final ladder = slot.ladder;
    final rate   = ladder.checkRate;
    final perCheck = ladder.dartsPerCheck;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isWinner)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.emoji_events_rounded,
                        size: 20, color: cs.primary),
                  ),
                Expanded(
                  child: Text(
                    slot.label(l),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isWinner ? cs.primary : null,
                    ),
                  ),
                ),
              ],
            ),
            if (slot.isTeamSlot)
              Text(
                slot.players.labels(l, ' & '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 4),
            StatRow(
              label: l.ladderHighestChecked,
              value: ladder.highestChecked?.toString() ?? '—',
            ),
            StatRow(
              label: l.ladderEndedOn,
              value: slot.position.completed
                  ? l.ladderCompleted
                  : '${slot.position.number}',
            ),
            StatRow(
              label: l.ladderChecksAttempts,
              value: '${ladder.checks} / ${ladder.attemptsCompleted}',
            ),
            StatRow(
              label: l.ladderCheckRate,
              value: rate == null ? '—' : '${(rate * 100).round()} %',
            ),
            StatRow(
              label: l.ladderDartsPerCheck,
              value: perCheck == null ? '—' : perCheck.toStringAsFixed(1),
            ),
            StatRow(label: l.ladderSafehouses, value: '${ladder.safehouses}'),
            StatRow(label: l.ladderDrops, value: '${ladder.drops}'),
            StatRow(label: l.ladderBusts, value: '${ladder.busts}'),
            StatRow(label: l.dartsThrown, value: '${ladder.darts}'),
          ],
        ),
      ),
    );
  }
}

/// The banner over a Checkout Ladder result: the winner of a race, or how high
/// a training alone got. Null where neither applies, a training of several.
Widget? checkoutLadderBanner(
  BuildContext context,
  List<CheckoutLadderSlotState> slots,
  int? winnerIndex,
) {
  final l     = context.l10n;
  final theme = Theme.of(context);
  final cs    = theme.colorScheme;

  final String text;
  if (winnerIndex != null) {
    text = l.ladderWinner(slots[winnerIndex].label(l));
  } else if (slots.length == 1) {
    final highest = slots.single.ladder.highestChecked;
    if (highest == null) return null;
    text = '${l.ladderHighestChecked}: $highest';
  } else {
    return null;
  }

  return Center(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: winnerIndex != null
              ? Icon(Icons.emoji_events_rounded, size: 52, color: cs.primary)
              : LadderIcon(size: 52, color: cs.primary),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
