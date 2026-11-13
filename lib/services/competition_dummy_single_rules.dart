/// Pure competition rules for a regulatory single involving DUMMY.
/// This does not start an X01 game or create individual statistics.
enum DummySingleDecision { normalGame, homeWins, awayWins, bullRequired }

class CompetitionDummySingleRules {
  static bool isDummy(String? bondNumber) =>
      bondNumber?.trim().toUpperCase() == 'DUMMY';

  static DummySingleDecision decide({
    required String? homeBond,
    required String? awayBond,
  }) {
    final home = isDummy(homeBond);
    final away = isDummy(awayBond);
    if (home && away) return DummySingleDecision.bullRequired;
    if (home) return DummySingleDecision.awayWins;
    if (away) return DummySingleDecision.homeWins;
    return DummySingleDecision.normalGame;
  }

  /// For a DUMMY-v-DUMMY bull, the operator must explicitly choose a side.
  static ({int homeLegs, int awayLegs}) regulatoryLegs({
    required int bestOf,
    required DummySingleDecision decision,
    bool? homeWonBull,
  }) {
    if (!{3, 5, 7, 9, 11}.contains(bestOf)) {
      throw ArgumentError.value(bestOf, 'bestOf', 'Unsupported best of');
    }
    final homeWins = switch (decision) {
      DummySingleDecision.homeWins => true,
      DummySingleDecision.awayWins => false,
      DummySingleDecision.bullRequired => homeWonBull ??
          (throw StateError('Bullwinnaar moet expliciet worden gekozen')),
      DummySingleDecision.normalGame =>
        throw StateError('Geen reglementaire single'),
    };
    final target = (bestOf + 1) ~/ 2;
    return (homeLegs: homeWins ? target : 0, awayLegs: homeWins ? 0 : target);
  }
}
