import 'dart:convert';
import 'competition_dummy_identity.dart';

/// C1B4.5 wire format for a completed doubles 701 result.
/// Transport acknowledgement and persistence are separate concerns.
class B74DoublesResultContract {
  static const type = 'b74.competition.doubles-result.v1';
  static const version = 1;

  static String resultId(String matchId, int slot, {String kind = 'doubles701'}) {
    if (kind == 'beer1001' && slot == 1 && matchId.trim().isNotEmpty) {
      return '$matchId:beer:1';
    }
    if (kind != 'doubles701') throw const FormatException('Ongeldige resultaatsoort');
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
    final kind = value['kind'] ?? 'doubles701';
    if (!{'doubles701', 'beer1001'}.contains(kind)) {
      throw const FormatException('Ongeldige resultaatsoort');
    }
    final matchId = value['matchId'];
    final slot = value['slot'];
    final gameId = value['gameId'];
    final revision = value['revision'];
    if (matchId is! String || slot is! int ||
        gameId is! String || gameId.trim().isEmpty ||
        revision is! int || revision < 1 ||
        value['resultId'] != resultId(matchId, slot, kind: kind)) {
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
    if (bestOf is! int || (kind == 'beer1001' ? bestOf != 1 : !{3, 5, 7, 9, 11}.contains(bestOf)) ||
        homeLegs is! int || awayLegs is! int ||
        homeLegs < 0 || awayLegs < 0 ||
        (homeLegs > awayLegs ? homeLegs : awayLegs) != bestOf ~/ 2 + 1 ||
        (homeLegs < awayLegs ? homeLegs : awayLegs) >= bestOf ~/ 2 + 1 ||
        value['winnerTeamId'] != (homeLegs > awayLegs ? home : away)) {
      throw const FormatException('Ongeldige definitieve wedstrijdstand');
    }
    final players = value['players'];
    if (players is! List || players.length != (kind == 'beer1001' ? 8 : 4)) {
      throw const FormatException('Ongeldig aantal spelerstatistieken');
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
      // Dummy occupies a lineup slot but never owns individual statistics.
      // Keep the participant in the wire contract for lineup verification.
      final id = player['playerId'] as String;
      final isDummy = CompetitionDummyIdentity.isParticipantId(id);
      if (isDummy) {
        if (id != CompetitionDummyIdentity.participantId(player['teamId'] as String) ||
            player['officialStatisticsEligible'] != false ||
            (player['statistics'] as Map<String, dynamic>).isNotEmpty) {
          throw const FormatException('DUMMY mag geen individuele statistieken hebben');
        }
      } else if (player['officialStatisticsEligible'] == false) {
        throw const FormatException('Echte speler mag niet als DUMMY worden uitgesloten');
      }
    }
  }
}
