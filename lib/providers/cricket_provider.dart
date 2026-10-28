import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBindingObserver;
import '../database/db_helper.dart';
import '../models/cricket_game.dart';
import '../models/player.dart';
import '../utils/bot_strategy_cricket.dart';
import '../utils/bot_thrower.dart';
import '../utils/player_label.dart';
import 'bot_runner.dart';

// ── CricketPlayerState ────────────────────────────────────────────────────────

/// Immutable Cricket state for one scoreboard slot: their marks per field and
/// total score.
///
/// A slot is either a single player or a whole team. For teams, [players]
/// holds every member and [currentPlayerIdx] tracks whose turn it is within
/// the team; marks and score are shared by the whole team (real cricket
/// doubles rules). [displayName] is the team or player name shown on the
/// scoreboard.
class CricketPlayerState implements LabelledSlot {
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

  /// Marks per field, capped at 3 because that closes it. Anything a Double or
  /// Triple adds beyond the third mark turns into points instead, so the excess
  /// is deliberately not kept here.
  final Map<int, int> marks;
  final int score;

  const CricketPlayerState({
    required this.displayName,
    required this.players,
    this.currentPlayerIdx = 0,
    this.isTeamSlot = false,
    required this.marks,
    required this.score,
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

  /// Whether this slot has closed [field] (three or more marks).
  bool hasClosedField(int field) => (marks[field] ?? 0) >= 3;

  /// Whether this slot has closed every Cricket field.
  bool get hasClosedAll => cricketFields.every(hasClosedField);

  /// Returns a copy with marks, score, and/or the active player index
  /// replaced; identity is preserved.
  CricketPlayerState copyWith({
    Map<int, int>? marks,
    int? score,
    int? currentPlayerIdx,
  }) => CricketPlayerState(
    displayName: displayName,
    players: players,
    currentPlayerIdx: currentPlayerIdx ?? this.currentPlayerIdx,
    isTeamSlot: isTeamSlot,
    marks: marks ?? Map.of(this.marks),
    score: score ?? this.score,
  );
}

/// The index in [members] of the member a slot has at the board: whoever threw
/// the last dart of an unfinished visit, or the one after them once that visit
/// is complete. A slot without darts starts with its first member.
///
/// [slotThrows] holds every member's darts for the slot, in throwing order. A
/// member throws a whole visit, so the visit boundary is the only place the
/// rotation moves on.
int _memberOnTurn(List<Player> members, List<CricketThrow> slotThrows) {
  if (slotThrows.isEmpty) return 0;
  final last = members.indexWhere((p) => p.id == slotThrows.last.playerId);
  if (last < 0) return 0;
  final visitComplete = slotThrows.length % 3 == 0;
  return visitComplete ? (last + 1) % members.length : last;
}

// ── CricketProvider ────────────────────────────────────────────────────────────

/// Active-game state machine for Cricket (normal and cut-throat).
///
/// Records darts one at a time into a three-dart visit buffer, applies marks and
/// scoring, and detects a win as soon as a player closes their last field while
/// ahead (or via score once all fields are closed). Every dart is persisted, so
/// undo simply deletes the last throw and replays the remaining ones.
class CricketProvider extends ChangeNotifier
    with WidgetsBindingObserver, BotRunner {
  final DbHelper _db = DbHelper.instance;

  CricketGame? _game;
  List<CricketPlayerState> _playerStates = [];
  int _currentPlayerIndex = 0;
  bool _gameOver = false;
  int? _winnerId;

  /// Darts thrown so far in the current visit (max 3).
  final List<CricketThrow> _visitBuffer = [];

  /// All persisted throws for undo (newest last).
  final List<CricketThrow> _throwHistory = [];

  CricketGame? get game => _game;
  List<CricketPlayerState> get playerStates => _playerStates;
  int get currentPlayerIndex => _currentPlayerIndex;
  CricketPlayerState get currentPlayerState =>
      _playerStates[_currentPlayerIndex];
  bool get gameOver => _gameOver;
  int? get winnerId => _winnerId;
  List<CricketThrow> get visitBuffer => List.unmodifiable(_visitBuffer);
  int get dartsInVisit => _visitBuffer.length;
  int get throwCount => _throwHistory.length;

  /// Every persisted dart of the game, oldest first.
  List<CricketThrow> get throwHistory => List.unmodifiable(_throwHistory);

  /// Whether there is a dart to undo. Not while a bot is throwing, and not
  /// when every recorded dart is a bot's: those are never undone on their
  /// own, see [undoLastDart].
  bool get canUndo =>
      !isBotTurn && _throwHistory.any((t) => !_isBotId(t.playerId));

  // ── Slot construction ────────────────────────────────────────────────────

  /// Builds one scoreboard slot per team (if [teams] is set) or one slot per
  /// player (individual game), each with empty marks and zero score.
  List<CricketPlayerState> _buildSlots(
    List<Player> players,
    List<TeamConfig>? teams,
  ) {
    if (teams != null && teams.isNotEmpty) {
      return teams.map((team) {
        final teamPlayers = team.playerIds
            .map((id) => players.firstWhere((p) => p.id == id))
            .toList();
        return CricketPlayerState(
          displayName: team.name,
          players: teamPlayers,
          isTeamSlot: true,
          marks: {},
          score: 0,
        );
      }).toList();
    }
    return players
        .map(
          (p) => CricketPlayerState(
            displayName: p.name,
            players: [p],
            marks: {},
            score: 0,
          ),
        )
        .toList();
  }

  // ── Resume ────────────────────────────────────────────────────────────────

  /// Restores an in-progress Cricket game and rebuilds marks/scores by
  /// replaying all stored darts.
  Future<void> resumeGame(CricketGame game, List<Player> players) async {
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

  // ── Start ──────────────────────────────────────────────────────────────────

  /// Starts a new Cricket game: persists it, builds fresh zeroed player states,
  /// and resets the visit buffer and history.
  Future<void> startGame(CricketGame game, List<Player> players) async {
    final gameId = await _db.insertCricketGame(game);
    // Re-read to get the auto-generated id
    _game = CricketGame(
      id: gameId,
      variant: game.variant,
      scoringMode: game.scoringMode,
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

  /// Starts a fresh Cricket game that reuses [template]'s settings (variant,
  /// scoring mode, legs/sets, teams) and the given [players]. The template's id
  /// and timestamps are not carried over, so a new game row is persisted and
  /// the finished one stays untouched. The throwing order follows the
  /// template's [StartingOrder]: drawn again for [StartingOrder.random], kept
  /// as it is for a fixed order.
  Future<void> startRematch(CricketGame template, List<Player> players) async {
    final isRandom = template.startingOrder == StartingOrder.random;
    final ordered = isRandom
        ? (List.of(players)..shuffle(Random()))
        : List.of(players);
    final teams = isRandom && template.teams != null
        ? (List.of(template.teams!)..shuffle(Random()))
        : template.teams;
    final game = CricketGame(
      variant: template.variant,
      scoringMode: template.scoringMode,
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
    final own = currentPlayerState;
    final others = [
      for (var i = 0; i < _playerStates.length; i++)
        if (i != _currentPlayerIndex) _playerStates[i],
    ];
    final target = cricketTarget(
      ownMarks: own.marks,
      opponentMarks: others.map((s) => s.marks).toList(),
      ownScore: own.score,
      opponentScores: others.map((s) => s.score).toList(),
      variant: _game!.variant,
      scoring: _game!.scoringMode,
      aimTriples: aimsForTriples(own.player.botLevel!),
    );
    final hit = botThrower.throwAt(target, own.player.botLevel!);
    // A number off the seven is a miss here: the board has no marks for it,
    // and applying one would let a stray dart on the 1 score points.
    final counts = cricketFields.contains(hit.field);
    await _recordDart(counts ? hit.field : 0, counts ? hit.multiplier : 0);
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

    final t = CricketThrow(
      gameId: _game!.id!,
      playerId: currentPlayerState.player.id!,
      field: field,
      multiplier: multiplier,
      leg: 1,
      set_: 1,
      thrownAt: DateTime.now(),
    );
    final id = await _db.insertCricketThrow(t);
    final saved = CricketThrow(
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
      _applyDart(_currentPlayerIndex, field, multiplier);

      // A leg ends the instant a player closes the last field while leading
      // (or level), no need to finish the rest of the visit.
      if (_checkWin(_currentPlayerIndex)) {
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

  /// Applies one scoring dart to [slotIdx]: adds marks toward closing [field]
  /// and awards points for any marks beyond closing, routing points to the
  /// slot (normal) or to opponent slots who have not closed the field
  /// (cut-throat).
  void _applyDart(int slotIdx, int field, int multiplier) {
    final state = _playerStates[slotIdx];
    final isCutThroat = _game!.variant == CricketVariant.cutThroat;
    final isSimple = _game!.scoringMode == CricketScoringMode.simple;

    final effectiveMarks = isSimple ? 1 : multiplier;
    final currentMarks = state.marks[field] ?? 0;
    final newTotalMarks = currentMarks + effectiveMarks;

    // How many marks go towards closing, how many score?
    final marksToClose = (3 - currentMarks).clamp(0, effectiveMarks);
    final scoringMarks = effectiveMarks - marksToClose;

    // Update marks for this slot (cap at 3 for display, but track excess via score)
    final updatedMarks = Map<int, int>.of(state.marks);
    updatedMarks[field] = newTotalMarks.clamp(0, 3); // visual: max 3

    _playerStates[slotIdx] = state.copyWith(marks: updatedMarks);

    if (scoringMarks <= 0) return;

    // The field is now open (or was already open): handle scoring
    final fieldValue = field == 25 ? 25 : field;
    final points = scoringMarks * fieldValue;

    if (isCutThroat) {
      // Distribute points to opponent slots who haven't closed this field
      for (var i = 0; i < _playerStates.length; i++) {
        if (i == slotIdx) continue;
        if (!_playerStates[i].hasClosedField(field)) {
          _playerStates[i] = _playerStates[i].copyWith(
            score: _playerStates[i].score + points,
          );
        }
      }
    } else {
      // Score for current slot: only if at least one opponent hasn't closed it
      final fieldAlive = _playerStates.indexed.any(
        (e) => e.$1 != slotIdx && !e.$2.hasClosedField(field),
      );
      if (fieldAlive) {
        _playerStates[slotIdx] = _playerStates[slotIdx].copyWith(
          score: _playerStates[slotIdx].score + points,
        );
      }
    }
  }

  // ── End of visit ──────────────────────────────────────────────────────────

  /// Ends the current three-dart visit: resolves a score-based win if everyone
  /// has closed all fields, otherwise advances to the next slot.
  Future<void> _endVisit() async {
    _visitBuffer.clear();

    // A win for the current slot is already handled right after the dart
    // that closes their last field (see recordDart), so only the "stalemate"
    // case remains here.

    // All slots have closed all fields: nobody can score anymore, decide by score
    if (_playerStates.every((s) => s.hasClosedAll)) {
      await _handleWin(_scoreWinnerIndex());
      return;
    }

    _advanceSlot();
    notifyListeners();
  }

  /// Advances to the next slot. In team mode, also rotates the player within
  /// the team that just threw, so its next visit is taken by the next member.
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

  /// Whether [slotIdx] has won: all fields closed and a non-losing score
  /// (highest in normal, lowest in cut-throat) compared to every other slot.
  bool _checkWin(int slotIdx) {
    final state = _playerStates[slotIdx];
    if (!state.hasClosedAll) return false;

    final isCutThroat = _game!.variant == CricketVariant.cutThroat;
    for (var i = 0; i < _playerStates.length; i++) {
      if (i == slotIdx) continue;
      final other = _playerStates[i];
      final ahead = isCutThroat
          ? state.score <= other.score
          : state.score >= other.score;
      if (!ahead) return false;
    }
    return true;
  }

  /// Returns the index of the slot that wins when all fields are closed.
  int _scoreWinnerIndex() {
    final isCutThroat = _game!.variant == CricketVariant.cutThroat;
    int best = 0;
    for (var i = 1; i < _playerStates.length; i++) {
      final challenger = _playerStates[i].score;
      final current = _playerStates[best].score;
      if (isCutThroat ? challenger < current : challenger > current) {
        best = i;
      }
    }
    return best;
  }

  /// Marks the game over with [slotIdx] as the winner and persists the finish time.
  Future<void> _handleWin(int slotIdx) async {
    _gameOver = true;
    _winnerId = _playerStates[slotIdx].player.id;
    await _db.updateCricketGame(_game!.copyWith(finishedAt: DateTime.now()));
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
      await _db.deleteCricketThrow(_throwHistory.removeLast().id!);
    }
    dropHeldVisit();
    botSuspended = true;

    final last = _throwHistory.removeLast();
    await _db.deleteCricketThrow(last.id!);

    // Remove from visit buffer if it's still in there
    if (_visitBuffer.isNotEmpty && _visitBuffer.last.id == last.id) {
      _visitBuffer.removeLast();
    }

    // Undoing the winning dart un-finishes the game (recordDart blocks any
    // dart from being recorded once the game is over, so the last dart in
    // history can only be the winning one if the game was over).
    if (_gameOver) {
      _gameOver = false;
      _winnerId = null;
      _game = _game!.copyWith(clearFinishedAt: true);
      await _db.updateCricketGame(_game!);
    }

    // Replay from scratch for this leg/set
    await _replayState();
    botSuspended = false;
    notifyListeners();
    scheduleBot();
  }

  /// Rebuilds all slot states from the persisted darts: zeroes marks/scores,
  /// replays every dart chronologically, then restores the current slot, its
  /// active player (for teams), and the in-progress visit buffer.
  Future<void> _replayState() async {
    if (_game == null) return;

    final allThrows = await _db.getCricketThrowsForGame(_game!.id!);

    // Reset marks and scores to zero, keep slot identity
    _playerStates = _playerStates
        .map(
          (s) => CricketPlayerState(
            displayName: s.displayName,
            players: s.players,
            isTeamSlot: s.isTeamSlot,
            marks: {},
            score: 0,
          ),
        )
        .toList();

    // Replay all darts in chronological order, each routed to the slot of the
    // player that threw it. Shanghai and Around the Clock instead follow the
    // turn order; both work, this one also survives a dart stored out of turn.
    //
    // The win is decided here as well, on the same two rules [recordDart] and
    // [_endVisit] use, so that a finished game resumed from history reports its
    // winner rather than none. Deriving it a second time somewhere else is how
    // the summary and the history would start naming different winners.
    for (final t in allThrows) {
      if (t.isMiss) continue;
      final slotIdx = _playerStates.indexWhere(
        (s) => s.players.any((p) => p.id == t.playerId),
      );
      if (slotIdx < 0) continue;
      _applyDart(slotIdx, t.field, t.multiplier);

      // Closing the last field while ahead ends the leg on this very dart, so
      // the winner is the player who threw it.
      if (_checkWin(slotIdx)) {
        _gameOver = true;
        _winnerId = t.playerId;
        break;
      }
      // Everyone has closed everything: nothing can score any more, so the
      // score decides. Live play settles this at the end of the visit, which
      // reaches the same slot because no dart after this one can change a
      // score.
      if (_playerStates.every((s) => s.hasClosedAll)) {
        _gameOver = true;
        _winnerId = _playerStates[_scoreWinnerIndex()].player.id;
        break;
      }
    }

    // Throws per slot, in the order the database hands them out, which is the
    // order they were thrown in. Used to determine turn order.
    final slotThrows = _playerStates.map((s) {
      final ids = s.players.map((p) => p.id).toSet();
      return allThrows.where((t) => ids.contains(t.playerId)).toList();
    }).toList();

    // Determine current slot: fewest completed visits (groups of 3)
    final visitsPerSlot = slotThrows.map((t) => t.length ~/ 3).toList();
    final minVisits = visitsPerSlot.fold(999, (a, b) => a < b ? a : b);
    _currentPlayerIndex = visitsPerSlot.indexWhere((v) => v == minVisits);
    if (_currentPlayerIndex < 0) _currentPlayerIndex = 0;

    // Restore the team rotation of every slot, not only of the one at the
    // oche. An idle team keeps the member who steps up when it comes around
    // again, and a rebuild that left it at the first member would put the
    // wrong one at the board and file their darts under the wrong name.
    for (var i = 0; i < _playerStates.length; i++) {
      final slot = _playerStates[i];
      if (!slot.isTeamSlot) continue;
      _playerStates[i] = slot.copyWith(
        currentPlayerIdx: _memberOnTurn(slot.players, slotThrows[i]),
      );
    }

    final currentThrows = slotThrows[_currentPlayerIndex];

    // Rebuild visit buffer for the current slot
    final dartsInCurrentVisit = currentThrows.length % 3;
    _visitBuffer
      ..clear()
      ..addAll(
        currentThrows.reversed.take(dartsInCurrentVisit).toList().reversed,
      );

    _throwHistory
      ..clear()
      ..addAll(allThrows);
  }
}
