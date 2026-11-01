/// Pure B74 doubles turn order; does not modify the existing X01 engine.
/// Team slot 0 = home, 1 = away; player position 0/1 follows the captain's
/// supplied order. Each team has one shared score.
class B74DoublesRotation {
  const B74DoublesRotation._();

  /// [starterTeam] starts this leg. [turnIndex] is zero-based within the leg.
  /// Every second visit belongs to the same team, whose players alternate.
  static ({int team, int player}) visit({
    required int starterTeam,
    required int turnIndex,
    int playersPerTeam = 2,
  }) {
    if (playersPerTeam < 1) {
      throw ArgumentError.value(playersPerTeam, 'playersPerTeam');
    }
    if (starterTeam != 0 && starterTeam != 1) {
      throw ArgumentError.value(starterTeam, 'starterTeam');
    }
    if (turnIndex < 0) {
      throw ArgumentError.value(turnIndex, 'turnIndex');
    }
    final team = turnIndex.isEven ? starterTeam : 1 - starterTeam;
    final player = (turnIndex ~/ 2) % playersPerTeam;
    return (team: team, player: player);
  }

  /// A leg starts with the first player of the chosen starting team.
  /// This deliberately resets the intra-team player rotation per leg.
  static ({int team, int player}) firstVisit(int starterTeam) =>
      visit(starterTeam: starterTeam, turnIndex: 0);
}
