import 'dart:math' show max, min;

import '../models/checkout_ladder_game.dart';
import 'finish_calculator.dart';

// ── One slot on the ladder ────────────────────────────────────────────────────

/// Where one slot stands on the Checkout Ladder.
///
/// An attempt is the darts a slot has to check [number] in, [CheckoutLadderGame.dartsFor]
/// of them, thrown over its next visits. Climbing, a number gets two attempts;
/// falling, one. Nothing below [floor] is ever played again.
class LadderPosition {
  /// The number the current attempt has to check.
  final int number;

  /// The lowest number this slot can fall to: the start number, raised by
  /// every safehouse.
  final int floor;

  /// Whether the slot arrived at [number] by checking the one below it, rather
  /// than by falling from the one above.
  final bool climbing;

  /// 1 or 2. Only a climbing slot ever plays a second attempt on a number.
  final int attempt;

  /// What is left of [number] in this attempt.
  final int rest;

  /// [rest] when the current visit began, which a bust falls back to.
  final int restAtVisitStart;

  /// Dart slots of the attempt used up so far. A bust uses up the whole visit
  /// it happened in, so this can run ahead of the darts actually thrown.
  final int dartsInAttempt;

  /// Darts thrown in the current visit, reset when the visit ends.
  final int dartsInVisit;

  /// Whether the slot has checked [kCheckoutLadderTop]. Nothing follows that.
  final bool completed;

  const LadderPosition({
    required this.number,
    required this.floor,
    this.climbing = true,
    this.attempt = 1,
    required this.rest,
    required this.restAtVisitStart,
    this.dartsInAttempt = 0,
    this.dartsInVisit = 0,
    this.completed = false,
  });

  /// A slot standing on [startNumber] before its first dart: climbing, first
  /// attempt, with the start number as its floor.
  factory LadderPosition.start(int startNumber) => LadderPosition(
    number: startNumber,
    floor: startNumber,
    rest: startNumber,
    restAtVisitStart: startNumber,
  );

  /// A fresh attempt on [number], keeping nothing of the attempt before it.
  factory LadderPosition.freshAttempt({
    required int number,
    required int floor,
    required bool climbing,
    int attempt = 1,
  }) => LadderPosition(
    number: number,
    floor: floor,
    climbing: climbing,
    attempt: attempt,
    rest: number,
    restAtVisitStart: number,
  );

  /// Whether the slot stands on its floor, where a failed attempt costs
  /// nothing and the slot simply tries again.
  bool get onFloor => number == floor;
}

/// What one dart did on the ladder: the [position] it leaves and what
/// happened on the way there.
class LadderStep {
  /// Where the slot stands after the dart, already on the next attempt when
  /// this dart ended one.
  final LadderPosition position;

  /// The number the dart was thrown at.
  final int number;

  /// What is left of [number] once the dart has landed: zero after a check,
  /// the rest the visit began with after a bust. Read before the attempt moves
  /// on, so a missed attempt still says where it stopped.
  final int restAfter;

  /// Whether the dart took the rest to zero under the check-out rule.
  final bool checked;

  /// Whether the dart busted the visit.
  final bool bust;

  /// Whether the check came with the first visit of the attempt and raised
  /// the floor.
  final bool safehouse;

  /// Whether the visit is over: three darts, a check or a bust.
  final bool visitOver;

  /// Whether the attempt is over, checked or not.
  final bool attemptOver;

  /// Whether the slot has to step down a number after this attempt.
  final bool dropped;

  const LadderStep({
    required this.position,
    required this.number,
    required this.restAfter,
    this.checked = false,
    this.bust = false,
    this.safehouse = false,
    this.visitOver = false,
    this.attemptOver = false,
    this.dropped = false,
  });
}

