import 'dart:convert';

import 'b74_doubles_701.dart';

/// Correctie-bewuste statistieken uit het bestaande append-only 701-journal.
/// Een scorebeurt heeft geen betrouwbaar aantal gegooide darts; daarom worden
/// hier beurtgemiddelden getoond en geen fictieve 3-dart gemiddelden.
class B74DoublesPlayerStats {
  final List<int> scores;
  final List<int> dartsPerVisit;
  const B74DoublesPlayerStats(this.scores, this.dartsPerVisit);

  int get visits => scores.length;
  int get dartsThrown => dartsPerVisit.fold(0, (a, b) => a + b);
  int get points => scores.fold(0, (a, b) => a + b);
  int get bestVisit =>
      scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
  double get threeDartAverage =>
      dartsThrown == 0 ? 0 : points * 3 / dartsThrown;
  // First 9 is only exact when the first three visits each used 3 darts.
  // Without per-dart scores, partial checkout visits cannot be split.
  double? get firstNineAverage {
    if (scores.length < 3 || dartsPerVisit.take(3).any((d) => d != 3)) {
      return null;
    }
    return scores.take(3).fold<int>(0, (a, b) => a + b) / 3;
  }

  List<int> get lastThree => scores.reversed.take(3).toList();
  int get hundreds => scores.where((v) => v >= 100).length;
  int get oneForties => scores.where((v) => v >= 140).length;
  int get oneEighties => scores.where((v) => v == 180).length;
}

class B74DoublesLiveStats {
  B74DoublesLiveStats._(this._players);
  final List<List<B74DoublesPlayerStats>> _players;
  B74DoublesPlayerStats player(int team, int player) => _players[team][player];

  static B74DoublesLiveStats fromEvents(
    List<String> events, {
    required int startTeam,
    required int bestOf,
    required bool openingBullRequired,
    int startingScore = 701,
    int playersPerTeam = 2,
    String checkIn = 'straight',
  }) {
    final decoded = events
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
    final revoked = <int>{};
    final corrections = <int, Map<String, dynamic>>{};
    for (final event in decoded) {
      if (event['type'] == 'undoVisit') {
        revoked.add(event['targetSequence'] as int);
        if (event['starterSequence'] is int)
          revoked.add(event['starterSequence'] as int);
      } else if (event['type'] == 'correctVisit') {
        corrections[event['targetSequence'] as int] = event;
      }
    }
    final scores = List.generate(2, (_) => List.generate(playersPerTeam, (_) => <int>[]));
    final darts = List.generate(2, (_) => List.generate(playersPerTeam, (_) => <int>[]));
    final core = B74Doubles701(
      starterTeam: startTeam, bestOf: bestOf,
      startingScore: startingScore, playersPerTeam: playersPerTeam,
      checkIn: checkIn,
    );
    for (var i = 0; i < decoded.length; i++) {
      if (revoked.contains(i)) continue;
      final event = corrections[i] == null
          ? decoded[i]
          : {...corrections[i]!, 'type': 'visit'};
      switch (event['type']) {
        case 'starter':
          final team = event['team'] as int;
          if (core.needsBull) {
            core.recordDecidingBullWinner(team);
          } else if (core.leg == 1 && openingBullRequired) {
            core.recordOpeningBullWinner(team);
          } else {
            core.confirmLegStarter(team);
          }
        case 'visit':
          final turn = core.currentVisit;
          scores[turn.team][turn.player].add(
            event['bust'] == true ? 0 : event['score'] as int,
          );
          final checkoutDart = event['checkoutDart'];
          final checkoutDarts = event['checkoutDarts'];
          darts[turn.team][turn.player].add(
            event['validCheckout'] == true && checkoutDart is int
                ? checkoutDart
                : event['validCheckout'] == true && checkoutDarts is List
                ? checkoutDarts.length
                : 3,
          );
          core.completeVisit(
            score: event['score'] as int,
            bust: event['bust'] as bool,
            validCheckout: event['validCheckout'] as bool,
            openingDouble: event['openingDouble'] as int?,
            openingDart: event['openingDart'] as int?,
          );
      }
    }
    return B74DoublesLiveStats._(
      List.generate(
        2,
        (t) => List.generate(
          playersPerTeam,
          (p) => B74DoublesPlayerStats(scores[t][p], darts[t][p]),
        ),
      ),
    );
  }
}
