/// Projects the provider's within-set legs onto the live scoreboard.
///
/// Competition singles use one set; the provider resets legsWon to zero
/// when that set is won. Preserve existing within-set display for multi-set games.
class B74LiveLegScore {
  const B74LiveLegScore._();

  static int forScoreboard({
    required int gameLegs,
    required int gameSets,
    required int setsWon,
    required int legsWon,
  }) => gameSets == 1 ? setsWon * gameLegs + legsWon : legsWon;
}
