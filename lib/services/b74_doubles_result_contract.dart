import 'dart:convert';

/// C1B4.5 wire format for a completed doubles 701 result.
/// Transport acknowledgement and persistence are separate concerns.
class B74DoublesResultContract {
  static const type = 'b74.competition.doubles-result.v1';
  static const version = 1;

  static String resultId(String matchId, int slot) {
    if (matchId.trim().isEmpty || slot < 1 || slot > 4) {
      throw const FormatException('Ongeldige koppelwedstrijdidentiteit');
    }
    return '$matchId:doubles:$slot';
  }

  static Map<String, dynamic> decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Resultaat moet JSON-object zijn');
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
      throw const FormatException('Onbekend koppelresultaatprotocol');
    }
    final matchId = value['matchId'];
    final slot = value['slot'];
    final gameId = value['gameId'];
    final revision = value['revision'];
    if (matchId is! String || slot is! int ||
        gameId is! String || gameId.trim().isEmpty ||
        revision is! int || revision < 1 ||
        value['resultId'] != resultId(matchId, slot)) {
      throw const FormatException('Ongeldige wedstrijdkoppeling');
    }
    final home = value['homeTeamId'];
    final away = value['awayTeamId'];
    if (home is! String || home.trim().isEmpty ||
        away is! String || away.trim().isEmpty || home == away) {
      throw const FormatException('Ongeldige teams');
    }
    final bestOf = value['bestOf'];
    final homeLegs = value['homeLegs'];
    final awayLegs = value['awayLegs'];
    if (bestOf is! int || !{3, 5, 7}.contains(bestOf) ||
        homeLegs is! int || awayLegs is! int ||
        homeLegs < 0 || awayLegs < 0 ||
        (homeLegs > awayLegs ? homeLegs : awayLegs) != bestOf ~/ 2 + 1 ||
        (homeLegs < awayLegs ? homeLegs : awayLegs) >= bestOf ~/ 2 + 1 ||
        value['winnerTeamId'] != (homeLegs > awayLegs ? home : away)) {
      throw const FormatException('Ongeldige definitieve wedstrijdstand');
    }
    final players = value['players'];
    if (players is! List || players.length != 4) {
      throw const FormatException('Vier spelerstatistieken vereist');
    }
    final ids = <String>{};
    for (final player in players) {
      if (player is! Map<String, dynamic> ||
          player['playerId'] is! String ||
          (player['playerId'] as String).trim().isEmpty ||
          !ids.add(player['playerId'] as String) ||
          player['teamId'] != home && player['teamId'] != away ||
          player['statistics'] is! Map<String, dynamic>) {
        throw const FormatException('Ongeldige spelerstatistieken');
      }
    }
  }
}
