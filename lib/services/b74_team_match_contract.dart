import 'dart:convert';
import 'b74_match_rules_contract.dart';

/// C1B4 teamwedstrijd-contract. Staat los van het bestaande singles-v1-contract.
/// Dit contract valideert de berichtstructuur; speelgerechtigdheid en revisies
/// worden transactioneel op de ontvangende database gecontroleerd.
class B74TeamMatchContract {
  static const type = 'b74.competition.team-match.v1';
  static const version = 1;

  static String encode(Map<String, dynamic> packet) {
    validate(packet);
    return jsonEncode(packet);
  }

  static Map<String, dynamic> decode(String raw) {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Teamwedstrijd moet een JSON-object zijn');
    }
    validate(parsed);
    return parsed;
  }

  static void validate(Map<String, dynamic> packet) {
    if (packet['type'] != type || packet['version'] != version) {
      throw const FormatException('Onbekend teamwedstrijdprotocol');
    }
    final division = packet['division'];
    if (division != null &&
        (division is! String || division.trim().isEmpty)) {
      throw const FormatException('Ongeldige divisie');
    }
    _text(packet, 'matchId');
    _text(packet, 'gameId');
    final revision = packet['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Ongeldige revisie');
    }
    final slot = packet['slot'];
    final kind = packet['kind'];
    final count = kind == 'doubles701' ? 2 : kind == 'beer1001' ? 4 : 0;
    if (count == 0 || (kind == 'doubles701' && (slot is! int || slot < 1 || slot > 4)) ||
        (kind == 'beer1001' && slot != 1)) {
      throw const FormatException('Ongeldige wedstrijdvorm of wedstrijdregel');
    }
    if (packet['startingScore'] != (count == 2 ? 701 : 1001)) {
      throw const FormatException('Ongeldige startscore');
    }
    final bestOf = packet['bestOf'];
    if (bestOf is! int || (count == 4 ? bestOf != 1 : !{3, 5, 7}.contains(bestOf))) {
      throw const FormatException('Ongeldig aantal legs');
    }
    // Optional v1 extension. Old 701/1001 packets remain Straight In.
    // Never confuse check-in with startPolicy (which team starts).
    if (packet.containsKey('checkIn') &&
        !{'straight', 'double'}.contains(packet['checkIn'])) {
      throw const FormatException('Ongeldige check-in regel');
    }
    if (!{'home', 'away', 'bull'}.contains(packet['startPolicy'])) {
      throw const FormatException('Ongeldig beginnend team');
    }
    // C1B11: optional, immutable match-wide rules envelope. Legacy packets
    // remain valid. Fail closed if the attached snapshot belongs to another
    // match or contradicts the actual game settings in this v1 packet.
    if (packet.containsKey('matchRules')) {
      final rawRules = packet['matchRules'];
      if (rawRules is! Map<String, dynamic>) {
        throw const FormatException('Ongeldig wedstrijdreglement');
      }
      B74MatchRulesContract.validate(rawRules);
      if (rawRules['matchId'] != packet['matchId']) {
        throw const FormatException('Reglement hoort bij andere wedstrijd');
      }
      final group = B74MatchRulesContract.forGame(
        rawRules, count == 2 ? 'doubles' : 'beer',
      );
      if (group['startingScore'] != packet['startingScore'] ||
          group['bestOf'] != packet['bestOf'] ||
          (packet['checkIn'] ?? 'straight') != group['checkIn']) {
        throw const FormatException('Reglement en spelinstellingen verschillen');
      }
      // Further C1B11 settings are transported without activating the
      // legacy score engine prematurely.
    }
    final home = _side(packet['home'], count);
    final away = _side(packet['away'], count);
    if (home.$1 == away.$1) {
      throw const FormatException('Thuis- en uitteam zijn identiek');
    }
    if (home.$2.intersection(away.$2).isNotEmpty) {
      throw const FormatException('Speler aan beide zijden');
    }
  }

  static String _text(Map<String, dynamic> value, String key) {
    final text = value[key];
    if (text is! String || text.trim().isEmpty) {
      throw FormatException('Ontbrekend veld: $key');
    }
    return text.trim();
  }

  static (String, Set<String>) _side(dynamic raw, int count) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Team ontbreekt');
    }
    final id = _text(raw, 'teamId');
    _text(raw, 'teamName');
    final players = raw['players'];
    if (players is! List || players.length != count) {
      throw FormatException('Exact $count spelers vereist');
    }
    final bonds = <String>{};
    for (var index = 0; index < players.length; index++) {
      final player = players[index];
      if (player is! Map<String, dynamic>) {
        throw const FormatException('Ongeldige speler');
      }
      _text(player, 'playerId');
      _text(player, 'name');
      final bond = _text(player, 'bondNumber');
      if (!bonds.add(bond)) {
        throw const FormatException('Dubbel bondsnummer binnen team');
      }
      if (player['position'] != index + 1) {
        throw const FormatException('Spelersvolgorde niet aaneengesloten');
      }
    }
    return (id, bonds);
  }
}
