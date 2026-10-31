import 'b74_doubles_rotation.dart';

/// Independent, deterministic 701 scoring core for competition doubles.
/// Does not write to SQLite or change the existing singles GameProvider.
/// All scoring operations represent one completed visit (up to three darts).
class B74Doubles701 {
  B74Doubles701({required this.starterTeam, this.bestOf = 5}) {
    if (starterTeam != 0 && starterTeam != 1) {
      throw ArgumentError.value(starterTeam, 'starterTeam');
    }
    if (!{3, 5, 7}.contains(bestOf)) {
      throw ArgumentError.value(bestOf, 'bestOf');
    }
  }

  final int starterTeam;
  final int bestOf;
  final List<int> remaining = [701, 701];
  final List<int> legsWon = [0, 0];
  int leg = 1;
  int visitIndex = 0;
  int? decidingBullWinner;
  int? _confirmedStarter;
  final List<B74LegStarterRecord> starterHistory = [];

  bool get awaitingStarter => winner == null && _confirmedStarter == null;
  int? get suggestedStarter => winner != null || needsBull
      ? null
      : ((leg - 1).isEven ? starterTeam : 1 - starterTeam);
  int? winner;

  int get targetLegs => (bestOf + 1) ~/ 2;
  bool get needsBull =>
      winner == null &&
      legsWon[0] == targetLegs - 1 &&
      legsWon[1] == targetLegs - 1;
  bool get awaitingBull => needsBull && decidingBullWinner == null;

  int get legStarter {
    if (winner != null) throw StateError('Match already finished');
    if (_confirmedStarter == null) {
      throw StateError(
        needsBull
            ? 'Deciding bull winner required before starting leg'
            : 'Explicit starter confirmation required before starting leg',
      );
    }
    return _confirmedStarter!;
  }

  ({int team, int player}) get currentVisit {
    if (winner != null) throw StateError('Match already finished');
    return B74DoublesRotation.visit(
      starterTeam: legStarter,
      turnIndex: visitIndex,
    );
  }

  /// Confirm or override the proposed starter before a non-deciding leg.
  void confirmLegStarter(int team) {
    _validateTeam(team);
    if (winner != null || !awaitingStarter || needsBull || visitIndex != 0) {
      throw StateError('Starter cannot be confirmed for this leg');
    }
    _setStarter(team, viaBull: false);
  }

  /// Opening bull when the imported match explicitly requires bull start.
  void recordOpeningBullWinner(int team) {
    _validateTeam(team);
    if (leg != 1 || winner != null || !awaitingStarter || visitIndex != 0) {
      throw StateError('No opening bull pending');
    }
    _setStarter(team, viaBull: true);
  }

  /// A deciding leg can only start after an explicitly selected bull winner.
  void recordDecidingBullWinner(int team) {
    _validateTeam(team);
    if (winner != null ||
        !needsBull ||
        !awaitingStarter ||
        decidingBullWinner != null ||
        visitIndex != 0) {
      throw StateError('No deciding bull pending');
    }
    decidingBullWinner = team;
    _setStarter(team, viaBull: true);
  }

  void _validateTeam(int team) {
    if (team != 0 && team != 1) throw ArgumentError.value(team, 'team');
  }

  void _setStarter(int team, {required bool viaBull}) {
    _confirmedStarter = team;
    starterHistory.add(
      B74LegStarterRecord(legNumber: leg, team: team, viaBull: viaBull),
    );
  }

  /// The caller must validate dart values and checkout (double-out) using
  /// the existing X01 rules. A bust never changes the shared team score.
  void completeVisit({
    required int score,
    bool bust = false,
    bool validCheckout = false,
  }) {
    final turn = currentVisit;
    if (score < 0 || score > 180) throw ArgumentError.value(score, 'score');
    final before = remaining[turn.team];
    final after = before - score;
    if (!bust && (after < 0 || after == 1)) {
      throw StateError('Bust must be marked by X01 checkout validation');
    }
    if (!bust && after == 0 && !validCheckout) {
      throw StateError('Checkout must be validated by X01');
    }
    if (!bust && after != 0 && validCheckout) {
      throw StateError('Cannot checkout with score remaining');
    }
    if (!bust) remaining[turn.team] = after;
    if (!bust && after == 0) {
      legsWon[turn.team]++;
      if (legsWon[turn.team] == targetLegs) {
        winner = turn.team;
      } else {
        leg++;
        remaining[0] = 701;
        remaining[1] = 701;
        visitIndex = 0;
        _confirmedStarter = null;
      }
    } else {
      visitIndex++;
    }
  }
}

/// Immutable leg-start event for subsequent UI and SQLite integration.
class B74LegStarterRecord {
  const B74LegStarterRecord({
    required this.legNumber,
    required this.team,
    required this.viaBull,
  });

  final int legNumber;
  final int team;
  final bool viaBull;
}
