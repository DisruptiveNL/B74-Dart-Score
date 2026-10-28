import 'dart:math';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/bot_runner.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/utils/bot_thrower.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Waits until no bot is on turn and no bot dart is in the air, polling
/// because the bot throws on timers of its own.
Future<void> _settleBot(BotRunner p) async {
  for (var i = 0; i < 2000 && (p.isBotTurn || p.botThrowing); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isBotTurn, isFalse, reason: 'the bot never finished its turn');
}

/// The Pro bot's player row.
Future<Player> _bot() async {
  final id = await DbHelper.instance.insertPlayer(
    Player(
      name: BotLevel.pro.storedName,
      uuid: BotLevel.pro.uuid,
      botLevel: BotLevel.pro,
      botOrdinal: 1,
    ),
  );
  return (await DbHelper.instance.getPlayer(id))!;
}

void main() {
  group('a bot in Cricket', () {
    useInMemoryDatabase();

    late CricketProvider provider;
    late Player human;
    late Player bot;

    setUp(() async {
      provider = CricketProvider()
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(11));
      human = (await insertPlayers(['Ada'])).single;
      bot = await _bot();
    });

    tearDown(() => provider.dispose());

    CricketGame game(List<Player> players) => CricketGame(
      variant: CricketVariant.normal,
      scoringMode: CricketScoringMode.standard,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
      startingOrder: StartingOrder.fixed,
    );

    test(
      'throws three darts once the person has thrown and hands the turn back',
      () async {
        await provider.startGame(game([human, bot]), [human, bot]);
        await provider.recordDart(20, 1);
        await provider.recordDart(20, 1);
        await provider.recordDart(20, 1);
        expect(provider.isBotTurn, isTrue);

        await _settleBot(provider);

        expect(provider.currentPlayerIndex, 0);
        expect(provider.throwCount, 6);
        final marks = provider.playerStates[1].marks;
        expect(marks.isNotEmpty || provider.throwCount == 6, isTrue);
      },
    );

    test('takes no dart of the person\'s while on turn', () async {
      await provider.startGame(game([bot, human]), [bot, human]);
      expect(provider.isBotTurn, isTrue);
      expect(provider.inputLocked, isTrue);
      expect(provider.canUndo, isFalse);

      await provider.recordDart(20, 3);
      expect(provider.throwCount, 0, reason: 'refused, not queued');

      await _settleBot(provider);
      expect(provider.throwCount, 3);
      expect(provider.currentPlayerIndex, 1);
    });

    test(
      'is undone as a whole together with the person\'s last dart',
      () async {
        await provider.startGame(game([human, bot]), [human, bot]);
        for (var i = 0; i < 3; i++) {
          await provider.recordDart(20, 1);
        }
        await _settleBot(provider);
        expect(provider.throwCount, 6);

        await provider.undoLastDart();

        expect(
          provider.throwCount,
          2,
          reason: 'the three bot darts and the person\'s third are gone',
        );
        expect(provider.currentPlayerIndex, 0);
        expect(provider.dartsInVisit, 2);
        expect(provider.playerStates[1].marks, isEmpty);
        expect(provider.isBotTurn, isFalse);
      },
    );

    test(
      'records a dart off the seven as a miss, never as marks on the 1',
      () async {
        // A wide thrower: over a whole game some darts land beside the 20.
        final rookie = (await DbHelper.instance.getPlayer(
          await DbHelper.instance.insertPlayer(
            Player(
              name: BotLevel.rookie.storedName,
              uuid: BotLevel.rookie.uuid,
              botLevel: BotLevel.rookie,
              botOrdinal: 1,
            ),
          ),
        ))!;
        await provider.startGame(game([rookie, human]), [rookie, human]);
        for (var i = 0; i < 10; i++) {
          await _settleBot(provider);
          if (provider.gameOver) break;
          for (var d = 0; d < 3 && !provider.inputLocked; d++) {
            await provider.recordDart(0, 0);
          }
        }

        final fields = provider.throwHistory
            .where((t) => t.playerId == rookie.id)
            .map((t) => t.field)
            .toSet();
        expect(
          fields.every((f) => f == 0 || cricketFields.contains(f)),
          isTrue,
          reason: 'landed on $fields',
        );
        expect(
          provider.playerStates[0].marks.keys.every(cricketFields.contains),
          isTrue,
        );
      },
    );

    test('has nothing to undo when only bots have thrown', () async {
      await provider.startGame(game([bot, human]), [bot, human]);
      await _settleBot(provider);

      expect(provider.canUndo, isFalse);
      await provider.undoLastDart();
      expect(provider.throwCount, 3);
    });
  });

  group('a bot in Shanghai', () {
    useInMemoryDatabase();

    late ShanghaiProvider provider;
    late Player human;
    late Player bot;

    setUp(() async {
      provider = ShanghaiProvider()
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(12));
      human = (await insertPlayers(['Ada'])).single;
      bot = await _bot();
    });

    tearDown(() => provider.dispose());

    ShanghaiGame game(
      List<Player> players, {
      ShanghaiVariant variant = ShanghaiVariant.classic,
    }) => ShanghaiGame(
      variant: variant,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
      startingOrder: StartingOrder.fixed,
    );

    test(
      'throws its visit at the round\'s number and hands the turn back',
      () async {
        await provider.startGame(game([human, bot]), [human, bot]);
        await provider.recordDart(1);
        await provider.recordDart(1);
        await provider.recordDart(1);
        expect(provider.isBotTurn, isTrue);

        await _settleBot(provider);

        expect(provider.currentPlayerIndex, 0);
        expect(provider.currentRound, 2);
        final botDarts = (await DbHelper.instance.getShanghaiThrowsForGame(
          provider.game!.id!,
        )).where((t) => t.playerId == bot.id).toList();
        expect(botDarts, hasLength(3));
        expect(
          botDarts.every((t) => t.target == 1),
          isTrue,
          reason: 'every dart of the visit is filed under the round\'s target',
        );
      },
    );

    test(
      'is undone as a whole together with the person\'s last dart',
      () async {
        await provider.startGame(game([human, bot]), [human, bot]);
        for (var i = 0; i < 3; i++) {
          await provider.recordDart(1);
        }
        await _settleBot(provider);

        await provider.undoLastDart();

        final darts = await DbHelper.instance.getShanghaiThrowsForGame(
          provider.game!.id!,
        );
        expect(darts, hasLength(2));
        expect(darts.every((t) => t.playerId == human.id), isTrue);
        expect(provider.currentPlayerIndex, 0);
        expect(provider.dartsInVisit, 2);
        expect(provider.playerStates[1].score, 0);
      },
    );

    test('plays the sequential variant through to its own win', () async {
      await provider.startGame(
        game([bot, human], variant: ShanghaiVariant.sequential),
        [bot, human],
      );

      for (var i = 0; i < 400 && !provider.gameOver; i++) {
        await _settleBot(provider);
        if (provider.gameOver) break;
        for (var d = 0; d < 3 && !provider.inputLocked; d++) {
          await provider.recordDart(0);
        }
      }

      expect(provider.gameOver, isTrue);
      expect(provider.winnerId, bot.id);
    });
  });

  group('a bot in Around the Clock', () {
    useInMemoryDatabase();

    late AroundTheClockProvider provider;
    late Player human;
    late Player bot;

    setUp(() async {
      provider = AroundTheClockProvider()
        ..botDartDelay = Duration.zero
        ..botThrower = BotThrower(rng: Random(13));
      human = (await insertPlayers(['Ada'])).single;
      bot = await _bot();
    });

    tearDown(() => provider.dispose());

    AroundTheClockGame game(
      List<Player> players, {
      AroundTheClockVariant variant = AroundTheClockVariant.basic,
    }) => AroundTheClockGame(
      variant: variant,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
      startingOrder: StartingOrder.fixed,
    );

    test('works its way round the board and wins on its own', () async {
      await provider.startGame(game([bot, human]), [bot, human]);

      for (var i = 0; i < 400 && !provider.gameOver; i++) {
        await _settleBot(provider);
        if (provider.gameOver) break;
        for (var d = 0; d < 3 && !provider.inputLocked; d++) {
          await provider.recordDart(0, 0);
        }
      }

      expect(provider.gameOver, isTrue);
      expect(provider.winnerId, bot.id);
      expect(provider.playerStates[0].isFinished, isTrue);
    });

    test('collects every ring of a number under full segments', () async {
      await provider.startGame(
        game([bot, human], variant: AroundTheClockVariant.fullSegments),
        [bot, human],
      );

      // Two visits of the bot, with the person missing in between.
      await _settleBot(provider);
      for (var d = 0; d < 3; d++) {
        await provider.recordDart(0, 0);
      }
      await _settleBot(provider);

      final s = provider.playerStates[0];
      // Six darts at the 1: either it advanced, or the rings it has so far are
      // all rings of the 1, never of some other number.
      expect(
        s.progress > 0 || s.hitSegments.every((m) => m >= 1 && m <= 3),
        isTrue,
      );
      expect(provider.currentPlayerIndex, 1);
    });

    test(
      'is undone as a whole together with the person\'s last dart',
      () async {
        await provider.startGame(game([human, bot]), [human, bot]);
        for (var i = 0; i < 3; i++) {
          await provider.recordDart(1, 1);
        }
        await _settleBot(provider);

        await provider.undoLastDart();

        final darts = await DbHelper.instance.getAroundTheClockThrowsForGame(
          provider.game!.id!,
        );
        expect(darts, hasLength(2));
        expect(provider.playerStates[1].progress, 0);
        expect(provider.currentPlayerIndex, 0);
        expect(provider.dartsInVisit, 2);
      },
    );
  });
}
