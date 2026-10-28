import 'dart:convert';
import 'starting_order.dart';
import 'team_config.dart';

export 'starting_order.dart';
export 'team_config.dart';

/// Cricket rule variant: [normal] (close fields and score) or [cutThroat]
/// (points are added to opponents instead of yourself).
enum CricketVariant { normal, cutThroat }

/// Cricket scoring mode: [standard] awards points for hits on closed fields;
/// [simple] is closing-only with no point scoring.
enum CricketScoringMode { standard, simple }

/// The seven Cricket fields in display order (20..15 then 25 for the Bull).
const List<int> cricketFields = [20, 19, 18, 17, 16, 15, 25];

/// Maps a Cricket field number to its label value (25 is displayed as "Bull").
int cricketFieldLabel(int field) => field; // 25 displayed as "Bull"

/// A Cricket game configuration and result. Per-dart hits are stored separately
/// as [CricketThrow] records.
class CricketGame {
  final int? id;
  final CricketVariant variant;
  final CricketScoringMode scoringMode;
  final int legs;
  final int sets;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<int> playerIds;

  /// Non-null when this is a team game.
  final List<TeamConfig>? teams;

  /// How the throwing order was determined.
  final StartingOrder startingOrder;

  const CricketGame({
    this.id,
    required this.variant,
    required this.scoringMode,
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

  /// Serializes this game to a row map for the SQLite `cricket_games` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'variant': variant.index,
    'scoring_mode': scoringMode.index,
    'legs': legs,
    'sets': sets,
    'created_at': createdAt.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
    'player_ids': jsonEncode(playerIds),
    'team_config_json': encodeTeamConfigs(teams),
    'starting_order': startingOrder.index,
  };

  /// Reconstructs a Cricket game from a SQLite row map.
  factory CricketGame.fromMap(Map<String, dynamic> map) => CricketGame(
    id: map['id'] as int?,
    variant: CricketVariant.values[map['variant'] as int],
    scoringMode: CricketScoringMode.values[map['scoring_mode'] as int],
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
  CricketGame copyWith({DateTime? finishedAt, bool clearFinishedAt = false}) =>
      CricketGame(
        id: id,
        variant: variant,
        scoringMode: scoringMode,
        legs: legs,
        sets: sets,
        createdAt: createdAt,
        finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
        playerIds: playerIds,
        teams: teams,
        startingOrder: startingOrder,
      );
}

/// A single dart thrown in a Cricket game (one dart, not a full visit), used to
/// reconstruct marks and scores and to support undo.
class CricketThrow {
  final int? id;
  final int gameId;
  final int playerId;
  final int field; // 15-20, 25=Bull, 0=miss
  final int multiplier; // 1-3; 0 for miss
  final int leg;
  final int set_;
  final DateTime thrownAt;

  const CricketThrow({
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

  /// Serializes this throw to a row map for the SQLite `cricket_throws` table.
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

  /// Reconstructs a Cricket throw from a SQLite row map.
  factory CricketThrow.fromMap(Map<String, dynamic> map) => CricketThrow(
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