/// The one rule of the Checkout Ladder: where [position] moves when a dart
/// lands on [field] with [multiplier] in [game].
///
/// The engine applies it live and on replay, and the statistics read what it
/// returns, so that a dart is judged in exactly one place.
///
/// A check moves the slot up a number, climbing, with two attempts again, and
/// a check with the first visit of the attempt (darts one to three) raises the
/// floor to the number above. A bust is X01's: the rest goes back to where the
/// visit began, the visit is over, and the attempt plays its next visit if it
/// has one. An attempt that runs out of darts unchecked leaves the slot where
/// it is on its floor, gives a climbing slot its second attempt, and otherwise
/// steps it down a number, falling, with a single attempt.
LadderStep applyLadderDart({
  required CheckoutLadderGame game,
  required LadderPosition position,
  required int field,
  required int multiplier,
}) {
  final p = position;
  final score = field == 0 || multiplier == 0
      ? 0
      : field == 25
      ? (multiplier == 2 ? 50 : 25)
      : field * multiplier;
  final newRest = p.rest - score;
  final dartsInVisit = p.dartsInVisit + 1;
  final dartsInAttempt = p.dartsInAttempt + 1;

  final bust =
      newRest < 0 ||
      (newRest == 0 &&
          !FinishCalculator.finishesOn(field, multiplier, game.checkOut)) ||
      (newRest > 0 && !FinishCalculator.canStillFinish(newRest, game.checkOut));
  final checked = newRest == 0 && !bust;

  if (checked) {
    final safehouse = dartsInAttempt <= 3;
    final floor = safehouse
        ? min(max(p.floor, p.number + 1), kCheckoutLadderTop)
        : p.floor;
    if (p.number >= kCheckoutLadderTop) {
      return LadderStep(
        position: LadderPosition(
          number: p.number,
          floor: floor,
          rest: 0,
          restAtVisitStart: 0,
          completed: true,
        ),
        number: p.number,
        restAfter: 0,
        checked: true,
        safehouse: safehouse,
        visitOver: true,
        attemptOver: true,
      );
    }
    return LadderStep(
      position: LadderPosition.freshAttempt(
        number: p.number + 1,
        floor: floor,
        climbing: true,
      ),
      number: p.number,
      restAfter: 0,
      checked: true,
      safehouse: safehouse,
      visitOver: true,
      attemptOver: true,
    );
  }

  final budget = game.dartsFor(p.number);
  // A bust gives up what is left of its visit, so the attempt counts the
  // visit as thrown in full.
  final used = bust ? p.dartsInAttempt - p.dartsInVisit + 3 : dartsInAttempt;
  final rest = bust ? p.restAtVisitStart : newRest;
  final visitOver = bust || dartsInVisit >= 3;
  final attemptOver = visitOver && used >= budget;

  if (!attemptOver) {
    return LadderStep(
      position: LadderPosition(
        number: p.number,
        floor: p.floor,
        climbing: p.climbing,
        attempt: p.attempt,
        rest: rest,
        restAtVisitStart: visitOver ? rest : p.restAtVisitStart,
        dartsInAttempt: used,
        dartsInVisit: visitOver ? 0 : dartsInVisit,
      ),
      number: p.number,
      restAfter: rest,
      bust: bust,
      visitOver: visitOver,
    );
  }

  final LadderPosition next;
  var dropped = false;
  if (p.onFloor) {
    next = LadderPosition.freshAttempt(
      number: p.number,
      floor: p.floor,
      climbing: p.climbing,
    );
  } else if (p.climbing && p.attempt == 1) {
    next = LadderPosition.freshAttempt(
      number: p.number,
      floor: p.floor,
      climbing: true,
      attempt: 2,
    );
  } else {
    dropped = true;
    next = LadderPosition.freshAttempt(
      number: p.number - 1,
      floor: p.floor,
      climbing: false,
    );
  }
  return LadderStep(
    position: next,
    number: p.number,
    restAfter: rest,
    bust: bust,
    visitOver: true,
    attemptOver: true,
    dropped: dropped,
  );
}

// ── A whole game ──────────────────────────────────────────────────────────────

/// One dart as the engine keeps it for the visit on show.
typedef LadderDart = ({int field, int multiplier});

/// One finished visit of a slot: its darts, the number they were thrown at,
/// and how the visit ended.
typedef LadderVisit = ({
  List<LadderDart> darts,
  int number,
  bool checked,
  bool bust,
  bool safehouse,
  int restAfter,
});

/// Everything the engine knows about one slot: where it stands, and the
/// numbers the summary and the race are decided by.
///
/// Owned and changed by [CheckoutLadderEngine] alone; everything outside it
/// only reads.
class LadderSlot {
  /// How many players take turns in this slot: one, or the team's size.
  final int memberCount;
  LadderPosition position;

  /// Attempts begun, the current one included. Decides which member starts it.
  int attemptsStarted = 1;

  /// Attempts played to the end, checked or not.
  int attemptsCompleted = 0;

  /// Darts actually thrown in the whole game.
  int darts = 0;

  /// Darts actually thrown in the current attempt.
  int dartsThisAttempt = 0;

  /// Visits begun in the current attempt, the current one included once its
  /// first dart has landed.
  int visitsThisAttempt = 0;
  int checks = 0;

  /// Darts actually thrown in the attempts that ended in a check.
  int dartsInChecks = 0;
  int safehouses = 0;
  int busts = 0;
  int drops = 0;

  /// The highest number this slot has checked, null before its first check.
  int? highestChecked;

  /// Race only: the attempt count at which the target was checked.
  int? reachedTargetAt;

  /// Race only: darts in the whole game when the target was checked.
  int? reachedTargetDarts;

  /// Every finished visit of this slot, oldest first. A visit can end after
  /// one dart, on a check or a bust, so the darts are never grouped in threes.
  final List<LadderVisit> visits = [];

