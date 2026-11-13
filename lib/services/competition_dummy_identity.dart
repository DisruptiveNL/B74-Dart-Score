/// Stable, side-specific identity for a regulatory DUMMY participant.
/// This is a wire participant identity, NOT a registered player ID.
/// It must never be used to create a player or individual statistics.
class CompetitionDummyIdentity {
  static bool isDummyBond(String? bondNumber) =>
      bondNumber?.trim().toUpperCase() == 'DUMMY';

  /// Team IDs are used instead of names because names may change.
  /// Prefix/encoding avoid collisions with ordinary UUID player IDs.
  static String participantId(String teamId) {
    if (teamId.trim().isEmpty) {
      throw ArgumentError.value(teamId, 'teamId', 'Team ID ontbreekt');
    }
    return 'b74:dummy:team:${Uri.encodeComponent(teamId)}';
  }

  static bool isParticipantId(String id) =>
      id.startsWith('b74:dummy:team:') &&
      id.length > 'b74:dummy:team:'.length;
}
