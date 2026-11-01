import 'b74_doubles_rotation.dart';

/// Independent, deterministic 701 scoring core for competition doubles.
/// Does not write to SQLite or change the existing singles GameProvider.
/// All scoring operations represent one completed visit (up to three darts).
class B74Doubles701 {
  B74Doubles701({
    required this.starterTeam,
    this.bestOf = 5,
    this.startingScore = 701,
    this.playersPerTeam = 2,
    this.checkIn = 'straight',
  }) {
    if (!{'straight', 'double'}.contains(checkIn)) {
      throw ArgumentError.value(checkIn, 'checkIn');
    }
    if (startingScore != 701 && startingScore != 1001) {
      throw ArgumentError.value(startingScore, 'startingScore');
    }
    if (playersPerTeam != 2 && playersPerTeam != 4) {
      throw ArgumentError.value(playersPerTeam, 'playersPerTeam');
    }
    if (startingScore == 701 && playersPerTeam != 2 ||
        startingScore == 1001 && playersPerTeam != 4) {
      throw ArgumentError('Ongeldige teamspelconfiguratie');
    }
    if (starterTeam != 0 && starterTeam != 1) {
      throw ArgumentError.value(starterTeam, 'starterTeam');
    }
    if (!(startingScore == 1001 ? bestOf == 1 : {3, 5, 7}.contains(bestOf))) {
      throw ArgumentError.value(bestOf, 'bestOf');
    }
  }

  final int starterTeam;
  final int bestOf;
  final int startingScore;
  final int playersPerTeam;
  final String checkIn;
  final List<bool> opened = [false, false];
  bool isOpened(int team) => checkIn == 'straight' || opened[team];
  late final List<int> remaining = [startingScore, startingScore];
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
      bestOf > 1 &&
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
      playersPerTeam: playersPerTeam,
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
    int? openingDouble,
    int? openingDart,
  }) {
    final turn = currentVisit;
    if (score < 0 || score > 180) throw ArgumentError.value(score, 'score');
    // For Double In, score is the sum from the opening double onward.
    // A visit before opening has zero credited points. The caller must
    // explicitly supply the opening double; a turn total cannot prove it.
    final wasOpened = isOpened(turn.team);
    if (checkIn == 'double' && !wasOpened) {
      if (openingDouble == null) {
        if (openingDart != null) throw StateError('Openingsdart zonder dubbel');
        if (score != 0 || validCheckout) {
          throw StateError('Team moet eerst openen met een dubbel');
        }
      } else {
        if (!(openingDouble == 50 ||
            (openingDouble >= 2 && openingDouble <= 40 && openingDouble.isEven))) {
          throw ArgumentError.value(openingDouble, 'openingDouble');
        }
        if (openingDart != null && (openingDart < 1 || openingDart > 3)) {
          throw StateError('Openingsdart moet 1, 2 of 3 zijn');
        }
        if (score < openingDouble) {
          throw StateError('Openingsdubbel telt mee in de score');
        }
        if (bust) throw StateError('Bust mag geen opening vastleggen');
      }
    } else if (openingDouble != null || openingDart != null) {
      throw StateError('Openingsdubbel niet toegestaan voor geopend team');
    }
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
    if (!bust) {
      remaining[turn.team] = after;
      if (checkIn == 'double' && openingDouble != null) opened[turn.team] = true;
    }
    if (!bust && after == 0) {
      legsWon[turn.team]++;
      if (legsWon[turn.team] == targetLegs) {
        winner = turn.team;
      } else {
        leg++;
        remaining[0] = startingScore;
        remaining[1] = startingScore;
        opened[0] = false;
        opened[1] = false;
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