  /// Sudden death only: whether this slot is still in it.
  bool inSuddenDeath = false;

  /// Sudden death only: whether this slot has played its attempt of the round.
  bool suddenDeathPlayed = false;

  /// Sudden death only: whether that attempt checked, and in how many darts.
  bool suddenDeathChecked = false;
  int suddenDeathDarts = 0;

  LadderSlot({required this.memberCount, required this.position});

  /// Share of the finished attempts that ended in a check, null before the
  /// first attempt is over.
  double? get checkRate =>
      attemptsCompleted == 0 ? null : checks / attemptsCompleted;

  /// Darts a check took on average, null before the first check.
  double? get dartsPerCheck => checks == 0 ? null : dartsInChecks / checks;

  /// The member on turn, counted from zero in team order.
  ///
  /// Members take the visits of an attempt in turn, and the member who starts
  /// moves on by one with every attempt, so in a pair both set up and both
  /// check.
  int get currentMember => memberCount <= 1
      ? 0
      : (attemptsStarted - 1 + visitsInProgress) % memberCount;

  /// Visits of the current attempt already over. The visit in progress
  /// belongs to the member after them.
  int get visitsInProgress =>
      position.dartsInVisit > 0 ? visitsThisAttempt - 1 : visitsThisAttempt;
}

/// The whole of a Checkout Ladder game, one dart at a time: every slot's
/// ladder, whose turn it is, and in a race who has won.
///
/// Pure and deterministic, so the provider builds the board by feeding it the
/// stored darts in order, live, on undo and on resume alike. A dart is applied
/// to whoever the engine has on turn, never to the slot its row names.
///
/// The turn moves on after every visit, as in every other mode, so a slot's
/// attempt is spread over its next visits. A slot that has nothing left to
/// play is skipped: a completed ladder, and in a race a slot that has checked
/// the target or used as many attempts as the best slot that has.
///
/// A race ends once nobody can play any more. The slots that checked the
/// target in the fewest attempts are compared on the darts they needed for the
/// whole game. A tie goes to sudden death: one attempt each on the number above
/// the target until one slot alone checks it in the fewest darts. Nobody
/// checking replays the round on the same number; a tie among the checkers
/// moves it up one.
class CheckoutLadderEngine {
  final CheckoutLadderGame game;
  final List<LadderSlot> slots;

  int _current = 0;
  bool _visitOver = false;
  final List<LadderDart> _visit = [];
  LadderStep? _lastStep;
  bool _gameOver = false;
  int? _winner;
  int? _suddenDeathNumber;

  /// Builds the board before the first dart, one slot per entry of
  /// [memberCounts], in throwing order.
  CheckoutLadderEngine(this.game, List<int> memberCounts)
    : slots = [
        for (final count in memberCounts)
          LadderSlot(
            memberCount: count,
            position: LadderPosition.start(game.startNumber),
          ),
      ];

  /// Index of the slot on turn, or of the slot whose finished visit is still
  /// waiting for [endVisit].
  int get currentSlot => _current;

  /// Whether the visit on the board is over and waits for [endVisit].
  bool get visitOver => _visitOver;

  /// The darts of the visit on the board, oldest first.
  List<LadderDart> get currentVisit => List.unmodifiable(_visit);

  /// What the last dart did, null before the first one.
  LadderStep? get lastStep => _lastStep;

  /// Whether nobody throws any more: a race decided, or every ladder in a
  /// training completed.
  bool get gameOver => _gameOver;

  /// Race only: the slot that won, once the race is decided.
  int? get winner => _winner;

  /// The number the sudden death is played on, null outside one.
  int? get suddenDeathNumber => _suddenDeathNumber;

  /// Throws one dart for the slot on turn and returns what it did. Refused,
  /// returning null, once the game is over or while a finished visit still
  /// waits for [endVisit].
  LadderStep? throwDart(int field, int multiplier) {
    if (_gameOver || _visitOver) return null;
    final slot = slots[_current];
    if (slot.position.dartsInVisit == 0) slot.visitsThisAttempt++;

    final step = applyLadderDart(
      game: game,
      position: slot.position,
      field: field,
      multiplier: multiplier,
    );
    _visit.add((field: field, multiplier: multiplier));
    _lastStep = step;
    slot.darts++;
    slot.dartsThisAttempt++;
    if (step.bust) slot.busts++;
    if (step.checked) {
      slot.checks++;
      slot.dartsInChecks += slot.dartsThisAttempt;
      slot.highestChecked = max(slot.highestChecked ?? 0, step.number);
      if (step.safehouse) slot.safehouses++;
    }
    if (step.dropped) slot.drops++;
    slot.position = step.position;

    if (step.attemptOver) _endAttempt(slot, step);
    if (step.visitOver) {
      _visitOver = true;
      slot.visits.add((
        darts: List.of(_visit),
        number: step.number,
        checked: step.checked,
        bust: step.bust,
        safehouse: step.safehouse,
        restAfter: step.restAfter,
      ));
    }
    return step;
  }

