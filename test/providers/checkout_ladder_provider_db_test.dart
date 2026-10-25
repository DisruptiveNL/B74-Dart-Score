import 'dart:math';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/checkout_ladder_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/checkout_ladder_provider.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// The finish time the Checkout Ladder game [gameId] carries in the database.
Future<DateTime?> _storedFinishedAt(int gameId) async =>
    (await DbHelper.instance.getCheckoutLadderGames())
        .firstWhere((g) => g.id == gameId)
        .finishedAt;

/// Waits until no bot is on turn and no bot dart is in the air, polling
/// because the bot throws on timers of its own.
Future<void> _settleBot(CheckoutLadderProvider p) async {
  for (var i = 0; i < 2000 && (p.isBotTurn || p.botThrowing); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isBotTurn, isFalse, reason: 'the bot never finished its turn');
}

void main() {
  group('CheckoutLadderProvider against a real database', () {
    useInMemoryDatabase();

    late CheckoutLadderProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = CheckoutLadderProvider();
      players = await insertPlayers(['A', 'B']);
    });

    tearDown(() => provider.dispose());

    CheckoutLadderGame game({
      CheckoutLadderVariant variant = CheckoutLadderVariant.training,
      int? target,
      List<Player>? who,
      List<TeamConfig>? teams,
    }) =>
        CheckoutLadderGame(
          variant:         variant,
          startNumber:     81,
          targetNumber:    target,
          dartsPerAttempt: 6,
          createdAt:       DateTime.now(),
          playerIds:       (who ?? players).map((p) => p.id!).toList(),
          teams:           teams,
          startingOrder:   StartingOrder.fixed,
        );

    /// Enters darts in the board's notation (`T15`, `D10`, `S16`, `M`) for
    /// whoever is on turn.
    Future<void> tap(String darts) async {
      for (final s in darts.split(' ')) {
        if (s == 'M') {
          await provider.tapField(0, 1);
          continue;
        }
        final m = switch (s[0]) { 'T' => 3, 'D' => 2, _ => 1 };
        await provider.tapField(int.parse(s.substring(1)), m);
      }
    }

    test('a check moves the slot up and the turn on', () async {
      await provider.startGame(game(), players);

      await tap('T15 S16 D10');

      expect(provider.slots[0].position.number, 82);
      expect(provider.slots[0].position.floor, 82);
      expect(provider.currentSlotIndex, 1);
      expect(provider.currentVisitDarts, isEmpty);
    });

    test('every dart is stored the moment it lands', () async {
      await provider.startGame(game(), players);

      await tap('T15 S16');

      final stored = await DbHelper.instance
          .getCheckoutLadderThrowsForGame(provider.game!.id!);
      expect(stored.map((t) => t.score), [45, 16]);
      expect(stored.every((t) => t.playerId == players[0].id), isTrue);
    });

    test('undo replays the board from the darts that are left', () async {
      await provider.startGame(game(), players);
      await tap('T15 S16 D10');
      expect(provider.currentSlotIndex, 1);

      await provider.undoLastDart();

      expect(provider.currentSlotIndex, 0);
      expect(provider.slots[0].position.number, 81);
      expect(provider.slots[0].position.rest, 20);
      expect(provider.currentVisitDarts.map((d) => d.score), [45, 16]);
      expect(provider.canRedoDart, isTrue);
    });

    test('redo throws the undone dart again', () async {
      await provider.startGame(game(), players);
      await tap('T15 S16 D10');
      await provider.undoLastDart();

      await provider.redoLastDart();

      expect(provider.slots[0].position.number, 82);
      expect(provider.currentSlotIndex, 1);
      expect(provider.canRedoDart, isFalse);
    });

    test('a new dart clears what could be redone', () async {
      await provider.startGame(game(), players);
      await tap('T15 S16');
      await provider.undoLastDart();

      await tap('S20');

      expect(provider.canRedoDart, isFalse);
    });

    test('a bust stays on the board for the pause, then the turn moves on',
        () async {
      TurnPacing.debugVisitPause = const Duration(hours: 1);
      await provider.startGame(game(), players);
      await tap('S20 S20 T20');

      expect(provider.visitPending, isTrue);
      expect(provider.liveBust, isTrue);
      expect(provider.currentVisitDarts, hasLength(3));
      expect(provider.currentSlotIndex, 0);
      expect(provider.slots[0].position.rest, 81);

      await provider.flushHeldVisit();

      expect(provider.liveBust, isFalse);
      expect(provider.currentSlotIndex, 1);
    });

    test('resume rebuilds positions, turn and the open visit', () async {
      await provider.startGame(game(), players);
      await tap('T15 S16 D10');              // A: 81, safehouse
      await tap('M M M');                    // B
      await tap('T14');                      // A: 82, one dart in
      final saved = provider.game!;

      final resumed = CheckoutLadderProvider();
      addTearDown(resumed.dispose);
      await resumed.resumeGame(saved, players);

      expect(resumed.slots[0].position.number, 82);
      expect(resumed.slots[0].position.rest, 40);
      expect(resumed.slots[1].position.dartsInAttempt, 3);
      expect(resumed.currentSlotIndex, 0);
      expect(resumed.currentVisitDarts.map((d) => d.score), [42]);
    });

    test('a team shares one ladder and alternates its members', () async {
      final team = [
        TeamConfig(name: 'Team', playerIds: [players[0].id!, players[1].id!]),
      ];
      await provider.startGame(game(teams: team), players);

      expect(provider.currentSlot.player.id, players[0].id);
      await tap('M M M');
      expect(provider.currentSlot.player.id, players[1].id);
      await tap('M M M');
      // Second attempt: the other member starts.
      expect(provider.currentSlot.player.id, players[1].id);

      final stored = await DbHelper.instance
          .getCheckoutLadderThrowsForGame(provider.game!.id!);
      expect(stored.map((t) => t.playerId).toSet(),
          {players[0].id, players[1].id});
    });

    test('a decided race is stored as finished and undo reopens it', () async {
      await provider.startGame(
          game(variant: CheckoutLadderVariant.race, target: 82), players);
      await tap('T15 S16 D10');              // A: 81
      await tap('T15 S16 D10');              // B: 81
      await tap('T14 M D20');                // A: target, six darts in all
      await tap('T14 D20');                  // B: target, five darts in all

      expect(provider.gameOver, isTrue);
      expect(provider.winnerIndex, 1);
      expect(await _storedFinishedAt(provider.game!.id!), isNotNull);

      await provider.undoLastDart();

      expect(provider.gameOver, isFalse);
      expect(await _storedFinishedAt(provider.game!.id!), isNull);
    });

    test('ending a training stores it as finished, also after a resume',
        () async {
      await provider.startGame(game(), players);
      await tap('T15 S16');
      await provider.endTraining();

      expect(provider.gameOver, isTrue);
      final saved = (await DbHelper.instance.getCheckoutLadderGames()).single;
      expect(saved.finishedAt, isNotNull);

      final resumed = CheckoutLadderProvider();
      addTearDown(resumed.dispose);
      await resumed.resumeGame(saved, players);
      expect(resumed.gameOver, isTrue);
    });

    test('deleting a game takes its darts with it', () async {
      await provider.startGame(game(), players);
      await tap('T15 S16');
      final id = provider.game!.id!;

      await DbHelper.instance.deleteCheckoutLadderGame(id);

      expect(await DbHelper.instance.getCheckoutLadderGames(), isEmpty);
      expect(await DbHelper.instance.getCheckoutLadderThrowsForGame(id), isEmpty);
    });
  });

  group('a bot on the Checkout Ladder', () {
    useInMemoryDatabase();

    late CheckoutLadderProvider provider;
    late Player human;
    late Player bot;

    setUp(() async {
      provider = CheckoutLadderProvider()
        ..botDartDelay = Duration.zero
        ..botThrower   = BotThrower(rng: Random(7));
      human = (await insertPlayers(['Ada'])).single;
      final id = await DbHelper.instance.insertPlayer(Player(
          name:       BotLevel.pro.storedName,
          uuid:       BotLevel.pro.uuid,
          botLevel:   BotLevel.pro,
          botOrdinal: 1));
      bot = (await DbHelper.instance.getPlayer(id))!;
    });

    tearDown(() => provider.dispose());

    CheckoutLadderGame game() => CheckoutLadderGame(
          variant:         CheckoutLadderVariant.training,
          startNumber:     81,
          dartsPerAttempt: 6,
          createdAt:       DateTime.now(),
          playerIds:       [human.id!, bot.id!],
          startingOrder:   StartingOrder.fixed,
        );

    test('throws one visit after the person and hands the turn back',
        () async {
      await provider.startGame(game(), [human, bot]);
      await provider.tapField(0, 1);
      await provider.tapField(0, 1);
      await provider.tapField(0, 1);
      expect(provider.isBotTurn, isTrue);

      await _settleBot(provider);

      expect(provider.currentSlotIndex, 0);
      final botDarts = provider.throwHistory
          .where((t) => t.playerId == bot.id)
          .length;
      expect(botDarts, inInclusiveRange(1, 3));
    });

    test('undo over a bot visit takes back the person\'s dart too', () async {
      await provider.startGame(game(), [human, bot]);
      await provider.tapField(0, 1);
      await provider.tapField(0, 1);
      await provider.tapField(0, 1);
      await _settleBot(provider);

      await provider.undoLastDart();

      expect(provider.throwHistory.where((t) => t.playerId == bot.id), isEmpty);
      expect(provider.throwHistory, hasLength(2));
      expect(provider.currentSlotIndex, 0);
    });
  });
}
