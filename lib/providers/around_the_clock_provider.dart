import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBindingObserver;
import '../database/db_helper.dart';
import '../models/around_the_clock_game.dart';
import '../models/player.dart';
import '../utils/around_the_clock_rules.dart';
import '../utils/bot_strategy_around_the_clock.dart';
import '../utils/bot_thrower.dart';
import '../utils/player_label.dart';
import 'bot_runner.dart';

// ── AroundTheClockPlayerState ─────────────────────────────────────────────────

/// Immutable Around the Clock state for one scoreboard slot: how far it has
/// advanced through the target order, the segments hit on the current target
/// (full-segment variant), and when it finished.
///
/// A slot is either a single player or a whole team. For teams, [players]
/// holds every member and [currentPlayerIdx] tracks whose turn it is within
/// the team; progress and hit segments are shared by the whole team,
/// relay-style. [displayName] is the team or player name shown on the
/// scoreboard.
class AroundTheClockPlayerState implements LabelledSlot {
  @override
  final String displayName;

  /// All players in this slot: 1 for individual, N for team.
  @override
  final List<Player> players;

  /// Which player in [players] throws NEXT (rotates after each team visit).
  final int currentPlayerIdx;

  /// Whether this slot represents a team rather than a single player.
  @override
  final bool isTeamSlot;

  /// Index into [aroundTheClockOrder] of the number this slot must hit next.
  final int progress;

  /// Full-segment variant only: multipliers (1/2/3) already hit on the current target.
  final Set<int> hitSegments;

  /// Total darts thrown once the slot completed the Bull's Eye.
  final int? finishedAtDart;

  const AroundTheClockPlayerState({
    required this.displayName,
    required this.players,
    this.currentPlayerIdx = 0,
    this.isTeamSlot = false,
    this.progress = 0,
    this.hitSegments = const {},
    this.finishedAtDart,
  });

  /// The player who throws next (backward-compatible accessor).
  Player get player => players[currentPlayerIdx];

  /// Whether [winnerId] names anyone in this slot.
  ///
  /// Matched against every member rather than against [player]: in team mode
  /// [player] is only whoever the rotation has on turn, and it moves on as the
  /// game runs, so comparing against it makes the winning slot unrecognisable
  /// from one moment to the next.
  bool isWonBy(int? winnerId) =>
      winnerId != null && players.any((p) => p.id == winnerId);

  /// The number this slot must currently hit.
  int get currentTarget =>
      aroundTheClockOrder[progress.clamp(0, aroundTheClockOrder.length - 1)];

  /// Whether this slot has completed the final target (the Bull).
  bool get isFinished => finishedAtDart != null;

  /// Returns a copy with progress/segments/finish/active player replaced;
  /// identity is preserved.
  AroundTheClockPlayerState copyWith({
    int? progress,
    Set<int>? hitSegments,
    int? finishedAtDart,
    int? currentPlayerIdx,
  }) => AroundTheClockPlayerState(
    displayName: displayName,
    players: players,
    currentPlayerIdx: currentPlayerIdx ?? this.currentPlayerIdx,
    isTeamSlot: isTeamSlot,
    progress: progress ?? this.progress,
    hitSegments: hitSegments ?? this.hitSegments,
    finishedAtDart: finishedAtDart ?? this.finishedAtDart,
  );
}

// ── AroundTheClockProvider ────────────────────────────────────────────────────