  /// Closes the visit on the board and hands the turn to the next slot that
  /// still has something to play, deciding the game when nobody has.
  void endVisit() {
    if (!_visitOver) return;
    _visitOver = false;
    _visit.clear();
    if (_gameOver) return;
    _advance();
  }

  /// Books the attempt [step] ended into [slot]: counters, and in a race the
  /// target or the sudden death attempt.
  void _endAttempt(LadderSlot slot, LadderStep step) {
    slot.attemptsCompleted++;
    final dartsThisAttempt = slot.dartsThisAttempt;
    if (!slot.position.completed) slot.attemptsStarted++;
    slot.dartsThisAttempt = 0;
    slot.visitsThisAttempt = 0;

    if (!game.isRace) {
      if (slots.every((s) => s.position.completed)) _gameOver = true;
      return;
    }

    if (_suddenDeathNumber != null) {
      slot.suddenDeathPlayed = true;
      slot.suddenDeathChecked = step.checked;
      slot.suddenDeathDarts = dartsThisAttempt;
      return;
    }

    if (step.checked && step.number == game.targetNumber) {
      slot.reachedTargetAt = slot.attemptsCompleted;
      slot.reachedTargetDarts = slot.darts;
    }
  }

  /// The fewest attempts any slot has checked the race target in, null while
  /// nobody has.
  int? get _bestAttempts {
    int? best;
    for (final s in slots) {
      final at = s.reachedTargetAt;
      if (at != null && (best == null || at < best)) best = at;
    }
    return best;
  }

  /// Whether [slot] still has darts to throw.
  bool _canPlay(LadderSlot slot) {
    if (slot.position.completed && _suddenDeathNumber == null) return false;
    if (!game.isRace) return true;
    if (_suddenDeathNumber != null) {
      return slot.inSuddenDeath && !slot.suddenDeathPlayed;
    }
    if (slot.reachedTargetAt != null) return false;
    final best = _bestAttempts;
    return best == null || slot.attemptsCompleted < best;
  }

  /// Moves the turn to the next slot after the current one that can play, or
  /// settles the round when none can.
  void _advance() {
    for (var i = 1; i <= slots.length; i++) {
      final next = (_current + i) % slots.length;
      if (_canPlay(slots[next])) {
        _current = next;
        return;
      }
    }
    if (!game.isRace) {
      _gameOver = true;
      return;
    }
    _settleRace();
  }

  /// Decides the race once nobody can play: a winner, or a round of sudden
  /// death among the slots still level.
  void _settleRace() {
    final List<int> level;
    if (_suddenDeathNumber == null) {
      final best = _bestAttempts!;
      final reached = [
        for (var i = 0; i < slots.length; i++)
          if (slots[i].reachedTargetAt == best) i,
      ];
      final fewest = reached
          .map((i) => slots[i].reachedTargetDarts!)
          .reduce(min);
      level = reached
          .where((i) => slots[i].reachedTargetDarts == fewest)
          .toList();
      if (level.length == 1) return _decide(level.single);
      _startSuddenDeath(level, min(game.targetNumber! + 1, kCheckoutLadderTop));
      return;
    }

    final inIt = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].inSuddenDeath) i,
    ];
    final checkers = inIt.where((i) => slots[i].suddenDeathChecked).toList();
    if (checkers.isEmpty) {
      _startSuddenDeath(inIt, _suddenDeathNumber!);
      return;
    }
    final fewest = checkers.map((i) => slots[i].suddenDeathDarts).reduce(min);
    level = checkers.where((i) => slots[i].suddenDeathDarts == fewest).toList();
    if (level.length == 1) return _decide(level.single);
    _startSuddenDeath(level, min(_suddenDeathNumber! + 1, kCheckoutLadderTop));
  }

  /// Puts the slots in [level] on one fresh attempt each at [number], in
  /// throwing order, and everybody else out.
  void _startSuddenDeath(List<int> level, int number) {
    _suddenDeathNumber = number;
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      s.inSuddenDeath = level.contains(i);
      s.suddenDeathPlayed = false;
      s.suddenDeathChecked = false;
      s.suddenDeathDarts = 0;
      if (s.inSuddenDeath) {
        s.position = LadderPosition.freshAttempt(
          number: number,
          floor: number,
          climbing: true,
        );
      }
    }
    _current = level.first;
  }

  /// Ends the race with [slot] as the winner.
  void _decide(int slot) {
    _winner = slot;
    _gameOver = true;
  }
}
