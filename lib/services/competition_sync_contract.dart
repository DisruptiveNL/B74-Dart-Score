import 'dart:convert';

/// B74 Competition Sync protocol v1. Transport-independent JSON contract.
/// No existing player or statistics sync payloads are changed.
class CompetitionSyncContract {
  static const int version = 1;
  static const String type = 'b74.competition.match.v1';

  static Map<String, dynamic> decode(String payload) {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Competition payload must be an object');
    }
    validate(value);
    return value;
  }

  static String encode(Map<String, dynamic> payload) {
    validate(payload);
    return jsonEncode(payload);
  }

  static void validate(Map<String, dynamic> packet) {
    if (packet['type'] != type || packet['version'] != version) {
      throw const FormatException('Unsupported competition sync protocol');
    }
    final matchId = _required(packet, 'matchId');
    if (matchId.isEmpty) throw const FormatException('Empty match ID');
    final home = _team(packet['home']);
    final away = _team(packet['away']);
    if (home == away) throw const FormatException('Identical teams');
    final assignments = packet['singles'];
    if (assignments is! List || assignments.length != 4) {
      throw const FormatException('Exactly four singles are required');
    }
    final seenHome = <String>{};
    final seenAway = <String>{};
    final seenSlots = <int>{};
    for (final entry in assignments) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid singles assignment');
      }
      final slot = entry['slot'];
      if (slot is! int || slot < 1 || slot > 4 || !seenSlots.add(slot)) {
        throw const FormatException('Invalid or duplicate singles slot');
      }
      final homePlayer = _player(entry['homePlayer']);
      final awayPlayer = _player(entry['awayPlayer']);
      if (!seenHome.add(homePlayer) || !seenAway.add(awayPlayer)) {
        throw const FormatException('A starter appears more than once');
      }
      if (homePlayer == awayPlayer) {
        throw const FormatException('Player on both sides');
      }
    }
    // Legacy v1 packets have only startingScore=501. New packets may
    // include a complete, uniform ruleset for all four singles.
    final rules = packet['x01Rules'];
    if (rules == null) {
      if (packet['startingScore'] != 501) {
        throw const FormatException('Legacy singles must start at 501');
      }
    } else {
      CompetitionX01Rules.validate(rules);
      if (packet['startingScore'] != (rules as Map)['startingScore']) {
        throw const FormatException('Starting score conflicts with X01 rules');
      }
    }
  }

  static String _required(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  static String _team(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid team');
    }
    _required(value, 'name');
    return _required(value, 'id');
  }

  static String _player(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid player');
    }
    _required(value, 'name');
    final bond = value['bondNumber'];
    if (bond != null && bond is! String) {
      throw const FormatException('Invalid bond number');
    }
    return _required(value, 'id');
  }
}

/// Immutable competition rules shared by all four singles.
/// This is an additive v1 extension: old 501 packets remain readable.
class CompetitionX01Rules {
  static const String fixedAway = 'fixedAway';
  static const String fixedHome = 'fixedHome';
  static const String bull = 'bull';

  static Map<String, dynamic> defaults() => {
    'startingScore': 501,
    'bestOf': 5,
    'checkIn': 'straight',
    'checkOut': 'double',
    'startPolicy': fixedAway,
    'bullDecidingLeg': true,
  };

  static void validate(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid X01 rules');
    }
    const scores = {101, 201, 301, 401, 501, 601, 701, 801, 901, 1001};
    if (!scores.contains(value['startingScore'])) {
      throw const FormatException('Invalid X01 starting score');
    }
    final bestOf = value['bestOf'];
    if (bestOf is! int || bestOf < 1 || bestOf.isEven || bestOf > 21) {
      throw const FormatException('Best of must be an odd number from 1 to 21');
    }
    const checks = {'straight', 'double', 'master'};
    if (!checks.contains(value['checkIn']) ||
        !checks.contains(value['checkOut'])) {
      throw const FormatException('Invalid X01 check-in/out');
    }
    if (!{fixedAway, fixedHome, bull}.contains(value['startPolicy'])) {
      throw const FormatException('Invalid start policy');
    }
    if (value['bullDecidingLeg'] is! bool) {
      throw const FormatException('Missing deciding-leg bull policy');
    }
  }

  /// Fixed team starts alternate across *parties*, not only within singles.
  /// partyIndex is zero-based across singles, doubles, triples and beer game.
  /// For bull mode the starter is determined at the oche, not in the export.
  static String? startingTeam(String policy, int partyIndex) {
    if (partyIndex < 0) throw ArgumentError.value(partyIndex);
    if (policy == bull) return null;
    if (policy != fixedAway && policy != fixedHome) {
      throw ArgumentError.value(policy);
    }
    final awayFirst = policy == fixedAway;
    return (partyIndex.isEven == awayFirst) ? 'away' : 'home';
  }

  /// At 2-2 in best-of-5, 3-3 in best-of-7, etc.
  static bool needsDecidingLegBull({
    required int homeLegs,
    required int awayLegs,
    required int bestOf,
    required bool enabled,
  }) {
    if (!enabled || bestOf < 3 || bestOf.isEven) return false;
    final threshold = bestOf ~/ 2;
    return homeLegs == threshold && awayLegs == threshold;
  }
}
