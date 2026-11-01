import 'dart:convert';

/// C1B6b.2: versioned payload for a final match closure.
/// Authentication, persistence, retry and ACK are transport responsibilities.
class B74MatchLockedContract {
  static const type = 'b74.competition.match-locked.v1';
  static const version = 1;

  static String encode(Map<String, dynamic> message) {
    validate(message);
    return jsonEncode(message);
  }

  static Map<String, dynamic> decode(String payload) {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('LOCKED-bericht moet een object zijn');
    }
    validate(value);
    return value;
  }

  static void validate(Map<String, dynamic> message) {
    if (message['type'] != type || message['version'] != version) {
      throw const FormatException('Onbekend LOCKED-protocol');
    }
    final matchId = message['matchId'];
    if (matchId is! String || matchId.trim().isEmpty) {
      throw const FormatException('Ontbrekend wedstrijd-ID');
    }
    final closedAt = message['closedAt'];
    if (closedAt is! int || closedAt <= 0) {
      throw const FormatException('Ongeldig afsluitmoment');
    }
    final homeWins = message['homeWins'];
    final awayWins = message['awayWins'];
    if (homeWins is! int || awayWins is! int ||
        homeWins < 0 || awayWins < 0 || homeWins + awayWins != 9) {
      throw const FormatException('Afsluiting vereist exact negen uitslagen');
    }
  }

  /// Stable identifier for idempotent delivery and acknowledgement.
  static String deliveryId(Map<String, dynamic> message) {
    validate(message);
    return 'match-locked:${message['matchId']}';
  }
}
