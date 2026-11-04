import 'dart:convert';

/// C1B11: versioned, platform-independent rules envelope.
/// This is a contract building block; it is not yet sent by the app.
class B74MatchRulesContract {
  static const type = 'b74.competition.match-rules.v1';
  static const version = 1;

  static Map<String, dynamic> create({
    required String matchId,
    required String matchType,
    required Map<String, dynamic> snapshot,
  }) {
    final packet = <String, dynamic>{
      'type': type,
      'version': version,
      'matchId': matchId,
      'matchType': matchType,
      'rules': jsonDecode(jsonEncode(snapshot)),
    };
    validate(packet);
    return packet;
  }

  static String encode(Map<String, dynamic> packet) {
    validate(packet);
    return jsonEncode(packet);
  }

  static Map<String, dynamic> decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Reglementbericht moet een JSON-object zijn');
    }
    validate(value);
    return value;
  }

  static void validate(Map<String, dynamic> packet) {
    if (packet['type'] != type || packet['version'] != version) {
      throw const FormatException('Onbekend reglementprotocol');
    }
    final matchId = packet['matchId'];
    if (matchId is! String || matchId.trim().isEmpty) {
      throw const FormatException('Ongeldig matchId');
    }
    if (!{'regular', 'cup'}.contains(packet['matchType'])) {
      throw const FormatException('Ongeldig wedstrijdtype');
    }
    final rules = packet['rules'];
    if (rules is! Map<String, dynamic> || rules['version'] != 1) {
      throw const FormatException('Ongeldig reglementsnapshot');
    }
    const scores = <String, Set<int>>{
      'singles': {301, 501, 701},
      'doubles': {301, 501, 701},
      'beer': {301, 501, 701, 1001},
    };
    for (final kind in scores.keys) {
      final group = rules[kind];
      if (group is! Map<String, dynamic>) {
        throw FormatException('Ontbrekend reglement: $kind');
      }
      if (!scores[kind]!.contains(group['startingScore'])) {
        throw FormatException('Ongeldige startscore: $kind');
      }
      final bestOf = group['bestOf'];
      if (kind == 'beer' ? bestOf != 1 : !{3, 5, 7, 9, 11}.contains(bestOf)) {
        throw FormatException('Ongeldige Best of: $kind');
      }
      if (!{'straight', 'double'}.contains(group['checkIn']) ||
          !{'straight', 'double', 'master'}.contains(group['checkOut'])) {
        throw FormatException('Ongeldige in/out: $kind');
      }
      if (!{'fixedHome', 'fixedAway', 'bull'}.contains(group['startPolicy'])) {
        throw FormatException('Ongeldige startregeling: $kind');
      }
      if (group['bullDecidingLeg'] is! bool ||
          (kind == 'beer' && group['bullDecidingLeg'] != false)) {
        throw FormatException('Ongeldige beslissende-leg-bull: $kind');
      }
      if (group['winPoints'] is! int || group['winPoints'] < 1) {
        throw FormatException('Ongeldige wedstrijdpunten: $kind');
      }
    }
  }

  /// Returns a defensive copy of the rules for a specific game group.
  static Map<String, dynamic> forGame(Map<String, dynamic> packet, String kind) {
    validate(packet);
    if (!{'singles', 'doubles', 'beer'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    final rules = packet['rules'] as Map<String, dynamic>;
    return Map<String, dynamic>.from(rules[kind] as Map);
  }
}
