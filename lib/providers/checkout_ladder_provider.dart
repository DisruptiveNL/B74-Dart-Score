import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBindingObserver;
import '../database/db_helper.dart';
import '../models/checkout_ladder_game.dart';
import '../models/player.dart';
import '../utils/bot_strategy_x01.dart';
import '../utils/checkout_ladder_rules.dart';
import '../utils/player_label.dart';
import '../widgets/dartboard_input.dart' show DartEntry, DartboardInputSource;
import 'bot_runner.dart';

// ── CheckoutLadderSlotState ───────────────────────────────────────────────────

/// One scoreboard slot of a Checkout Ladder game: who throws in it, and the
/// ladder the engine keeps for it.
///
/// A slot is either a single player or a whole team sharing one ladder. The
/// member on turn is decided by the engine from the attempt and the visit, so
/// it is read off [ladder] rather than kept here.
class CheckoutLadderSlotState implements LabelledSlot {
  @override
  final String displayName;
  /// All players in this slot: 1 for individual, N for team.
  @override
  final List<Player> players;
  /// Whether this slot represents a team rather than a single player.
  @override
  final bool isTeamSlot;
  /// Where this slot stands and what it has done so far. Owned by the engine;
  /// read it, never change it.
  final LadderSlot ladder;

  const CheckoutLadderSlotState({
    required this.displayName,
    required this.players,
    required this.isTeamSlot,
    required this.ladder,
  });

  /// The player who throws next in this slot.
  Player get player => players[ladder.currentMember];

  /// Where this slot stands on the ladder.
  LadderPosition get position => ladder.position;
}

// ── CheckoutLadderProvider ────────────────────────────────────────────────────

