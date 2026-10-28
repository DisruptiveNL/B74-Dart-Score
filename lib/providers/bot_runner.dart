import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../utils/bot_thrower.dart';

/// How fast a game moves on its own: how long a finished visit stays on the
/// board and how quickly a bot throws. Picked in the settings, kept by
/// [PaceProvider], read through [TurnPacing]. The index is what the setting
/// stores, so the order is fixed.
enum GamePace {
  fast,
  normal,
  slow;

  /// How long a finished visit stays on the board.
  Duration get visitPause => switch (this) {
    GamePace.fast => const Duration(seconds: 1),
    GamePace.normal => const Duration(seconds: 2),
    GamePace.slow => const Duration(seconds: 3),
  };

  /// The pause before each bot dart.
  Duration get botDartDelay => switch (this) {
    GamePace.fast => const Duration(milliseconds: 400),
    GamePace.normal => const Duration(milliseconds: 800),
    GamePace.slow => const Duration(milliseconds: 1400),
  };
}

/// The pauses the game providers keep, and the test hooks over them.
abstract final class TurnPacing {
  /// The pace the reader picked. [PaceProvider] sets it when it loads and
  /// whenever the setting changes; every provider reads it as it goes, so a
  /// game already running follows a change at its next visit.
  static GamePace pace = GamePace.normal;

  /// Overrides the pause a completed visit stays on the board for. Tests set
  /// it to zero so a visit settles in the same call that completes it; the
  /// tests of the pause itself set a short real one. Null in the app.
  static Duration? debugVisitPause;

  /// How long a completed visit stays on the board before it is recorded and
  /// the turn moves on, so the thrower sees their last dart.
  static Duration get visitPause => debugVisitPause ?? pace.visitPause;

  /// The pause before each bot dart, long enough to follow on the scoreboard.
  static Duration get botDartDelay => pace.botDartDelay;
}

/// What every game provider does the same way once a computer opponent can be
/// on turn: throws the bot's darts one timer at a time, holds a completed
/// visit on the board for [TurnPacing.visitPause], and stops both while the
/// board is being rebuilt, when the game is left, and while the app is in the
/// background.
///
/// The provider says who is on turn ([isBotTurn]) and how one bot dart is
/// aimed and recorded ([throwBotDart]); everything about timing lives here.
/// Each dart is its own timer rather than one loop, so that anything that
/// happens between two darts, an undo, a quit, the app going away, only has
/// to cancel the timer to stop the bot.
mixin BotRunner on ChangeNotifier, WidgetsBindingObserver {
  /// Throws the bots' darts. Replaceable so a test can seed it.
  BotThrower botThrower = BotThrower();

  /// Overrides the pace's pause before each bot dart. Tests set it to zero;
  /// the app leaves it null and follows [TurnPacing.botDartDelay].
  Duration? botDartDelay;

  Timer? _botTimer;
  bool _botDartInFlight = false;
  bool _botSuspended = false;
  bool _observing = false;

  Timer? _holdTimer;
  Future<void> Function()? _heldVisit;

  /// Whether the slot about to throw is a computer opponent in a game that
  /// is still open.
  bool get isBotTurn;

  /// Aims and records one dart for the bot on turn, down the same path a
  /// person's dart takes.
  Future<void> throwBotDart();

  /// Called when the app leaves the foreground, for what must not wait until
  /// it comes back. The default records a held visit.
  Future<void> onAppBackground() => flushHeldVisit();

  /// Whether a bot dart is scheduled or being recorded right now. Tests wait
  /// on this rather than on a guessed duration.
  bool get botThrowing => _botTimer != null || _botDartInFlight;

  /// Whether a completed visit is waiting out its pause on the board.
  bool get visitPending => _heldVisit != null;

  /// Whether no dart of the person's may land right now: a bot is on turn,
  /// or a completed visit is still being shown.
  bool get inputLocked => isBotTurn || visitPending;

  /// Holds the bot back, for as long as a rebuild of the board is under way.
  /// Undo and redo set it before they start and clear it once the in-progress
  /// visit is restored, so no bot dart lands on a half restored board.
  set botSuspended(bool value) => _botSuspended = value;

  /// Lines the next bot dart up, if it is a bot's turn and nothing holds it
  /// back. Called after every change of turn; a call that finds a person on
  /// turn, or a visit still on show, does nothing, so it is cheap to call
  /// generously.
  void scheduleBot() {
    _botTimer?.cancel();
    _botTimer = null;
    if (_botSuspended || visitPending || !isBotTurn) return;
    _observeLifecycle();
    _botTimer = Timer(botDartDelay ?? TurnPacing.botDartDelay, _fireBotDart);
  }

  /// Throws one bot dart, then lines up the next.
  Future<void> _fireBotDart() async {
    _botTimer = null;
    if (_botSuspended || !isBotTurn) return;
    _botDartInFlight = true;
    try {
      await throwBotDart();
    } finally {
      _botDartInFlight = false;
    }
    scheduleBot();
  }

  /// Lets the bot throw again after [stopBot]: the next start or resume.
  void releaseBot() => _botSuspended = false;

  /// Stops the bot for good until the next start or resume, so a bot does not
  /// keep throwing into a game nobody is watching.
  void stopBot() {
    _botSuspended = true;
    _botTimer?.cancel();
    _botTimer = null;
  }

  /// What the live screen calls before it pops: stops the bot and records a
  /// visit still waiting out its pause, so nothing thrown is lost with the
  /// screen.
  Future<void> leaveGame() async {
    stopBot();
    await flushHeldVisit();
  }

  /// Keeps a completed visit on the board for [TurnPacing.visitPause], then
  /// runs [settle], which records it and moves the turn on. With the pause at
  /// zero it settles right here, so a test sees the turn move in the same
  /// call. The bot is lined up again once it has settled.
  Future<void> holdVisit(Future<void> Function() settle) async {
    if (TurnPacing.visitPause == Duration.zero) {
      await settle();
      scheduleBot();
      return;
    }
    _heldVisit = settle;
    _observeLifecycle();
    _holdTimer = Timer(TurnPacing.visitPause, _releaseHeldVisit);
  }

  /// Settles the held visit now rather than after its pause. Nothing to do
  /// when none is held.
  Future<void> flushHeldVisit() async {
    if (_heldVisit == null) return;
    _holdTimer?.cancel();
    await _releaseHeldVisit();
  }

  /// Forgets a held visit without settling it, for an undo that takes the
  /// last dart back off the board instead.
  void dropHeldVisit() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _heldVisit = null;
  }

  Future<void> _releaseHeldVisit() async {
    final settle = _heldVisit;
    _holdTimer = null;
    _heldVisit = null;
    if (settle != null) await settle();
    scheduleBot();
  }

  /// Registers for app lifecycle events the first time a timer is needed, so
  /// that the bot pauses while the app is in the background on either
  /// platform and picks up where it left off when it comes back.
  void _observeLifecycle() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleBot();
    } else {
      _botTimer?.cancel();
      _botTimer = null;
      unawaited(onAppBackground());
    }
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _holdTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
