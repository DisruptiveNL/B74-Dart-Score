import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBindingObserver;
import '../database/db_helper.dart';
import '../models/player.dart';
import '../models/game.dart';
import '../models/dart_throw.dart';
import '../utils/bot_strategy_x01.dart';
import '../utils/finish_calculator.dart';
import '../utils/b74_finish_validation.dart';
import 'bot_runner.dart';
import '../utils/placement.dart';
import '../utils/throw_stats.dart';
import '../utils/player_label.dart';
import '../widgets/dartboard_input.dart' show DartEntry, DartboardInputSource;

/// Minimum darts to finish a game from a given start score (double-out).
const Map<int, int> minimumDartsForScore = {
  101: 2,
  170: 3,
  201: 4,
  301: 6,
  501: 9,
  701: 12,
  1001: 17,
};

/// The set and leg that [throws] last reached: the highest set with throws,
/// and the highest leg *within that set*.
///
/// Leg numbering restarts at 1 in every set, so the leg maximum must never be
/// taken across sets. Doing so points a resume at a leg/set pair that has no
/// throws, which wipes the running leg's scores and misnumbers every later
/// throw. Returns leg 1 / set 1 for a game without throws.
({int leg, int set}) currentLegAndSet(List<DartThrow> throws) {
  var set = 1;
  for (final t in throws) {
    if (t.set > set) set = t.set;
  }
  var leg = 1;
  for (final t in throws) {
    if (t.set == set && t.leg > leg) leg = t.leg;
  }
  return (leg: leg, set: set);
}

/// Every set/leg pair [throws] contains, in playing order.
///
/// Tallying legs and sets by counting from 1 up to the highest leg number does
/// not work, because each set runs its own number of legs: an earlier set can
/// hold more legs than the one in play. Iterating the pairs that really exist
/// avoids both missing a leg and inventing one.
List<({int set, int leg})> playedLegs(List<DartThrow> throws) {
  final seen = <({int set, int leg})>{};
  for (final t in throws) {
    seen.add((set: t.set, leg: t.leg));
  }
  return seen.toList()..sort(
    (a, b) => a.set != b.set ? a.set.compareTo(b.set) : a.leg.compareTo(b.leg),
  );
}

/// The leg and set the game stands in, given every throw it holds.
///
/// Usually that is the leg the last throws fell in. Once those throws have
/// decided it, the game stands at the start of the next leg, or of the next
/// set when the checkout also took the set, which is where [_handleCheckout]
/// leaves it during play. A decided leg is over: resuming on it would put the
/// winner back on the board at zero, drop the leg it just won, and file the
/// next dart under a leg number that is spent. A checkout that won the game
/// moves nothing, there is no leg after it.
///
/// Placement games keep the plain position. Every slot plays every leg out
/// there, so a checkout does not end the leg and the placement resume decides
/// on its own when it is over.
({int leg, int set}) openLegAndSet(Game game, List<DartThrow> throws) {
  final position = currentLegAndSet(throws);
  if (game.placementMode) return position;

  final legThrows = throwsInLeg(throws, position.leg, position.set)
    ..sort(_byThrowOrder);
  if (legThrows.isEmpty) return position;

  final decider = legThrows.last;
  if (decider.bust || decider.remainingBefore - decider.score != 0) {
    return position;
  }

  final winner = _sideOf(game, decider.playerId);

  // Replay the winner's legs and sets the way a live checkout counts them, so
  // that a leg won as the last of its set moves the game on to the next set.
  var legsInSet = 0;
  var setsWon = 0;
  var set = 0;
  var tookSet = false;
  for (final pos in playedLegs(throws)) {
    if (pos.set != set) {
      set = pos.set;
      legsInSet = 0;
    }
    if (!_sideWonLeg(throws, winner, pos.leg, pos.set)) continue;
    legsInSet++;
    if (legsInSet >= game.legs) {
      setsWon++;
      legsInSet = 0;
      tookSet = pos.leg == position.leg && pos.set == position.set;
    }
  }

  if (setsWon >= game.sets) return position;
  return tookSet
      ? (leg: 1, set: position.set + 1)
      : (leg: position.leg + 1, set: position.set);
}

/// The player ids that share a slot with [playerId]: the whole team in a team
/// game, the player alone otherwise.
List<int> _sideOf(Game game, int playerId) {
  if (game.isTeamGame) {
    for (final team in game.teams!) {
      if (team.playerIds.contains(playerId)) return team.playerIds;
    }
  }
  return [playerId];
}

/// Perfect legs a slot has finished, rebuilt from [slotThrows] alone.
///
/// A rebuild loses the counter [_handleCheckout] keeps live, so it is counted
/// again here rather than left at zero, which would drop the badge the summary
/// shows. [slotThrows] holds every member's throws for a team, whose darts all
/// count towards the same leg.
int _perfectLegsOf(int startScore, List<DartThrow> slotThrows) =>
    perfectLegsFromThrows(slotThrows, (_) => minimumDartsForScore[startScore]);

/// Whether the slot made up of [ids] checked out in [leg] of [set].
bool _sideWonLeg(List<DartThrow> throws, List<int> ids, int leg, int set) {
  for (final t in throws) {
    if (t.leg != leg || t.set != set || !ids.contains(t.playerId)) continue;
    if (!t.bust && t.remainingBefore - t.score == 0) return true;
  }
  return false;
}

/// Orders throws the way they were played: by time, and by row id when two
/// visits fall in the same millisecond.
int _byThrowOrder(DartThrow a, DartThrow b) {
  final byTime = a.thrownAt.compareTo(b.thrownAt);
  return byTime != 0 ? byTime : (a.id ?? 0).compareTo(b.id ?? 0);
}

/// The index in [members] of the team member who throws the next visit:
/// the one after whoever threw [teamThrows] last, or the first member for a
/// team that has not thrown yet. [teamThrows] must be in playing order.
///
/// The rotation runs on across legs and sets, so it cannot be recovered from
/// the number of visits that fell in the leg in play: a leg that opened on the
/// second member would hand the turn to the wrong one for the rest of the game.
int _nextMemberIndex(List<Player> members, List<DartThrow> teamThrows) {
  if (teamThrows.isEmpty) return 0;
  final last = members.indexWhere((p) => p.id == teamThrows.last.playerId);
  return last < 0 ? 0 : (last + 1) % members.length;
}

/// Darts a slot has used in [leg]/[set] of the current game.
///
/// [throws] is the slot's full throw history, which already contains the visit
/// that just checked out: the caller must not add that visit's darts on top.
/// Pass [playerId] to count a single player's darts, or null for a team slot,
/// where every member's darts belong to the same leg.
int legDartsUsed(List<DartThrow> throws, int leg, int set, {int? playerId}) =>
    throws
        .where(
          (t) =>
              t.leg == leg &&
              t.set == set &&
              (playerId == null || t.playerId == playerId),
        )
        .fold(0, (sum, t) => sum + t.dartsUsed);

/// Decodes a [DartThrow.hitsJson] string back into individual dart entries,
/// or null if no per-dart hits were recorded for that visit.
List<DartEntry>? _parseHits(String? hitsJson) {
  if (hitsJson == null) return null;
  final list = jsonDecode(hitsJson) as List;
  return list.map((e) {
    final m = e as Map<String, dynamic>;
    final field = m['f'] as int;
    final modifier = m['m'] as int;
    final score = field == 0
        ? 0
        : (field == 25 ? (modifier == 2 ? 50 : 25) : field * modifier);
    return DartEntry(field: field, modifier: modifier, score: score);
  }).toList();
}

/// A unit of redo state for [GameProvider.redoLastDart]: either a single dart
/// to re-add to the in-progress visit, or, for legacy throws recorded before
/// per-dart [DartThrow.hitsJson] was captured, a whole visit to re-insert verbatim.
class _RedoEntry {
  final DartEntry? dart;
  final DartThrow? legacyVisit;

  const _RedoEntry.dart(DartEntry entry) : dart = entry, legacyVisit = null;
  const _RedoEntry.legacyVisit(DartThrow visit)
    : dart = null,
      legacyVisit = visit;
}

// ── PlayerState ───────────────────────────────────────────────────────────────

