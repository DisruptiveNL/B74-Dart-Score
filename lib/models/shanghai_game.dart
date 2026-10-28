import 'dart:convert';
import 'starting_order.dart';
import 'team_config.dart';

export 'starting_order.dart';
export 'team_config.dart';

/// Shanghai target progression: [classic] (numbers 1-7), [clockwise] (full
/// board order) or [sequential] (advance only after hitting the current target).
enum ShanghaiVariant { classic, clockwise, sequential }

/// A Shanghai game configuration and result. Per-dart hits are stored separately
/// as [ShanghaiThrow] records.
class ShanghaiGame {
  final int? id;
  final ShanghaiVariant variant;
  final int legs;
  final int sets;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<int> playerIds;

  /// Non-null when this is a team game.
  final List<TeamConfig>? teams;

  /// How the throwing order was determined.
  final StartingOrder startingOrder;

  const ShanghaiGame({
    this.id,
    required this.variant,
    required this.legs,
    required this.sets,
    required this.createdAt,
    this.finishedAt,
    required this.playerIds,
    this.teams,
    this.startingOrder = StartingOrder.random,
  });

  /// Whether this game is played in teams rather than individually.
  bool get isTeamGame => teams != null && teams!.isNotEmpty;

  /// Serializes this game to a row map for the SQLite `shanghai_games` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'variant': variant.index,
    'legs': legs,
    'sets': sets,
    'created_at': createdAt.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
    'player_ids': jsonEncode(playerIds),
    'team_config_json': encodeTeamConfigs(teams),
    'starting_order': startingOrder.index,
  };

  /// Reconstructs a Shanghai game from a SQLite row map.
  factory ShanghaiGame.fromMap(Map<String, dynamic> map) => ShanghaiGame(
    id: map['id'] as int?,
    variant: ShanghaiVariant.values[map['variant'] as int],
    legs: map['legs'] as int,
    sets: map['sets'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    finishedAt: map['finished_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['finished_at'] as int)
        : null,
    playerIds: (jsonDecode(map['player_ids'] as String) as List).cast<int>(),
    teams: decodeTeamConfigs(map['team_config_json'] as String?),
    startingOrder: StartingOrder.values[map['starting_order'] as int? ?? 0],
  );

  /// Returns a copy with [finishedAt] optionally updated (used to mark a game done).
  ShanghaiGame copyWith({DateTime? finishedAt}) => ShanghaiGame(
    id: id,
    variant: variant,
    legs: legs,
    sets: sets,
    createdAt: createdAt,
    finishedAt: finishedAt ?? this.finishedAt,
    playerIds: playerIds,
    teams: teams,
    startingOrder: startingOrder,
  );
}

/// A single dart thrown in a Shanghai game (one dart, not a full visit), used to
/// reconstruct scores and to support undo.
class ShanghaiThrow {
  final int? id;
  final int gameId;
  final int playerId;
  final int target; // the number this dart aimed at
  final int multiplier; // 1-3; 0 for miss
  final int round; // visit/round index (1-based)
  final int leg;
  final int set_;
  final DateTime thrownAt;

  const ShanghaiThrow({
    this.id,
    required this.gameId,
    required this.playerId,
    required this.target,
    required this.multiplier,
    required this.round,
    required this.leg,
    required this.set_,
    required this.thrownAt,
  });

  /// Whether this dart missed its target.
  bool get isMiss => multiplier == 0;

  /// Serializes this throw to a row map for the SQLite `shanghai_throws` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'game_id': gameId,
    'player_id': playerId,
    'target': target,
    'multiplier': multiplier,
    'round': round,
    'leg': leg,
    'set_': set_,
    'thrown_at': thrownAt.millisecondsSinceEpoch,
  };

  /// Reconstructs a Shanghai throw from a SQLite row map.
  factory ShanghaiThrow.fromMap(Map<String, dynamic> map) => ShanghaiThrow(
    id: map['id'] as int?,
    gameId: map['game_id'] as int,
    playerId: map['player_id'] as int,
    target: map['target'] as int,
    multiplier: map['multiplier'] as int,
    round: map['round'] as int,
    leg: map['leg'] as int,
    set_: map['set_'] as int,
    thrownAt: DateTime.fromMillisecondsSinceEpoch(map['thrown_at'] as int),
  );
}