/// Active-game state machine for the Checkout Ladder, training and race.
///
/// Every rule lives in [CheckoutLadderEngine]; this provider persists the
/// darts, feeds them to the engine, holds a finished visit on show, runs the
/// bots and takes darts back. Each dart is written the moment it lands, and
/// undo, redo and resume all rebuild the board by replaying the stored darts
/// through a fresh engine.
class CheckoutLadderProvider extends ChangeNotifier
    with WidgetsBindingObserver, BotRunner
    implements DartboardInputSource {
  final DbHelper _db = DbHelper.instance;

  CheckoutLadderGame? _game;
  CheckoutLadderEngine? _engine;
  /// The members of every slot in throwing order, kept so a replay can build
  /// a fresh engine for the same board.
  List<({String name, List<Player> players, bool isTeam})> _slotMembers = [];
  List<CheckoutLadderSlotState> _slots = [];
  /// Every persisted dart of the game, oldest first.
  final List<CheckoutLadderThrow> _throws = [];
  /// Darts of the person's taken back by undo, the latest last. Any new dart
  /// of theirs clears it.
  final List<LadderDart> _redo = [];
  /// Whether a training was ended by hand. A race ends on its own.
  bool _ended = false;

  CheckoutLadderGame?            get game              => _game;
  List<CheckoutLadderSlotState>  get slots             => _slots;
  int                            get currentSlotIndex  => _engine?.currentSlot ?? 0;
  CheckoutLadderSlotState        get currentSlot       => _slots[currentSlotIndex];
  List<CheckoutLadderThrow>      get throwHistory      => List.unmodifiable(_throws);
  /// What the last dart did, for the board to say so. Null before the first.
  LadderStep?                    get lastStep          => _engine?.lastStep;
  /// The number a race's sudden death is played on, null outside one.
  int?                           get suddenDeathNumber => _engine?.suddenDeathNumber;

  /// Whether nobody throws any more: a race decided, every ladder of a
  /// training completed, or a training ended by hand.
  bool get gameOver => _ended || (_engine?.gameOver ?? false);

  /// The slot that won the race, null in training and before the end.
  int? get winnerIndex => _engine?.winner;

  // ── Dartboard input ────────────────────────────────────────────────────────

  @override
  List<DartEntry> get currentVisitDarts => [
        for (final d in _engine?.currentVisit ?? const <LadderDart>[])
          DartEntry(
            field:    d.field,
            modifier: d.field == 0 ? 1 : d.multiplier,
            score:    d.field == 0
                ? 0
                : d.field == 25
                    ? (d.multiplier == 2 ? 50 : 25)
                    : d.field * d.multiplier,
          ),
      ];

  @override
  bool get liveBust =>
      (_engine?.visitOver ?? false) && (_engine?.lastStep?.bust ?? false);

  /// Whether there is a dart to undo. Not while a bot is throwing, and not
  /// when every recorded dart is a bot's: those are never undone on their
  /// own, see [undoLastDart].
  @override
  bool get canUndoDart =>
      !isBotTurn && _throws.any((t) => !_isBotId(t.playerId));

  @override
  bool get canRedoDart => !isBotTurn && _redo.isNotEmpty;

  @override
  Future<void> tapField(int field, int modifier) async {
    if (inputLocked) return;
    _redo.clear();
    await _recordDart(field, modifier);
    scheduleBot();
  }

  // ── Slot construction ──────────────────────────────────────────────────────

  /// The members of one slot per team (if [teams] is set) or one slot per
  /// player (individual game), in throwing order.
  List<({String name, List<Player> players, bool isTeam})> _membersOf(
      List<Player> players, List<TeamConfig>? teams) {
    if (teams != null && teams.isNotEmpty) {
      return [
        for (final team in teams)
          (
            name:    team.name,
            players: [
              for (final id in team.playerIds)
                players.firstWhere((p) => p.id == id),
            ],
            isTeam:  true,
          ),
      ];
    }
    return [
      for (final p in players) (name: p.name, players: [p], isTeam: false),
    ];
  }

  /// Puts a fresh engine on the board, every ladder at the start number.
  void _freshBoard() {
    _engine = CheckoutLadderEngine(
        _game!, [for (final s in _slotMembers) s.players.length]);
    _slots = [
      for (var i = 0; i < _slotMembers.length; i++)
        CheckoutLadderSlotState(
          displayName: _slotMembers[i].name,
          players:     _slotMembers[i].players,
          isTeamSlot:  _slotMembers[i].isTeam,
          ladder:      _engine!.slots[i],
        ),
    ];
  }

  // ── Start / Resume ─────────────────────────────────────────────────────────

  /// Starts a new game: persists it and puts every ladder on the start number.
  Future<void> startGame(CheckoutLadderGame game, List<Player> players) async {
    final gameId = await _db.insertCheckoutLadderGame(game);
    _game        = game.copyWith(id: gameId);
    _slotMembers = _membersOf(players, game.teams);
    _throws.clear();
    _redo.clear();
    _ended = false;
    dropHeldVisit();
    releaseBot();
    _freshBoard();
    notifyListeners();
    scheduleBot();
  }

  /// Restores an in-progress game and rebuilds the board by replaying all
  /// stored darts.
  Future<void> resumeGame(CheckoutLadderGame game, List<Player> players) async {
    _game        = game;
    _slotMembers = _membersOf(players, game.teams);
    _redo.clear();
    dropHeldVisit();
    releaseBot();
    await _replay();
    notifyListeners();
    scheduleBot();
  }

  /// Starts a fresh game with [template]'s settings and the given [players].
  /// The template's id and timestamps are not carried over, so a new game row
  /// is persisted and the finished one stays untouched. The throwing order
  /// follows the template's [StartingOrder]: drawn again for
  /// [StartingOrder.random], kept as it is for a fixed order.
  Future<void> startRematch(
      CheckoutLadderGame template, List<Player> players) async {
    final isRandom = template.startingOrder == StartingOrder.random;
    final ordered  = isRandom ? (List.of(players)..shuffle(Random()))
                              : List.of(players);
    final teams    = isRandom && template.teams != null
        ? (List.of(template.teams!)..shuffle(Random()))
        : template.teams;
    final game = CheckoutLadderGame(
      variant:         template.variant,
      startNumber:     template.startNumber,
      targetNumber:    template.targetNumber,
      dartsPerAttempt: template.dartsPerAttempt,
      stepFrom:        template.stepFrom,
      stepDarts:       template.stepDarts,
      checkOut:        template.checkOut,
      createdAt:       DateTime.now(),
      playerIds:       ordered.map((p) => p.id!).toList(),
      teams:           teams,
      startingOrder:   template.startingOrder,
    );
    await startGame(game, ordered);
  }

  /// Ends a training by hand: the visit on show is settled, the bots stop and
  /// the game is stored as finished. A race cannot be ended this way, it ends
  /// when it is decided.
  Future<void> endTraining() async {
    if (_game == null || _game!.isRace || gameOver) return;
    stopBot();
    await flushHeldVisit();
    _ended = true;
    _game  = _game!.copyWith(finishedAt: DateTime.now());
    await _db.updateCheckoutLadderGame(_game!);
    notifyListeners();
  }

  // ── Bot ────────────────────────────────────────────────────────────────────

  @override
  bool get isBotTurn =>
      _game != null &&
      !gameOver &&
      _slots.isNotEmpty &&
      currentSlot.player.isBot;

  /// Whether [playerId] belongs to one of the bots in this game.
  bool _isBotId(int playerId) => _slots
      .expand((s) => s.players)
      .any((p) => p.id == playerId && p.isBot);

  /// Aims like an X01 bot at the rest of the attempt with the darts the visit
  /// has left: the ladder is scored like X01, under the game's check-out rule.
  @override
  Future<void> throwBotDart() async {
    final level    = currentSlot.player.botLevel!;
    final position = currentSlot.position;
    final aim = x01Target(
      remaining: position.rest,
      dartsLeft: 3 - position.dartsInVisit,
      checkedIn: true,
      checkOut:  _game!.checkOut,
    );
    final hit = botThrower.throwAt(aim, level);
    await _recordDart(hit.field, hit.multiplier);
  }

  // ── Record a dart ──────────────────────────────────────────────────────────

  /// Records one dart for whoever is on turn, bot or person: persists it,
  /// applies it, and holds the visit on show once it is over.
  ///
  /// A miss is stored as field and multiplier zero, and a triple on the bull,
  /// which the board does not have, as the single bull.
  Future<void> _recordDart(int field, int multiplier) async {
    final engine = _engine;
    if (_game == null || engine == null || gameOver || engine.visitOver) return;
    final m = field == 0
        ? 0
        : field == 25 && multiplier == 3
            ? 1
            : multiplier;

    final t = CheckoutLadderThrow(
      gameId:     _game!.id!,
      playerId:   currentSlot.player.id!,
      field:      field,
      multiplier: m,
      thrownAt:   DateTime.now(),
    );
    final saved = t.withId(await _db.insertCheckoutLadderThrow(t));
    _throws.add(saved);
    engine.throwDart(saved.field, saved.multiplier);
    notifyListeners();

    if (engine.visitOver) await holdVisit(_endVisit);
  }

  /// Closes the visit on show and moves the turn on, storing the finish once
  /// the engine says the game is over.
  Future<void> _endVisit() async {
    _engine?.endVisit();
    if ((_engine?.gameOver ?? false) && _game!.finishedAt == null) {
      _game = _game!.copyWith(finishedAt: DateTime.now());
      await _db.updateCheckoutLadderGame(_game!);
    }
    notifyListeners();
  }

  // ── Undo / Redo ────────────────────────────────────────────────────────────

  /// Undoes the last dart of the person's: deletes it, reopens the game if it
  /// was over, and replays the rest to rebuild the board.
  ///
  /// A bot's darts are never undone one at a time: the bot would only throw
  /// again, and the person could never get back to their own visit. Undo over
  /// a bot's darts removes every bot dart since the last human dart, then that
  /// dart, in one rebuild. Only the human dart can be redone.
  @override
  Future<void> undoLastDart() async {
    if (_game == null || isBotTurn) return;
    if (!_throws.any((t) => !_isBotId(t.playerId))) return;
    dropHeldVisit();
    botSuspended = true;
    while (_isBotId(_throws.last.playerId)) {
      await _db.deleteCheckoutLadderThrow(_throws.removeLast().id!);
    }
    final last = _throws.removeLast();
    await _db.deleteCheckoutLadderThrow(last.id!);
    _redo.add((field: last.field, multiplier: last.multiplier));

    if (_game!.finishedAt != null) {
      _game = _game!.copyWith(clearFinishedAt: true);
      await _db.updateCheckoutLadderGame(_game!);
    }

    await _replay();
    botSuspended = false;
    notifyListeners();
    scheduleBot();
  }

  /// Throws the last dart undo took back again, for whoever the board now has
  /// on turn.
  @override
  Future<void> redoLastDart() async {
    if (_game == null || _redo.isEmpty || inputLocked) return;
    final d = _redo.removeLast();
    await _recordDart(d.field, d.multiplier);
    scheduleBot();
  }

  /// Rebuilds the board from the persisted darts through a fresh engine,
  /// closing every visit the moment it ends.
  ///
  /// Each dart is applied to whoever the engine has on turn, not to the player
  /// its row names. That relies on darts being stored in the order they were
  /// thrown, which [DbHelper] guarantees by ordering on the throw time and,
  /// for ties within a millisecond, the row id.
  Future<void> _replay() async {
    if (_game == null) return;
    final stored = await _db.getCheckoutLadderThrowsForGame(_game!.id!);
    _throws
      ..clear()
      ..addAll(stored);
    _freshBoard();
    final engine = _engine!;
    for (final t in stored) {
      if (engine.gameOver) break;
      engine.throwDart(t.field, t.multiplier);
      if (engine.visitOver) engine.endVisit();
    }
    _ended = !_game!.isRace && _game!.finishedAt != null;
  }
}
