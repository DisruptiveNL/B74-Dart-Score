import 'b74_match_rules_contract.dart';
import 'b74_team_match_contract.dart';

/// C1B11 4c.1: prevent a valid transported regulation from being played by
/// a legacy engine that cannot yet enforce every rule. No silent defaults.
class CompetitionTeamRulesGuard {
  static void validateForCurrentEngine(Map<String, dynamic> packet) {
    B74TeamMatchContract.validate(packet);
    final envelope = packet['matchRules'];
    if (envelope == null) return; // Pre-C1B11 matches retain legacy behavior.
    final kind = packet['kind'] == 'beer1001' ? 'beer' : 'doubles';
    final rules = B74MatchRulesContract.forGame(
      envelope as Map<String, dynamic>, kind,
    );
    if (rules['checkOut'] != 'double') {
      throw StateError('Dit reglement vereist ${rules['checkOut']} Out; de huidige competitie-engine ondersteunt alleen Double Out.');
    }
    if (kind == 'doubles' && rules['bullDecidingLeg'] != true) {
      throw StateError('Dit reglement schakelt de beslissende-leg-bull uit; de huidige competitie-engine vereist deze nog.');
    }
    // The current engine reads startingScore, bestOf and checkIn from the
    // packet. Their equality with the frozen rules is checked by the contract.
  }
}
