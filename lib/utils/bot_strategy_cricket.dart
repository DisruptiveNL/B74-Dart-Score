import '../models/cricket_game.dart';
import 'dartboard_geometry.dart';

/// Where a bot aims its next dart in Cricket.
///
/// [ownMarks] and [opponentMarks] hold each slot's marks per field, capped at
/// three; [ownScore] and [opponentScores] the points. The choice, in order:
/// 1. Behind on points with a field of its own closed that an opponent still
///    has open: score there, on the highest such field. Behind means fewer
///    points in normal Cricket and more in cut-throat, where points are the
///    thing to avoid. Simple scoring has no points, so this never applies.
/// 2. A field of its own still open: close it, the highest first.
/// 3. Everything closed but not ahead: the only move left is to score, on
///    the highest field an opponent has open.
/// 4. Nothing open anywhere: the bull, for want of a better target.
///
/// A number is aimed at its triple by a bot that [aimTriples], at the fat
/// single otherwise; under simple scoring every hit is one mark, so the
/// single is always the target. The bull is always aimed at its centre.
BoardHit cricketTarget({
  required Map<int, int> ownMarks,
  required List<Map<int, int>> opponentMarks,
  required int ownScore,
  required List<int> opponentScores,
  required CricketVariant variant,
  required CricketScoringMode scoring,
  required bool aimTriples,
}) {
  bool ownClosed(int f) => (ownMarks[f] ?? 0) >= 3;
  bool anyOpponentOpen(int f) => opponentMarks.any((m) => (m[f] ?? 0) < 3);

  final behind =
      scoring == CricketScoringMode.standard &&
      opponentScores.isNotEmpty &&
      (variant == CricketVariant.cutThroat
          ? ownScore > opponentScores.reduce((a, b) => a < b ? a : b)
          : ownScore < opponentScores.reduce((a, b) => a > b ? a : b));

  int? scoringField() {
    for (final f in cricketFields) {
      if (ownClosed(f) && anyOpponentOpen(f)) return f;
    }
    return null;
  }

  int? openField() {
    for (final f in cricketFields) {
      if (!ownClosed(f)) return f;
    }
    return null;
  }

  final field =
      (behind ? scoringField() : null) ?? openField() ?? scoringField() ?? 25;

  return _aimAt(field, aimTriples && scoring == CricketScoringMode.standard);
}

/// The ring to throw at on [field]: the centre of the bull, otherwise the
/// triple or the fat single.
BoardHit _aimAt(int field, bool triple) {
  if (field == 25) return (field: 25, multiplier: 2);
  return (field: field, multiplier: triple ? 3 : 1);
}
