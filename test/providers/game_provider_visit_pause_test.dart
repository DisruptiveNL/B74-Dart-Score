import 'dart:math';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Throws the given darts one after the other.
Future<void> _visit(
  GameProvider p,
  List<(int field, int modifier)> darts,
) async {
  for (final d in darts) {
    await p.tapField(d.$1, d.$2);
  }
}

/// Waits a little longer than the pause under test.
Future<void> _wait() => Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  group('the pause after a completed visit', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      // Short, but real: what is under test is that the game holds still for
      // it and moves on after it.
      TurnPacing.debugVisitPause = const Duration(milliseconds: 40);
      provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
    });

    tearDown(() => provider.dispose());

    Game game({int startScore = 501}) => Game(
      startScore: startScore,
      legs: 1,
      createdAt: DateTime.now(),
      startingOrder: StartingOrder.fixed,
    );

    test('keeps the finished visit on the board, then records it', () async {
      await provider.startGame(game(), players);

      await _visit(provider, const [(20, 1), (20, 1), (20, 1)]);

      expect(provider.visitPending, isTrue);
      expect(provider.inputLocked, isTrue);
      expect(provider.dartsInVisit, 3, reason: 'still on show');
      expect(provider.currentPlayerIndex, 0, reason: 'the turn has not moved');
      expect(provider.liveRunningRemaining, 441);
      expect(provider.allThrows(), isEmpty, reason: 'not recorded yet');

      await _wait();

      expect(provider.visitPending, isFalse);
      expect(provider.currentPlayerIndex, 1);
      expect(provider.dartsInVisit, 0);
      expect(provider.playerStates[0].remaining, 441);
      expect(provider.allThrows().single.score, 60);
    });

    test('holds a bust the same way, and takes no dart meanwhile', () async {
      await provider.startGame(game(startScore: 101), players);

      await _visit(provider, const [(20, 3), (20, 3)]);

      expect(provider.visitPending, isTrue);
      expect(provider.liveBust, isTrue, reason: 'the bust stays readable');
      await provider.tapField(1, 1);
      expect(provider.dartsInVisit, 2, reason: 'refused during the pause');

      await _wait();

      expect(provider.allThrows().single.bust, isTrue);
      expect(provider.allThrows().single.dartsUsed, 2);
      expect(provider.currentPlayerIndex, 1);
    });

    test('lets the last dart be taken back before it is recorded', () async {
      await provider.startGame(game(), players);
      await _visit(provider, const [(20, 1), (20, 1), (20, 1)]);

      await provider.undoLastDart();

      expect(provider.visitPending, isFalse);
      expect(provider.dartsInVisit, 2);
      expect(provider.canRedoDart, isTrue);
      await _wait();
      expect(
        provider.allThrows(),
        isEmpty,
        reason: 'the cancelled pause never recorded anything',
      );
      expect(provider.currentPlayerIndex, 0);

      await provider.redoLastDart();
      expect(provider.visitPending, isTrue);
      await _wait();
      expect(provider.allThrows().single.score, 60);
      expect(provider.currentPlayerIndex, 1);
    });

    test('is cut short by a tap on the dart row', () async {
      await provider.startGame(game(), players);
      await _visit(provider, const [(20, 1), (20, 1), (20, 1)]);
      expect(provider.visitPending, isTrue);

      await provider.flushHeldVisit();

      expect(provider.visitPending, isFalse);
      expect(provider.currentPlayerIndex, 1);
      expect(provider.allThrows().single.score, 60);
    });

    test('follows the pace the settings hand it', () async {
      TurnPacing.debugVisitPause = null;
      TurnPacing.pace = GamePace.fast;
      addTearDown(() => TurnPacing.pace = GamePace.normal);

      expect(TurnPacing.visitPause, GamePace.fast.visitPause);
      expect(TurnPacing.botDartDelay, GamePace.fast.botDartDelay);
    });

    test('is cut short when the game is left, so nothing is lost', () async {
      await provider.startGame(game(), players);
      await _visit(provider, const [(20, 1), (20, 1), (20, 1)]);

      await provider.leaveGame();

      expect(provider.visitPending, isFalse);
      expect(provider.allThrows().single.score, 60);
      expect(
        (await DbHelper.instance.getThrowsForGame(
          provider.game!.id!,
        )).single.score,
        60,
      );
    });

    test('applies to a bot\'s visit before the turn comes back', () async {
      provider
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(5));
      final botId = await DbHelper.instance.insertPlayer(
        Player(
          name: BotLevel.pro.storedName,
          uuid: BotLevel.pro.uuid,
          botLevel: BotLevel.pro,
        ),
      );
      final bot = (await DbHelper.instance.getPlayer(botId))!;
      await provider.startGame(game(), [players.first, bot]);

      await _visit(provider, const [(20, 1), (20, 1), (20, 1)]);

      // Ada's pause runs out, the bot's three darts land at once, and then
      // its visit waits out the same pause. Polled, because the bot throws
      // on timers of its own and the moment is not worth guessing at.
      for (
        var i = 0;
        i < 500 && !(provider.isBotTurn && provider.visitPending);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(provider.visitPending, isTrue);
      expect(provider.isBotTurn, isTrue);
      expect(provider.dartsInVisit, 3);
      expect(provider.allThrows(), hasLength(1), reason: 'only Ada\'s so far');

      await _wait();

      expect(provider.isBotTurn, isFalse);
      expect(provider.currentPlayerIndex, 0);
      expect(provider.playerStates[1].throws, hasLength(1));
    });
  });
}
