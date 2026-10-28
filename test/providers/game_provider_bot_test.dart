import 'dart:math';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Throws a full visit of three darts, or fewer if the visit ends early.
Future<void> _visit(
  GameProvider p,
  List<(int field, int modifier)> darts,
) async {
  for (final d in darts) {
    await p.tapField(d.$1, d.$2);
  }
}

/// Three singles of 20.
Future<void> _sixty(GameProvider p) =>
    _visit(p, const [(20, 1), (20, 1), (20, 1)]);

/// Three misses.
Future<void> _missedVisit(GameProvider p) =>
    _visit(p, const [(0, 1), (0, 1), (0, 1)]);

/// Waits until no bot is on turn and no bot dart is in the air.
///
/// The bot throws on real zero-length timers here, one dart per turn of the
/// event loop, so polling is the honest way to wait: there is no future that
/// completes when the bot is done, and a fixed delay would be a guess.
Future<void> _settleBot(GameProvider p) async {
  for (var i = 0; i < 2000 && (p.isBotTurn || p.botThrowing); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isBotTurn, isFalse, reason: 'the bot never finished its turn');
}

void main() {
  group('a bot in an X01 game', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late Player human;
    late Player bot;

    setUp(() async {
      provider = GameProvider()
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(3));
      human = (await insertPlayers(['Ada'])).single;
      final botId = await DbHelper.instance.insertPlayer(
        Player(
          name: BotLevel.pro.storedName,
          uuid: BotLevel.pro.uuid,
          botLevel: BotLevel.pro,
        ),
      );
      bot = (await DbHelper.instance.getPlayer(botId))!;
    });

    tearDown(() => provider.dispose());

    Game game({int startScore = 501, int legs = 3, List<TeamConfig>? teams}) =>
        Game(
          startScore: startScore,
          legs: legs,
          createdAt: DateTime.now(),
          startingOrder: StartingOrder.fixed,
          teams: teams,
        );

    test(
      'throws its visit once the person has thrown and hands the turn back',
      () async {
        await provider.startGame(game(), [human, bot]);
        await _sixty(provider);
        expect(provider.isBotTurn, isTrue);

        await _settleBot(provider);

        final botThrows = provider.playerStates[1].throws;
        expect(botThrows, hasLength(1));
        expect(botThrows.single.playerId, bot.id);
        expect(botThrows.single.dartsUsed, 3);
        expect(
          botThrows.single.hitsJson,
          isNotNull,
          reason: 'a bot visit records its darts like a person\'s',
        );
        expect(provider.currentPlayerIndex, 0);
        expect(provider.playerStates[1].remaining, lessThan(501));
      },
    );

    test('throws first when it opens the game', () async {
      await provider.startGame(game(), [bot, human]);

      await _settleBot(provider);

      expect(provider.playerStates[0].throws, hasLength(1));
      expect(provider.currentPlayerIndex, 1);
    });

    test('takes no taps and no undo while it is on turn', () async {
      await provider.startGame(game(), [human, bot]);
      await _sixty(provider);
      expect(provider.isBotTurn, isTrue);

      // Refused, not queued: the bot's visit has nothing of the person's in it.
      await provider.tapField(20, 3);
      expect(provider.dartsInVisit, 0);
      expect(provider.canUndoDart, isFalse);
      expect(provider.canRedoDart, isFalse);

      await _settleBot(provider);

      expect(
        provider.playerStates[1].throws.single.dartsUsed,
        3,
        reason: 'three darts of its own, none of the person\'s',
      );
      expect(provider.playerStates[0].throws, hasLength(1));
    });

    test(
      'is undone as a whole together with the person\'s last dart',
      () async {
        await provider.startGame(game(), [human, bot]);
        await _sixty(provider);
        await _settleBot(provider);
        expect(provider.allThrows(), hasLength(2));

        await provider.undoLastDart();

        expect(
          provider.allThrows(),
          isEmpty,
          reason: 'the bot visit and the visit before it are both gone',
        );
        expect(provider.currentPlayerIndex, 0);
        expect(
          provider.dartsInVisit,
          2,
          reason: 'the person\'s first two darts are back on the board',
        );
        expect(provider.canRedoDart, isTrue);
        expect(provider.isBotTurn, isFalse);
        expect(provider.botThrowing, isFalse);
      },
    );

    test('throws again once the undone dart is redone', () async {
      await provider.startGame(game(), [human, bot]);
      await _sixty(provider);
      await _settleBot(provider);
      final firstBotScore = provider.playerStates[1].throws.single.score;
      await provider.undoLastDart();

      await provider.redoLastDart();
      await _settleBot(provider);

      expect(provider.playerStates[0].throws.single.score, 60);
      expect(provider.playerStates[1].throws, hasLength(1));
      expect(provider.currentPlayerIndex, 0);
      // Not asserted equal: a fresh visit draws fresh darts.
      expect(firstBotScore, isA<int>());
    });

    test('has nothing to undo when only bots have thrown', () async {
      await provider.startGame(game(), [bot, human]);
      await _settleBot(provider);

      expect(provider.canUndoDart, isFalse);
      await provider.undoLastDart();

      expect(
        provider.playerStates[0].throws,
        hasLength(1),
        reason: 'a bot visit is never undone on its own',
      );
    });

    test('stops when the game is left and picks up again on resume', () async {
      await provider.startGame(game(), [human, bot]);
      await _sixty(provider);
      provider.stopBot();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(provider.playerStates[1].throws, isEmpty);
      expect(provider.isBotTurn, isTrue);

      final resumed = GameProvider()
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(3));
      addTearDown(resumed.dispose);
      await resumed.resumeGame(provider.game!, [human, bot]);
      await _settleBot(resumed);

      expect(resumed.playerStates[1].throws, hasLength(1));
      expect(resumed.currentPlayerIndex, 0);
    });

    test('throws for its team when the rotation reaches it', () async {
      final other = (await insertPlayers(['Zoe'])).single;
      final teams = [
        TeamConfig(name: 'Us', playerIds: [human.id!, bot.id!]),
        TeamConfig(name: 'Them', playerIds: [other.id!]),
      ];
      await provider.startGame(game(teams: teams), [human, bot, other]);

      await _sixty(provider); // Ada for Us
      await _missedVisit(provider); // Zoe for Them
      expect(
        provider.isBotTurn,
        isTrue,
        reason: 'the bot is the next member of Us',
      );
      await _settleBot(provider);

      final us = provider.playerStates[0];
      expect(us.throws.map((t) => t.playerId), [human.id, bot.id]);
      expect(provider.currentPlayerIndex, 1);
    });

    test('plays a leg out to the finish on its own', () async {
      await provider.startGame(game(startScore: 101, legs: 1), [bot, human]);

      for (var i = 0; i < 100 && !provider.gameOver; i++) {
        await _settleBot(provider);
        if (provider.gameOver) break;
        await _missedVisit(provider);
      }

      expect(provider.gameOver, isTrue);
      expect(provider.winnerId, bot.id);
      expect(provider.botThrowing, isFalse);
      expect(
        provider.playerStates[0].throws.last.checkoutDarts,
        greaterThan(0),
        reason: 'the finishing visit is recorded as a checkout attempt',
      );
    });
  });
}
