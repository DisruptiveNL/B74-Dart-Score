import '../models/dart_throw.dart';
import '../models/game.dart';
import 'placement.dart';

/// Who won a finished X01 game, read back off the throws it left behind.
///
/// No column records a winner: a game row knows when it was finished, not by
/// whom. Deciding it therefore means reading the throws, and it is decided in
/// this one place so the history summary and the lifetime statistics cannot
/// drift into naming two different winners for the same game.

/// The player who threw the last checkout in [throws], or null when nobody
/// finished a leg.
///
/// In an ordinary game that is the player who won it: the game ends the moment
/// somebody takes the deciding leg, so the last leg won is the match won.
int? lastCheckoutPlayerId(List<DartThrow> throws) {
  DartThrow? last;
  for (final t in throws) {
    if (t.bust || t.remainingAfter != 0) continue;
    if (last == null || _isAfter(t, last)) last = t;
  }
  return last?.playerId;
}

/// The players on the side that won [game], given every throw of it and the
/// [participantIds] it was played by, in turn order.
///
/// A side is a team in a team game and a single player otherwise, so a team
/// game hands back every member of the winning team rather than only the one
/// who hit the double.
///
/// [participantIds] is the game's line-up, not the players who happen to appear
/// in [throws]. A placement game is scored against how many sides took part, and
/// a side without a single dart is still one of them: counting the sides off the
/// throws drops that side from the ranking and scores every other side against
/// one participant too few. Only placement mode reads it, every other game is
/// decided by its last checkout, but it is asked for either way so no caller has
/// to know which rule applies.
///
/// An unfinished or undecided game hands back an empty set.
Set<int> winningPlayerIds(
  Game game,
  List<DartThrow> throws, {
  required Iterable<int> participantIds,
}) {
  if (throws.isEmpty) return const {};

  final teams = game.teams;
  if (teams == null || teams.isEmpty) {
    final winner = game.placementMode
        ? _bestPlaced(
            _groupBy(throws, (t) => t.playerId, slots: participantIds),
          )
        : lastCheckoutPlayerId(throws);
    return winner == null ? const {} : {winner};
  }

  final sideOf = <int, int>{};
  for (var i = 0; i < teams.length; i++) {
    for (final id in teams[i].playerIds) {
      sideOf[id] = i;
    }
  }

  int? side;
  if (game.placementMode) {
    final bySide = _groupBy(
      throws.where((t) => sideOf.containsKey(t.playerId)),
      (t) => sideOf[t.playerId]!,
      slots: [for (var i = 0; i < teams.length; i++) i],
    );
    side = _bestPlaced(bySide);
  } else {
    final last = lastCheckoutPlayerId(throws);
    side = last == null ? null : sideOf[last];
  }
  return side == null ? const {} : teams[side].playerIds.toSet();
}

/// The side that comes first in a placement game, or null when there is
/// nothing to rank.
///
/// Placement mode is not decided by who finished last: there every side checks
/// out every leg, and the game is played for points. The order is
/// [placementOrder]'s, the same one the live game names its winner by and the
/// final ranking card lists its rows in.
int? _bestPlaced(Map<int, List<DartThrow>> throwsById) {
  if (throwsById.isEmpty) return null;

  final maxLeg = throwsById.values
      .expand((t) => t)
      .map((t) => t.leg)
      .fold(0, (a, b) => b > a ? b : a);
  return placementOrderFromThrows(throwsById, maxLeg, 1).first;
}

/// Groups [throws] under the key [keyOf] gives each of them, over the full set
/// of [slots]: a slot without a throw of its own is present with an empty list
/// rather than absent, which is what keeps the participant count right.
Map<int, List<DartThrow>> _groupBy(
  Iterable<DartThrow> throws,
  int Function(DartThrow) keyOf, {
  required Iterable<int> slots,
}) {
  final grouped = <int, List<DartThrow>>{
    for (final slot in slots) slot: <DartThrow>[],
  };
  for (final t in throws) {
    grouped.putIfAbsent(keyOf(t), () => []).add(t);
  }
  return grouped;
}

/// Whether [a] was thrown after [b], falling back to the insertion order when
/// two throws carry the same timestamp.
bool _isAfter(DartThrow a, DartThrow b) {
  final byTime = a.thrownAt.compareTo(b.thrownAt);
  if (byTime != 0) return byTime > 0;
  return (a.id ?? 0) > (b.id ?? 0);
}
