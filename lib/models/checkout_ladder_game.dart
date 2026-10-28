import 'dart:convert';
import 'game.dart' show CheckoutMode;
import 'starting_order.dart';
import 'team_config.dart';

export 'game.dart' show CheckoutMode;
export 'starting_order.dart';
export 'team_config.dart';

/// How a Checkout Ladder game is played: [training] climbs without a winner
/// until the game is ended or 170 is checked, [race] is won by the first slot
/// to check the target number.
///
/// Stored by index, so never reorder it.
enum CheckoutLadderVariant { training, race }

/// The highest number a ladder reaches. Checking it completes the ladder.
const int kCheckoutLadderTop = 170;

/// A Checkout Ladder game configuration and result. The darts are stored
/// separately as [CheckoutLadderThrow] records; where every slot stands is
/// replayed from them.
class CheckoutLadderGame {
  final int? id;
  final CheckoutLadderVariant variant;

  /// The number every ladder starts on, and its first floor.
  final int startNumber;

  /// The number a race is won on. Null in training.
  final int? targetNumber;

  /// Darts an attempt holds below [stepFrom], or everywhere when that is null.
  final int dartsPerAttempt;

  /// The number from which an attempt holds [stepDarts] instead. Null when the
  /// attempt size never changes.
  final int? stepFrom;

  /// Darts an attempt holds from [stepFrom] on.
  final int? stepDarts;

  /// The check-out rule every slot finishes under.
  final CheckoutMode checkOut;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<int> playerIds;

  /// Non-null when this is a team game.
  final List<TeamConfig>? teams;

  /// How the throwing order was determined.
  final StartingOrder startingOrder;

  const CheckoutLadderGame({
    this.id,
    required this.variant,
    required this.startNumber,
    this.targetNumber,
    required this.dartsPerAttempt,
    this.stepFrom,
    this.stepDarts,
    this.checkOut = CheckoutMode.doubleOut,
    required this.createdAt,
    this.finishedAt,
    required this.playerIds,
    this.teams,
    this.startingOrder = StartingOrder.random,
  });

  /// Whether this game is played in teams rather than individually.
  bool get isTeamGame => teams != null && teams!.isNotEmpty;

  /// Whether this game is a race rather than a training session.
  bool get isRace => variant == CheckoutLadderVariant.race;

  /// How many darts an attempt on [number] holds.
  int dartsFor(int number) =>
      stepFrom != null && stepDarts != null && number >= stepFrom!
      ? stepDarts!
      : dartsPerAttempt;

  /// Serializes this game to a row map for the SQLite `checkout_ladder_games` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'variant': variant.index,
    'start_number': startNumber,
    'target_number': targetNumber,
    'darts_per_attempt': dartsPerAttempt,
    'step_from': stepFrom,
    'step_darts': stepDarts,
    'checkout_mode': checkOut.index,
    'created_at': createdAt.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
    'player_ids': jsonEncode(playerIds),
    'team_config_json': encodeTeamConfigs(teams),
    'starting_order': startingOrder.index,
  };

  /// Reconstructs a Checkout Ladder game from a SQLite row map.
  factory CheckoutLadderGame.fromMap(
    Map<String, dynamic> map,
  ) => CheckoutLadderGame(
    id: map['id'] as int?,
    variant: CheckoutLadderVariant.values[map['variant'] as int],
    startNumber: map['start_number'] as int,
    targetNumber: map['target_number'] as int?,
    dartsPerAttempt: map['darts_per_attempt'] as int,
    stepFrom: map['step_from'] as int?,
    stepDarts: map['step_darts'] as int?,
    checkOut: CheckoutMode.values[map['checkout_mode'] as int],
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    finishedAt: map['finished_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['finished_at'] as int)
        : null,
    playerIds: (jsonDecode(map['player_ids'] as String) as List).cast<int>(),
    teams: decodeTeamConfigs(map['team_config_json'] as String?),
    startingOrder: StartingOrder.values[map['starting_order'] as int? ?? 0],
  );

  /// Returns a copy with [id] or [finishedAt] replaced, or [finishedAt]
  /// cleared when [clearFinishedAt] is set, which reopens a game whose deciding
  /// dart was undone. Copying rather than rebuilding the object by hand keeps
  /// every other field, so a new field cannot be forgotten here.
  CheckoutLadderGame copyWith({
    int? id,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
  }) => CheckoutLadderGame(
    id: id ?? this.id,
    variant: variant,
    startNumber: startNumber,
    targetNumber: targetNumber,
    dartsPerAttempt: dartsPerAttempt,
    stepFrom: stepFrom,
    stepDarts: stepDarts,
    checkOut: checkOut,
    createdAt: createdAt,
    finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
    playerIds: playerIds,
    teams: teams,
    startingOrder: startingOrder,
  );
}

/// A single dart thrown in a Checkout Ladder game. Only what was hit is
/// stored: the number, the rest, the attempt and the floor it was thrown at
/// are replayed from the darts before it.
class CheckoutLadderThrow {
  final int? id;
  final int gameId;
  final int playerId;
  final int field; // 1-20, 25=Bull, 0=miss
  final int multiplier; // 1-3; 0 for miss
  final DateTime thrownAt;

  const CheckoutLadderThrow({
    this.id,
    required this.gameId,
    required this.playerId,
    required this.field,
    required this.multiplier,
    required this.thrownAt,
  });

  /// Whether this dart missed all scoring fields.
  bool get isMiss => field == 0 || multiplier == 0;

  /// The points this dart scores, the bull counting 25 single and 50 double.
  int get score {
    if (isMiss) return 0;
    if (field == 25) return multiplier == 2 ? 50 : 25;
    return field * multiplier;
  }

  /// Returns a copy carrying the row [id] the database assigned.
  CheckoutLadderThrow withId(int id) => CheckoutLadderThrow(
    id: id,
    gameId: gameId,
    playerId: playerId,
    field: field,
    multiplier: multiplier,
    thrownAt: thrownAt,
  );

  /// Serializes this throw to a row map for the SQLite `checkout_ladder_throws` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'game_id': gameId,
    'player_id': playerId,
    'field': field,
    'multiplier': multiplier,
    'thrown_at': thrownAt.millisecondsSinceEpoch,
  };

  /// Reconstructs a Checkout Ladder throw from a SQLite row map.
  factory CheckoutLadderThrow.fromMap(Map<String, dynamic> map) =>
      CheckoutLadderThrow(
        id: map['id'] as int?,
        gameId: map['game_id'] as int,
        playerId: map['player_id'] as int,
        field: map['field'] as int,
        multiplier: map['multiplier'] as int,
        thrownAt: DateTime.fromMillisecondsSinceEpoch(map['thrown_at'] as int),
      );
}
