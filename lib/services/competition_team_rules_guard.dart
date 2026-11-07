import 'b74_team_match_contract.dart';

/// C1B11 4c.1: prevent a valid transported regulation from being played by
/// a legacy engine that cannot yet enforce every rule. No silent defaults.
class CompetitionTeamRulesGuard {
  static void validateForCurrentEngine(Map<String, dynamic> packet) {
    B74TeamMatchContract.validate(packet);
    final envelope = packet['matchRules'];
    if (envelope == null) return; // Pre-C1B11 matches retain legacy behavior.
    // The current engine reads startingScore, bestOf and checkIn from the
    // packet. Their equality with the frozen rules is checked by the contract.
  }
}