/// Active-game state machine for Around the Clock (basic, full-segments, skip).
///
/// Each player works through [aroundTheClockOrder] one target at a time; the
/// first to complete the final Bull target wins instantly. Darts are recorded
/// into a three-dart visit buffer and persisted, so undo deletes the last dart
/// and replays the rest.
class AroundTheClockProvider extends ChangeNotifier
    with WidgetsBindingObserver, BotRunner {
  final DbHelper _db = DbHelper.instance;

  AroundTheClockGame? _game;
  List<AroundTheClockPlayerState> _playerStates = [];
  int _currentPlayerIndex = 0;
  bool _gameOver = false;
  int? _winnerId;

  /// Darts thrown so far in the current visit (max 3).
  final List<AroundTheClockThrow> _visitBuffer = [];

  /// All persisted throws for undo (newest last).
  final List<AroundTheClockThrow> _throwHistory = [];

  AroundTheClockGame? get game => _game;
  List<AroundTheClockPlayerState> get playerStates => _playerStates;
  int get currentPlayerIndex => _currentPlayerIndex;
  AroundTheClockPlayerState get currentPlayerState =>
      _playerStates[_currentPlayerIndex];
  bool get gameOver => _gameOver;
  int? get winnerId => _winnerId;
  List<AroundTheClockThrow> get visitBuffer => List.unmodifiable(_visitBuffer);
  int get dartsInVisit => _visitBuffer.length;

  /// Whether there is a dart to undo. Not while a bot is throwing, and not
  /// when every recorded dart is a bot's: those are never undone on their
  /// own, see [undoLastDart].
  /// Every persisted dart of the game, oldest first.
  List<AroundTheClockThrow> get throwHistory =>
      List.unmodifiable(_throwHistory);
  bool get canUndo =>
      !isBotTurn && _throwHistory.any((t) => !_isBotId(t.playerId));

  /// The active game's rule variant.
  AroundTheClockVariant get _variant => _game!.variant;

  /// The number the current player must hit next.
  int get activeTarget => currentPlayerState.currentTarget;

  /// Full-segment variant only: multipliers still missing on the active
  /// target before the player can advance.
  List<int>? get neededSegments {
    if (_game == null || _variant != AroundTheClockVariant.fullSegments)
      return null;
    final target = activeTarget;
    final hit = currentPlayerState.hitSegments;
    // The Bull only has Single (25) and Double (50), no Triple.
    final segments = target == 25 ? const [1, 2] : const [1, 2, 3];
    return segments.where((m) => !hit.contains(m)).toList();
  }

  // ── Slot construction ────────────────────────────────────────────────────

  /// Builds one scoreboard slot per team (if [teams] is set) or one slot per
  /// player (individual game), each with fresh progress.
  List<AroundTheClockPlayerState> _buildSlots(
    List<Player> players,
    List<TeamConfig>? teams,
  ) {
    if (teams != null && teams.isNotEmpty) {
      return teams.map((team) {
        final teamPlayers = team.playerIds
            .map((id) => players.firstWhere((p) => p.id == id))
            .toList();
        return AroundTheClockPlayerState(
          displayName: team.name,
          players: teamPlayers,
          isTeamSlot: true,
        );
      }).toList();
    }
    return players
        .map(
          (p) => AroundTheClockPlayerState(displayName: p.name, players: [p]),
        )
        .toList();
  }

  // ── Resume / Start ─────────────────────────────────────────────────────────

  /// Restores an in-progress game and rebuilds progress/turn state by replaying
  /// all stored darts.
  Future<void> resumeGame(AroundTheClockGame game, List<Player> players) async {
    _game = game;
    _playerStates = _buildSlots(players, game.teams);
    _currentPlayerIndex = 0;
    _gameOver = false;
    _winnerId = null;
    _visitBuffer.clear();
    _throwHistory.clear();
    dropHeldVisit();
    releaseBot();
    await _replayState();
    notifyListeners();
    scheduleBot();
  }

  /// Starts a new game: persists it, builds fresh player states, and resets the
  /// visit buffer and history.
  Future<void> startGame(AroundTheClockGame game, List<Player> players) async {
    final gameId = await _db.insertAroundTheClockGame(game);
    _game = AroundTheClockGame(
      id: gameId,
      variant: game.variant,
      legs: game.legs,
      sets: game.sets,
      createdAt: game.createdAt,
      playerIds: game.playerIds,
      teams: game.teams,
      startingOrder: game.startingOrder,
    );

    _playerStates = _buildSlots(players, game.teams);
    _currentPlayerIndex = 0;
    _gameOver = false;
    _winnerId = null;
    _visitBuffer.clear();
    _throwHistory.clear();
    dropHeldVisit();
    releaseBot();
    notifyListeners();
    scheduleBot();
  }

  /// Starts a fresh Around the Clock game that reuses [template]'s settings
  /// (variant, legs/sets, teams) and the given [players]. The template's id and
  /// timestamps are not carried over, so a new game row is persisted and the
  /// finished one stays untouched. The throwing order follows the template's
  /// [StartingOrder]: drawn again for [StartingOrder.random], kept as it is for
  /// a fixed order.
  Future<void> startRematch(
    AroundTheClockGame template,
    List<Player> players,
  ) async {
    final isRandom = template.startingOrder == StartingOrder.random;
    final ordered = isRandom
        ? (List.of(players)..shuffle(Random()))
        : List.of(players);
    final teams = isRandom && template.teams != null
        ? (List.of(template.teams!)..shuffle(Random()))
        : template.teams;
    final game = AroundTheClockGame(
      variant: template.variant,
      legs: template.legs,
      sets: template.sets,
      createdAt: DateTime.now(),
      playerIds: ordered.map((p) => p.id!).toList(),
      teams: teams,
      startingOrder: template.startingOrder,
    );
    await startGame(game, ordered);
  }

  // ── Record a dart ──────────────────────────────────────────────────────────

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
    final level = currentPlayerState.player.botLevel!;
    final aim = aroundTheClockTarget(
      target: activeTarget,
      variant: _variant,
      aimTriples: aimsForTriples(level),
      neededSegments: neededSegments,
    );
    final hit = botThrower.throwAt(aim, level);
    await _recordDart(hit.field, hit.multiplier);
  }

  // ── Record a dart ──────────────────────────────────────────────────────────

  /// Records one dart of the person on turn. [field]=0 / [multiplier]=0 means
  /// miss. Refused while a bot is on turn or a finished visit is still shown.
  Future<void> recordDart(int field, int multiplier) async {
    if (inputLocked) return;
    await _recordDart(field, multiplier);
    scheduleBot();
  }

  /// Records one dart for whoever is on turn, bot or person.
  Future<void> _recordDart(int field, int multiplier) async {
    if (_game == null || _gameOver) return;
    if (_visitBuffer.length >= 3) return;

    final t = AroundTheClockThrow(
      gameId: _game!.id!,
      playerId: currentPlayerState.player.id!,
      field: field,
      multiplier: multiplier,
      leg: 1,
      set_: 1,
      thrownAt: DateTime.now(),
    );
    final id = await _db.insertAroundTheClockThrow(t);
    final saved = AroundTheClockThrow(
      id: id,
      gameId: t.gameId,
      playerId: t.playerId,
      field: t.field,
      multiplier: t.multiplier,
      leg: t.leg,
      set_: t.set_,
      thrownAt: t.thrownAt,
    );

    _visitBuffer.add(saved);
    _throwHistory.add(saved);

    if (!saved.isMiss) {
      _applyDart(_currentPlayerIndex, saved);

      if (currentPlayerState.isFinished) {
        _visitBuffer.clear();
        await _handleWin(_currentPlayerIndex);
        return;
      }
    }

    if (_visitBuffer.length == 3) {
      notifyListeners();
      await holdVisit(_endVisit);
    } else {
      notifyListeners();
    }
  }

  // ── Apply dart to state ────────────────────────────────────────────────────

  /// Applies one dart to [playerIdx]'s progress through
  /// [applyAroundTheClockDart], the one place the variant rules live, and
  /// records the finishing dart when the final target is completed.
  void _applyDart(int playerIdx, AroundTheClockThrow t) {
    final state = _playerStates[playerIdx];
    final next = applyAroundTheClockDart(
      variant: _variant,
      position: (progress: state.progress, hitSegments: state.hitSegments),
      field: t.field,
      multiplier: t.multiplier,
    );
    final newProgress = next.progress;

    var updated = state.copyWith(
      progress: newProgress,
      hitSegments: next.hitSegments,
    );
    if (newProgress >= aroundTheClockOrder.length) {
      final slotPlayerIds = state.players.map((p) => p.id).toSet();
      final dartsThrown = _throwHistory
          .where((h) => slotPlayerIds.contains(h.playerId))
          .length;
      updated = updated.copyWith(finishedAtDart: dartsThrown);
    }

    _playerStates[playerIdx] = updated;
  }

  // ── End of visit ──────────────────────────────────────────────────────────

  /// Ends the current three-dart visit and advances to the next slot, rotating
  /// the active player within a team slot first.
  Future<void> _endVisit() async {
    _visitBuffer.clear();
    _advanceSlot();
    notifyListeners();
  }

  /// Advances to the next slot. In team mode, also rotates the player within
  /// the slot that just threw, so its next visit is taken by the next member.
  void _advanceSlot() {
    final s = _playerStates[_currentPlayerIndex];
    if (s.isTeamSlot) {
      final nextIdx = (s.currentPlayerIdx + 1) % s.players.length;
      _playerStates[_currentPlayerIndex] = s.copyWith(
        currentPlayerIdx: nextIdx,
      );
    }
    _currentPlayerIndex = (_currentPlayerIndex + 1) % _playerStates.length;
  }

  /// Marks the game over with [playerIdx] as the winner and persists the finish time.
  Future<void> _handleWin(int playerIdx) async {
    _gameOver = true;
    _winnerId = _playerStates[playerIdx].player.id;
    await _db.updateAroundTheClockGame(
      _game!.copyWith(finishedAt: DateTime.now()),
    );
    notifyListeners();
  }

  // ── Undo ───────────────────────────────────────────────────────────────────

  /// Undoes the last dart: deletes it from the database, un-finishes the game if
  /// it was the winning dart, and replays the remaining darts to rebuild state.
  ///
  /// A bot's darts are never undone one at a time: the bot would only throw
  /// again, and the person could never get back to their own visit. Undo over
  /// a bot's darts removes every bot dart since the last human dart, then that
  /// dart, in one rebuild.
  Future<void> undoLastDart() async {
    if (_game == null || isBotTurn) return;
    if (!_throwHistory.any((t) => !_isBotId(t.playerId))) return;
    while (_isBotId(_throwHistory.last.playerId)) {
      await _db.deleteAroundTheClockThrow(_throwHistory.removeLast().id!);
    }
    dropHeldVisit();
    botSuspended = true;

    final last = _throwHistory.removeLast();
    await _db.deleteAroundTheClockThrow(last.id!);

    if (_visitBuffer.isNotEmpty && _visitBuffer.last.id == last.id) {
      _visitBuffer.removeLast();
    }

    if (_gameOver) {
      _gameOver = false;
      _winnerId = null;
      _game = _game!.copyWith(clearFinishedAt: true);
      await _db.updateAroundTheClockGame(_game!);
    }

    await _replayState();
    botSuspended = false;
    notifyListeners();
    scheduleBot();
  }

  /// Rebuilds the full game state from the persisted darts: resets progress and
  /// turn counters, then replays every dart, advancing turns and detecting the
  /// winning dart along the way.
  /// Each dart is applied to whoever the replay currently has on turn, not to
  /// the player its row names. That relies on darts being stored in the order
  /// they were thrown, which [DbHelper] guarantees by ordering on the throw
  /// time and, for ties within a millisecond, the row id. Recording a dart out
  /// of turn would silently shift every later dart onto the wrong slot.
  Future<void> _replayState() async {
    if (_game == null) return;

    final allThrows = await _db.getAroundTheClockThrowsForGame(_game!.id!);

    _playerStates = _playerStates
        .map(
          (s) => AroundTheClockPlayerState(
            displayName: s.displayName,
            players: s.players,
            isTeamSlot: s.isTeamSlot,
          ),
        )
        .toList();
    _currentPlayerIndex = 0;
    _gameOver = false;
    _winnerId = null;
    _visitBuffer.clear();
    _throwHistory.clear();

    for (final t in allThrows) {
      _visitBuffer.add(t);
      _throwHistory.add(t);

      if (!t.isMiss) {
        _applyDart(_currentPlayerIndex, t);
        if (currentPlayerState.isFinished) {
          _visitBuffer.clear();
          _gameOver = true;
          _winnerId = currentPlayerState.player.id;
          break;
        }
      }

      if (_visitBuffer.length == 3) {
        _visitBuffer.clear();
        _advanceSlot();
      }
    }
  }
}
