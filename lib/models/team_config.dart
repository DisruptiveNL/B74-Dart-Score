import 'dart:convert';

/// Team assignment for team-game mode.
class TeamConfig {
  final String name;
  final List<int> playerIds; // DB IDs of players in this team

  const TeamConfig({required this.name, required this.playerIds});

  /// Serializes this team to a JSON map for the game's `team_config_json` column.
  Map<String, dynamic> toJson() => {'name': name, 'player_ids': playerIds};

  /// Reconstructs a team from its JSON map.
  factory TeamConfig.fromJson(Map<String, dynamic> j) => TeamConfig(
    name: j['name'] as String,
    playerIds: (j['player_ids'] as List).cast<int>(),
  );
}

/// Encodes [teams] for storage in a `team_config_json` column, or null for a
/// non-team game.
String? encodeTeamConfigs(List<TeamConfig>? teams) =>
    teams == null ? null : jsonEncode(teams.map((t) => t.toJson()).toList());

/// Decodes the stored team-config JSON into [TeamConfig]s, or null for a
/// non-team game.
List<TeamConfig>? decodeTeamConfigs(String? json) {
  if (json == null) return null;
  final list = jsonDecode(json) as List;
  return list
      .map((e) => TeamConfig.fromJson(e as Map<String, dynamic>))
      .toList();
}
