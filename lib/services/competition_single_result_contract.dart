import 'dart:convert';

/// Wire contract for one completed competition single.
/// The result ID is stable across retries. Transport and storage live elsewhere.
class CompetitionSingleResultContract {
  static const int version = 1;
  static const String type = 'b74.competition.single-result.v1';

  static String resultId(String matchId, int slot) {
    if (matchId.trim().isEmpty || slot < 1 || slot > 4) {
      throw const FormatException('Invalid competition single identity');
    }
    return '$matchId:single:$slot';
  }

  static Map<String, dynamic> decode(String json) {
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Single result must be an object');
    }
    validate(value);
    return value;
  }

  static String encode(Map<String, dynamic> value) {
    validate(value);
    return jsonEncode(value);
  }

  static void validate(Map<String, dynamic> value) {
    if (value['type'] != type || value['version'] != version) {
      throw const FormatException('Unsupported single result protocol');
    }
    final matchId = value['matchId'];
    final slot = value['slot'];
    if (matchId is! String || slot is! int) {
      throw const FormatException('Missing single identity');
    }
    final id = resultId(matchId, slot);
    if (value['resultId'] != id) {
      throw const FormatException('Result identity mismatch');
    }
    final homeId = value['homePlayerId'];
    final awayId = value['awayPlayerId'];
    if (homeId is! String ||
        homeId.trim().isEmpty ||
        awayId is! String ||
        awayId.trim().isEmpty ||
        homeId == awayId) {
      throw const FormatException('Invalid players');
    }
    final homeLegs = value['homeLegs'];
    final awayLegs = value['awayLegs'];
    if (homeLegs is! int ||
        awayLegs is! int ||
        homeLegs < 0 ||
        awayLegs < 0 ||
        homeLegs == awayLegs) {
      throw const FormatException('Invalid final leg score');
    }
    final winnerId = value['winnerPlayerId'];
    if (winnerId != (homeLegs > awayLegs ? homeId : awayId)) {
      throw const FormatException('Winner and leg score conflict');
    }
    final stats = value['statistics'];
    if (stats is! Map<String, dynamic>) {
      throw const FormatException('Statistics object required');
    }
  }
}