/// Immutable scoreboard state for one slot in an X01 game.
///
/// A slot is either a single player or a whole team. For teams, [players] holds
/// every member and [currentPlayerIdx] tracks whose turn it is within the team;
/// [displayName] is the team or player name shown on the scoreboard.
class PlayerState implements LabelledSlot {
  /// Human-readable name for the scoreboard: team name or player name.
  @override
  final String displayName;

  /// All players in this slot: 1 for individual, N for team.
  @override
  final List<Player> players;

  /// Which player in [players] throws NEXT (rotates after each team visit).
  final int currentPlayerIdx;

  final int legsWon;
  final int setsWon;
  final int remaining;
  final List<DartThrow> throws;
  final int perfectLegs;

  @override
  final bool isTeamSlot;

  /// In placement-mode games: this slot's 1-based finishing position for the
  /// current leg, or null if it hasn't checked out yet this leg.
  final int? legPlacement;

  /// In placement-mode games: cumulative sum of [legPlacement] across all
  /// completed legs, used as a tie-breaker for the final ranking.
  final int placementSum;

  /// In placement-mode games: cumulative [placementPoints] across all completed
  /// legs, which is what the final ranking is decided on.
  final int placementPoints;

  const PlayerState({
    required this.displayName,
    required this.players,
    this.currentPlayerIdx = 0,
    required this.legsWon,
    required this.setsWon,
    required this.remaining,
    required this.throws,
    this.perfectLegs = 0,
    this.isTeamSlot = false,
    this.legPlacement,
    this.placementSum = 0,
    this.placementPoints = 0,
  });

  /// The player who throws next (backward-compatible accessor).
  Player get player => players[currentPlayerIdx];

  /// This slot's members in the order they throw from now on, starting with
  /// [player].
  ///
  /// [currentPlayerIdx] always points at the member who throws this slot's next
  /// dart: while the slot holds the turn that is the member at the oche, while
  /// it is idle it is the member who steps up when the slot comes around again.
  /// One rotation covers both readings.
  List<Player> get throwingOrder => [
    for (var k = 0; k < players.length; k++)
      players[(currentPlayerIdx + k) % players.length],
  ];

  /// Whether this slot represents a team rather than a single player.
  bool get isTeam => players.length > 1;

  /// Total number of darts thrown by this slot across the game.
  int get totalDarts => throws.fold(0, (s, t) => s + t.dartsUsed);

  /// Total number of visits (turns) taken by this slot.
  int get totalVisits => throws.length;

  /// Three-dart average for this slot; busts count as zero scored.
  double get average {
    if (totalDarts == 0) return 0;
    final scored = throws.fold(0, (s, t) => s + (t.bust ? 0 : t.score));
    return (scored / totalDarts) * 3;
  }

  /// Returns a copy with the given mutable fields replaced; identity fields
  /// ([displayName], [players], [isTeamSlot]) are preserved.
  /// Returns a copy with the given mutable fields replaced. [legPlacement] is
  /// only overridden when [resetLegPlacement] is true (so a normal copyWith
  /// call doesn't accidentally clear it), in which case [legPlacement] itself
  /// supplies the new value (including null).
  PlayerState copyWith({
    int? currentPlayerIdx,
    int? legsWon,
    int? setsWon,
    int? remaining,
    List<DartThrow>? throws,
    int? perfectLegs,
    int? legPlacement,
    bool resetLegPlacement = false,
    int? placementSum,
    int? placementPoints,
  }) => PlayerState(
    displayName: displayName,
    players: players,
    currentPlayerIdx: currentPlayerIdx ?? this.currentPlayerIdx,
    legsWon: legsWon ?? this.legsWon,
    setsWon: setsWon ?? this.setsWon,
    remaining: remaining ?? this.remaining,
    throws: throws ?? this.throws,
    perfectLegs: perfectLegs ?? this.perfectLegs,
    isTeamSlot: isTeamSlot,
    legPlacement: resetLegPlacement
        ? legPlacement
        : (legPlacement ?? this.legPlacement),
    placementSum: placementSum ?? this.placementSum,
    placementPoints: placementPoints ?? this.placementPoints,
  );
}

// ── GameProvider ──────────────────────────────────────────────────────────────

