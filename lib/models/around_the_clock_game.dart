import 'dart:convert';
import 'starting_order.dart';
import 'team_config.dart';

export 'starting_order.dart';
export 'team_config.dart';

/// Around the Clock rule variant: [basic] (single hit advances), [fullSegments]
/// (single, double and triple of a number must all be hit) or [skipRules]
/// (doubles/triples let the player skip ahead).
enum AroundTheClockVariant { basic, fullSegments, skipRules }

/// Clockwise target order, ending at the Bull's Eye (25). Hitting the final
/// entry wins the game.
const List<int> aroundTheClockOrder = [
  1,
  18,
  4,
  13,
  6,
  10,
  15,
  2,
  17,
  3,
  19,
  7,
  16,
  8,
  11,
  14,
  9,
  12,
  5,
  20,
  25,
];

/// An Around the Clock game configuration and result. Per-dart hits are stored
/// separately as [AroundTheClockThrow] records.
class AroundTheClockGame {
  final int? id;
  final AroundTheClockVariant variant;
  final int legs;
  final int sets;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<int> playerIds;

  /// Non-null when this is a team game.
  final List<TeamConfig>? teams;

  /// How the throwing order was determined.
  final StartingOrder startingOrder;

  const AroundTheClockGame({
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

  /// Serializes this game to a row map for the SQLite `around_the_clock_games` table.
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

  /// Reconstructs an Around the Clock game from a SQLite row map.
  factory AroundTheClockGame.fromMap(
    Map<String, dynamic> map,
  ) => AroundTheClockGame(
    id: map['id'] as int?,
    variant: AroundTheClockVariant.values[map['variant'] as int],
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

  /// Returns a copy with [finishedAt] updated (marking a game done), or cleared
  /// when [clearFinishedAt] is set, which reopens a game whose winning dart was
  /// undone. Copying rather than rebuilding the object by hand keeps every
  /// other field, so a new field cannot be forgotten here.
  AroundTheClockGame copyWith({
    DateTime? finishedAt,
    bool clearFinishedAt = false,
  }) => AroundTheClockGame(
    id: id,
    variant: variant,
    legs: legs,
    sets: sets,
    createdAt: createdAt,
    finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
    playerIds: playerIds,
    teams: teams,
    startingOrder: startingOrder,
  );
}

/// A single dart thrown in an Around the Clock game (one dart, not a full
/// visit), used to reconstruct progress and to support undo.
class AroundTheClockThrow {
  final int? id;
  final int gameId;
  final int playerId;
  final int field; // 1-20, 25=Bull, 0=miss
  final int multiplier; // 1-3; 0 for miss
  final int leg;
  final int set_;
  final DateTime thrownAt;

  const AroundTheClockThrow({
    this.id,
    required this.gameId,
    required this.playerId,
    required this.field,
    required this.multiplier,
    required this.leg,
    required this.set_,
    required this.thrownAt,
  });

  /// Whether this dart missed all scoring fields.
  bool get isMiss => field == 0 || multiplier == 0;

  /// Serializes this throw to a row map for the SQLite `around_the_clock_throws` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'game_id': gameId,
    'player_id': playerId,
    'field': field,
    'multiplier': multiplier,
    'leg': leg,
    'set_': set_,
    'thrown_at': thrownAt.millisecondsSinceEpoch,
  };

  /// Reconstructs an Around the Clock throw from a SQLite row map.
  factory AroundTheClockThrow.fromMap(Map<String, dynamic> map) =>
      AroundTheClockThrow(
        id: map['id'] as int?,
        gameId: map['game_id'] as int,
        playerId: map['player_id'] as int,
        field: map['field'] as int,
        multiplier: map['multiplier'] as int,
        leg: map['leg'] as int,
        set_: map['set_'] as int,
        thrownAt: DateTime.fromMillisecondsSinceEpoch(map['thrown_at'] as int),
      );
}
