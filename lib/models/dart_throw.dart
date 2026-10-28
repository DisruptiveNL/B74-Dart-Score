/// A single recorded visit (turn) in an X01 game: the points scored, how many
/// darts were used, where in the leg/set it happened, and whether it busted.
///
/// One row corresponds to up to three darts thrown in one turn, not a single
/// dart. Individual dart hits are optionally captured in [hitsJson].
class DartThrow {
  final int? id;
  final int gameId;
  final int playerId;
  final int score; // points scored in this visit (0-180)
  final int dartsUsed; // 1-3 darts used
  final int leg;
  final int set;
  final int remainingBefore; // score before this throw
  final DateTime thrownAt;
  final bool bust;

  /// JSON-encoded list of individual dart hits: [{"f":20,"m":3}, ...]
  /// f = field (1-20, 25=bull), m = multiplier (1/2/3). Null if not captured.
  final String? hitsJson;

  /// How many darts of this visit were thrown at a finish, decided when the
  /// visit was recorded by `checkoutDartsInVisit`. 0 to 3.
  ///
  /// Stored rather than derived, because deciding it needs the individual darts
  /// and the check-out rule that applied to this player in this game, and
  /// neither survives into every place the statistics are counted: throws that
  /// arrive over sync carry no hits and hang off a game that was never played.
  final int checkoutDarts;

  const DartThrow({
    this.id,
    required this.gameId,
    required this.playerId,
    required this.score,
    required this.dartsUsed,
    required this.leg,
    required this.set,
    required this.remainingBefore,
    required this.thrownAt,
    this.bust = false,
    this.hitsJson,
    this.checkoutDarts = 0,
  });

  /// Whether this visit was an attempt at the leg: at least one of its darts
  /// flew while a single dart could have finished.
  bool get checkoutAttempt => checkoutDarts > 0;

  /// Remaining score after this visit; unchanged from [remainingBefore] on a bust.
  int get remainingAfter => bust ? remainingBefore : remainingBefore - score;

  /// Serializes this throw to a row map for the SQLite `throws` table.
  Map<String, dynamic> toMap() => {
    'id': id,
    'game_id': gameId,
    'player_id': playerId,
    'score': score,
    'darts_used': dartsUsed,
    'leg': leg,
    'set': set,
    'remaining_before': remainingBefore,
    'thrown_at': thrownAt.millisecondsSinceEpoch,
    'bust': bust ? 1 : 0,
    'hits_json': hitsJson,
    'checkout_darts': checkoutDarts,
  };

  /// Reconstructs a throw from a SQLite row map.
  factory DartThrow.fromMap(Map<String, dynamic> map) => DartThrow(
    id: map['id'] as int?,
    gameId: map['game_id'] as int,
    playerId: map['player_id'] as int,
    score: map['score'] as int,
    dartsUsed: map['darts_used'] as int,
    leg: map['leg'] as int,
    set: map['set'] as int,
    remainingBefore: map['remaining_before'] as int,
    thrownAt: DateTime.fromMillisecondsSinceEpoch(map['thrown_at'] as int),
    bust: (map['bust'] as int) == 1,
    hitsJson: map['hits_json'] as String?,
    checkoutDarts: map['checkout_darts'] as int? ?? 0,
  );
}
