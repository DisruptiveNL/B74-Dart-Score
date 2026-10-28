import '../models/around_the_clock_game.dart';

/// Where a slot stands in Around the Clock: its index into
/// [aroundTheClockOrder] and, under full segments, the rings already hit on
/// the current number.
typedef AroundTheClockPosition = ({int progress, Set<int> hitSegments});

/// The one rule of Around the Clock: where [position] moves to when a dart
/// lands on [field] with [multiplier] under [variant].
///
/// The provider applies it live and on replay, and the live statistics replay
/// it to tell a hit from a miss, so that a dart advances in exactly one
/// place. Basic advances on any ring of the number; full segments collect the
/// single, the double and the triple (the bull has no triple) before moving
/// on; skip rules jump by the ring and let the bull skip the current number.
AroundTheClockPosition applyAroundTheClockDart({
  required AroundTheClockVariant variant,
  required AroundTheClockPosition position,
  required int field,
  required int multiplier,
}) {
  final target =
      aroundTheClockOrder[position.progress.clamp(
        0,
        aroundTheClockOrder.length - 1,
      )];
  var progress = position.progress;
  var hitSegments = position.hitSegments;

  if (field == target) {
    switch (variant) {
      case AroundTheClockVariant.basic:
        progress += 1;
      case AroundTheClockVariant.fullSegments:
        final required = target == 25 ? const [1, 2] : const [1, 2, 3];
        hitSegments = {...hitSegments, multiplier};
        if (hitSegments.containsAll(required)) {
          progress += 1;
          hitSegments = const {};
        }
      case AroundTheClockVariant.skipRules:
        progress += switch (multiplier) {
          3 => 3,
          2 => 2,
          _ => 1,
        };
    }
  } else if (variant == AroundTheClockVariant.skipRules &&
      field == 25 &&
      target != 25) {
    // Bull's Eye joker: skip the current field, advance by one.
    progress += 1;
  }

  return (
    progress: progress.clamp(0, aroundTheClockOrder.length),
    hitSegments: hitSegments,
  );
}

/// The darts of one slot in Around the Clock, three to a visit, oldest first.
List<List<AroundTheClockThrow>> aroundTheClockVisits(
  List<AroundTheClockThrow> throws,
) => [
  for (var i = 0; i < throws.length; i += 3)
    throws.sublist(i, i + 3 > throws.length ? throws.length : i + 3),
];

/// What one slot's darts add up to in Around the Clock, for the live info,
/// found by replaying them through [applyAroundTheClockDart].
class AroundTheClockStats {
  final int darts;

  /// Darts that moved the slot on: a number advanced, a ring collected, or a
  /// joker played.
  final int hits;

  /// Numbers completed.
  final int progress;

  /// Most hits in a row.
  final int longestStreak;

  /// Under skip rules, numbers passed without being hit.
  final int fieldsSkipped;

  /// Per visit, whether each dart was a hit, oldest visit first.
  final List<List<bool>> visitHits;

  const AroundTheClockStats({
    required this.darts,
    required this.hits,
    required this.progress,
    required this.longestStreak,
    required this.fieldsSkipped,
    required this.visitHits,
  });

  /// Darts spent per number completed.
  double get dartsPerTarget => progress == 0 ? 0 : darts / progress;

  /// The share of darts that moved the slot on, 0 to 1.
  double get hitRate => darts == 0 ? 0 : hits / darts;

  /// Replays [throws] of one slot under [variant].
  factory AroundTheClockStats.of(
    List<AroundTheClockThrow> throws,
    AroundTheClockVariant variant,
  ) {
    AroundTheClockPosition position = (progress: 0, hitSegments: const {});
    var hits = 0, streak = 0, longest = 0, onTarget = 0;
    final hitFlags = <bool>[];

    for (final t in throws) {
      final next = applyAroundTheClockDart(
        variant: variant,
        position: position,
        field: t.field,
        multiplier: t.multiplier,
      );
      final target =
          aroundTheClockOrder[position.progress.clamp(
            0,
            aroundTheClockOrder.length - 1,
          )];
      final hit =
          next.progress > position.progress ||
          next.hitSegments.length > position.hitSegments.length;
      if (hit && t.field == target) onTarget++;
      hitFlags.add(hit);
      if (hit) {
        hits++;
        streak++;
        if (streak > longest) longest = streak;
      } else {
        streak = 0;
      }
      position = next;
    }

    final visitHits = [
      for (var i = 0; i < hitFlags.length; i += 3)
        hitFlags.sublist(i, i + 3 > hitFlags.length ? hitFlags.length : i + 3),
    ];
    final skipped = variant == AroundTheClockVariant.skipRules
        ? (position.progress - onTarget).clamp(0, aroundTheClockOrder.length)
        : 0;

    return AroundTheClockStats(
      darts: throws.length,
      hits: hits,
      progress: position.progress,
      longestStreak: longest,
      fieldsSkipped: skipped,
      visitHits: visitHits,
    );
  }
}
