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
    if (packet['startingScore'] != 501) {
      throw const FormatException('Singles must start at 501');
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
