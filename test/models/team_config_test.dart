import 'dart:convert';

import 'package:dartscore_app/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the team_config_json column', () {
    test('gives back the teams it was handed', () {
      final teams = [
        const TeamConfig(name: 'Reds', playerIds: [1, 2]),
        const TeamConfig(name: 'Blues', playerIds: [3]),
      ];

      final decoded = decodeTeamConfigs(encodeTeamConfigs(teams))!;

      expect(decoded.map((t) => t.name), ['Reds', 'Blues']);
      expect(decoded.map((t) => t.playerIds), [
        [1, 2],
        [3],
      ]);
    });

    test('keeps the order of the teams and of the players inside them', () {
      // Turn order is read straight off these lists, so a round trip that
      // reorders them changes who throws when.
      const teams = [
        TeamConfig(name: 'B', playerIds: [9, 3, 7]),
        TeamConfig(name: 'A', playerIds: [4, 1]),
      ];

      final decoded = decodeTeamConfigs(encodeTeamConfigs(teams))!;

      expect(decoded[0].playerIds, [9, 3, 7]);
      expect(decoded[1].playerIds, [4, 1]);
    });

    test('stays null for a game that has no teams', () {
      expect(encodeTeamConfigs(null), isNull);
      expect(decodeTeamConfigs(null), isNull);
    });

    test('tells an empty team list apart from no teams at all', () {
      // A team game the user emptied is not the same as an individual game,
      // and the column has to carry that difference.
      expect(decodeTeamConfigs(encodeTeamConfigs([])), isEmpty);
      expect(decodeTeamConfigs(encodeTeamConfigs([])), isNotNull);
    });

    test('survives a team with no players yet', () {
      const teams = [TeamConfig(name: 'Empty', playerIds: [])];

      final decoded = decodeTeamConfigs(encodeTeamConfigs(teams))!;

      expect(decoded.single.name, 'Empty');
      expect(decoded.single.playerIds, isEmpty);
    });

    test('reads back a team name that carries JSON punctuation', () {
      const teams = [
        TeamConfig(name: 'The "A", {Team}', playerIds: [1]),
      ];

      final decoded = decodeTeamConfigs(encodeTeamConfigs(teams))!;

      expect(decoded.single.name, 'The "A", {Team}');
    });

    test('writes the column shape the migrations and the sync expect', () {
      const teams = [
        TeamConfig(name: 'Reds', playerIds: [1, 2]),
      ];

      final raw = jsonDecode(encodeTeamConfigs(teams)!) as List;

      expect(raw.single, {
        'name': 'Reds',
        'player_ids': [1, 2],
      });
    });
  });
}