/// Active-game state machine for X01 games (individual and team).
///
/// Owns the per-slot [PlayerState]s, the current leg/set/turn, win detection,
/// and undo/redo. Every throw is persisted immediately via [DbHelper]; resuming
/// rebuilds the full state by replaying stored throws, which is also how undo
/// and redo recompute the board.
class GameProvider extends ChangeNotifier
    with WidgetsBindingObserver, BotRunner
    implements DartboardInputSource {
  final DbHelper _db = DbHelper.instance;

  Game? _game;
  // Competition singles alternate leg starters independently of the checkout winner.
  bool _competitionSingle = false;
  List<PlayerState> _playerStates = [];
  int _currentPlayerIndex = 0;
  int _currentLeg = 1;
  int _currentSet = 1;
  bool _gameOver = false;
  int? _winnerId;
  Map<int, PlayerHandicap> _handicaps = {};

  /// Darts entered so far for the current player's in-progress (not yet
  /// committed) visit, in throw order. Cleared whenever the visit is
  /// committed or the turn moves on.
  List<DartEntry> _currentVisitDarts = [];

  /// Tracks if a check-in double/triple was hit within [_currentVisitDarts].
  bool _checkedInThisVisit = false;

  /// Darts (or, for legacy throws without per-dart hits, whole visits)
  /// removed by [undoLastDart], in undo order, restorable via [redoLastDart].
  final List<_RedoEntry> _redoStack = [];

  Game? get game => _game;
  List<PlayerState> get playerStates => _playerStates;
  int get currentPlayerIndex => _currentPlayerIndex;
  PlayerState get currentPlayerState => _playerStates[_currentPlayerIndex];
  int get currentLeg => _currentLeg;
  int get currentSet => _currentSet;
  bool get gameOver => _gameOver;
  int? get winnerId => _winnerId;

  /// Darts entered so far for the current player's in-progress visit.
  @override
  List<DartEntry> get currentVisitDarts =>
      List.unmodifiable(_currentVisitDarts);

  /// Number of darts entered so far in the current in-progress visit.
  int get dartsInVisit => _currentVisitDarts.length;

  /// Whether a qualifying check-in dart was thrown this visit (live).
  bool get checkedInThisVisit => _checkedInThisVisit;

  /// Whether there is any dart left to undo: either in the in-progress visit
  /// or in a previously recorded visit (possibly a previous player's turn).
  ///
  /// Not while a bot is throwing, and not when every recorded visit is a
  /// bot's: those are never undone on their own, see [undoLastDart].
  @override
  bool get canUndoDart =>
      !isBotTurn &&
      (_currentVisitDarts.isNotEmpty ||
          allThrows().any((t) => !_isBotId(t.playerId)));

  /// Whether a previously undone dart (or legacy visit) can be restored.
  @override
  bool get canRedoDart => !isBotTurn && _redoStack.isNotEmpty;

  /// The slot that throws after the current one.
  ///
  /// In placement mode a slot that already checked out this leg is skipped, the
  /// same way the scoreboard drops it to a chip. Falls back to the current slot
  /// when nobody else is left to throw.
  int get nextSlotIndex {
    final active = [
      for (var i = 0; i < _playerStates.length; i++)
        if (!(_game?.placementMode ?? false) ||
            _playerStates[i].legPlacement == null)
          i,
    ];
    if (active.length < 2) return _currentPlayerIndex;
    final pos = active.indexOf(_currentPlayerIndex);
    if (pos < 0) return active.first;
    return active[(pos + 1) % active.length];
  }

  /// Whether check-in rules apply: only in the very first leg of the game.
  bool get _checkInActive => _currentLeg == 1 && _currentSet == 1;

  /// Check-in rule for the player about to throw (handicap overrides game default).
  GameMode get currentGameMode {
    if (!_checkInActive) return GameMode.straightIn;
    final pid = currentPlayerState.player.id;
    return _handicaps[pid]?.checkIn ?? _game!.gameMode;
  }

  /// Checkout rule for the player about to throw (handicap overrides game default).
  CheckoutMode get currentCheckoutMode {
    final pid = currentPlayerState.player.id;
    return _handicaps[pid]?.checkOut ?? _game!.checkoutMode;
  }

  /// Whether the player about to throw already checked in earlier this leg
  /// (i.e. before the in-progress visit).
  bool get currentHasCheckedIn =>
      currentGameMode == GameMode.straightIn ||
      currentPlayerState.remaining < _game!.startScore;

  /// Sum of dart scores entered so far in the in-progress visit.
  int get _visitScoreSoFar => _currentVisitDarts.fold(0, (s, d) => s + d.score);

  /// Remaining score if the in-progress visit ended right now.
  int get liveRunningRemaining =>
      currentPlayerState.remaining - _visitScoreSoFar;

  /// Whether the in-progress visit would currently bust (negative remaining,
  /// or stuck on 1 with double/master-out while checked in).
  @override
  bool get liveBust {
    final running = liveRunningRemaining;
    final stuck =
        running == 1 &&
        currentCheckoutMode != CheckoutMode.straightOut &&
        (currentHasCheckedIn || _checkedInThisVisit);
    return running < 0 || stuck;
  }

  /// Remaining score to display for the current player: the live running
  /// remaining, or the pre-visit remaining if the in-progress visit busts.
  int get liveDisplayRemaining =>
      liveBust ? currentPlayerState.remaining : liveRunningRemaining;

  /// Per-player check-in/check-out handicap for the player about to throw, if any.
  PlayerHandicap? get currentPlayerHandicap {
    if (_playerStates.isEmpty) return null;
    final pid = _playerStates[_currentPlayerIndex].player.id;
    return pid != null ? _handicaps[pid] : null;
  }

  /// Read-only view of all per-player handicaps keyed by player id.
  Map<int, PlayerHandicap> get handicaps => Map.unmodifiable(_handicaps);

  // ── Bot ───────────────────────────────────────────────────────────────────

  @override
  bool get isBotTurn =>
      _game != null &&
      !_gameOver &&
      _playerStates.isNotEmpty &&
      currentPlayerState.player.isBot;

  /// Whether [playerId] belongs to one of the bots in this game.
  bool _isBotId(int playerId) => _playerStates
      .expand((s) => s.players)
      .any((p) => p.id == playerId && p.isBot);

  @override
  Future<void> throwBotDart() async {
    final target = x01Target(
      remaining: liveRunningRemaining,
      dartsLeft: 3 - _currentVisitDarts.length,
      checkedIn: currentHasCheckedIn || _checkedInThisVisit,
      checkOut: currentCheckoutMode,
      checkIn: currentGameMode,
    );
    final hit = botThrower.throwAt(target, currentPlayerState.player.botLevel!);
    _redoStack.clear();
    await _addDart(hit.field, hit.multiplier == 0 ? 1 : hit.multiplier);
    notifyListeners();
  }

  /// Records [pending] as the current slot's visit and moves the turn on.
  Future<void> _settleVisit(
    ({int score, int dartsUsed, bool bust, List<DartEntry> hits}) pending,
  ) async {
    _currentVisitDarts = [];
    _checkedInThisVisit = false;
    await _submitVisit(
      pending.score,
      pending.dartsUsed,
      bust: pending.bust,
      hits: pending.hits,
    );
  }

  // ── Resume ────────────────────────────────────────────────────────────────

  /// Restores a previously started game from the database by replaying all
  /// stored throws, rebuilding per-slot state and the current leg/set/turn,
  /// and sets a bot on turn throwing again.
  Future<void> resumeGame(Game game, List<Player> players) async {
    releaseBot();
    await _rebuildFromDb(game, players);
    scheduleBot();
  }

  /// The rebuild behind [resumeGame], shared with undo and redo, which must
  /// finish restoring the in-progress visit before any bot dart may fly and so
  /// keep the bot held back until they are done.
  Future<void> _rebuildFromDb(Game game, List<Player> players) async {
    // Always reassign, never merge: leaving the previous game's handicaps in
    // place would silently apply them to this one.
    _handicaps = game.handicaps ?? {};

    // In-progress visit and undo/redo state is only valid for the GameScreen
    // that produced it; drop it on every full rebuild of the board. Callers
    // that need to preserve it across a rebuild (undo/redo) restore it
    // afterwards.
    _currentVisitDarts = [];
    _checkedInThisVisit = false;
    _redoStack.clear();
    dropHeldVisit();

    _competitionSingle = await _db.isCompetitionGame(game.id!);
    final allThrowsRaw = await _db.getThrowsForGame(game.id!);

    final throwsByPlayer = <int, List<DartThrow>>{};
    for (final t in allThrowsRaw) {
      throwsByPlayer.putIfAbsent(t.playerId, () => []).add(t);
    }

    final position = openLegAndSet(game, allThrowsRaw);
    final maxLeg = position.leg;
    final maxSet = position.set;
    // Everything except the leg in play has been decided and counts toward
    // legs and sets won.
    final finishedLegs = playedLegs(
      allThrowsRaw,
    ).where((p) => p.set != maxSet || p.leg != maxLeg).toList();

    if (game.isTeamGame) {
      await _resumeTeamGame(
        game,
        players,
        throwsByPlayer,
        maxLeg,
        maxSet,
        finishedLegs,
      );
    } else {
      await _resumeIndividualGame(
        game,
        players,
        throwsByPlayer,
        maxLeg,
        maxSet,
        finishedLegs,
      );
    }

    _game = game;
    _gameOver = false;
    _winnerId = null;
    notifyListeners();
  }

  /// Rebuilds team-game state: tallies legs/sets won per team across completed
  /// legs, reconstructs each team's remaining score and player rotation for the
  /// current leg, and picks the team that throws next (fewest visits).
  Future<void> _resumeTeamGame(
    Game game,
    List<Player> players,
    Map<int, List<DartThrow>> throwsByPlayer,
    int maxLeg,
    int maxSet,
    List<({int set, int leg})> finishedLegs,
  ) async {
    if (game.placementMode) {
      _resumeTeamPlacementGame(game, players, throwsByPlayer, maxLeg);
      return;
    }

    final teams = game.teams!;
    final legsToWin = game.legs;

    // Compute legs/sets won per team
    final teamLegsWon = List<int>.filled(teams.length, 0);
    final teamSetsWon = List<int>.filled(teams.length, 0);
    final tempLegs = List<int>.filled(teams.length, 0);

    for (final pos in finishedLegs) {
      for (var ti = 0; ti < teams.length; ti++) {
        final winner = _teamCheckedOutLeg(
          teams[ti],
          throwsByPlayer,
          pos.leg,
          pos.set,
        );
        if (winner) {
          tempLegs[ti]++;
          if (tempLegs[ti] >= legsToWin) {
            teamSetsWon[ti]++;
            tempLegs[ti] = 0;
          }
        }
      }
    }
    for (var ti = 0; ti < teams.length; ti++) {
      teamLegsWon[ti] = tempLegs[ti];
    }

    // Build team states
    _playerStates = teams.asMap().entries.map((entry) {
      final ti = entry.key;
      final team = entry.value;
      final teamPlayers = team.playerIds
          .map((id) => players.firstWhere((p) => p.id == id))
          .toList();

      // All throws by team members
      final allTeamThrows =
          teamPlayers
              .expand((p) => throwsByPlayer[p.id!] ?? <DartThrow>[])
              .toList()
            ..sort(_byThrowOrder);

      final currentLegThrows = allTeamThrows
          .where((t) => t.leg == maxLeg && t.set == maxSet)
          .toList();

      int remaining = game.startScore;
      for (final t in currentLegThrows) {
        if (!t.bust) remaining -= t.score;
      }

      // Current player in rotation
      final currentIdx = _nextMemberIndex(teamPlayers, allTeamThrows);

      return PlayerState(
        displayName: team.name,
        players: teamPlayers,
        currentPlayerIdx: currentIdx,
        legsWon: teamLegsWon[ti],
        setsWon: teamSetsWon[ti],
        remaining: remaining,
        throws: allTeamThrows,
        perfectLegs: _perfectLegsOf(game.startScore, allTeamThrows),
        isTeamSlot: true,
      );
    }).toList();

    _resumePickTurn();

    _currentLeg = maxLeg;
    _currentSet = maxSet;
  }

  /// Rebuilds team placement-mode state: every leg is played to the end by all
  /// teams, so [legsWon]/[PlayerState.placementSum]/
  /// [PlayerState.placementPoints] and [PlayerState.legPlacement] for the
  /// current leg come from [_placementResumeState] (keyed by team index).
  void _resumeTeamPlacementGame(
    Game game,
    List<Player> players,
    Map<int, List<DartThrow>> throwsByPlayer,
    int maxLeg,
  ) {
    final teams = game.teams!;

    final throwsByTeam = <int, List<DartThrow>>{
      for (var ti = 0; ti < teams.length; ti++)
        ti:
            teams[ti].playerIds
                .expand((id) => throwsByPlayer[id] ?? <DartThrow>[])
                .toList()
              ..sort(_byThrowOrder),
    };

    final r = _placementResumeState(throwsByTeam, maxLeg);

    _playerStates = teams.asMap().entries.map((entry) {
      final ti = entry.key;
      final team = entry.value;
      final teamPlayers = team.playerIds
          .map((id) => players.firstWhere((p) => p.id == id))
          .toList();

      final allTeamThrows = throwsByTeam[ti]!;
      final currentLegThrows = allTeamThrows
          .where((t) => t.leg == maxLeg && t.set == 1)
          .toList();
      final currentIdx = _nextMemberIndex(teamPlayers, allTeamThrows);

      final placement = r.legPlacement[ti];
      int remaining = game.startScore;
      if (!r.legComplete) {
        if (placement == null) {
          for (final t in currentLegThrows) {
            if (!t.bust) remaining -= t.score;
          }
        } else {
          remaining = 0;
        }
      }

      return PlayerState(
        displayName: team.name,
        players: teamPlayers,
        currentPlayerIdx: currentIdx,
        legsWon: r.legsWon[ti] ?? 0,
        setsWon: 0,
        remaining: remaining,
        throws: allTeamThrows,
        perfectLegs: _perfectLegsOf(game.startScore, allTeamThrows),
        isTeamSlot: true,
        legPlacement: placement,
        placementSum: r.placementSum[ti] ?? 0,
        placementPoints: r.placementPoints[ti] ?? 0,
      );
    }).toList();

    if (r.legComplete) {
      _currentLeg = maxLeg + 1;
      _resumePickTurn();
      _currentSet = 1;
    } else {
      _resumePickNextSlot(maxLeg);
    }
  }

  /// Whether any member of [team] checked out (reached exactly zero) in the
  /// given [leg] and [set].
  bool _teamCheckedOutLeg(
    TeamConfig team,
    Map<int, List<DartThrow>> throwsByPlayer,
    int leg,
    int set,
  ) {
    for (final id in team.playerIds) {
      final legThrows =
          throwsByPlayer[id]
              ?.where((t) => t.leg == leg && t.set == set)
              .toList() ??
          [];
      if (legThrows.isNotEmpty &&
          !legThrows.last.bust &&
          legThrows.last.remainingBefore - legThrows.last.score == 0) {
        return true;
      }
    }
    return false;
  }

  /// Rebuilds individual-game state: tallies legs/sets won per player across
  /// completed legs, reconstructs each player's remaining score for the current
  /// leg, and picks the player who throws next (fewest visits).
  Future<void> _resumeIndividualGame(
    Game game,
    List<Player> players,
    Map<int, List<DartThrow>> throwsByPlayer,
    int maxLeg,
    int maxSet,
    List<({int set, int leg})> finishedLegs,
  ) async {
    if (game.placementMode) {
      _resumeIndividualPlacementGame(game, players, throwsByPlayer, maxLeg);
      return;
    }

    final legsWon = <int, int>{for (final p in players) p.id!: 0};
    final setsWon = <int, int>{for (final p in players) p.id!: 0};
    final legsToWinSet = game.legs;

    for (final pos in finishedLegs) {
      for (final p in players) {
        final legThrows =
            throwsByPlayer[p.id!]
                ?.where((t) => t.leg == pos.leg && t.set == pos.set)
                .toList() ??
            [];
        if (legThrows.isNotEmpty &&
            !legThrows.last.bust &&
            legThrows.last.remainingBefore - legThrows.last.score == 0) {
          legsWon[p.id!] = (legsWon[p.id!] ?? 0) + 1;
          if ((legsWon[p.id!] ?? 0) >= legsToWinSet) {
            setsWon[p.id!] = (setsWon[p.id!] ?? 0) + 1;
            legsWon[p.id!] = 0;
          }
        }
      }
    }

    _playerStates = players.map((p) {
      final currentLegThrows =
          throwsByPlayer[p.id!]
              ?.where((t) => t.leg == maxLeg && t.set == maxSet)
              .toList() ??
          [];
      int remaining = game.startScore;
      for (final t in currentLegThrows) {
        if (!t.bust) remaining -= t.score;
      }
      return PlayerState(
        displayName: p.name,
        players: [p],
        legsWon: legsWon[p.id!] ?? 0,
        setsWon: setsWon[p.id!] ?? 0,
        remaining: remaining,
        throws: throwsByPlayer[p.id!] ?? [],
        perfectLegs: _perfectLegsOf(
          game.startScore,
          throwsByPlayer[p.id!] ?? const [],
        ),
      );
    }).toList();

    if (_competitionSingle && _playerStates.length == 2) {
      _resumeCompetitionTurn(maxLeg, maxSet);
    } else {
      _resumePickTurn();
    }

    _currentLeg = maxLeg;
    _currentSet = maxSet;
  }

  /// Competition resume: on a fresh leg start with the alternating slot,
  /// otherwise resume after the last visit in this leg (not the last checkout
  /// of the previous leg). The slot order is fixed at game creation.
  void _resumeCompetitionTurn(int leg, int set) {
    DartThrow? last;
    var lastSlot = -1;
    for (var i = 0; i < _playerStates.length; i++) {
      for (final t in _playerStates[i].throws) {
        if (t.leg != leg || t.set != set) continue;
        if (last == null || _byThrowOrder(t, last) > 0) {
          last = t;
          lastSlot = i;
        }
      }
    }
    _currentPlayerIndex = lastSlot < 0 ? (leg - 1) % 2 : (lastSlot + 1) % 2;
  }

  /// The index of the slot the final ranking puts first, through the one order
  /// [placementOrder] defines, so the winner this provider names and the winner
  /// the ranking card lists first are the same slot.
  int _placementLeader() => placementOrder(
    [for (var i = 0; i < _playerStates.length; i++) i],
    points: {
      for (var i = 0; i < _playerStates.length; i++)
        i: _playerStates[i].placementPoints,
    },
    legsWon: {
      for (var i = 0; i < _playerStates.length; i++)
        i: _playerStates[i].legsWon,
    },
    placementSum: {
      for (var i = 0; i < _playerStates.length; i++)
        i: _playerStates[i].placementSum,
    },
  ).first;

  /// Computes the placement-mode ranking for a resume. [maxLeg] is treated as
  /// fully complete (and its results folded into
  /// [legsWon]/[placementSum]/[placementPoints])
  /// either when every id already has a checkout in [maxLeg], or when all but
  /// one do -- the last remaining id then automatically takes last place, per
  /// [_handlePlacementCheckout]'s "second-to-last checkout ends the leg" rule.
  /// [legPlacement] gives each id's finishing position in [maxLeg], or `null`
  /// if [maxLeg] is still in progress for that id.
  ({
    Map<int, int> legsWon,
    Map<int, int> placementSum,
    Map<int, int> placementPoints,
    Map<int, int?> legPlacement,
    bool legComplete,
  })
  _placementResumeState(Map<int, List<DartThrow>> throwsById, int maxLeg) {
    final ids = throwsById.keys.toList();
    final currentPlacements = legPlacements(throwsById, maxLeg, 1);
    final completePlacements = completedLegPlacements(throwsById, maxLeg, 1);
    final legComplete = completePlacements.length == ids.length;

    final ranking = placementRanking(throwsById, maxLeg - 1, 1);
    final legsWon = Map<int, int>.of(ranking.legsWon);
    final placementSum = Map<int, int>.of(ranking.placementSum);
    final points = Map<int, int>.of(
      placementPointsTotal(throwsById, maxLeg - 1, 1),
    );

    final placementsForMaxLeg = legComplete
        ? completePlacements
        : currentPlacements;
    for (final entry in placementsForMaxLeg.entries) {
      placementSum[entry.key] = (placementSum[entry.key] ?? 0) + entry.value;
      points[entry.key] =
          (points[entry.key] ?? 0) + placementPoints(entry.value, ids.length);
      if (entry.value == 1) legsWon[entry.key] = (legsWon[entry.key] ?? 0) + 1;
    }

    return (
      legsWon: legsWon,
      placementSum: placementSum,
      placementPoints: points,
      legPlacement: {
        for (final id in ids) id: legComplete ? null : currentPlacements[id],
      },
      legComplete: legComplete,
    );
  }

  /// Rebuilds individual placement-mode state: every leg is played to the end
  /// by all players, so [legsWon]/[PlayerState.placementSum]/
  /// [PlayerState.placementPoints] come from [_placementResumeState], and
  /// [PlayerState.legPlacement] for the current leg comes from the same.
  void _resumeIndividualPlacementGame(
    Game game,
    List<Player> players,
    Map<int, List<DartThrow>> throwsByPlayer,
    int maxLeg,
  ) {
    final throwsById = {
      for (final p in players) p.id!: throwsByPlayer[p.id!] ?? <DartThrow>[],
    };

    final r = _placementResumeState(throwsById, maxLeg);

    _playerStates = players.map((p) {
      final placement = r.legPlacement[p.id!];
      int remaining = game.startScore;
      if (!r.legComplete) {
        if (placement == null) {
          final currentLegThrows = (throwsById[p.id!] ?? [])
              .where((t) => t.leg == maxLeg && t.set == 1)
              .toList();
          for (final t in currentLegThrows) {
            if (!t.bust) remaining -= t.score;
          }
        } else {
          remaining = 0;
        }
      }

      return PlayerState(
        displayName: p.name,
        players: [p],
        legsWon: r.legsWon[p.id!] ?? 0,
        setsWon: 0,
        remaining: remaining,
        throws: throwsByPlayer[p.id!] ?? [],
        perfectLegs: _perfectLegsOf(
          game.startScore,
          throwsByPlayer[p.id!] ?? const [],
        ),
        legPlacement: placement,
        placementSum: r.placementSum[p.id!] ?? 0,
        placementPoints: r.placementPoints[p.id!] ?? 0,
      );
    }).toList();

    if (r.legComplete) {
      _currentLeg = maxLeg + 1;
      _resumePickTurn();
      _currentSet = 1;
    } else {
      _resumePickNextSlot(maxLeg);
    }
  }

  /// Points the turn at the slot that throws next after a rebuild: the one
  /// after whoever threw the game's last visit, mirroring [_advancePlayer].
  /// Slots that already finished the leg in placement mode are skipped. A game
  /// without throws starts at the first slot.
  ///
  /// Counting the visits of the leg in play cannot decide this. A leg does not
  /// have to open with the first slot: the slot after the one that won the
  /// previous leg does, and from then on the counts point at the wrong slot for
  /// the rest of the leg.
  void _resumePickTurn() {
    DartThrow? last;
    var lastSlot = -1;
    for (var i = 0; i < _playerStates.length; i++) {
      for (final t in _playerStates[i].throws) {
        if (last == null || _byThrowOrder(t, last) > 0) {
          last = t;
          lastSlot = i;
        }
      }
    }

    if (lastSlot < 0) {
      _currentPlayerIndex = 0;
      return;
    }

    var idx = (lastSlot + 1) % _playerStates.length;
    for (
      var k = 0;
      k < _playerStates.length && _playerStates[idx].legPlacement != null;
      k++
    ) {
      idx = (idx + 1) % _playerStates.length;
    }
    _currentPlayerIndex = idx;
  }

  /// Picks the next slot to throw for a placement-mode resume and restores the
  /// leg/set counters to [maxLeg] of the only set a placement game has.
  void _resumePickNextSlot(int maxLeg) {
    _resumePickTurn();
    _currentLeg = maxLeg;
    _currentSet = 1;
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Starts a brand-new game: persists it, builds fresh per-slot state for the
  /// players or teams, resets leg/set/turn counters, and clears undo/redo.
  Future<void> startGame(
    Game game,
    List<Player> players, {
    String? competitionMatchId,
    int? competitionSlot,
    String? starterExternalId,
  }) async {
    _handicaps = game.handicaps ?? {};
    _competitionSingle = competitionMatchId != null;

    final ids = players.map((p) => p.id!).toList();
    final gameId = await _db.insertGame(
      game,
      ids,
      competitionMatchId: competitionMatchId,
      competitionSlot: competitionSlot,
      starterExternalId: starterExternalId,
    );
    _game = Game(
      id: gameId,
      startScore: game.startScore,
      gameMode: game.gameMode,
      checkoutMode: game.checkoutMode,
      legs: game.legs,
      sets: game.sets,
      createdAt: game.createdAt,
      teams: game.teams,
      handicaps: game.handicaps,
      placementMode: game.placementMode,
      startingOrder: game.startingOrder,
    );

    if (game.isTeamGame) {
      _playerStates = game.teams!.map((team) {
        final teamPlayers = team.playerIds
            .map((id) => players.firstWhere((p) => p.id == id))
            .toList();
        return PlayerState(
          displayName: team.name,
          players: teamPlayers,
          legsWon: 0,
          setsWon: 0,
          remaining: game.startScore,
          throws: [],
          isTeamSlot: true,
        );
      }).toList();
    } else {
      _playerStates = players
          .map(
            (p) => PlayerState(
              displayName: p.name,
              players: [p],
              legsWon: 0,
              setsWon: 0,
              remaining: game.startScore,
              throws: [],
            ),
          )
          .toList();
    }

    _currentPlayerIndex = 0;
    _currentLeg = 1;
    _currentSet = 1;
    _gameOver = false;
    _winnerId = null;
    _currentVisitDarts = [];
    _checkedInThisVisit = false;
    _redoStack.clear();
    dropHeldVisit();
    releaseBot();
    notifyListeners();
    scheduleBot();
  }

  /// Starts a fresh game that reuses [template]'s settings (start score, check
  /// in/out, legs/sets, placement mode, teams and handicaps) and the given
  /// [players]. The template's id and timestamps are not carried over, so a
  /// new game row is persisted and the finished one stays untouched. The
  /// throwing order follows the template's [StartingOrder]: drawn again for
  /// [StartingOrder.random], kept as it is for a fixed order.
  Future<void> startRematch(Game template, List<Player> players) async {
    final isRandom = template.startingOrder == StartingOrder.random;
    final ordered = isRandom
        ? (List.of(players)..shuffle(Random()))
        : List.of(players);
    final teams = isRandom && template.teams != null
        ? (List.of(template.teams!)..shuffle(Random()))
        : template.teams;
    final game = Game(
      startScore: template.startScore,
      gameMode: template.gameMode,
      checkoutMode: template.checkoutMode,
      legs: template.legs,
      sets: template.sets,
      createdAt: DateTime.now(),
      teams: teams,
      handicaps: template.handicaps,
      placementMode: template.placementMode,
      startingOrder: template.startingOrder,
    );
    await startGame(game, ordered);
  }

  /// B74 v0.3: commit one numeric X01 visit only after explicit ACCEPT.
  /// [finishDart] is required for a checkout, and forbidden otherwise.
  /// This first increment supports straight-in, double-out competition games.
  bool _numericVisitSubmitting = false;

  Future<void> submitNumericVisit(
    int score, {
    int? finishDart,
    bool bust = false,
    int? bustDarts,
  }) async {
    if (_numericVisitSubmitting) throw StateError('Beurt wordt al verwerkt');
    if (_game == null || _gameOver || isBotTurn || inputLocked) {
      throw StateError('Score-invoer is momenteel niet beschikbaar');
    }
    if (_currentVisitDarts.isNotEmpty) {
      throw StateError(
        'Wissel niet tussen dart- en beurtinvoer binnen een beurt',
      );
    }
    if (score < 0 || score > 180) {
      throw ArgumentError('Score moet tussen 0 en 180 liggen');
    }
    if (bust && score != 0) throw ArgumentError('BUST heeft altijd score 0');
    if (bust && (bustDarts == null || bustDarts < 1 || bustDarts > 3)) {
      throw ArgumentError('Selecteer bij BUST dart 1, 2 of 3');
    }
    if (!bust && bustDarts != null) {
      throw ArgumentError('Geen BUST-darts zonder BUST');
    }
    if (currentGameMode != GameMode.straightIn) {
      throw StateError(
        'Numerieke invoer ondersteunt nog geen double/master-in',
      );
    }
    final remaining = currentPlayerState.remaining;
    final after = remaining - score;
    if (!bust &&
        (after < 0 ||
            (currentCheckoutMode != CheckoutMode.straightOut && after == 1))) {
      throw ArgumentError('Ongeldige score: gebruik BUST');
    }
    final checkout = !bust && after == 0;
    if (checkout && (finishDart == null || finishDart < 1 || finishDart > 3)) {
      throw ArgumentError('Selecteer finishdart 1, 2 of 3');
    }
    if (!checkout && finishDart != null) {
      throw ArgumentError('Geen finishdart zonder checkout');
    }
    if (checkout &&
        !b74CanFinishInDarts(remaining, finishDart!, currentCheckoutMode)) {
      throw ArgumentError(
        'Deze finish is niet mogelijk met $finishDart dart(s)',
      );
    }
    if (checkout &&
        currentCheckoutMode == CheckoutMode.doubleOut &&
        (remaining > 170 ||
            const {159, 162, 163, 165, 166, 168, 169}.contains(remaining))) {
      throw ArgumentError('Geen mogelijke double-out finish');
    }
    _numericVisitSubmitting = true;
    try {
      await _submitVisit(
        score,
        bust ? bustDarts! : (checkout ? finishDart! : 3),
        bust: bust,
      );
    } finally {
      _numericVisitSubmitting = false;
    }
  }

  /// The three most recent visits by this player in the active leg.
  /// Completed legs are intentionally not editable.
  List<DartThrow> correctableVisits(int slotIndex) {
    if (_game == null ||
        _gameOver ||
        slotIndex < 0 ||
        slotIndex >= _playerStates.length) {
      return const [];
    }
    final visits = _playerStates[slotIndex].throws
        .where(
          (t) =>
              t.leg == _currentLeg &&
              t.set == _currentSet &&
              t.hitsJson == null &&
              t.remainingAfter > 0,
        )
        .toList();
    return visits.reversed.take(3).toList();
  }

  /// Correct a numeric visit without adding a turn or changing who throws.
  /// Recalculates subsequent visits for that player and rejects a correction
  /// if it would invalidate any later score, bust or checkout.
  Future<void> correctNumericVisit(
    int slotIndex,
    int throwId,
    int newScore,
    int dartsUsed,
  ) => correctVisit(
    slotIndex,
    throwId,
    newScore,
    dartsUsed,
    bust: correctableVisits(slotIndex).firstWhere((t) => t.id == throwId).bust,
  );

  /// Correct the score, BUST flag and dart count as one atomic visit update.
  Future<void> correctVisit(
    int slotIndex,
    int throwId,
    int newScore,
    int dartsUsed, {
    required bool bust,
  }) async {
    if (_game == null ||
        _gameOver ||
        _numericVisitSubmitting ||
        _currentVisitDarts.isNotEmpty ||
        isBotTurn ||
        inputLocked) {
      throw StateError('Correctie is momenteel niet beschikbaar');
    }
    if (newScore < 0 ||
        newScore > 180 ||
        dartsUsed < 1 ||
        dartsUsed > 3 ||
        newScore > dartsUsed * 60) {
      throw ArgumentError('Ongeldige score of aantal darts');
    }
    final candidates = correctableVisits(slotIndex);
    if (!candidates.any((t) => t.id == throwId)) {
      throw StateError('Deze beurt kan niet worden gecorrigeerd');
    }
    if (bust && newScore != 0) {
      throw ArgumentError('BUST heeft altijd 0 punten');
    }
    final state = _playerStates[slotIndex];
    final visits = state.throws
        .where((t) => t.leg == _currentLeg && t.set == _currentSet)
        .toList();
    // A recorded first remainingBefore also supports games with a custom
    // starting score; never assume the configured default is the first visit.
    var remaining = visits.isEmpty
        ? _game!.startScore
        : visits.first.remainingBefore;
    final changes = <int, int>{};
    for (final t in visits) {
      final score = t.id == throwId ? newScore : t.score;
      final isBust = t.id == throwId ? bust : t.bust;
      if (t.id != throwId) changes[t.id!] = remaining;
      if (t.bust && t.id != throwId && remaining != t.remainingBefore) {
        throw StateError(
          'Correctie verandert de uitgangspositie van een latere BUST',
        );
      }
      if (isBust && score != 0) {
        throw StateError('BUST moet 0 punten behouden');
      }
      if (!isBust) {
        if (score > remaining ||
            (score == remaining &&
                _game!.checkoutMode != CheckoutMode.straightOut)) {
          throw StateError('Correctie maakt een latere beurt ongeldig');
        }
        remaining -= score;
        if (remaining <= 0 ||
            (remaining == 1 &&
                _game!.checkoutMode != CheckoutMode.straightOut)) {
          throw StateError('Correctie maakt een latere beurt ongeldig');
        }
      }
    }
    _numericVisitSubmitting = true;
    try {
      await _db.correctVisit(
        _game!.id!,
        throwId,
        newScore,
        dartsUsed,
        bust,
        changes,
      );
      final players = _playerStates.expand((s) => s.players).toList();
      final activeSlotIndex = _currentPlayerIndex;
      final activePlayerId = currentPlayerState.player.id;
      await _rebuildFromDb(_game!, players);
      // Replay should preserve the active turn; never silently switch players.
      if (_game!.isTeamGame) {
        // Team member rotation is derived from persisted visit order.
        // Keep the active team slot, not an individual teammate's index.
        _currentPlayerIndex = activeSlotIndex;
      } else if (currentPlayerState.player.id != activePlayerId) {
        final index = _playerStates.indexWhere(
          (s) => s.player.id == activePlayerId,
        );
        if (index >= 0) _currentPlayerIndex = index;
      }
      notifyListeners();
    } finally {
      _numericVisitSubmitting = false;
    }
  }

  // ── Submit visit ──────────────────────────────────────────────────────────

  /// Records the current slot's visit: persists the throw (optionally with
  /// per-dart [hits]), updates the remaining score, and either handles a
  /// checkout or advances to the next slot. Busts keep the remaining score
  /// unchanged.
  Future<void> _submitVisit(
    int score,
    int dartsUsed, {
    bool bust = false,
    List<DartEntry>? hits,
  }) async {
    if (_game == null || _gameOver) return;
    final state = _playerStates[_currentPlayerIndex];
    final remaining = state.remaining;
    final newRemaining = remaining - score;

    final checkout = !bust && newRemaining == 0;

    final hitsJson = hits != null && hits.isNotEmpty
        ? jsonEncode(hits.map((h) => {'f': h.field, 'm': h.modifier}).toList())
        : null;

    // Decided here, where the darts and the player's own check-out rule are
    // both at hand, and stored on the visit. Nothing downstream can work it
    // out again: a synced throw arrives without its darts and without the game
    // it was really played in.
    final checkoutDarts = checkoutDartsInVisit(
      remaining,
      (hits ?? const <DartEntry>[]).map((h) => h.score).toList(),
      currentCheckoutMode,
      checkedOut: checkout,
    );

    final t = DartThrow(
      gameId: _game!.id!,
      playerId: state.player.id!, // individual player: even in team mode
      score: bust ? 0 : score,
      dartsUsed: dartsUsed,
      leg: _currentLeg,
      set: _currentSet,
      remainingBefore: remaining,
      thrownAt: DateTime.now(),
      bust: bust,
      hitsJson: hitsJson,
      checkoutDarts: checkoutDarts,
    );

    final id = await _db.insertThrow(t);
    final saved = DartThrow(
      id: id,
      gameId: t.gameId,
      playerId: t.playerId,
      score: t.score,
      dartsUsed: t.dartsUsed,
      leg: t.leg,
      set: t.set,
      remainingBefore: t.remainingBefore,
      thrownAt: t.thrownAt,
      bust: t.bust,
      hitsJson: t.hitsJson,
      checkoutDarts: t.checkoutDarts,
    );

    _playerStates[_currentPlayerIndex] = state.copyWith(
      remaining: bust ? remaining : newRemaining,
      throws: [...state.throws, saved],
    );

    if (checkout) {
      await _handleCheckout();
    } else {
      _advancePlayer();
    }
    notifyListeners();
  }

  // ── Checkout ──────────────────────────────────────────────────────────────

  /// Resolves a successful checkout: awards the leg, tracks perfect legs, and
  /// promotes to set/game win as needed. Scores reset and play advances to
  /// the next slot, including solo games, which simply continue to the next
  /// leg until [Game.legs] is reached.
  Future<void> _handleCheckout() async {
    final state = _playerStates[_currentPlayerIndex];
    int legsWon = state.legsWon + 1;
    int setsWon = state.setsWon;

    // Perfect leg. The checkout visit is already part of state.throws by the
    // time this runs, so counting it again here would put every leg over the
    // minimum and no perfect leg would ever be recognised.
    final minDarts = minimumDartsForScore[_game!.startScore];
    final legDarts = legDartsUsed(
      state.throws,
      _currentLeg,
      _currentSet,
      playerId: state.isTeam ? null : state.player.id,
    );
    final isPerfect = minDarts != null && legDarts <= minDarts;
    final perfectLegs = state.perfectLegs + (isPerfect ? 1 : 0);

    // Placement mode: award the leg, but keep playing until every slot has
    // checked out, producing a 1st/2nd/3rd/... finishing order for this leg.
    if (_game!.placementMode) {
      await _handlePlacementCheckout(perfectLegs);
      return;
    }

    final legsToWinSet = _game!.legs;
    if (legsWon >= legsToWinSet) {
      // Set won
      setsWon += 1;
      legsWon = 0;

      final setsToWin = _game!.sets;
      if (setsWon >= setsToWin) {
        // Game over
        _playerStates[_currentPlayerIndex] = state.copyWith(
          legsWon: legsWon,
          setsWon: setsWon,
          perfectLegs: perfectLegs,
        );
        _gameOver = true;
        _winnerId = state.isTeam ? state.players.first.id : state.player.id;
        await _db.updateGame(_game!.copyWith(finishedAt: DateTime.now()));
        return;
      }
      // New set: reset legs for all players
      _currentSet += 1;
      _currentLeg = 1;
      _playerStates = _playerStates.map((s) => s.copyWith(legsWon: 0)).toList();
    } else {
      // Same set, next leg
      _currentLeg += 1;
    }

    _playerStates[_currentPlayerIndex] = state.copyWith(
      legsWon: legsWon,
      setsWon: setsWon,
      perfectLegs: perfectLegs,
    );

    _resetScores();
    if (_competitionSingle && _playerStates.length == 2) {
      _currentPlayerIndex = (_currentLeg - 1) % 2;
    } else {
      _advancePlayer();
    }
  }

  /// Resolves a checkout in a placement-mode game: records this slot's
  /// finishing position for the current leg, and awards a leg win
  /// ([PlayerState.legsWon]) only to whoever finishes 1st. If this was the
  /// second-to-last slot to check out, the one remaining slot automatically
  /// takes last place without having to finish its visit. Both get the points
  /// their placement is worth. Once every slot has a placement, either ends the
  /// game (if the 1st-place slot's [PlayerState.legsWon] reached [Game.legs]) or
  /// starts the next leg with everyone active again.
  ///
  /// Reaching [Game.legs] ends the game; it does not win it. The winner is the
  /// slot [_placementLeader] names, because the format is played for points.
  Future<void> _handlePlacementCheckout(int perfectLegs) async {
    final state = _playerStates[_currentPlayerIndex];
    final slots = _playerStates.length;
    final placement =
        _playerStates.where((s) => s.legPlacement != null).length + 1;
    final legsWon = placement == 1 ? state.legsWon + 1 : state.legsWon;

    _playerStates[_currentPlayerIndex] = state.copyWith(
      legsWon: legsWon,
      perfectLegs: perfectLegs,
      legPlacement: placement,
      resetLegPlacement: true,
      placementSum: state.placementSum + placement,
      placementPoints:
          state.placementPoints + placementPoints(placement, slots),
    );

    // If only one slot is left without a placement, it automatically takes
    // last place -- the leg ends without that slot finishing its throws.
    final stillPlaying = _playerStates
        .where((s) => s.legPlacement == null)
        .toList();
    if (stillPlaying.length == 1) {
      final lastIdx = _playerStates.indexOf(stillPlaying.first);
      final lastState = _playerStates[lastIdx];
      final lastPlacement = placement + 1;
      _playerStates[lastIdx] = lastState.copyWith(
        legPlacement: lastPlacement,
        resetLegPlacement: true,
        placementSum: lastState.placementSum + lastPlacement,
        placementPoints:
            lastState.placementPoints + placementPoints(lastPlacement, slots),
      );
    }

    final legComplete = _playerStates.every((s) => s.legPlacement != null);
    if (!legComplete) {
      _advancePlayer();
      return;
    }

    // The game is over once the leg winner has taken as many legs as the format
    // asks for. Who won it is a separate question, and not this method's to
    // answer: the game is played for points, so the winner is the one the final
    // ranking puts first.
    final legWinner = _playerStates.firstWhere((s) => s.legPlacement == 1);
    if (legWinner.legsWon >= _game!.legs) {
      _gameOver = true;
      final winner = _playerStates[_placementLeader()];
      _winnerId = winner.isTeam ? winner.players.first.id : winner.player.id;
      await _db.updateGame(_game!.copyWith(finishedAt: DateTime.now()));
      return;
    }

    _currentLeg += 1;
    _resetScores();
    _advancePlayer();
  }

  /// Resets every slot's remaining score back to the start score for a new leg,
  /// preserving legs/sets won, throw history, and player rotation. In
  /// placement-mode games this also clears [PlayerState.legPlacement] so
  /// everyone is active again.
  void _resetScores() {
    _playerStates = _playerStates
        .map(
          (s) => PlayerState(
            displayName: s.displayName,
            players: s.players,
            currentPlayerIdx: s.currentPlayerIdx,
            legsWon: s.legsWon,
            setsWon: s.setsWon,
            remaining: _game!.startScore,
            throws: s.throws,
            perfectLegs: s.perfectLegs,
            isTeamSlot: s.isTeamSlot,
            legPlacement: null,
            placementSum: s.placementSum,
            placementPoints: s.placementPoints,
          ),
        )
        .toList();
  }

  /// Advance to the next team/player. In team mode, also rotate the player
  /// within the team that just threw. In placement-mode games, slots that
  /// already checked out this leg ([PlayerState.legPlacement] set) are skipped.
  void _advancePlayer() {
    // Rotate player within current team BEFORE advancing to next slot
    if (_playerStates[_currentPlayerIndex].isTeam) {
      final s = _playerStates[_currentPlayerIndex];
      final nextIdx = (s.currentPlayerIdx + 1) % s.players.length;
      _playerStates[_currentPlayerIndex] = s.copyWith(
        currentPlayerIdx: nextIdx,
      );
    }
    _currentPlayerIndex = (_currentPlayerIndex + 1) % _playerStates.length;

    if (_game!.placementMode) {
      while (_playerStates[_currentPlayerIndex].legPlacement != null) {
        _currentPlayerIndex = (_currentPlayerIndex + 1) % _playerStates.length;
      }
    }
  }

  // ── Dart input ────────────────────────────────────────────────────────────

  /// Re-evaluates [_checkedInThisVisit] from [_currentVisitDarts] under the
  /// current player's check-in rule, e.g. after a dart that triggered
  /// check-in was undone.
  void _recomputeCheckedInThisVisit() {
    final gameMode = currentGameMode;
    if (gameMode == GameMode.straightIn || currentHasCheckedIn) {
      _checkedInThisVisit = false;
      return;
    }
    _checkedInThisVisit = _currentVisitDarts.any((d) {
      if (d.field == 0) return false;
      final isDouble = d.modifier == 2;
      final isTriple = d.modifier == 3 && d.field != 25;
      return gameMode == GameMode.doubleIn ? isDouble : (isDouble || isTriple);
    });
  }

  /// Registers [field] (0=miss, 1-20, 25=bull)/[modifier] (1/2/3) as the next
  /// dart of the current player's in-progress visit: computes its score under
  /// the active check-in rule, detects a bust or completed checkout, and
  /// commits the visit once three darts are thrown or it ends early.
  Future<void> _addDart(int field, int modifier) async {
    int score;
    if (field == 0) {
      score = 0;
    } else if (field == 25) {
      score = modifier == 2 ? 50 : 25;
    } else {
      score = field * modifier;
    }

    final gameMode = currentGameMode;
    final checkoutMode = currentCheckoutMode;
    final requiresCheckIn =
        gameMode == GameMode.doubleIn || gameMode == GameMode.masterIn;

    final isDouble = field != 0 && modifier == 2;
    final isTriple = field != 0 && modifier == 3 && field != 25;
    final qualifiesForCheckIn = gameMode == GameMode.doubleIn
        ? isDouble
        : (gameMode == GameMode.masterIn ? (isDouble || isTriple) : false);

    bool dartScores = true;
    if (requiresCheckIn && !(currentHasCheckedIn || _checkedInThisVisit)) {
      if (qualifiesForCheckIn) {
        _checkedInThisVisit = true;
      } else {
        dartScores = false;
        score = 0;
      }
    }
    final isCheckedIn = currentHasCheckedIn || _checkedInThisVisit;

    final entry = DartEntry(
      field: field,
      modifier: field == 0 ? 1 : modifier,
      score: score,
    );
    _currentVisitDarts.add(entry);

    final newVisitTotal = _visitScoreSoFar;
    final newRemaining = currentPlayerState.remaining - newVisitTotal;

    bool bust = false;
    bool endVisit = false;

    if (!dartScores) {
      if (_currentVisitDarts.length == 3) endVisit = true;
    } else if (newRemaining < 0) {
      bust = true;
      endVisit = true;
    } else if (newRemaining == 0) {
      bust = !FinishCalculator.finishesOn(field, modifier, checkoutMode);
      endVisit = true;
    } else if (!FinishCalculator.canStillFinish(newRemaining, checkoutMode) &&
        isCheckedIn) {
      bust = true;
      endVisit = true;
    } else if (_currentVisitDarts.length == 3) {
      endVisit = true;
    }

    if (endVisit) {
      final pending = (
        score: bust ? 0 : newVisitTotal,
        dartsUsed: _currentVisitDarts.length,
        bust: bust,
        hits: List<DartEntry>.from(_currentVisitDarts),
      );
      await holdVisit(() => _settleVisit(pending));
    }
  }

  /// Handles a tap on [field] (0=miss, 1-20, 25=bull) with the given
  /// [modifier] (1=single, 2=double, 3=triple) for the current player's
  /// in-progress visit. Any new dart invalidates the redo stack.
  @override
  Future<void> tapField(int field, int modifier) async {
    if (_game == null || _gameOver || _currentVisitDarts.length >= 3) return;
    if (inputLocked) return;
    _redoStack.clear();
    await _addDart(field, modifier);
    notifyListeners();
    scheduleBot();
  }

  // ── Undo / Redo ───────────────────────────────────────────────────────────

  /// Undoes the last individual dart, even across visit and player boundaries.
  ///
  /// If the current player still has darts entered for their in-progress
  /// visit, the most recent one is simply removed. Otherwise, the most
  /// recently recorded visit is deleted from the database and the game state
  /// is rebuilt, which naturally returns the turn to whoever threw it (and
  /// reverts any leg/set it had completed). If that visit had more than one
  /// dart, the darts before the removed one become the new in-progress visit
  /// so the UI shows them pre-filled.
  ///
  /// A bot's darts are never undone one at a time: the bot would only throw
  /// the same dart again, and the person could never get back to their own
  /// visit. Undo over a bot's visit removes every bot visit since the last
  /// human dart, then that dart, and the bot throws afresh once the person
  /// has thrown again.
  @override
  Future<void> undoLastDart() async {
    if (_game == null || isBotTurn) return;

    // A visit still on the board is not recorded yet: taking its last dart
    // back is enough, and the pause it was waiting out is off.
    dropHeldVisit();

    if (_currentVisitDarts.isNotEmpty) {
      _redoStack.add(_RedoEntry.dart(_currentVisitDarts.removeLast()));
      _recomputeCheckedInThisVisit();
      notifyListeners();
      return;
    }

    final all = allThrows();
    while (all.isNotEmpty && _isBotId(all.last.playerId)) {
      all.removeLast();
    }
    if (all.isEmpty) return;

    botSuspended = true;
    final wasGameOver = _gameOver;
    final lastVisit = all.last;
    final hits = _parseHits(lastVisit.hitsJson);

    for (final t in allThrows().where((t) => _byThrowOrder(t, lastVisit) > 0)) {
      await _db.deleteThrow(t.id!);
    }
    await _db.deleteThrow(lastVisit.id!);

    final preservedRedo = List<_RedoEntry>.from(_redoStack);
    List<DartEntry> prefill;
    if (hits != null && hits.isNotEmpty) {
      preservedRedo.add(_RedoEntry.dart(hits.removeLast()));
      prefill = hits;
    } else {
      preservedRedo.add(_RedoEntry.legacyVisit(lastVisit));
      prefill = const [];
    }

    final players = _playerStates.expand((s) => s.players).toList();
    await _rebuildFromDb(_game!, players);

    // Undoing the winning dart un-finishes the game; resumeGame already reset
    // _gameOver/_winnerId in-memory, so persist that the game is open again.
    if (wasGameOver) {
      await _db.updateGame(_game!);
    }

    _currentVisitDarts = prefill;
    _redoStack
      ..clear()
      ..addAll(preservedRedo);
    _recomputeCheckedInThisVisit();
    botSuspended = false;
    notifyListeners();
    scheduleBot();
  }

  /// Redoes the last undone dart: restores it to the in-progress visit
  /// (committing the visit again if that completes it), or, for a legacy
  /// whole-visit redo, re-inserts the previously removed visit verbatim.
  @override
  Future<void> redoLastDart() async {
    if (_game == null || _redoStack.isEmpty || inputLocked) return;

    final entry = _redoStack.removeLast();

    if (entry.dart != null) {
      await _addDart(entry.dart!.field, entry.dart!.modifier);
      notifyListeners();
      scheduleBot();
      return;
    }

    final t = entry.legacyVisit!;
    await _db.insertThrow(
      DartThrow(
        gameId: t.gameId,
        playerId: t.playerId,
        score: t.score,
        dartsUsed: t.dartsUsed,
        leg: t.leg,
        set: t.set,
        remainingBefore: t.remainingBefore,
        thrownAt: t.thrownAt,
        bust: t.bust,
        hitsJson: t.hitsJson,
        checkoutDarts: t.checkoutDarts,
      ),
    );

    final preservedRedo = List<_RedoEntry>.from(_redoStack);
    final players = _playerStates.expand((s) => s.players).toList();
    botSuspended = true;
    await _rebuildFromDb(_game!, players);

    _redoStack
      ..clear()
      ..addAll(preservedRedo);
    botSuspended = false;
    notifyListeners();
    scheduleBot();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// All throws across every slot, sorted chronologically. Two throws can share
  /// a millisecond, so the row id breaks the tie and undo always removes the
  /// visit that was really thrown last.
  List<DartThrow> allThrows() {
    return _playerStates.expand((s) => s.throws).toList()..sort(_byThrowOrder);
  }
}
