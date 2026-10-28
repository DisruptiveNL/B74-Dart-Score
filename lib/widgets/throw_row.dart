import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/dart_throw.dart';
import '../utils/game_labels.dart';

/// One recorded visit as a list entry, shared by the throw log of a finished
/// game and the recent-throws list of the lifetime statistics.
///
/// Both lists answer the same question, what happened in this visit, and used
/// to answer it in two different shapes. The layout is a grid of four slots
/// over two lines, each line spanning the full width:
///
/// ```
/// [ 140 ]  Anna                        301 → 161
///          Set 2 · Leg 1 · T20 T20 S19    3 Darts
/// ```
///
/// The remaining score is shown as a step from before to after rather than as
/// the resulting number alone: a visit is only readable next to what it was
/// thrown at. Where the individual darts were recorded they are named as well,
/// which is what turns a bare 140 into a story.
class ThrowRow extends StatelessWidget {
  /// The visit to render.
  final DartThrow t;

  /// Who threw it, for a log that mixes several throwers. Null in a list that
  /// belongs to one player anyway.
  final String? playerName;

  /// Whether the leg and set of the visit are worth naming. False for lists
  /// whose entries come from different games, where the position says nothing.
  final bool showPosition;

  /// Whether to name the set as well; pointless in a single-set game.
  final bool showSet;

  /// When the visit was thrown, for a list that spans several sessions. Null
  /// inside a single game, where every entry shares the evening.
  final DateTime? thrownAt;

  const ThrowRow({
    super.key,
    required this.t,
    this.playerName,
    this.showPosition = true,
    this.showSet = false,
    this.thrownAt,
  });

  /// Width of the score pill plus the gap behind it, the offset the second
  /// line starts at so it lines up with the first line's text.
  static const _pillWidth = 48.0;
  static const _pillGap = 10.0;

  /// Names the individual darts of the visit, `T20 · T20 · S19`, or null when
  /// the visit was entered as a plain score and the darts were never recorded.
  static String? _dartsLabel(AppLocalizations l, String? hitsJson) {
    if (hitsJson == null) return null;
    try {
      final hits = jsonDecode(hitsJson) as List<dynamic>;
      if (hits.isEmpty) return null;
      return hits
          .map((h) => segmentLabel(l, h['f'] as int, h['m'] as int))
          .join(' · ');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final progression = '${t.remainingBefore} → ${t.remainingAfter}';
    final darts = l.dartsN(t.dartsUsed);
    final position = showPosition
        ? (showSet
              ? '${l.setLabel(t.set)} · ${l.legLabel(t.leg)}'
              : l.legLabel(t.leg))
        : null;
    final when = thrownAt == null
        ? null
        : DateFormat('dd.MM  HH:mm').format(thrownAt!);
    final hits = _dartsLabel(l, t.hitsJson);

    // Slot assignment. A log names the thrower first and reads the score step
    // on the right; a single player's list has no name to show, so the step
    // moves up front and the right of the line goes to the date.
    final main = playerName ?? progression;
    final trailing = playerName != null ? progression : (when ?? darts);
    final sub = [?position, ?hits].join('  ·  ');
    final subTrailing = playerName != null || when != null ? darts : null;

    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ScorePill(t: t),
              const SizedBox(width: _pillGap),
              Expanded(
                child: Text(
                  main,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty || subTrailing != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: _pillWidth + _pillGap),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ),
                  if (subTrailing != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      subTrailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The visit's score in front of the row, tinted by how big it was so a page
/// of throws shows its high visits at a glance.
class _ScorePill extends StatelessWidget {
  final DartThrow t;
  const _ScorePill({required this.t});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (background, foreground) = t.bust
        ? (cs.errorContainer, cs.onErrorContainer)
        : t.score >= 140
        ? (cs.tertiaryContainer, cs.onTertiaryContainer)
        : t.score >= 100
        ? (cs.secondaryContainer, cs.onSecondaryContainer)
        : (cs.surfaceContainerHighest, cs.onSurface);

    return Container(
      width: ThrowRow._pillWidth,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t.bust ? context.l10n.bust.toUpperCase() : '${t.score}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}
